// ============================================================================
// app_lock_gate_test.dart —— 应用启动锁门回归测试（2026-09-01）
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_gate.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';

Future<AppLockService> _configuredService(String pin) async {
  SharedPreferences.setMockInitialValues({});
  final service = AppLockService();
  await service.setPin(pin);
  return service;
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  // 输满后异步校验 + 失败抖动动画，等其完成。
  await tester.pumpAndSettle();
}

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

  testWidgets('未配置 PIN：不锁屏，内容直接可见', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = AppLockService();

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsNothing);
    expect(find.text('SECRET_HOME'), findsOneWidget);
  });

  testWidgets('冷启动已配置 PIN：显示锁屏，正确 PIN 解锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsOneWidget);

    await _enterPin(tester, '1357');

    expect(find.text('输入密码'), findsNothing);
    expect(find.text('SECRET_HOME'), findsOneWidget);
  });

  testWidgets('错误 PIN：抖动清空，仍锁定；随后正确输入可解锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();

    await _enterPin(tester, '2468');
    expect(find.text('输入密码'), findsOneWidget);

    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });

  testWidgets('切后台回锁（宽限关闭）：解锁后 app 退到后台再回来必须重新解锁', (
    tester,
  ) async {
    final service = await _configuredService('1357');
    await service.setGraceSeconds(0); // 关闭宽限 = 旧行为

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // 应用退到后台（paused）→ 回到前台即锁。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsOneWidget);
  });

  testWidgets('宽限期（默认 30s）：瞬时切后台回来免重新解锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // Windows 任务视图扫一眼：立即回来（真实秒表 ≈ 0s < 30s）→ 不弹锁屏。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsNothing);
    expect(find.text('SECRET_HOME'), findsOneWidget);
  });

  testWidgets('宽限期超时（离开 > 30s）：回来仍须重新解锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        // awayDurationReader 注入模拟「离开 31s」（真实秒表无法快进）。
        home: AppLockGate(
          service: service,
          awayDurationReader: () => const Duration(seconds: 31),
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsOneWidget);

    // 超宽限锁定后：连续快切不重置资格，须输 PIN 解锁。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsOneWidget);

    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });

  testWidgets('冷启动锁定不吃宽限期（未解锁即切后台再回来仍锁）', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();
    // 冷启动：锁屏在场、尚未解锁。
    expect(find.text('输入密码'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // 不是「切后台触发的锁定」→ 宽限不适用，锁屏仍在。
    expect(find.text('输入密码'), findsOneWidget);
  });

  testWidgets('设置页关闭应用锁（disable 通知）→ 锁屏立即放行', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(service: service, child: const Text('SECRET_HOME')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsOneWidget);

    await service.disable();
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsNothing);
    expect(find.text('SECRET_HOME'), findsOneWidget);
  });
}
