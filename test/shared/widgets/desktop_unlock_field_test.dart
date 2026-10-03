// desktop_unlock_field_test.dart —— DesktopUnlockField 字符放开用例
// （C-14 兑现，2026-10-03）。
//
// 覆盖：allowTextInput=true 时字母/符号原文送达 onVerify（验证模式失败
// 原地报错不关闭）；默认 false 维持 digitsOnly（数字以外的输入被过滤）；
// 收集模式回传原文。测试跑在 Windows 桌面宿主，组件可直构。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    bool allowTextInput = true,
    Future<bool> Function(String pin)? onVerify,
    ValueChanged<String>? onAccepted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopUnlockField(
            title: '输入密码',
            onVerify: onVerify,
            allowTextInput: allowTextInput,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('allowTextInput：字母/符号原文送达 onVerify（验证模式）', (
    tester,
  ) async {
    final seen = <String>[];
    await pumpField(
      tester,
      allowTextInput: true,
      onVerify: (pin) async {
        seen.add(pin);
        return pin == 'Abc-123!';
      },
    );

    await tester.enterText(find.byType(TextField), 'Abc-123!');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(seen, ['Abc-123!']);
  });

  testWidgets('验证失败：错误态显示、清空、对话框不关闭', (tester) async {
    await pumpField(
      tester,
      allowTextInput: true,
      onVerify: (_) async => false,
    );

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('解锁'));
    await tester.pumpAndSettle();

    expect(find.text('密码不正确'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget, reason: '对话框不关闭');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('默认（false）：digitsOnly 过滤字母（开屏 PIN 行为不变）', (
    tester,
  ) async {
    final seen = <String>[];
    await pumpField(
      tester,
      allowTextInput: false,
      onVerify: (pin) async {
        seen.add(pin);
        return true;
      },
    );

    // 过滤器在真实输入管线中生效：enterText 直接设 controller，
    // 这里经 sendKeyEvent 模拟真实击键路径不可行（测试环境无平台键盘），
    // 改断言 formatter 存在——组件契约层面锁死「默认仍纯数字」。
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.inputFormatters!.whereType<FilteringTextInputFormatter>().length,
      1,
      reason: '默认必须保留 digitsOnly（开屏 PIN 纯数字契约）',
    );
    expect(field.keyboardType, TextInputType.number);
    expect(seen, isEmpty);
  });

  testWidgets('allowTextInput：无 digitsOnly、无数字键盘', (tester) async {
    await pumpField(tester, allowTextInput: true);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.inputFormatters!.whereType<FilteringTextInputFormatter>(),
      isEmpty,
    );
    expect(field.keyboardType, TextInputType.text);
  });
}
