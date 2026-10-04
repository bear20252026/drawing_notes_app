// keepBoth 云端副本没保住时的「摘要可见性」回归锁（本批诚实化修复）。
//
// SyncService 现在会为这类文档跳过上传并给出 SyncResult.unprotectedRemoteDocIds；
// 光有字段不够——设置页摘要必须把「本次没同步上去」说清楚，否则用户以为
// 「两者皆保留」已经生效。这里用桩控制器把结果直接喂给页面，锁两条：
// ①走 l10n 新键（zh arb 有文案）；②l10n 缺失时兜底文案仍在（不得静默）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _runSync(WidgetTester tester, _StubController controller) async {
  await tester.pumpWidget(
    _wrap(WebDavSyncSettingsPage(syncController: controller)),
  );
  await tester.pump(); // initState 的配置加载落地
  await tester.tap(find.text('立即同步'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('未能保护的云端副本进摘要：l10n 新键文案可见', (tester) async {
    await _runSync(
      tester,
      _StubController(
        const SyncResult(
          uploaded: 2,
          downloaded: 0,
          deletedRemote: 0,
          conflictedDocIds: ['c'],
          unprotectedRemoteDocIds: ['c'],
        ),
      ),
    );

    expect(
      find.textContaining('个云端副本暂时读不出来，为避免覆盖已跳过这几个文档的上传'),
      findsWidgets,
      reason: '跳过上传必须对用户可见，且给出可执行指引（口令 / 稍后再同步）',
    );
    expect(find.textContaining('请确认同步口令是否填回原值'), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('l10n 缺席时兜底文案仍在（不得退化成静默「同步完成」）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          syncController: _StubController(
            const SyncResult(
              uploaded: 0,
              downloaded: 0,
              deletedRemote: 0,
              unprotectedRemoteDocIds: ['c'],
            ),
          ),
        ),
        withL10n: false,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('立即同步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('为避免覆盖已跳过这几个文档的上传'), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有未能保护的副本时，摘要不得凭空出现该提示', (tester) async {
    await _runSync(
      tester,
      _StubController(
        const SyncResult(uploaded: 1, downloaded: 0, deletedRemote: 0),
      ),
    );
    expect(find.textContaining('云端副本暂时读不出来'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
