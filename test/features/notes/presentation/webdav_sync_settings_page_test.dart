// M10-B 冒烟测试：WebDavSyncSettingsPage 渲染骨架 + 表单字段。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: child,
  );
}

void main() {
  testWidgets('WebDavSyncSettingsPage 渲染：表单字段 + 按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          configStore: WebDavConfigStore(),
          secretStore: MemorySyncSecretStore(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('WebDAV 同步'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('立即同步'), findsOneWidget);
  });

  // S-03（审计 2026-09-27）方案 A：口令不回填控制器。
  //
  // 回归锁一：明文驻留 = 本审计条目的全部问题——`TextEditingController`
  // 持有的字符串绕过 `SessionSecrets.clearAll()`（切后台只清各 store 的
  // 会话缓存，清不到 widget 树），堆转储可直接读出。故断言输入框必须为空、
  // 且存在性只以占位提示呈现。
  testWidgets('S-03：已存口令不回填输入框，改用占位提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemorySyncSecretStore(
      const SyncSecrets(
        webdavPassword: 'secret-webdav-pass',
        syncPassphrase: 'secret-sync-passphrase',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          configStore: WebDavConfigStore(),
          secretStore: store,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    // 密码 / 同步口令是第 3、4 个输入框（前两个是 URL / 用户名）。
    expect(fields[2].controller!.text, isEmpty);
    expect(fields[3].controller!.text, isEmpty);
    // 明文绝不出现在任何可见文本里。
    expect(find.text('secret-webdav-pass'), findsNothing);
    expect(find.text('secret-sync-passphrase'), findsNothing);
    // 存在性以占位提示呈现（hintText 只在框空时渲染，此处两框皆空）。
    expect(find.text('已保存 · 留空保持不变'), findsNWidgets(2));
  });

  // 回归锁二：空值 = 沿用已存。方案 A 把「未改」与「清空」合并成了空值，
  // 若哪天有人把保存写回成 `空 → null`，用户留空点保存就会静默抹掉口令，
  // 下一次同步直接认证失败。这条锁死「留空保存后原值仍在」。
  testWidgets('S-03：留空点保存，已存口令不被抹掉', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemorySyncSecretStore(
      const SyncSecrets(
        webdavPassword: 'secret-webdav-pass',
        syncPassphrase: 'secret-sync-passphrase',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          configStore: WebDavConfigStore(),
          secretStore: store,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('保存配置'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final saved = await store.read();
    expect(saved.webdavPassword, 'secret-webdav-pass');
    expect(saved.syncPassphrase, 'secret-sync-passphrase');
  });

  // 回归锁三：输入新值覆盖旧值——确保「留空沿用」没有把覆盖能力一起关掉。
  testWidgets('S-03：输入新口令覆盖旧值', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemorySyncSecretStore(
      const SyncSecrets(webdavPassword: 'old-pass', syncPassphrase: 'old-passphrase'),
    );
    await tester.pumpWidget(
      _wrap(
        WebDavSyncSettingsPage(
          configStore: WebDavConfigStore(),
          secretStore: store,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    // 直接写 controller：两个口令框当前为空，按 index 定位最稳
    //（enterText 需要先 focus，空框无法用 find.widgetWithText 唯一定位）。
    fields[2].controller!.text = 'new-pass';
    fields[3].controller!.text = 'new-passphrase';
    await tester.pump();

    await tester.tap(find.text('保存配置'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final saved = await store.read();
    expect(saved.webdavPassword, 'new-pass');
    expect(saved.syncPassphrase, 'new-passphrase');
  });
}
