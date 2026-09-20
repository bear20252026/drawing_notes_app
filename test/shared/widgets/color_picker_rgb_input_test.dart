// B3 键盘调色回归（审计 2026-09-07）：RGB 数字输入是键盘用户唯一的
// 全键盘取色通道——锁定「输入→提交→回传」链路与焦点环存在性。
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/shared/widgets/color_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 打开对话框；结果经 [holder] 在 pop 后写入（helper 不得在关闭前返回 picked）。
  Future<void> openPicker(
    WidgetTester tester,
    Color initial, {
    required ValueNotifier<Color?> holder,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  holder.value = await showDialog<Color>(
                    context: context,
                    builder: (_) => ColorPickerDialog(initialColor: initial),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('RGB 输入 Enter 提交回传精确色值', (tester) async {
    final holder = ValueNotifier<Color?>(null);
    addTearDown(holder.dispose);
    await openPicker(tester, const Color(0xFF000000), holder: holder);
    // 三个输入框（R/G/B 前缀标签）。
    final rField = find.widgetWithText(TextField, 'R ');
    expect(rField, findsOneWidget);
    // 聚焦 R 框，改值 200，回车提交；再改 B 框 100 后点确定。
    await tester.enterText(rField, '200');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final bField = find.widgetWithText(TextField, 'B ');
    await tester.enterText(bField, '100');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final picked = holder.value;
    expect(picked, isNotNull);
    expect(picked!.r * 255, closeTo(200, 1));
    expect(picked.g * 255, closeTo(0, 1));
    expect(picked.b * 255, closeTo(100, 1));
  });

  testWidgets('非法输入被忽略，保持原色', (tester) async {
    final holder = ValueNotifier<Color?>(null);
    addTearDown(holder.dispose);
    await openPicker(tester, const Color(0xFF336699), holder: holder);
    final gField = find.widgetWithText(TextField, 'G ');
    // digitsOnly 会拦字母；用空串模拟解析失败路径。
    await tester.enterText(gField, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(holder.value, const Color(0xFF336699));
  });

  testWidgets('输入框聚焦显示 2px Focus Blue 焦点环（DESIGN.md:300）',
      (tester) async {
    final holder = ValueNotifier<Color?>(null);
    addTearDown(holder.dispose);
    await openPicker(tester, const Color(0xFF000000), holder: holder);
    final rField = find.widgetWithText(TextField, 'R ');
    await tester.tap(rField);
    await tester.pump();
    final tf = tester.widget<TextField>(rField);
    final border = tf.decoration?.focusedBorder;
    expect(border, isA<OutlineInputBorder>());
    expect(
      (border as OutlineInputBorder).borderSide.color,
      AppleColor.focusBlue,
    );
    expect(border.borderSide.width, 2);
    // 圆角必须落在合法档位（0/5/8/11/18/pill），禁止默认 4。
    // BorderRadiusGeometry.resolve → BorderRadius；取角上的 Radius.x。
    final radius = border.borderRadius.resolve(null).topLeft;
    expect(
      radius.x,
      anyOf(AppleRadius.xs, AppleRadius.sm, AppleRadius.md, AppleRadius.lg),
    );
  });
}
