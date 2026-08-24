import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/shared/widgets/breathing_text.dart';

void main() {
  group('BreathingText', () {
    testWidgets('显示文本', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreathingText(
              text: 'Hello',
              duration: Duration(milliseconds: 100),
              staggerDuration: Duration(milliseconds: 10),
            ),
          ),
        ),
      );

      // BreathingText renders each letter as a separate Text widget.
      expect(find.byType(BreathingText), findsOneWidget);
      expect(find.text('H'), findsOneWidget);
      expect(find.text('e'), findsOneWidget);
      expect(find.text('l'), findsNWidgets(2));
      expect(find.text('o'), findsOneWidget);

      // Advance time to let all staggered timers fire.
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('空文本不报错', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreathingText(
              text: '',
              duration: Duration(milliseconds: 100),
              staggerDuration: Duration(milliseconds: 10),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('支持自定义样式', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreathingText(
              text: 'Styled',
              style: TextStyle(fontSize: 24, color: Colors.red),
              duration: Duration(milliseconds: 100),
              staggerDuration: Duration(milliseconds: 10),
            ),
          ),
        ),
      );

      expect(find.byType(BreathingText), findsOneWidget);
      expect(find.text('S'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('支持文本对齐', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreathingText(
              text: 'Centered',
              textAlign: TextAlign.center,
              duration: Duration(milliseconds: 100),
              staggerDuration: Duration(milliseconds: 10),
            ),
          ),
        ),
      );

      expect(find.byType(BreathingText), findsOneWidget);
      expect(find.text('C'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('字体粗细范围可配置', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreathingText(
              text: 'Weight',
              minFontWeight: 300,
              maxFontWeight: 700,
              duration: Duration(milliseconds: 100),
              staggerDuration: Duration(milliseconds: 10),
            ),
          ),
        ),
      );

      expect(find.byType(BreathingText), findsOneWidget);
      expect(find.text('W'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
