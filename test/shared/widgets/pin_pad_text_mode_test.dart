// pin_pad_text_mode_test.dart —— PinPadCore 文本切换模式 widget 测试
// （C-14 兑现，2026-10-03）。
//
// 覆盖：切换键仅在 enableTextInput 出现；文本模式字母输入端到端
// （验证模式原文送达 onVerify / 收集模式 onAccepted 返回）；验证失败
// 抖动清空；空提交忽略；凭据单一真源——跨模式不丢不串（P1 修复）；
// 数字模式回归（无切换键）。
//
// 2026-10-03：原「往返切换：文本输入不串入数字模式」用例把「切换即丢弃」
// 当成了预期（旧实现切文本只 setState，1234 被静默丢掉）。真源改为
// [_entered] 缓冲后，该断言与缺陷同源，按新语义重写。

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

  testWidgets('往返切换：凭据单一真源——切换不丢不串（P1 修复）', (tester) async {
    String? accepted;
    await pumpPad(tester, onAccepted: (p) => accepted = p);

    // 数字模式输入 12（未到最短 4 位，不提交）。
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();

    // 切文本：九宫格已输入的 12 必须搬进文本框——旧实现只 setState，
    // 12 被静默丢弃（`12abcd` 变 `abcd`：设成非预期密码/永远解不开）。
    await tester.tap(find.text('字母'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12',
      reason: '切换即把当前凭据同步进文本框',
    );

    // 文本框在 12 之后追加 abcd（enterText 经真实输入通道整值替换）。
    await tester.enterText(find.byType(TextField), '12abcd');
    await tester.pump();

    // 切回九宫格：缓冲 = 文本框当前值（6 位），既没退回旧的 12，
    // 也没把文本内容丢掉（两模式共用同一真源）。
    await tester.tap(find.text('数字'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('6 / 12 位（4–12 位可选）'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(accepted, '12abcd');
  });
}
