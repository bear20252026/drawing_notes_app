// ============================================================================
// app_lock_gate_test.dart —— 应用启动锁门回归测试（2026-09-01）
// ============================================================================
//
// 生命周期用例的驱动纪律（2026-10-03 修）：一律走 [_toBackground]/[_toForeground]
// 的完整链路，不许再直接 `paused`/`resumed` 跳变——原因见那两个函数。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_gate.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/session_guard.dart'
    show LockExemption;

/// 走**合法状态机链路**切到后台：resumed → inactive → hidden → paused。
///
/// 为什么不能像旧用例那样直接投 `paused`：Flutter 3.13+ 起
/// `AppLifecycleListener.didChangeAppLifecycleState` 在 debug 下断言状态机
/// 顺序，`paused` 只接受 `null`/`hidden` 作前态（框架源码
/// `widgets/app_lifecycle_listener.dart:255-259`），`resumed` 只接受
/// `null`/`inactive`/`detached`（同文件 :222-229）。而**凡树里有输入框就有一个
/// 活的监听器**——`EditableTextState.initState` 注册（框架源码
/// `widgets/editable_text.dart:3320`）、`dispose` 注销（:3628），监听器的
/// `_lifecycleState` 还以注册那一刻的 `binding.lifecycleState` 为种子。
/// 锁屏自本批起在桌面宿主上叠了物理键盘槽（`_DesktopPinField` 的
/// `TextField`），于是「解锁→切后台」的树里多了这个框架监听器，旧的
/// resumed→paused 快进法被框架断言捕获并报
/// 「EXCEPTION CAUGHT BY WIDGETS LIBRARY … Invalid state transition」，
/// 用例随即被判失败（真实操作系统投递的正是本函数的完整链路，故这不是
/// 产品缺陷而是测试驱动序列不合契约）。
Future<void> _toBackground(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

/// 走**合法状态机链路**回到前台：paused → hidden → inactive → resumed。
///
/// 宽限判定仍只看 `paused`（起表）与 `resumed`（读数）两端——中间态
/// `inactive`/`hidden` 不参与锁定/放行决策（`hidden` 只清敏感缓存），
/// 故本函数不改变「离开多久算超宽限」的语义。
Future<void> _toForeground(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

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
    // 豁免窗口是进程级静态——每个用例前后复位，防串味。
    LockExemption.resetForTest();
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
    LockExemption.resetForTest();
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

  testWidgets('切后台回锁（宽限关闭）：解锁后 app 退到后台再回来必须重新解锁', (tester) async {
    final service = await _configuredService('1357');
    await service.setGraceSeconds(0); // 关闭宽限 = 旧行为

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          // 固定开启桌面键盘槽：让本文件的生命周期链路在任何宿主上都被
          // 真实演练（槽在场 = 树里有一个框架内建 AppLifecycleListener）。
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // 回归锁「离开树即注销监听」：解锁后锁屏子树必须整棵撤下——若残留
    // TextField/EditableText，框架内建监听器就仍在册，后续生命周期事件会
    // 派发到已卸载页面的监听器上（本轮失败的同族形态）。
    expect(find.byType(TextField), findsNothing);

    // 应用退到后台（paused）→ 回到前台即锁。
    await _toBackground(tester);
    await _toForeground(tester);

    expect(find.text('输入密码'), findsOneWidget);
    // 键盘通道不获得旁路：冷却/验证仍只有九宫格那一条 service.verify 管线，
    // 锁屏在场时键盘槽与九宫格并存（鼠标/触屏入口不删）。
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('宽限期（默认 30s）：瞬时切后台回来免重新解锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // Windows 任务视图扫一眼：立即回来（真实秒表 ≈ 0s < 30s）→ 不弹锁屏。
    await _toBackground(tester);
    await _toForeground(tester);

    expect(find.text('输入密码'), findsNothing);
    expect(find.text('SECRET_HOME'), findsOneWidget);
    // 宽限放行同样把锁屏子树（含键盘槽/其框架监听器）连根撤掉。
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('宽限期超时（离开 > 30s）：回来仍须重新解锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        // awayDurationReader 注入模拟「离开 31s」（真实秒表无法快进）。
        home: AppLockGate(
          service: service,
          awayDurationReader: () => const Duration(seconds: 31),
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    await _toBackground(tester);
    await _toForeground(tester);

    expect(find.text('输入密码'), findsOneWidget);

    // 超宽限锁定后：连续快切不重置资格，须输 PIN 解锁。
    await _toBackground(tester);
    await _toForeground(tester);
    expect(find.text('输入密码'), findsOneWidget);

    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });

  testWidgets('冷启动锁定不吃宽限期（未解锁即切后台再回来仍锁）', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 冷启动：锁屏在场、尚未解锁（键盘槽在场 ⇒ 框架监听器以锁屏在场态
    // 全程在册，本用例即验证这种形态下不吃宽限）。
    expect(find.text('输入密码'), findsOneWidget);

    await _toBackground(tester);
    await _toForeground(tester);

    // 不是「切后台触发的锁定」→ 宽限不适用，锁屏仍在。
    expect(find.text('输入密码'), findsOneWidget);
  });

  testWidgets('设置页关闭应用锁（disable 通知）→ 锁屏立即放行', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsOneWidget);

    await service.disable();
    await tester.pumpAndSettle();

    expect(find.text('输入密码'), findsNothing);
    expect(find.text('SECRET_HOME'), findsOneWidget);
  });

  // ==========================================================================
  // 「切后台与最小化全量锁定」回归（2026-10-04 安全策略变更）。
  // ==========================================================================

  // ① 桌面纯失焦（仅 inactive，桌面从不投递 paused）：必须置锁并回前台重解锁。
  testWidgets('①仅 inactive 即锁：桌面纯失焦回前台须重新解锁', (tester) async {
    final service = await _configuredService('1357');
    await service.setGraceSeconds(0); // 关宽限，让「回前台仍锁」不依赖真实秒表

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // 只投 inactive（不经过 hidden/paused）——Windows「焦点切走、窗口仍可见」
    // 的真实形态。旧版门只认 paused ⇒ 此路径根本不锁；本批须锁。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('输入密码'), findsOneWidget); // 失焦即锁（隐藏内容）

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsOneWidget); // 回前台仍锁，须重解锁
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });

  // ② hidden（最小化）：随最小化链置锁，且保留「hidden 即清 KEK」的既有加固
  //    （不倒退）。注：hidden/paused 会关闭帧渲染，锁屏要到 resumed 才可见，
  //    故锁屏断言放在回前台后；KEK 清理是同步副作用，可在后台态即时断言。
  testWidgets('②最小化链锁定 + hidden 清 KEK 行为不倒退', (tester) async {
    final service = await _configuredService('1357');
    await service.setGraceSeconds(0); // 关宽限：回前台仍锁，不依赖真实秒表

    KekSessionCache.instance.clear(); // 归零起点
    await KekSessionCache.instance.deriveKek('seed', const [
      1,
      2,
      3,
    ], KdfParams.testLight);
    expect(KekSessionCache.instance.entryCount, greaterThan(0));

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // 最小化链（resumed→inactive→hidden→paused，Windows 真实形态）。
    await _toBackground(tester);
    // 行为保持：hidden 那一步即清 KEK（N3/审计 M-05），与是否渲染无关。
    expect(KekSessionCache.instance.entryCount, 0);

    await _toForeground(tester);
    expect(find.text('输入密码'), findsOneWidget); // 最小化 → 锁定（关宽限仍锁）
  });

  // ③ 同一后台会话 inactive+hidden(+paused) 双/三信号：宽限期锚在首个，
  //    后续信号不重置成「免锁」——超宽限回前台仍锁（既有「连续快切不重置
  //    资格」断言的同一会话版本）。
  testWidgets('③同一后台会话多信号不重置宽限期（超宽限仍锁）', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          // reader 恒「已超宽限」：证明第二/第三个信号没有把窗口刷新成免锁。
          awayDurationReader: () => const Duration(seconds: 40),
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');

    await _toBackground(tester); // inactive→hidden→paused，同一会话
    await _toForeground(tester);

    expect(find.text('输入密码'), findsOneWidget); // 锚在首个，未重置 → 仍锁
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });

  // ④ 豁免窗口内失焦不锁（不假锁）；释放后再真后台且超剩余宽限期 → 锁。
  //    hidden/paused 关帧，锁屏只在 resumed 可见；宽限期锚点仅在「非豁免」
  //    首信号起，故豁免期间的失焦不吃宽限期。
  testWidgets('④豁免窗口内不锁；释放后真后台超宽限才锁', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          awayDurationReader: () => const Duration(seconds: 61), // 超 30s 宽限
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);

    // —— 相位 A：原生对话框抢焦点（豁免窗口）期间切后台再回来 → 不假锁 ——
    LockExemption.begin();
    await _toBackground(tester); // inactive→hidden→paused，全程豁免
    await _toForeground(tester); // 回前台：豁免期未锚表/未置锁 → 放行
    expect(find.text('输入密码'), findsNothing); // ④a 窗口内不锁（不假锁）
    expect(find.text('SECRET_HOME'), findsOneWidget);
    LockExemption.end(); // 选择器关闭

    // —— 相位 B：释放后再真后台，宽限期锚在首个非豁免信号，超宽限 → 锁 ——
    await _toBackground(tester); // 非豁免：inactive 即锁 + 锚表
    await _toForeground(tester); // resumed：reader 61s > 30s → 仍锁
    expect(find.text('输入密码'), findsOneWidget); // ④b 超剩余宽限期锁定
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });

  // ④b hidden 在豁免窗口内不清 KEK 缓存（原生选择器不算切后台）；出窗口即清。
  testWidgets('④b 豁免窗口内 hidden 不清 KEK，出窗口后即清', (tester) async {
    final service = await _configuredService('1357');

    KekSessionCache.instance.clear();
    await KekSessionCache.instance.deriveKek('seed', const [
      1,
      2,
      3,
    ], KdfParams.testLight);
    expect(KekSessionCache.instance.entryCount, greaterThan(0));

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');

    LockExemption.begin();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    // 豁免期不清缓存（否则笔记本导入选择器会顺手清掉在用的派生材料）。
    expect(KekSessionCache.instance.entryCount, greaterThan(0));
    LockExemption.end();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(KekSessionCache.instance.entryCount, 0); // 出窗口 → 恢复即清
  });

  // ⑤a 新路径锁定后失败计数仍生效：键盘通道与九宫格都不获旁路。
  testWidgets('⑤a 新路径锁定后键盘/九宫格失败都计入防爆破', (tester) async {
    final service = await _configuredService('1357');
    await service.setGraceSeconds(0);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');
    expect(service.failedAttempts, 0);

    // inactive→resumed 触发新路径锁定。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsOneWidget);

    // 键盘通道输错——仍走同一条 service.verify，记一次失败（非旁路）。
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2468');
    await tester.pumpAndSettle();
    expect(service.failedAttempts, 1);
    expect(find.text('输入密码'), findsOneWidget);

    // 键盘输对——同管线解锁并清零计数。
    await tester.enterText(find.byType(TextField), '1357');
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsNothing);
    expect(service.failedAttempts, 0);
  });

  // ⑤b 冷却在新路径下仍生效：达阈值后锁屏切冷却面板，键盘槽一并销毁。
  testWidgets('⑤b 冷却期内新路径不获继续尝试（九宫格+键盘都被替换）', (tester) async {
    final service = await _configuredService('1357');
    await service.setGraceSeconds(0);

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');

    // 新路径锁定。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('输入密码'), findsOneWidget);

    // 打满防爆破阈值（默认 10 次）触发冷却。
    for (var i = 0; i < 10; i++) {
      await _enterPin(tester, '2468');
    }
    expect(service.isLockedOut, isTrue);
    // 冷却面板替换密码盘：九宫格与桌面键盘槽都撤下（都不获「冷却期继续猜」）。
    expect(find.text('输入密码'), findsNothing);
    expect(find.text('尝试次数过多'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  // ⑥ Android 既有链路（inactive→hidden→paused）宽限/锁定语义保持。
  testWidgets('⑥Android 三信号链路：超宽限仍锁（既有语义不破）', (tester) async {
    final service = await _configuredService('1357');

    await tester.pumpWidget(
      MaterialApp(
        home: AppLockGate(
          service: service,
          awayDurationReader: () => const Duration(seconds: 45), // > 30s
          desktopKeyboardInput: true,
          child: const Text('SECRET_HOME'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _enterPin(tester, '1357');

    await _toBackground(tester); // 移动端整切后台的合法链路
    await _toForeground(tester);

    expect(find.text('输入密码'), findsOneWidget);
    await _enterPin(tester, '1357');
    expect(find.text('输入密码'), findsNothing);
  });
}
