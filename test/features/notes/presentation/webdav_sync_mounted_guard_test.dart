// P2 修复回归锁（审计 2026-10）：设置页在 await 之后必须先过 mounted 再碰
// ScaffoldMessenger / setState。
//
// 旧写法把提示写成 `(mounted ? AppLocalizations.of(context) : null) ?? 兜底`，
// 却仍然无条件调用 _toast —— 页面被 pop 后用 defunct context 取 messenger
// 直接抛错（三个提示分支：未设密码 / 表单脏 / 缺盐，同款缺陷）。
//
// 时序由可控 Completer 决定（不拿 pump 时长赌竞速）：点「立即同步」→ 停在
// await 上 → 卸载页面 → 放行 await → 断言没有任何异常被抛进框架。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
// SyncResult 随 sync_controller.dart 再导出，无需直接 import 服务实现文件。
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: child,
);

/// 可控桩：[gateLoads]=true 时「同步按钮」触发的配置加载停在 [gate] 上，
/// 否则由 [gateSyncNow] 让同步执行停住。initState 的那次加载永远立即返回。
class _StubController extends SyncController {
  _StubController({required this.cfg, required this.secrets});

  final WebDavSyncConfig cfg;
  final SyncSecrets secrets;
  final Completer<void> gate = Completer<void>();
  bool gateLoads = false;
  bool gateSyncNow = false;
  int loadCalls = 0;
  int syncCalls = 0;

  @override
  Future<WebDavSyncConfig> loadConfig() async {
    loadCalls++;
    if (gateLoads && loadCalls > 1) await gate.future;
    return cfg;
  }

  @override
  Future<SyncSecrets> readSecrets() async => secrets;

  @override
  Future<SyncRunOutcome> syncNow({
    required Uri baseUrl,
    required String username,
    required String password,
    required String passphrase,
    required String? syncSalt,
    required ConflictHandler conflictHandler,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    syncCalls++;
    if (gateSyncNow) await gate.future;
    return (
      result: const SyncResult(uploaded: 0, downloaded: 0, deletedRemote: 0),
      error: null,
    );
  }
}

/// 点同步 → 停在 await 上 → 卸载页面 → 放行 await。
Future<void> _unmountWhileAwaiting(
  WidgetTester tester,
  _StubController controller,
) async {
  await tester.pumpWidget(
    _wrap(WebDavSyncSettingsPage(syncController: controller)),
  );
  await tester.pump(); // 让 initState 的配置加载落地
  await tester.tap(find.text('立即同步'));
  await tester.pump(); // 进入 _syncNow，停在 await 上
  // 用户在 await 期间退出页面。
  await tester.pumpWidget(_wrap(const SizedBox.shrink()));
  await tester.pump();
  controller.gate.complete();
  await tester.pumpAndSettle();
}

void main() {
  const cfgNoSalt = WebDavSyncConfig(
    baseUrl: 'https://dav.example.com/x/',
    username: 'u',
  );
  const cfgReady = WebDavSyncConfig(
    baseUrl: 'https://dav.example.com/x/',
    username: 'u',
    syncSalt: 'c2FsdA==',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('未设同步密码分支：await 后卸载页面不再抛错', (tester) async {
    final controller = _StubController(cfg: cfgNoSalt, secrets: const SyncSecrets())
      ..gateLoads = true;
    await _unmountWhileAwaiting(tester, controller);
    expect(tester.takeException(), isNull);
    expect(controller.loadCalls, 2);
  });

  testWidgets('缺加密盐分支：await 后卸载页面不再抛错', (tester) async {
    final controller = _StubController(
      cfg: cfgNoSalt,
      secrets: const SyncSecrets(webdavPassword: 'w', syncPassphrase: 'p'),
    )..gateLoads = true;
    await _unmountWhileAwaiting(tester, controller);
    expect(tester.takeException(), isNull);
    expect(controller.syncCalls, 0, reason: '缺盐时不该走到同步');
  });

  testWidgets('同步执行分支：await 后卸载页面不再抛错', (tester) async {
    final controller = _StubController(
      cfg: cfgReady,
      secrets: const SyncSecrets(webdavPassword: 'w', syncPassphrase: 'p'),
    )..gateSyncNow = true;
    await _unmountWhileAwaiting(tester, controller);
    expect(tester.takeException(), isNull);
    expect(controller.syncCalls, 1);
  });

  // 反向锁：页面仍在时提示必须照常出现（别把守卫写成永远静默）。
  testWidgets('页面未退出时 fail-closed 提示照常弹出', (tester) async {
    final controller = _StubController(cfg: cfgNoSalt, secrets: const SyncSecrets());
    await tester.pumpWidget(
      _wrap(WebDavSyncSettingsPage(syncController: controller)),
    );
    await tester.pump();
    await tester.tap(find.text('立即同步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.textContaining('为避免笔记明文上云'),
      findsOneWidget,
      reason: '阻止同步的提示不得因 mounted 守卫而消失',
    );
    await tester.pumpAndSettle(); // 等 SnackBar 自动消失，清掉计时器
    expect(tester.takeException(), isNull);
  });
}
