// ============================================================================
// app_lock_settings_page_test.dart —— 应用锁设置页回归测试（2026-09-01）
// ============================================================================
//
// 说明：测试运行在桌面宿主（Windows），UnlockFlow 走桌面端
// TextField 对话框分支（PinPadCore 弹出层另有门组件测试覆盖）。
// 批次②：设置流程前插入「密码长度」选择器（4–12 位）；
// 收集模式按钮文案为「确定」（验证模式仍为「解锁」）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/features/notes/presentation/app_lock_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // testWidgets 跑在 FakeAsync zone——Isolate KDF 永不完成，注入轻量档防挂起。
  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
  });

  /// 走过「密码长度」选择器（默认 4 位，直接下一步）。
  Future<void> confirmLength(tester) async {
    expect(find.text('密码长度'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
  }

  testWidgets('未配置：开关显示未开启；选长度→两步设 PIN 后生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    expect(find.text('未开启'), findsOneWidget);

    // 开启 → 密码长度选择器 → 设置密码 → 确认密码。
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await confirmLength(tester);
    expect(find.text('设置密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('确认密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(service.isConfigured, isTrue);
    expect(await service.verify('1234'), isTrue);
    expect(service.pinLength, 4);
    expect(find.text('已开启'), findsOneWidget);
  });

  testWidgets('选择非默认长度：PIN 长度持久化跟随', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    // 拖动 Slider（值域 4–12）：往右拖一段，落点即所选长度。
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();

    // 精确匹配「N 位」大字展示（不匹配「建议 N 位以上…」提示）。
    final shown = tester.firstWidget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text && w.data != null && RegExp(r'^\d+ 位$').hasMatch(w.data!),
      ),
    );
    final length = int.parse(shown.data!.split(' ').first);
    expect(length, inInclusiveRange(4, 12));
    expect(
      length,
      isNot(AppLockService.defaultPinLength),
      reason: '往右拖后应离开默认 4 位',
    );

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    final pin = '1' * length;
    await tester.enterText(find.byType(TextField), pin);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), pin);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(service.isConfigured, isTrue);
    expect(service.pinLength, length);
  });

  testWidgets('两次输入不一致：不生效并提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await confirmLength(tester);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(service.isConfigured, isFalse);
    expect(find.text('两次输入不一致，请重新设置'), findsOneWidget);
  });

  testWidgets('已配置：修改密码需先验证旧密码（验证模式按钮仍为「解锁」）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();
    await service.setPin('0000');

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);

    await tester.tap(find.text('修改密码'));
    await tester.pumpAndSettle();
    expect(find.text('验证当前密码'), findsOneWidget);

    // 输错旧密码：桌面端原地显示错误、对话框不关闭，锁不被关闭。
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('密码不正确'), findsOneWidget);
    expect(find.text('设置密码'), findsNothing);
    expect(service.isConfigured, isTrue);
    expect(await service.verify('0000'), isTrue);

    // 输对旧密码：进入长度选择 → 两步设置新密码流程。
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    await confirmLength(tester);
    expect(find.text('设置密码'), findsOneWidget);
  });

  testWidgets('长度选择器可取消：不进入设密流程', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('密码长度'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('设置密码'), findsNothing);
    expect(service.isConfigured, isFalse);
  });

  testWidgets('如实提示：未配置时引导绑定重置密码盘', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    expect(find.text('开启应用锁后，可绑定重置密码盘以防忘记密码。'), findsOneWidget);
    // 未配置时不展示重置密码盘 tile（需要 vault + 已开启应用锁）。
    expect(find.text('重置密码盘'), findsNothing);
  });

  testWidgets('已配置未绑定：提示未绑定无法找回', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();
    await service.setPin('135790');

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    expect(
      find.text('绑定重置密码盘后，忘记密码可用它重置；未绑定时忘记密码将无法找回。'),
      findsOneWidget,
    );
  });
}
