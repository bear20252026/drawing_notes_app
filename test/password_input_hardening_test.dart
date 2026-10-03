// password_input_hardening_test.dart —— 密码与解锁链路加固回归锁（审计 2026-10-03）。
//
// 覆盖四条已核实缺陷：
//  - P1 空密码/最短长度三层收口：第一层 UI（DesktopUnlockField 收集模式）、
//    第三层 store（StorageFilePasswordManager 对空串 fail-closed）；
//    第二层（收集方 `pin == null || pin.isEmpty`）在 home/doc/reset 三处；
//  - P1 PinPad 跨模式凭据单一真源：切「字母」不再丢弃已输入的 1234；
//  - P1 数字模式矮视口可滚动：`0`/退格/✓ 滚得进命中区（旧实现裸 Column +
//    Spacer，矮视口溢出后既提交不了也退不了格）；
//  - P2 同码探测不消耗防爆破计数 + 冷却期 fail-closed（不放行同码）；
//  - P2 桌面开屏锁物理键盘通道：走同一条 verify，九宫格不删（三输入并行）。
//
// KDF 一律注入轻量档（[KdfParams.testLight] + 同 isolate 直派生），
// 不新增真 KDF 慢用例（口径同 app_lock_gate_test / app_lock_guard_test）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_gate.dart';
import 'package:drawing_notes_app/core/security/app_lock_guard.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/shared/widgets/pin_pad.dart';
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
    KdfParams.newSlotDefault = KdfParams.testLight;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  // ==== 桌面收集入口（DesktopUnlockField / UnlockFlow 桌面分支）====

  String? popped;

  Future<void> pumpDesktopField(
    WidgetTester tester, {
    bool allowTextInput = true,
    int? minLength,
    Future<bool> Function(String pin)? onVerify,
  }) async {
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                unawaited(
                  DesktopUnlockField.show(
                    context,
                    title: '设置独立密码',
                    allowTextInput: allowTextInput,
                    minLength: minLength,
                    onVerify: onVerify,
                  ).then((value) => popped = value),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  group('桌面收集模式最短长度（P1 收口第一层，与移动端 flexibleMinLength 同口径）', () {
    testWidgets('空密码：不提交、就地提示、对话框不关闭', (tester) async {
      await pumpDesktopField(tester);

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('密码不能为空'), findsOneWidget);
      expect(popped, isNull, reason: '空串绝不回传给收集方');
      expect(find.byType(TextField), findsOneWidget, reason: '对话框不关闭');
    });

    testWidgets('短于 4 位拒收；补足 4 位才回传（两次回车设不出空密码）', (tester) async {
      await pumpDesktopField(tester);

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.textContaining('密码长度不足'), findsOneWidget);
      expect(popped, isNull);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(popped, '1234');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('minLength 透传：flexibleMinLength=6 时 5 位被拒', (tester) async {
      await pumpDesktopField(tester, minLength: 6);

      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(popped, isNull);
      expect(find.textContaining('密码长度不足'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(popped, '123456');
    });

    testWidgets('验证模式（解锁）语义不变：空串仍送后端、不过滤', (tester) async {
      final seen = <String>[];
      await pumpDesktopField(
        tester,
        onVerify: (pin) async {
          seen.add(pin);
          return false;
        },
      );

      await tester.tap(find.text('解锁'));
      await tester.pumpAndSettle();

      expect(seen, [''], reason: '既有短密码文档的解锁路径不被 UI 挡在门外');
      expect(find.text('密码不正确'), findsOneWidget);
      expect(popped, isNull);
    });

    testWidgets('UnlockFlow 桌面分支贯通：flexible 场景空串同样不收', (tester) async {
      // 锁参数链路：UnlockFlow(flexible) → DesktopUnlockField.minLength
      // = flexibleMinLength（桌面与移动端 flexibleMinLength 同口径）。
      String? viaFlow;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  unawaited(
                    UnlockFlow.show(
                      context,
                      title: '设置独立密码',
                      flexible: true,
                    ).then((value) => viaFlow = value),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('密码不能为空'), findsOneWidget);
      expect(viaFlow, isNull);

      await tester.enterText(find.byType(TextField), 'pw-1234');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(viaFlow, 'pw-1234');
    });
  });

  // ==== PinPad 跨模式凭据单一真源（P1）====

  Future<void> pumpPad(
    WidgetTester tester, {
    Size surface = const Size(500, 900),
    bool flexible = true,
    bool enableTextInput = true,
    Future<bool> Function(String pin)? onVerify,
    ValueChanged<String>? onAccepted,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinPadCore(
            title: '输入密码',
            flexible: flexible,
            enableTextInput: enableTextInput,
            onVerify: onVerify,
            onAccepted: onAccepted,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
  }

  group('PinPad 凭据单一真源（P1：切模式不丢不串）', () {
    testWidgets('九宫格 1234 → 切「字母」→ 追加 abcd → 提交 1234abcd', (tester) async {
      String? accepted;
      await pumpPad(tester, onAccepted: (p) => accepted = p);

      await tapDigits(tester, '1234');
      await tester.tap(find.text('字母'));
      await tester.pumpAndSettle();

      // 旧实现在这里只 setState：1234 被静默丢弃，设出来的密码是 abcd。
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1234',
        reason: '切换即把当前凭据同步进文本框',
      );

      await tester.enterText(find.byType(TextField), '1234abcd');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(accepted, '1234abcd');
      expect(tester.takeException(), isNull);
    });

    testWidgets('收集模式文本提交同样受 flexibleMinLength 约束（跨端口径一致）', (tester) async {
      var accepted = '';
      await pumpPad(tester, onAccepted: (p) => accepted = p);

      await tester.tap(find.text('字母'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(accepted, '', reason: '3 位不收——桌面/移动设出来的密码一样强');

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(accepted, '1234');
    });

    testWidgets('验证模式（解锁）不做长度约束：短/含符号密码原文送达 onVerify', (tester) async {
      final seen = <String>[];
      await pumpPad(
        tester,
        onVerify: (pin) async {
          seen.add(pin);
          return false;
        },
      );

      await tester.tap(find.text('字母'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a1');
      await tester.tap(find.text('解锁'));
      await tester.pumpAndSettle();

      expect(seen, ['a1'], reason: '既有超长/短密码的解锁不能被 UI 挡在门外');
      // 失败清空：缓冲与文本框一起归零（既有纪律）。
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });

    testWidgets('文本框改值后回切九宫格：缓冲跟随文本框（不残留旧值）', (tester) async {
      await pumpPad(tester);
      await tapDigits(tester, '1234');
      await tester.tap(find.text('字母'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '98');
      await tester.pump();
      await tester.tap(find.text('数字'));
      await tester.pumpAndSettle();

      // 真源是缓冲：文本框改成 98，回切后就是 2 位（旧的 1234 不残留）。
      expect(find.text('2 / 12 位（4–12 位可选）'), findsOneWidget);
    });
  });

  group('数字模式矮视口可达性（P1：九宫格无滚动容器）', () {
    for (final size in const <Size>[Size(390, 360), Size(800, 360)]) {
      testWidgets(
        '${size.width.toInt()}×${size.height.toInt()}：不溢出，0/退格/✓ 可达',
        (tester) async {
          String? accepted;
          await pumpPad(tester, surface: size, onAccepted: (p) => accepted = p);
          expect(
            tester.takeException(),
            isNull,
            reason: '裸 Column+Spacer 在矮视口会 RenderFlex 溢出',
          );

          // 顶部键区先输入 4 位（此刻可见）。
          await tapDigits(tester, '1234');

          final outer = find
              .descendant(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Scrollable),
              )
              .first;
          final position = tester.state<ScrollableState>(outer).position;
          expect(
            position.maxScrollExtent,
            greaterThan(0),
            reason: '矮视口下必须存在可滚动的余量',
          );
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();

          for (final key in <Finder>[
            find.text('0'),
            find.byIcon(Icons.backspace_outlined),
            find.byIcon(Icons.check_rounded),
          ]) {
            final rect = tester.getRect(key);
            expect(rect.top, greaterThanOrEqualTo(0), reason: '$key 未被顶出屏外');
            expect(
              rect.bottom,
              lessThanOrEqualTo(size.height + 0.5),
              reason: '$key 命中区在屏幕内',
            );
          }

          // 触控目标 ≥44（九宫格单元格 = (264 − 2×14)/3，退格/✓ 同槽位）。
          final cell = (tester.getSize(find.byType(GridView)).width - 28) / 3;
          expect(cell, greaterThanOrEqualTo(44));

          // 滚到底后 ✓ 真的可用（旧缺陷里既提交不了也退不了格）。
          await tester.tap(find.byIcon(Icons.check_rounded));
          await tester.pumpAndSettle();
          expect(accepted, '1234');
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // ==== 同码探测 × 防爆破计数（P2）====

  group('同码探测不消耗防爆破计数（P2）', () {
    test('探测零计数；verify 的既有语义（计次/清零）不变', () async {
      SharedPreferences.setMockInitialValues({});
      final guard = memoryGuard();
      final service = AppLockService(guard: guard);
      await service.setPin('9527');

      expect(service.failedAttempts, 0);
      expect(await service.matchPinReadOnly('9527'), isTrue);
      expect(await service.matchPinReadOnly('0000'), isFalse);
      expect(
        guard.failureCount,
        0,
        reason: '旧实现走 verify：每设一次独立密码就白记一次「开屏密码猜错」',
      );

      // 对照：登录校验照旧计次，成功照旧清零。
      expect(await service.verify('0000'), isFalse);
      expect(guard.failureCount, 1);
      expect(await service.verify('9527'), isTrue);
      expect(guard.failureCount, 0);
    });

    test('冷却期：探测返回 null（判定不了），调用方须 fail-closed', () async {
      SharedPreferences.setMockInitialValues({});
      // 不注入守卫：走默认 LockoutGuard（测试宿主下用进程内签名密钥）——
      // 静态探测入口读到的是同一条持久化记录，锁动态才可比对。
      final service = AppLockService();
      await service.load();
      await service.setPin('9527');
      for (var i = 0; i < 10; i++) {
        expect(await service.verify('wrong-$i'), isFalse);
      }
      expect(service.isLockedOut, isTrue);

      // 三态契约：null ≠ 「不同码」；收集方据此拒绝设密。
      expect(await service.matchPinReadOnly('9527'), isNull);
      expect(
        await AppLockService.probeMatchesAppLockPin('9527'),
        isNull,
        reason: '静态探测入口同样返回 null（旧实现在冷却期静默放行同码）',
      );
      // 兼容位：bool 入口仅在「确证同码」时为 true，签名不变。
      expect(await AppLockService.matchesAppLockPin('9527'), isFalse);
      // 冷却期内正确 PIN 也被拒——新增通道不削弱惩罚。
      expect(await service.verify('9527'), isFalse);
    });
  });

  // ==== 桌面开屏锁物理键盘通道（P2 可达性）====

  group('桌面开屏锁物理键盘通道（P2）', () {
    Future<void> pumpGate(
      WidgetTester tester,
      AppLockService service, {
      bool? desktopKeyboardInput,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppLockGate(
            service: service,
            desktopKeyboardInput: desktopKeyboardInput,
            child: const Text('SECRET_HOME'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('键盘直输解锁：九宫格仍在场，失败仍计入防爆破', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final guard = memoryGuard();
      final service = AppLockService(guard: guard);
      await service.setPin('1357');

      await pumpGate(tester, service, desktopKeyboardInput: true);

      expect(find.text('输入密码'), findsOneWidget);
      // 三输入并行：九宫格（鼠标/触屏）通道不删。
      expect(find.byType(PinPadCore), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // 新增物理键盘通道。
      expect(find.byType(TextField), findsOneWidget);

      // 键盘路径不获得旁路：错密码同样进 verify、同样记一次失败。
      await tester.enterText(find.byType(TextField), '2468');
      await tester.pumpAndSettle();
      expect(guard.failureCount, 1);
      expect(find.text('输入密码'), findsOneWidget, reason: '错密码仍锁着');
      expect(find.text('密码不正确'), findsOneWidget);

      // 正确密码：键盘通道同样把锁屏撤掉（旧实现只 verify 不放行）。
      await tester.enterText(find.byType(TextField), '1357');
      await tester.pumpAndSettle();
      expect(find.text('输入密码'), findsNothing);
      expect(find.text('SECRET_HOME'), findsOneWidget);
      expect(guard.failureCount, 0, reason: '校验成功即清零（既有语义）');
    });

    testWidgets('显式关闭：不叠加键盘槽（移动端/forced false 行为）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService(guard: memoryGuard());
      await service.setPin('1357');

      await pumpGate(tester, service, desktopKeyboardInput: false);

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(PinPadCore), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  });

  // ==== 存储层空密码 fail-closed（P1 收口第三层·画作文件密码）====

  group('画作文件密码存储层拒绝空串（P1 收口第三层）', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pw_hardening_');
      storage = StorageService(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      try {
        await deleteTempDirWithRetry(tempDir);
      } on FileSystemException {
        // Windows 句柄延迟释放——尽力清理。
      }
    });

    test('设密/改密/重置入口对空串直接抛错（不封「已加密」的空信封）', () {
      final usbKey = List<int>.generate(32, (i) => i + 1);

      expect(
        () => storage.setFilePassword('pw_empty_gate', ''),
        throwsArgumentError,
      );
      expect(
        () => storage.changeFilePassword('pw_empty_gate', 'old', ''),
        throwsArgumentError,
      );
      expect(
        () => storage.resetFilePasswordWithUsb('pw_empty_gate', usbKey, ''),
        throwsArgumentError,
      );
    });
  });
}
