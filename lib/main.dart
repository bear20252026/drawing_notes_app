import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/security/audit_logger.dart';
import 'core/security/root_guard.dart';

/// 单实例锁（借鉴 QOwnNotes 二次启动聚焦：
/// Windows 桌面重复启动时检测已有实例并退出，避免多窗口混乱）。
///
/// 实现：以"原子创建锁文件"（`File.create(exclusive: true)`）作为互斥——
/// 第二个实例创建失败即判定已有实例并退出（评审发现 P3 修复：
/// 原 `RandomAccessFile.lock()` 在 POSIX 上会阻塞挂起，而非立即失败）。
/// 锁文件写入启动进程的 PID；下次启动若发现 PID 已不存活，则清理陈旧锁
/// 后重试，避免上次异常退出留下的残留锁导致永远无法启动。
///
/// Android 上由系统管理应用生命周期，本机制自然退化为"始终通过"。
File? _instanceLockFile;

/// 是否持有单实例锁（供调试/退出时释放）。
bool get holdsInstanceLock => _instanceLockFile != null;

/// 释放单实例锁（应用正常退出时调用，删除锁文件）。
Future<void> releaseInstanceLock() async {
  try {
    await _instanceLockFile?.delete();
  } catch (_) {
    // 删除失败忽略（锁文件由 OS 进程退出自动清理语义兜底）。
  }
  _instanceLockFile = null;
}

/// 获取应用数据目录下的锁文件路径。
Future<File> _lockFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}app.lock');
}

/// 尝试获取单实例锁（尽力而为，绝不阻塞启动）。
///
/// 修复用户反馈"应用打不开/工具栏全用不了"的根因：原实现检测到已有
/// 实例时**静默退出**（main 直接 return），配合残留 app.lock 或 PID
/// 存活误判，用户双击图标毫无反应，表现为"所有功能都用不了"。
/// 现改为：锁获取失败不退出，正常启动（本地单机工具允许多实例无害）。
Future<bool> _acquireSingleInstance() async {
  try {
    final lockFile = await _lockFile();
    // 残留锁清理：读取 PID，若进程已不存活则删除陈旧锁。
    if (await lockFile.exists()) {
      final pid = int.tryParse((await lockFile.readAsString()).trim());
      if (pid != null && !await _isProcessAlive(pid)) {
        try {
          await lockFile.delete();
        } catch (_) {
          // 清理失败忽略。
        }
      }
    }
    try {
      final created = await lockFile.create(exclusive: true);
      await created.writeAsString(pid.toString(), flush: true);
      _instanceLockFile = created;
    } catch (_) {
      // 已有存活实例（锁被占用）：不退出，正常启动。
    }
    return true;
  } catch (_) {
    // 任何异常都不阻塞启动。
    return true;
  }
}

/// 判断进程 [pid] 是否存活（Windows: tasklist；POSIX: kill -0）。
Future<bool> _isProcessAlive(int pid) async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
      return r.stdout.toString().contains('$pid');
    }
    final r = await Process.run('kill', ['-0', '$pid']);
    return r.exitCode == 0;
  } catch (_) {
    // 无法判断时保守视为存活（避免误清活跃实例的锁）。
    return true;
  }
}

/// 应用入口。
///
/// 仅做初始化装配，不承载业务逻辑。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Root 守卫（用户拍板 2026-09-01；U1 修订 2026-09-02）：Android 检测
  // 到 root 拒绝启动——先于一切初始化执行；拒绝方式为明确提示页
  // （不再静默 exit(1) 闪退，应用本体照常不运行）。
  if (RootGuard.detect()) {
    RootGuard.logRefusal();
    runApp(const RootRefusalApp());
    return;
  }
  // L-01 错误边界（专家审计 2026-08-15）：Flutter 官方模式（FlutterError
  // .onError + PlatformDispatcher.onError）——保留 presentError 控制台输出，
  // 同时脱敏记录（仅错误类型/库名——不含敏感正文/路径/内部格式）。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AuditLogger.log(
      'app.error.${details.exception.runtimeType}',
      success: false,
      detail: details.library ?? 'framework',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AuditLogger.log('app.uncaught.${error.runtimeType}', success: false);
    return true;
  };
  // 二次启动检测：已有实例则直接退出（桌面单实例）。
  if (!await _acquireSingleInstance()) {
    return;
  }
  // R2 审计（用户拍板 2026-09-03）：桌面窗口最小尺寸 360×560——
  // 防止窗口拖得过窄触发布局溢出。尽力而为：失败不阻塞启动。
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(360, 560));
    } catch (_) {
      AuditLogger.log('app.desktop_window_min_size', success: false);
    }
  }
  runApp(const ProviderScope(child: DrawingNotesApp()));
}

/// Root 拒绝启动提示页（U1 2026-09-02）。
///
/// 应用本体不装配（不初始化存储/密钥/业务），仅告知用户拒绝原因——
/// 安全语义与原 exit(1) 一致（数据不可达），但不再表现为无解释闪退。
class RootRefusalApp extends StatelessWidget {
  const RootRefusalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.gpp_bad_rounded,
                  size: 64,
                  color: AppleColor.errorRed,
                ),
                const SizedBox(height: 20),
                Text(
                  '无法在此设备上启动',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  '检测到设备已获取 ROOT 权限。为保护你的加密笔记数据，'
                  '本应用在已破解设备上拒绝运行。',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
