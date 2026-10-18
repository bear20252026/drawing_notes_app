import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/utils/error_code.dart';
import 'package:drawing_notes_app/core/utils/single_instance.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/security/audit_logger.dart';
import 'core/security/root_guard.dart';
import 'l10n/app_localizations.dart';

import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

/// 单实例检测（ASM-02）。策略与三条现状写在
/// `core/utils/single_instance.dart` 文件头：**并存、不阻断、只上报事实**。
///
/// 历史教训（也是为什么这里刻意没有任何 `return`）：曾经的做法是「检测到已有实例
/// 就退出」，用户反馈回来的原话是「应用打不开 / 工具栏全用不了」——残留锁或 PID
/// 误判会让第二个实例**静默**起不来。Android 上由系统管理生命周期，本机制自然退化。
SingleInstanceLock? _instanceLock;

/// 是否持有单实例锁（诊断用；**今天零调用方**，台账 §24 已登记，删它需点名）。
bool get holdsInstanceLock => _instanceLock?.holdsLock ?? false;

/// 释放单实例锁（**今天零调用方**：桌面端没有可靠的退出钩子，见模块文件头①）。
Future<void> releaseInstanceLock() async {
  await _instanceLock?.release();
}

/// 取锁。**任何返回值、任何异常都不阻止启动**。
///
/// R51 之后这里多解析了一次数据根（`root()` 会顺带跑「旧位置→ApplicationSupport」的
/// 一次性迁移）⇒ 多了一条**能把启动打死**的路径：磁盘只读、迁移标记损坏、path_provider
/// 失败……所以整段包在 try 里，失败就退回「根未知」（`dataRootKey: ''` ⇒ 结果是
/// `undetectable`，不出提示、也不阻断）。这条契约写在
/// `test/app_shell_instance_notice_test.dart` 的「取锁之后不许有 return」判据旁边。
Future<SingleInstanceStatus> _acquireSingleInstance() async {
  try {
    final supportPath = (await getApplicationSupportDirectory()).path;
    // 根路径必须在 `applyPendingRestore()` 之后取：那一步会换根，取早了写进锁的就是
    // 另一个根，下一次启动会把「同一个数据根」判成「不同根」——静默失效，比误报更难查。
    final rootKey = (await AppDataRoot.defaultRootDir()).path;
    final lock = SingleInstanceLock(
      lockFile: File('$supportPath${Platform.pathSeparator}app.lock'),
    );
    _instanceLock = lock;
    // 先 await 再 return：直接把 `lock.acquire(...)` 从 try 里返回出去，返回的 Future 上的
    // 异常就不归这个 catch 管了（lint `unawaited_return_in_try_block`，CI 的 analyze 步骤拦下过）。
    final status = await lock.acquire(dataRootKey: rootKey);
    return status;
  } catch (e) {
    // 根都解析不出来 ⇒ 连锁放哪儿都不知道：这一格就是「判不出来」，不出提示、不阻断。
    AuditLogger.log(
      'app.instance_root_resolve_failed',
      success: false,
      detail: errorCode(e),
    );
    return SingleInstanceStatus.undetectable;
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
      'app.error.${errorCode(details.exception)}',
      success: false,
      detail: details.library ?? 'framework',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AuditLogger.log('app.uncaught.${errorCode(error)}', success: false);
    return true;
  };
  // R-13（审计 2026-09-27）：构建期异常兜底——此前全库无 ErrorWidget
  // .builder，release 下任何构建异常（如标签颜色解析损坏）渲染灰色
  // ErrorBox 且无用户可读信息。保持日志纪律：只记错误类型。
  ErrorWidget.builder = (details) {
    AuditLogger.log(
      'app.build.${errorCode(details.exception)}',
      success: false,
    );
    return const _BuildErrorFallback();
  };
  // 批次 M（2026-09-27）：应用「从备份恢复」的落地步——此刻无任何存储
  // 打开，原子交换目录最安全。失败不阻塞启动（fail-safe，标记保留）。
  try {
    await AppDataRoot.applyPendingRestore();
  } catch (_) {
    // 恢复检查失败不阻塞正常启动。
  }
  // ASM-02：二次启动检测。**这里没有任何 return**——把检测结果当事实上报，
  // 不当闸门（旧写法「已有实例就退出」被用户投诉成「应用打不开」，理由全写在
  // core/utils/single_instance.dart 文件头）。判不出来时也不谎报成「有另一个实例」。
  // 挪到 `applyPendingRestore()` 之后是 R51 要求的：锁里要写**换根之后**的数据根路径。
  final instanceStatus = await _acquireSingleInstance();
  instanceStatusAtLaunch = instanceStatus;
  if (instanceStatus != SingleInstanceStatus.acquired) {
    AuditLogger.log(
      'app.instance_${instanceStatus.name}',
      success: true,
      detail: 'startup_continues',
    );
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
  // L3 液态玻璃着色器预加载（失败静默回落 L2——不阻塞启动，见 LiquidGlassGate）。
  unawaited(LiquidGlassShader.init());
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppleSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.gpp_bad_rounded,
                      size: 64,
                      color: AppleColor.errorRed,
                    ),
                    const SizedBox(height: AppleSpacing.lg),
                    Text(
                      l10n?.rootRefusalTitle ?? '无法在此设备上启动',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppleSpacing.sm),
                    Text(
                      l10n?.rootRefusalBody ??
                          '检测到设备已获取 ROOT 权限。为保护你的加密笔记数据，本应用在已破解设备上拒绝运行。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 构建期异常的用户可见兜底（R-13，审计 2026-09-27）：release 下替换默认
/// 灰色 ErrorBox。兜底自身刻意零依赖——不取 Theme.of/InheritedWidget/l10n
/// （出错上下文可能已损坏）；排版走 AppleType 静态令牌；文案为无 arb
/// 上下文可用时的固定兜底（与全库 `?? '中文'` 双轨口径一致）。
class _BuildErrorFallback extends StatelessWidget {
  const _BuildErrorFallback();

  @override
  Widget build(BuildContext context) {
    // P2-18：深色模式用户此前会看到刺眼纯白错误页。platformBrightness 是
    // 纯 dart:ui API，不依赖 Theme/l10n——保持「零依赖」动机的同时适配
    // 深浅（构建失败兜底常量对，不经过任何 token 层）。
    final isDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final bg = isDark ? const Color(0xFF101521) : Colors.white;
    final fg = isDark ? const Color(0xFFEBEDF3) : Colors.black87;
    final fgMuted = isDark ? const Color(0xFF98989F) : Colors.black54;
    return ColoredBox(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: fgMuted, size: 40),
            const SizedBox(height: AppleSpacing.sm),
            Text(
              '页面显示出现问题，请返回后重试',
              textAlign: TextAlign.center,
              style: AppleType.bodyStyle(fg),
            ),
          ],
        ),
      ),
    );
  }
}
