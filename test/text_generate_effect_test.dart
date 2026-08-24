import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/shared/widgets/text_generate_effect.dart';

void main() {
  group('TextGenerateEffect', () {
    testWidgets('显示文本', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextGenerateEffect(
              text: 'Hello World',
              delay: Duration.zero,
              wordDelay: Duration.zero,
            ),
          ),
        ),
      );

      // 初始状态：文本存在但不可见
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
    });

    testWidgets('分词正确', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextGenerateEffect(
              text: 'one two three',
              delay: Duration.zero,
              wordDelay: Duration.zero,
            ),
          ),
        ),
      );

      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(find.text('three'), findsOneWidget);
    });

    testWidgets('空文本不报错', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextGenerateEffect(
              text: '',
              delay: Duration.zero,
              wordDelay: Duration.zero,
            ),
          ),
        ),
      );

      // 不应抛出异常
      expect(tester.takeException(), isNull);
    });

    testWidgets('动画参数可配置', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextGenerateEffect(
              text: 'Styled Text',
              duration: Duration(milliseconds: 500),
              delay: Duration(seconds: 1),
              enableBlur: false,
              blurSigma: 5.0,
            ),
          ),
        ),
      );

      expect(find.text('Styled'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
    });

    testWidgets('支持文本对齐', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextGenerateEffect(
              text: 'Centered',
              textAlign: TextAlign.center,
              delay: Duration.zero,
              wordDelay: Duration.zero,
            ),
          ),
        ),
      );

      expect(find.text('Centered'), findsOneWidget);
    });
  });
}
