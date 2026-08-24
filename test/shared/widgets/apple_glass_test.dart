import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/apple_glass.dart';

/// 苹果 Liquid Glass 借鉴——AppleGlassWidget 测试（Widget——不崩）。
void main() {
  testWidgets('AppleGlassWidget 渲染（毛玻璃容器——Liquid Glass——不崩）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AppleGlassWidget(
          child: Text('毛玻璃内容'),
        ),
      ),
    ));
    expect(find.text('毛玻璃内容'), findsOneWidget);
    expect(tester.takeException(), isNull); // 不崩。
  });

  testWidgets('AppleGlassWidget.card 便捷工厂（AppleTheme 参数——不崩）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppleGlassWidget.card(child: const Text('毛玻璃卡片')),
      ),
    ));
    expect(find.text('毛玻璃卡片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppleGlassWidget.toolbar 便捷工厂（大圆角——不崩）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppleGlassWidget.toolbar(child: const Text('毛玻璃工具栏')),
      ),
    ));
    expect(find.text('毛玻璃工具栏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
