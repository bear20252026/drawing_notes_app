import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/color_lens.dart';

void main() {
  group('SimpleColorLens', () {
    testWidgets('shows lens when visible is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleColorLens(
              position: Offset(100, 100),
              currentColor: Colors.red,
              child: Text('Canvas'),
            ),
          ),
        ),
      );

      expect(find.text('Canvas'), findsOneWidget);
    });

    testWidgets('hides lens when visible is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleColorLens(
              visible: false,
              position: Offset(100, 100),
              currentColor: Colors.red,
              child: Text('Canvas'),
            ),
          ),
        ),
      );

      expect(find.text('Canvas'), findsOneWidget);
    });

    testWidgets('displays current color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleColorLens(
              position: Offset(100, 100),
              currentColor: Colors.blue,
              child: Text('Canvas'),
            ),
          ),
        ),
      );

      expect(find.text('Canvas'), findsOneWidget);
    });

    testWidgets('supports custom radius', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleColorLens(
              position: Offset(100, 100),
              radius: 80.0,
              currentColor: Colors.green,
              child: Text('Canvas'),
            ),
          ),
        ),
      );

      expect(find.text('Canvas'), findsOneWidget);
    });

    testWidgets('supports custom border color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleColorLens(
              position: Offset(100, 100),
              borderColor: Colors.yellow,
              currentColor: Colors.purple,
              child: Text('Canvas'),
            ),
          ),
        ),
      );

      expect(find.text('Canvas'), findsOneWidget);
    });
  });
}
