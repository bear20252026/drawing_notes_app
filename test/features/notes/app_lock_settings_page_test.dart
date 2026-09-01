// ============================================================================
// app_lock_settings_page_test.dart —— 应用锁设置页回归测试（2026-09-01）
// ============================================================================
//
// 说明：测试运行在桌面宿主（Windows），UnlockFlow 走桌面端
// TextField 对话框分支（PinPadCore 弹出层另有门组件测试覆盖）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/features/notes/presentation/app_lock_settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('未配置：开关显示未开启；两步设 PIN 后生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    expect(find.text('未开启'), findsOneWidget);

    // 开启 → 设置密码 → 确认密码。
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('设置密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('确认密码'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(service.isConfigured, isTrue);
    expect(await service.verify('1234'), isTrue);
    expect(find.text('已开启'), findsOneWidget);
  });

  testWidgets('两次输入不一致：不生效并提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(service.isConfigured, isFalse);
    expect(find.text('两次输入不一致，请重新设置'), findsOneWidget);
  });

  testWidgets('已配置：修改密码需先验证旧密码', (tester) async {
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

    // 输对旧密码：进入两步设置新密码流程。
    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();
    expect(find.text('设置密码'), findsOneWidget);
  });

  testWidgets('如实提示：忘记密码无法找回', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(home: AppLockSettingsPage(service: service)),
    );
    expect(find.text('忘记密码将无法找回（首版无找回机制），请牢记密码。'), findsOneWidget);
  });
}
