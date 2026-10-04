// 修复 1①的 UI 侧回归锁：换同步口令必须**在保存前**二次确认——
// 取消则已存口令一个字节都不改；确认才落盘。弹窗与提示都不回显口令原文。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

// 刻意不装 AppLocalizations.delegate：页面与弹窗全部落到中文兜底字面量，
// 断言不随文案改写而漂移（同 webdav_sync_mounted_guard_test 的口径）。
Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: child,
);

const _oldPassphrase = 'fixture-old-phrase';
const _newPassphrase = 'brand-new-phrase';

SyncController _controller(MemorySyncSecretStore secrets) => SyncController(
  configStore: WebDavConfigStore(),
  secretStore: secrets,
);

/// 先落一次盘，让配置里有盐、凭据库里有口令（等价于「云端已在用加密同步」）。
Future<String?> _seed(MemorySyncSecretStore secrets) async {
  final controller = _controller(secrets);
  await controller.save(
    baseUrl: 'https://dav.example.com/dn/',
    username: 'alice',
    password: 'pw',
    passphrase: _oldPassphrase,
  );
  return (await controller.loadConfig()).syncSalt;
}

Future<void> _pumpPage(WidgetTester tester, MemorySyncSecretStore secrets) async {
  await tester.pumpWidget(_wrap(WebDavSyncSettingsPage(syncController: _controller(secrets))));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// 同步密码框 = 第 4 个输入框（前三个：URL / 用户名 / WebDAV 密码）。
void _typeSecret(WidgetTester tester, String value) {
  tester
      .widgetList<TextField>(find.byType(TextField))
      .toList()[3]
      .controller!
      .text = value;
}

/// 口令原文不得出现在弹窗/提示文案里（输入框本身是用户刚敲的，不算外泄面）。
void _expectNoPassphraseLeak(WidgetTester tester) {
  for (final phrase in [_oldPassphrase, _newPassphrase]) {
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining(phrase),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(phrase),
      ),
      findsNothing,
    );
  }
}

void main() {
  testWidgets('换口令：出确认弹窗；取消后口令与配置都不变', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySyncSecretStore();
    final saltBefore = await _seed(secrets);
    await _pumpPage(tester, secrets);
    _typeSecret(tester, _newPassphrase);
    await tester.pump();

    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    // 说清后果的二次确认文案必须出现（不是泛泛的「确定要保存吗」）。
    expect(find.text('确认更换同步口令？'), findsOneWidget);
    expect(find.textContaining('无法再解密'), findsOneWidget);
    expect(find.textContaining('全量重新上传'), findsOneWidget);
    // 弹窗文案不回显口令（S-03 不回填纪律在弹窗侧同样成立）。
    _expectNoPassphraseLeak(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect((await secrets.read()).syncPassphrase, _oldPassphrase);
    expect((await _controller(secrets).loadConfig()).syncSalt, saltBefore);
    expect(find.textContaining('同步口令保持原值'), findsOneWidget);
    _expectNoPassphraseLeak(tester);
  });

  testWidgets('换口令：确认后才落盘，盐仍复用（成因不变，只是如实告知）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySyncSecretStore();
    final saltBefore = await _seed(secrets);
    await _pumpPage(tester, secrets);
    _typeSecret(tester, _newPassphrase);
    await tester.pump();

    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仍要更换并重新上传'));
    await tester.pumpAndSettle();

    expect((await secrets.read()).syncPassphrase, _newPassphrase);
    expect((await _controller(secrets).loadConfig()).syncSalt, saltBefore);
    expect(find.textContaining('已保存 WebDAV 配置'), findsOneWidget);
    _expectNoPassphraseLeak(tester);
  });

  testWidgets('首次设口令（云端还没有本密钥体系的密文）→ 不打扰', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySyncSecretStore();
    await _pumpPage(tester, secrets);
    _typeSecret(tester, _newPassphrase);
    await tester.pump();

    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(find.text('确认更换同步口令？'), findsNothing);
    expect((await secrets.read()).syncPassphrase, _newPassphrase);
  });

  testWidgets('留空保存（沿用已存）→ 不打扰', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySyncSecretStore();
    await _seed(secrets);
    await _pumpPage(tester, secrets);

    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();

    expect(find.text('确认更换同步口令？'), findsNothing);
    expect((await secrets.read()).syncPassphrase, _oldPassphrase);
  });
}
