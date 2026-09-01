// ============================================================================
// pin_pad_flexible_test.dart —— PinPadCore 可变长度模式 widget 测试（批次②）
// ============================================================================
//
// 覆盖：圆点随输入增长、计数文案、退格、✓ 确认（不足最短长度抖动拒绝）、
// 校验失败清空、固定模式不受影响（无退格/✓ 键、输满自动提交）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/fix/security_and_sync_fix.dart';

void main() {
  Future<void> pumpPad(
    WidgetTester tester, {
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

  testWidgets('flexible：输入增长圆点与计数；不自动提交', (tester) async {
    var accepted = '';
    await pumpPad(tester, onAccepted: (p) => accepted = p);

    await tapDigits(tester, '123');
    await tester.pumpAndSettle();

    // 计数文案出现（固定模式没有）。
    expect(find.text('3 / 12 位（4–12 位可选）'), findsOneWidget);
    // 未输满自动提交不发生。
    expect(accepted, '');

    // 继续输到 6 位：计数跟随。
    await tapDigits(tester, '456');
    await tester.pumpAndSettle();
    expect(find.text('6 / 12 位（4–12 位可选）'), findsOneWidget);
    expect(accepted, '');
  });

  testWidgets('flexible：不足最短长度按 ✓ → 抖动拒绝，输入保留', (tester) async {
    var verifyCalls = 0;
    await pumpPad(
      tester,
      onVerify: (_) async {
        verifyCalls++;
        return true;
      },
    );

    await tapDigits(tester, '123'); // 3 < 4
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(verifyCalls, 0);
    expect(find.text('3 / 12 位（4–12 位可选）'), findsOneWidget); // 未清空
  });

  testWidgets('flexible：✓ 提交 → 校验通过回传 PIN；失败清空', (tester) async {
    var accepted = '';
    await pumpPad(
      tester,
      onVerify: (p) async => p == '13579',
      onAccepted: (p) => accepted = p,
    );

    await tapDigits(tester, '13579');
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(accepted, '13579');

    // 失败路径：错误 PIN 校验失败 → 清空（计数归 0）。
    await tapDigits(tester, '24680');
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(accepted, '13579'); // 未被错误 PIN 覆盖
    expect(find.text('0 / 12 位（4–12 位可选）'), findsOneWidget);
  });

  testWidgets('flexible：退格逐位删除；空输入退格无效果', (tester) async {
    await pumpPad(tester);

    await tapDigits(tester, '12345');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pumpAndSettle();
    expect(find.text('4 / 12 位（4–12 位可选）'), findsOneWidget);

    // 连续退格到空：再退格不报错、计数保持 0。
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('0 / 12 位（4–12 位可选）'), findsOneWidget);
  });

  testWidgets('flexible：上限 12 位——超出部分不收录', (tester) async {
    await pumpPad(tester);
    await tapDigits(tester, '123456789012'); // 恰好 12 位
    await tester.pumpAndSettle();
    expect(find.text('12 / 12 位（4–12 位可选）'), findsOneWidget);

    await tapDigits(tester, '34'); // 超出：应被忽略
    await tester.pumpAndSettle();
    expect(find.text('12 / 12 位（4–12 位可选）'), findsOneWidget);
  });

  testWidgets('固定模式：无退格/✓ 键，输满自动提交（回归保护）', (tester) async {
    var accepted = '';
    await pumpPad(tester, flexible: false, onAccepted: (p) => accepted = p);

    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.backspace_outlined), findsNothing);

    await tapDigits(tester, '9527');
    await tester.pumpAndSettle();
    expect(accepted, '9527'); // 4 位输满自动提交
  });
}
