import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';

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
  // 二次启动检测：已有实例则直接退出（桌面单实例）。
  if (!await _acquireSingleInstance()) {
    return;
  }
  runApp(const DrawingNotesApp());
}
