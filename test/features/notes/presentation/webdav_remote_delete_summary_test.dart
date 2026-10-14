// A3 读者上线的「摘要可见性」回归锁（与 webdav_remote_copy_unprotected_summary_test
// 同一手法：桩控制器把 SyncResult 直接喂给设置页）。
//
// 光有 `SyncResult.remoteDeletes` 字段不够——看不见就等于没说。这里锁三件事：
//  ① 三类（陈旧副本 / 本机改过 / 无从比对）各数各的，不许被压成一句
//     「有 N 篇不一致」；
//  ② l10n 缺席时兜底文案仍在（与 zh arb 逐字一致，由 l10n 门禁C 另一头锁）；
//  ③ 没有这类分叉时**不得凭空出现**该提示——它就是「本机什么都没删」这句话，
//     冒错了会让人以为自己的画布被程序删过。
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
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

const _cfgReady = WebDavSyncConfig(
  baseUrl: 'https://dav.example.com/x/',
  username: 'u',
  syncSalt: 'c2FsdA==',
);
const _secretsReady = SyncSecrets(webdavPassword: 'w', syncPassphrase: 'p');

const _stale = RemoteDeleteIssue(
  docId: 'stale',
  kind: RemoteDeleteKind.staleCopy,
  proof: RemoteDeleteProof.baselineUnchanged,
  localUpdatedAt: 200,
  localSize: 100,
  tombstoneBaseRev: 200,
);
const _edited = RemoteDeleteIssue(
  docId: 'edited',
  kind: RemoteDeleteKind.localHasEdits,
  proof: RemoteDeleteProof.baselineChanged,
  localUpdatedAt: 300,
  localSize: 120,
  tombstoneBaseRev: 200,
);
const _unknown = RemoteDeleteIssue(
  docId: 'unknown',
  kind: RemoteDeleteKind.unknowable,
  proof: RemoteDeleteProof.none,
  localUpdatedAt: 100,
  localSize: 80,
);

class _StubController extends SyncController {
  _StubController(this.result)
    : super(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(_secretsReady),
      );

  final SyncResult result;

  @override
  Future<WebDavSyncConfig> loadConfig() async => _cfgReady;

  @override
  Future<SyncSecrets> readSecrets() async => _secretsReady;

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
}

Widget _wrap(Widget child, {bool withL10n = true}) => MaterialApp(
  locale: withL10n ? const Locale('zh') : null,
  localizationsDelegates: [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    if (withL10n) AppLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: child,
);

Future<void> _runSync(
  WidgetTester tester,
  SyncResult result, {
  bool withL10n = true,
}) async {
  await tester.pumpWidget(
    _wrap(
      WebDavSyncSettingsPage(syncController: _StubController(result)),
      withL10n: withL10n,
    ),
  );
  await tester.pump();
  await tester.tap(find.text('立即同步'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('三类各数各的：陈旧 1 / 本机改过 1 / 无从比对 1 都进摘要', (tester) async {
    await _runSync(
      tester,
      const SyncResult(
        uploaded: 1,
        downloaded: 0,
        deletedRemote: 0,
        remoteDeletes: [_stale, _edited, _unknown],
      ),
    );

    expect(find.textContaining('云端报告已删除、本机仍留着 3 篇'), findsWidgets);
    expect(
      find.textContaining('1 篇自上次同步后一字未改（本机没有只此一份的内容）'),
      findsWidgets,
      reason: '无损那一类必须单独说，否则下一步会被当成「随便删哪边」',
    );
    expect(
      find.textContaining('1 篇在本机改过（删除与编辑撞上，两份都还在）'),
      findsWidgets,
    );
    expect(find.textContaining('1 篇无从比对（本机基线里没有它）'), findsWidgets);
    expect(
      find.textContaining('本机没有删掉任何东西'),
      findsWidgets,
      reason: '这句话是本轮「只报告不动手」的承诺，必须真的出现在界面上',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('l10n 缺席时兜底文案仍在（不得退化成静默「同步完成」）', (tester) async {
    await _runSync(
      tester,
      const SyncResult(
        uploaded: 0,
        downloaded: 0,
        deletedRemote: 0,
        remoteDeletes: [_stale],
      ),
      withL10n: false,
    );

    expect(find.textContaining('云端报告已删除、本机仍留着 1 篇'), findsWidgets);
    expect(find.textContaining('这几篇接下来怎么处理仍要你定'), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('甲方案：被按住的复活上传要单独说清「不是失败、也没删本机」', (tester) async {
    await _runSync(
      tester,
      const SyncResult(
        uploaded: 0,
        downloaded: 0,
        deletedRemote: 0,
        remoteDeletes: [_stale],
        resurrectionSuppressedDocIds: ['stale'],
      ),
    );

    expect(find.textContaining('这些没有再推上云端'), findsWidgets);
    expect(
      find.textContaining('本机没有删掉任何东西'),
      findsWidgets,
      reason: '这句话既否掉「失败」的误读，也否掉「程序删了我的画布」的误读',
    );
    expect(
      find.textContaining('这条提示每轮都会继续出现'),
      findsWidgets,
      reason: '不说明它会重复出现，用户会以为已经调和完了',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有被按住的上传时，这句不得凭空出现', (tester) async {
    await _runSync(
      tester,
      const SyncResult(
        uploaded: 0,
        downloaded: 0,
        deletedRemote: 0,
        remoteDeletes: [_edited],
      ),
    );
    expect(find.textContaining('这些没有再推上云端'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有这类分叉时，摘要不得凭空出现该提示', (tester) async {
    await _runSync(
      tester,
      const SyncResult(uploaded: 1, downloaded: 0, deletedRemote: 0),
    );

    expect(find.textContaining('云端报告已删除'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
