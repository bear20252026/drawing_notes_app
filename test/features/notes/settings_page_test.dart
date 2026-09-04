// 批次⑤：第四界面「设置」——密码体系集中管理测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/notes/presentation/app_lock_settings_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/settings_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // testWidgets 跑在 FakeAsync zone——后台 isolate 结果永不回投：
  // 轻量 KDF 档 + 同 isolate 直派生双保险（生产 isolate 路径不受影响）。
  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  group('SettingsPage（密码体系集中管理）', () {
    testWidgets('渲染密码体系卡 + 两大分组', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();

      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(appLockService: service)),
      );

      // 密码体系卡：标题 + 两层锁 + 重置密码盘。
      expect(find.text('密码体系'), findsOneWidget);
      expect(find.text('第 1 层 · 开屏密码'), findsOneWidget);
      expect(find.text('第 2 层 · 文件密码'), findsOneWidget);
      expect(find.text('重置密码盘（U 盘）'), findsOneWidget);

      // 密码与安全分组：应用锁 / 单文件密码（密码盘入口已删除）。
      expect(find.text('应用锁'), findsOneWidget);
      expect(find.text('单文件密码'), findsOneWidget);
      expect(find.text('密码盘与恢复'), findsNothing);

      // 通用分组：WebDAV（外观需要控制器注入，未注入时隐藏）。
      expect(find.text('WebDAV 同步'), findsOneWidget);
      expect(find.text('外观'), findsNothing);
    });

    testWidgets('应用锁入口：推入 AppLockSettingsPage（透传 vault）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      final vault = VaultKeyService();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(appLockService: service, vaultKeyService: vault),
        ),
      );
      await tester.tap(find.text('应用锁'));
      await tester.pumpAndSettle();

      expect(find.byType(AppLockSettingsPage), findsOneWidget);
    });

    testWidgets('WebDAV 入口：推入 WebDavSyncSettingsPage', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(appLockService: AppLockService())),
      );
      // WebDAV 项在首屏折叠线以下：滚动到可见、取 ListTile 中心点击。
      final webdavTile = find.ancestor(
        of: find.text('WebDAV 同步'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(webdavTile);
      await tester.pumpAndSettle();
      await tester.tap(webdavTile, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(WebDavSyncSettingsPage), findsOneWidget);
    });

    testWidgets('外观入口：注入控制器后显示，点击循环模式', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppThemeController();

      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(themeController: controller)),
      );
      expect(find.text('外观'), findsOneWidget);
      final before = controller.mode;

      await tester.tap(find.text('外观'));
      await tester.pump();
      expect(controller.mode, isNot(before));
    });

    testWidgets('单文件密码：帮助弹窗展示说明', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(appLockService: AppLockService())),
      );
      await tester.tap(find.text('单文件密码'));
      await tester.pumpAndSettle();

      expect(find.text('单文件密码'), findsWidgets); // 列表项 + 弹窗标题
      // 「锁形占位」只在弹窗文案出现（「独立于开屏密码」会同时命中
      // 密码体系卡第 2 层描述，故用弹窗专属词断言）。
      expect(find.textContaining('锁形占位'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('知道了'), findsNothing);
    });
  });
}
