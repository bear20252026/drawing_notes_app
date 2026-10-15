// A3-2 甲的处置入口（UI）回归锁。
//
// 界面这一层的主张只有三条，全部可失败：
//  ① 只对**陈旧副本**给按钮——`localHasEdits`（本机有只此一份的内容）与
//     `unknowable`（没证据）都照常上传，给它们摆按钮等于诱导用户做一次有代价的选择；
//  ② 唯一会移走本机文件的动作（认云端删除）**必须二次确认**，取消就真的不执行；
//  ③ 一轮同步正在跑时按钮禁用（与 DN-002a 单飞互斥同口径）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/sync/remote_deletes.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/remote_delete_disposition_banner.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

const _stale = RemoteDeleteIssue(
  docId: 'gone_stale',
  kind: RemoteDeleteKind.staleCopy,
  localUpdatedAt: 200,
  localSize: 100,
  proof: RemoteDeleteProof.causalAnchor,
  tombstoneBaseRev: 200,
);
const _edited = RemoteDeleteIssue(
  docId: 'gone_edited',
  kind: RemoteDeleteKind.localHasEdits,
  localUpdatedAt: 300,
  localSize: 120,
  proof: RemoteDeleteProof.baselineChanged,
);

const _cfg = WebDavSyncConfig(
  baseUrl: 'https://dav.example.com/x/',
  username: 'u',
  syncSalt: 'c2FsdA==',
);
const _secrets = SyncSecrets(webdavPassword: 'w', syncPassphrase: 'p');

class _StubController extends SyncController {
  _StubController({this.result = const SyncResult(uploaded: 0, downloaded: 0, deletedRemote: 0)})
    : super(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(_secrets),
      );

  final SyncResult result;
  final List<(String, RemoteDeleteDisposition)> calls = [];

  /// 处置结果：默认「已执行」，用例可改成「本机已无此篇」。
  ({bool applied, String? copyId}) outcome = (applied: true, copyId: 'gone_stale-copy-1');

  @override
  Future<WebDavSyncConfig> loadConfig() async => _cfg;

  @override
  Future<SyncSecrets> readSecrets() async => _secrets;

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
  }) async => (result: result, error: null);

  @override
  Future<({bool applied, String? copyId})> applyRemoteDeleteDisposition({
    required String docId,
    required RemoteDeleteDisposition disposition,
  }) async {
    calls.add((docId, disposition));
    return outcome;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    AppLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: child,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('只有陈旧副本拿到按钮；本机有独有内容的那一篇不出现', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteDeleteDispositionBanner(
          issues: const [_stale, _edited],
          enabled: true,
          onDispose: (id, d) {},
        ),
      ),
    );

    expect(find.text('gone_stale'), findsOneWidget);
    expect(find.text('gone_edited'), findsNothing,
        reason: '给不可无损处理的那一类摆按钮＝诱导用户做有代价的选择');
    expect(
      find.byKey(const ValueKey('rdKeepAsCopy-gone_stale')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('rdPushAnyway-gone_stale')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rdHonorDelete-gone_stale')),
      findsOneWidget,
    );
  });

  testWidgets('三个动作各自把 (docId, disposition) 传出去', (tester) async {
    final seen = <(String, RemoteDeleteDisposition)>[];
    await tester.pumpWidget(
      _wrap(
        RemoteDeleteDispositionBanner(
          issues: const [_stale],
          enabled: true,
          onDispose: (id, d) => seen.add((id, d)),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('rdKeepAsCopy-gone_stale')));
    await tester.tap(find.byKey(const ValueKey('rdPushAnyway-gone_stale')));
    await tester.tap(find.byKey(const ValueKey('rdHonorDelete-gone_stale')));

    expect(seen.map((e) => e.$2).toList(), [
      RemoteDeleteDisposition.keepAsCopy,
      RemoteDeleteDisposition.pushAnyway,
      RemoteDeleteDisposition.honorCloudDelete,
    ]);
    expect(seen.every((e) => e.$1 == 'gone_stale'), isTrue);
  });

  testWidgets('同步进行中 ⇒ 三个按钮全部禁用（不与在飞的那一轮抢）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteDeleteDispositionBanner(
          issues: const [_stale],
          enabled: false,
          onDispose: (id, d) {},
        ),
      ),
    );

    for (final key in [
      'rdKeepAsCopy-gone_stale',
      'rdPushAnyway-gone_stale',
      'rdHonorDelete-gone_stale',
    ]) {
      final button = tester.widget<TextButton>(find.byKey(ValueKey(key)));
      expect(
        button.onPressed,
        isNull,
        reason: '$key 在同步跑着时必须不可点（否则处置会插在一轮同步中间）',
      );
    }
  });

  testWidgets('没有陈旧副本时整条不占位', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteDeleteDispositionBanner(
          issues: const [_edited],
          enabled: true,
          onDispose: (id, d) {},
        ),
      ),
    );

    expect(find.byType(RemoteDeleteDispositionBanner), findsOneWidget);
    expect(find.text('gone_edited'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页：认云端删除要先确认，取消就什么都不执行', (tester) async {
    final controller = _StubController(
      result: const SyncResult(
        uploaded: 0,
        downloaded: 0,
        deletedRemote: 0,
        remoteDeletes: [_stale],
      ),
    );
    await tester.pumpWidget(_wrap(WebDavSyncSettingsPage(syncController: controller)));
    await tester.pump();
    await tester.tap(find.text('立即同步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 上一轮的结果要留在屏上（toast 会消失，未决事项不会自己消失）。
    expect(find.byKey(const ValueKey('rdHonorDelete-gone_stale')), findsOneWidget);
    controller.calls.clear();

    await tester.tap(find.byKey(const ValueKey('rdHonorDelete-gone_stale')));
    await tester.pumpAndSettle();
    expect(find.text('把这篇本机笔记移入回收站？'), findsOneWidget,
        reason: '唯一会移走本机文件的动作必须问一次');
    expect(controller.calls, isEmpty);

    // 取消（点掉对话框但不确认）⇒ 不执行。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页：确认之后条目从处置条上消失（不重跑同步也刷新）', (tester) async {
    final controller = _StubController(
      result: const SyncResult(
        uploaded: 0,
        downloaded: 0,
        deletedRemote: 0,
        remoteDeletes: [_stale],
      ),
    );
    await tester.pumpWidget(_wrap(WebDavSyncSettingsPage(syncController: controller)));
    await tester.pump();
    await tester.tap(find.text('立即同步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    controller.calls.clear();

    await tester.tap(find.byKey(const ValueKey('rdPushAnyway-gone_stale')));
    await tester.pumpAndSettle();

    expect(
      controller.calls,
      [('gone_stale', RemoteDeleteDisposition.pushAnyway)],
      reason: '豁免登记不需要二次确认——它不移走任何东西',
    );
    expect(find.byKey(const ValueKey('rdPushAnyway-gone_stale')), findsNothing,
        reason: '处理完的那一篇要从处置条上下来，否则用户会以为没点上');
    expect(tester.takeException(), isNull);
  });
}
