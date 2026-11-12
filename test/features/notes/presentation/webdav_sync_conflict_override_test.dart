// SYNC-003 设置页接线锁：改判在**下一轮**自动生效，而且不静默。
//
// 这是「改判」从数据到行为的唯一一段接线，两条判据都可失败且都不会报错：
//  ① 有长期改判的那篇再冲突时，**不再弹裁决窗**，直接按改判走；
//  ② 自动处理的那部分必须在摘要里**单独说**——「已按你的选择处理」在改判
//     场景下是假的（这轮用户根本没选），把两者混成一句就是静默覆盖的措辞版。
//
// 另有两条反向锁：没有改判的文档照常见窗；同一轮里「改判的自动走 + 没改判
// 的问一次」可以并存（真实场景就是一篇设了、一篇新冲突）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/conflict_resolution_dialog.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import '../../../helpers/wait_until.dart';

const _docA = 'doc-a';
const _docB = 'doc-b';

const _cfg = WebDavSyncConfig(
  baseUrl: 'https://dav.example.com/x/',
  username: 'u',
  syncSalt: 'c2FsdA==',
);
const _secrets = SyncSecrets(webdavPassword: 'w', syncPassphrase: 'p');

SyncConflict _conflict(String docId) => SyncConflict(
  docId: docId,
  localUpdatedAt: 17000000020000,
  localSize: 120,
  remoteUpdatedAt: 17000000010000,
  remoteSize: 140,
);

ConflictLedgerEntry _entry(
  String docId,
  ConflictResolution? override,
) => ConflictLedgerEntry(
  docId: docId,
  firstDetectedAtMs: 1700000000000,
  lastDetectedAtMs: 1700000000000,
  count: 1,
  lastConflict: _conflict(docId),
  resolutionOverride: override,
  overriddenAtMs: override == null ? null : 1700000000001,
);

/// 桩控制器：把 `syncNow` 收到的 conflictHandler 揪出来直接驱动，
/// 从而绕开真实网络（本页的装配收口在 SyncController，这里只测接线）。
class _StubController extends SyncController {
  _StubController({List<ConflictLedgerEntry> ledger = const []})
    : super(
        configStore: WebDavConfigStore(),
        secretStore: MemorySyncSecretStore(_secrets),
      ) {
    _ledger = ledger;
  }

  late List<ConflictLedgerEntry> _ledger;

  /// 本轮「检测到」的冲突（由用例设定）。
  List<SyncConflict> pending = const [];

  /// handler 实际返回的裁决（用例断言用）。
  Map<String, ConflictResolution> handlerResult = const {};

  bool handlerCalled = false;

  @override
  Future<WebDavSyncConfig> loadConfig() async => _cfg;

  @override
  Future<SyncSecrets> readSecrets() async => _secrets;

  @override
  Future<List<ConflictLedgerEntry>> loadConflictLedger() async => _ledger;

  @override
  Future<void> setConflictResolutionOverride(
    String docId,
    ConflictResolution? resolution,
  ) async {
    _ledger = [
      for (final e in _ledger)
        if (e.docId != docId) e,
      if (resolution != null) _entry(docId, resolution),
    ];
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
    if (pending.isEmpty) return (result: _emptyResult, error: null);
    handlerCalled = true;
    handlerResult = await conflictHandler.resolve(pending);
    return (
      result: SyncResult(
        uploaded: 0,
        downloaded: 1,
        deletedRemote: 0,
        conflictedDocIds: [for (final c in pending) c.docId],
        conflicts: [
          for (final c in pending)
            c.copyWith(
              resolvedResolution:
                  handlerResult[c.docId] ?? c.suggestedResolution,
            ),
        ],
      ),
      error: null,
    );
  }
}

const _emptyResult = SyncResult(
  uploaded: 0,
  downloaded: 0,
  deletedRemote: 0,
);

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

bool _formBuilt() => find.text('保存配置').evaluate().isNotEmpty;

/// 页面是 ListView，台账一长「立即同步」就被推出视口（懒构建 ⇒ find 也找不到）。
/// 先滚到它再点——真实用户也是这么做的。
Future<void> _tapSyncNow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('立即同步'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('立即同步'));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpPage(WidgetTester tester, _StubController controller) async {
    await tester.pumpWidget(_wrap(WebDavSyncSettingsPage(syncController: controller)));
    await tester.pump();
    await tester.pumpUntil(_formBuilt);
  }

  testWidgets('有长期改判的那篇再冲突 → 不再问，直接按改判走', (tester) async {
    final controller = _StubController(
      ledger: [_entry(_docA, ConflictResolution.keepLocal)],
    )..pending = [_conflict(_docA)];
    await pumpPage(tester, controller);

    await _tapSyncNow(tester);
    await tester.pump();
    await tester.pumpUntil(() => find.byType(SnackBar).evaluate().isNotEmpty);

    expect(controller.handlerCalled, isTrue);
    expect(controller.handlerResult, {
      _docA: ConflictResolution.keepLocal,
    });
    // 没有弹裁决窗（标题只在真问的时候出现）。
    expect(find.textContaining('同步冲突'), findsNothing);
    // 自动处理的那部分必须单独说出来。摘要同时出现在常驻的页内摘要和
    // SnackBar 里（同一条文本的两个载体），所以是 findsWidgets 而不是 1。
    expect(find.textContaining('本轮没有再问你'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没设改判的那篇 → 照常见窗问一次', (tester) async {
    final controller = _StubController()..pending = [_conflict(_docB)];
    await pumpPage(tester, controller);

    await _tapSyncNow(tester);
    await tester.pump();
    await tester.pumpUntil(() => find.textContaining('同步冲突').evaluate().isNotEmpty);

    expect(find.textContaining('同步冲突'), findsOneWidget);
    expect(controller.handlerResult, isEmpty, reason: '用户还没选，handler 不该有结果');
  });

  testWidgets('同一轮：改判的自动走 + 没改判的问一次，两者并存', (tester) async {
    final controller = _StubController(
      ledger: [_entry(_docA, ConflictResolution.keepLocal)],
    )..pending = [_conflict(_docA), _conflict(_docB)];
    await pumpPage(tester, controller);

    await _tapSyncNow(tester);
    await tester.pump();
    await tester.pumpUntil(() => find.textContaining('同步冲突').evaluate().isNotEmpty);

    // 弹窗里只该有 doc-b 那一篇（doc-a 已被改判自动处理）。
    // 注意 doc-a 仍出现在下方的台账行里，所以必须把范围限在弹窗内。
    expect(
      find.descendant(
        of: find.byType(ConflictResolutionDialog),
        matching: find.text(_docA),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(ConflictResolutionDialog),
        matching: find.text(_docB),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('应用全部'));
    await tester.pumpUntil(() => find.byType(SnackBar).evaluate().isNotEmpty);

    expect(controller.handlerResult[_docA], ConflictResolution.keepLocal);
    expect(controller.handlerResult[_docB], isNotNull);
    // 一篇自动 + 一篇手动 ⇒ 摘要里两句都在（页内摘要 + SnackBar 两份）。
    expect(find.textContaining('本轮没有再问你'), findsWidgets);
    expect(find.textContaining('已按你的选择处理'), findsWidgets);
  });

  testWidgets('台账为空时：设置页渲染出冲突记录区（空块不占位）', (tester) async {
    final controller = _StubController();
    await pumpPage(tester, controller);

    expect(find.text('冲突记录'), findsNothing);
    expect(find.text(_docA), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
