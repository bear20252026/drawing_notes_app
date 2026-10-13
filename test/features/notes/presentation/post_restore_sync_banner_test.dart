// DN-204 的 UI 面：恢复换根后同步设置页必须把「同步被按住、等你选方向」显形，
// 并把所选方向原样带进那一轮同步。
//
// 钉四件事（都是审计点名的「静默」反面）：
//  ① 判据判定隔离 ⇒ 提示条出现；判据说可信 ⇒ 提示条绝不出现（反向锁）；
//  ② 四个按钮各自把正确的方向交给 SyncController；
//  ③ 「用本机覆盖云端」必须先过危险二次确认，取消时一轮都不跑；
//  ④ reportOnly 的摘要绝不能写成「同步完成 / 已是最新」。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/sync/post_restore_baseline.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
// SyncResult 随 sync_controller.dart 再导出；差异/方向类型走 core 的纯值模块。
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

const _cfgReady = WebDavSyncConfig(
  baseUrl: 'https://dav.example.com/x/',
  username: 'u',
  syncSalt: 'c2FsdA==',
);
const _secretsReady = SyncSecrets(webdavPassword: 'w', syncPassphrase: 'p');

class _StubController extends SyncController {
  _StubController({required this.held, this.results = const []})
    : super(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(_secretsReady),
      );

  /// 桩侧的隔离判据返回值。
  bool held;

  /// 依序吐出的同步结果；用完之后重复最后一项。
  final List<SyncResult> results;

  final List<PostRestoreReconcile?> seenReconciles = [];
  int holdQueries = 0;

  /// 置 true 时 `syncNow` 停在 [syncGate] 上（用来观察「一轮在飞」的中间态）。
  bool gateSyncNow = false;
  final Completer<void> syncGate = Completer<void>();

  @override
  Future<WebDavSyncConfig> loadConfig() async => _cfgReady;

  @override
  Future<SyncSecrets> readSecrets() async => _secretsReady;

  @override
  Future<bool> isBaselineHeldForRestore() async {
    holdQueries++;
    return held;
  }

  @override
  Future<SyncRunOutcome> syncNow({
    required Uri baseUrl,
    required String username,
    required String password,
    required String passphrase,
    required String? syncSalt,
    required ConflictHandler conflictHandler,
    void Function(SyncProgress progress)? onProgress,
    PostRestoreReconcile? reconcile,
  }) async {
    seenReconciles.add(reconcile);
    if (gateSyncNow) await syncGate.future;
    final index = seenReconciles.length - 1;
    return (
      result: index < results.length
          ? results[index]
          : (results.isEmpty
                ? const SyncResult(uploaded: 0, downloaded: 0, deletedRemote: 0)
                : results.last),
      error: null,
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    AppLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: child,
);

Future<void> _pumpPage(WidgetTester tester, _StubController controller) async {
  await tester.pumpWidget(
    _wrap(WebDavSyncSettingsPage(syncController: controller)),
  );
  await tester.pump();
}

const _diff = PostRestoreDiff(
  localOnlyIds: ['x'],
  remoteOnlyIds: ['b', 'c'],
  divergedIds: ['a'],
  suppressedTombstoneIds: ['b', 'c'],
);

SyncResult _heldResult() => const SyncResult(
  uploaded: 0,
  downloaded: 0,
  deletedRemote: 0,
  postRestorePolicy: PostRestoreReconcile.reportOnly,
  postRestoreDiff: _diff,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('隔离态：提示条出现，四个方向都在', (tester) async {
    final controller = _StubController(held: true);
    await _pumpPage(tester, controller);

    expect(find.byKey(const ValueKey('postRestoreMerge')), findsOneWidget);
    expect(find.byKey(const ValueKey('postRestoreKeepRemote')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('postRestoreOverwriteRemote')),
      findsOneWidget,
    );
    expect(
      find.textContaining('刚恢复过备份'),
      findsOneWidget,
      reason: '文案走 arb（zh），不是代码里写死的第二套措辞',
    );
    expect(controller.holdQueries, greaterThan(0));
  });

  testWidgets('反向锁：判据说基线可信时提示条绝不出现', (tester) async {
    final controller = _StubController(held: false);
    await _pumpPage(tester, controller);

    expect(find.byKey(const ValueKey('postRestoreMerge')), findsNothing);
    expect(find.textContaining('刚恢复过备份'), findsNothing);
  });

  testWidgets('四个按钮把各自的方向交给 SyncController', (tester) async {
    final controller = _StubController(held: true, results: [_heldResult()]);
    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey('postRestoreShowDiff')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.seenReconciles.single, PostRestoreReconcile.reportOnly);

    for (final (key, mode) in const [
      ('postRestoreMerge', PostRestoreReconcile.merge),
      ('postRestoreKeepRemote', PostRestoreReconcile.keepRemote),
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.seenReconciles.last, mode);
    }
  });

  testWidgets('reportOnly 的摘要不得写成「同步完成 / 已是最新」', (tester) async {
    final controller = _StubController(held: true, results: [_heldResult()]);
    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey('postRestoreShowDiff')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('已是最新'), findsNothing);
    expect(find.textContaining('同步完成'), findsNothing);
    expect(
      find.textContaining('同步已暂停'),
      findsWidgets,
      reason: '摘要与提示条都要说「本轮什么都没写」',
    );
    // 差异数字常驻在提示条上，不是弹一次就消失的 toast。
    expect(
      find.textContaining('已拦住「删除云端」'),
      findsWidgets,
      reason: '审计要求先把差异摆出来，再让用户选方向',
    );
  });

  testWidgets('覆盖云端必须先过危险确认；取消时一轮都不跑', (tester) async {
    final controller = _StubController(held: true, results: [_heldResult()]);
    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey('postRestoreOverwriteRemote')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('云端较新的版本会被恢复出来的旧版本替换'),
      findsOneWidget,
    );
    expect(controller.seenReconciles, isEmpty, reason: '弹窗还没放行');

    // 关掉弹窗（点遮罩或取消）⇒ 不发起同步。
    Navigator.of(tester.element(find.byType(Dialog).first)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.seenReconciles, isEmpty);
  });

  testWidgets('一轮在飞时提示条按钮禁用（单飞互斥的 UI 侧同口径）', (tester) async {
    final controller = _StubController(held: true, results: [_heldResult()])
      ..gateSyncNow = true;
    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey('postRestoreMerge')));
    await tester.pump();
    expect(
      tester.widget<TextButton>(
        find.byKey(const ValueKey('postRestoreKeepRemote')),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(
        find.byKey(const ValueKey('postRestoreShowDiff')),
      ).onPressed,
      isNull,
    );

    controller.syncGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextButton>(
        find.byKey(const ValueKey('postRestoreKeepRemote')),
      ).onPressed,
      isNotNull,
      reason: '轮次结束后必须重新可点，否则方向永远选不了',
    );
  });
}
