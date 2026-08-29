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
}
