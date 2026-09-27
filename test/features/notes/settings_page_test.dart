// 批次⑤：第四界面「设置」——密码体系集中管理测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/theme/app_locale_controller.dart';
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

    testWidgets('语言入口：注入控制器后显示，点击三态循环', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = AppLocaleController();

      // 生产装配：app.dart 的 ListenableBuilder 监听控制器重建整树——
      // SettingsPage 为 StatelessWidget，测试须镜像同一 rebuild 通道。
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => SettingsPage(localeController: controller),
          ),
        ),
      );
      expect(find.text('语言'), findsOneWidget);
      expect(find.textContaining('跟随系统'), findsOneWidget);

      await tester.tap(find.text('语言'));
      await tester.pump();
      expect(controller.locale, const Locale('zh'));
      expect(find.textContaining('点击切换为 English'), findsOneWidget);

      await tester.tap(find.text('语言'));
      await tester.pump();
      expect(controller.locale, const Locale('en'));
      expect(find.textContaining('点击切换为跟随系统'), findsOneWidget);
    });

    testWidgets('诊断导出入口默认可见（无需注入控制器）', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      expect(find.text('导出诊断信息'), findsOneWidget);
      expect(find.text('脱敏日志，帮助排查问题'), findsOneWidget);
    });

    testWidgets('备份/恢复入口：注入数据根后显示，未注入隐藏（批次 M）', (tester) async {
      SharedPreferences.setMockInitialValues({});

      // 未注入 AppDataRoot：两行隐藏（测试装配兼容）。
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      expect(find.text('备份全部数据'), findsNothing);
      expect(find.text('从备份恢复'), findsNothing);

      // 注入后可见（不点按——打包/恢复流涉及文件选择器，服务级测试覆盖）。
      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(appDataRoot: AppDataRoot())),
      );
      expect(find.text('备份全部数据'), findsOneWidget);
      expect(find.text('从备份恢复'), findsOneWidget);
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
