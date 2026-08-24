import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/shared/widgets/box_reveal.dart';

void main() {
  group('BoxReveal', () {
    testWidgets('显示子组件', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BoxReveal(
              triggerOnScroll: false,
              child: Text('Hello World'),
            ),
          ),
        ),
      );

      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('支持自定义颜色', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BoxReveal(
              color: Colors.red,
              triggerOnScroll: false,
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('支持自定义时长和延迟', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BoxReveal(
              duration: Duration(milliseconds: 300),
              delay: Duration(milliseconds: 100),
              triggerOnScroll: false,
              child: Text('Custom'),
            ),
          ),
        ),
      );

      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('复杂子组件', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BoxReveal(
              triggerOnScroll: false,
              child: Column(
                children: [
                  Text('Line 1'),
                  Text('Line 2'),
                  Icon(Icons.star),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Line 1'), findsOneWidget);
      expect(find.text('Line 2'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('空子组件不报错', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BoxReveal(
              triggerOnScroll: false,
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
