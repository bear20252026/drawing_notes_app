// 真机锁定/生命周期集成用例（台账 §六 开放项 1，2026-10-10 落地）。
//
// 前置：AW21 数据根隔离口 `--dart-define=DRAWING_NOTES_DATA_ROOT`（仅 debug
// 生效、跳过旧位置迁移、define 值即根本身）。**安全闩**：第一个断言先核对
// 数据根 == 隔离路径，define 一旦失效（误用 profile 构建等）用例当场失败，
// 应用尚未 pump、真实库零写入——绝不重演 2026-10-08「测试写用户画布库」。
//
// 覆盖（与 app_lock_gate_test 单测互补的是「真机上的完整进程链」）：
//   ① 冷启动即锁：已配置 PIN 的真机冷启动直接见到锁屏，正确 PIN 放行；
//   ② 宽限 0：切后台（inactive）立即回锁，回前台必须重新验证；
//   ③ 宽限 30：瞬时切后台再回前，宽限内自动放行（无锁屏闪现）。
//
// 运行方式（会弹出被测窗口，需本人在场）：
//   flutter test integration_test/app_lock_lifecycle_test.dart -d windows \
//     --dart-define=DRAWING_NOTES_DATA_ROOT=D:/Workbuddy/tmp_lock_e2e
//
// PIN 走 SharedPreferences mock（smoke_test 同款先例——真机上 mock 照样
// 生效），不落真实 prefs；KDF 走 testLight 档（生命周期语义验证，非 KDF
// 强度验证——真 Argon2id 生产档会让每条用例白等数秒）。
import 'dart:io';

import 'package:drawing_notes_app/app.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _pin = '135790';

/// 必须与运行命令的 --dart-define 值逐字一致（AppDataRoot 语义③：值即根）。
const String _isoRoot = 'D:/Workbuddy/tmp_lock_e2e';

Future<void> _seedPin(int graceSeconds) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_seen_v1': true,
    'app_lock.grace_seconds': graceSeconds,
  });
  final service = AppLockService();
  await service.setPin(_pin);
}

/// 轮询等待 finder 达到期望的存在性（真机集成测试的帧泵与真实异步不同步：
/// 建保险库的生产档 Argon2id 在真 isolate 里跑约 1-2s，期间无帧可泵，
/// pumpAndSettle 会提前返回——首解锁必须轮询，不能单发 settle）。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder,
  bool present, {
  String? reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty == present) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('等待超时（${present ? '应出现' : '应消失'}）: $finder${reason == null ? '' : ' —— $reason'}');
}

/// 九宫格逐位点按（与 app_lock_gate_test 单测同一驱动方式；桌面宿主九宫格
/// 与键盘槽并存，鼠标/触屏通道不删）。
Future<void> _enterPinByGrid(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.text(d));
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue =
      const Locale('zh');
  TestWidgetsFlutterBinding.instance.platformDispatcher.localesTestValue = const [
    Locale('zh'),
  ];

  setUpAll(() async {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    final stale = Directory(_isoRoot);
    if (stale.existsSync()) await stale.delete(recursive: true);
  });

  tearDownAll(() {
    AppLockService.testPinKdfOverride = null;
  });

  Future<Directory> pumpApp(WidgetTester tester, int graceSeconds) async {
    await _seedPin(graceSeconds);
    // 安全闩（先断言后 pump）：根不是隔离路径就 abort，真实库零写入。
    final root = await AppDataRoot().root();
    expect(
      root.path.replaceAll('\\', '/'),
      _isoRoot,
      reason:
          '数据根不是隔离路径——dart-define 未生效（误用 profile 构建？）。'
          '继续跑会写用户真实库，必须中止。',
    );
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();
    return root;
  }

  testWidgets('① 冷启动即锁：锁屏在位，正确 PIN 放行', (tester) async {
    await pumpApp(tester, 0);

    expect(find.text('输入密码'), findsOneWidget, reason: '已配置 PIN 的冷启动必须先见锁屏');

    await _enterPinByGrid(tester, _pin);
    await _waitFor(tester, find.text('输入密码'), false, reason: '正确 PIN 后锁屏撤下（含建保险库耗时）');
    expect(find.text('全部文档'), findsWidgets, reason: '回到主工作台');
  });

  testWidgets('② 宽限 0：切后台立即回锁，回前台必须重新验证', (tester) async {
    await pumpApp(tester, 0);
    await _enterPinByGrid(tester, _pin);
    await _waitFor(tester, find.text('输入密码'), false);

    // 切后台（真实引擎事件在窗口保持焦点时不会自发到来，按合法状态机驱动）。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _waitFor(tester, find.text('输入密码'), true, reason: '宽限 0：inactive 即回锁');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('输入密码'),
      findsOneWidget,
      reason: '宽限 0：回前台不自动放行，必须重新验证',
    );
    await _enterPinByGrid(tester, _pin);
    await _waitFor(tester, find.text('输入密码'), false, reason: '重验后放行');
  });

  testWidgets('③ 宽限 30：瞬时切后台回前，宽限内自动放行不闪锁', (tester) async {
    await pumpApp(tester, 30);
    await _enterPinByGrid(tester, _pin);
    expect(find.text('输入密码'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _waitFor(tester, find.text('输入密码'), true, reason: '切后台置锁（真锁，UI 门盖上）');

    // 瞬时回前（away ≈ 0 < 30s）——门在 resumed 自动撤锁屏（2026-10-04
    // 语义：置锁与放行同帧合并，宽限内用户直接看到内容，无闪现）。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsNothing, reason: '宽限内回来必须免重输');
    expect(find.text('全部文档'), findsWidgets);
  });
}
