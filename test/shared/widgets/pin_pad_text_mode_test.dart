// pin_pad_text_mode_test.dart —— PinPadCore 文本切换模式 widget 测试
// （C-14 兑现，2026-10-03）。
//
// 覆盖：切换键仅在 enableTextInput 出现；文本模式字母输入端到端
// （验证模式原文送达 onVerify / 收集模式 onAccepted 返回）；验证失败
// 抖动清空；空提交忽略；数字缓冲跨切换保留；数字模式回归（无切换键）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/pin_pad.dart';

void main() {
  Future<void> pumpPad(
    WidgetTester tester, {
    bool enableTextInput = true,
    bool flexible = true,
    Future<bool> Function(String pin)? onVerify,
    ValueChanged<String>? onAccepted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinPadCore(
            title: '输入密码',
            flexible: flexible,
            onVerify: onVerify,
            onAccepted: onAccepted ?? (_) {},
            enableTextInput: enableTextInput,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('enableTextInput=true：出现「字母」切换键；false：不出现', (
    tester,
  ) async {
    await pumpPad(tester);
    expect(find.text('字母'), findsOneWidget);

    await pumpPad(tester, enableTextInput: false);
    expect(find.text('字母'), findsNothing);
  });

  testWidgets('文本模式：字母输入经验证模式原文送达 onVerify', (tester) async {
    final seen = <String>[];
    await pumpPad(
      tester,
      onVerify: (pin) async {
        seen.add(pin);
        return pin == 'Abc-123!';
      },
    );

    await tester.tap(find.text('字母'));
    await tester.pumpAndSettle();

    // 九宫格消失、 obscure TextField 出现。
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Abc-123!');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(seen, ['Abc-123!']);
  });

  testWidgets('收集模式：文本提交经 onAccepted 返回（设密场景）', (tester) async {
    String? accepted;
    await pumpPad(tester, onAccepted: (p) => accepted = p);

    await tester.tap(find.text('字母'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'p@ss 开头也可以');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(accepted, 'p@ss 开头也可以');
  });

  testWidgets('验证失败：抖动清空且不回调 onAccepted', (tester) async {
    var accepted = 0;
    var calls = 0;
    await pumpPad(
      tester,
      onVerify: (_) async {
        calls++;
        return false;
      },
      onAccepted: (_) => accepted++,
    );

    await tester.tap(find.text('字母'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(accepted, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
      reason: '失败清空与数字模式同一纪律',
    );
  });

  testWidgets('空提交：忽略（不回调、不进验证）', (tester) async {
    var calls = 0;
    String? accepted;
    await pumpPad(
      tester,
      onVerify: (_) async {
        calls++;
        return true;
      },
      onAccepted: (p) => accepted = p,
    );

    await tester.tap(find.text('字母'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(accepted, isNull);
  });

  testWidgets('往返切换：数字缓冲保留，文本输入不串入数字模式', (tester) async {
    String? accepted;
    await pumpPad(tester, onAccepted: (p) => accepted = p);

    // 数字模式输入 12（未到最短 4 位，不提交）。
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();

    // 切文本 → 输字母 → 不提交，切回数字。
    await tester.tap(find.text('字母'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('数字'));
    await tester.pumpAndSettle();

    // 九宫格回归，圆点仍是 2 位（文本输入未污染数字缓冲）。
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('2 / 12 位（4–12 位可选）'), findsOneWidget);

    // 补足 4 位提交：值 = 纯数字缓冲（abc 未混入）。
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('4'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(accepted, '1234');
  });
}
