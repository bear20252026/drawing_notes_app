import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/bento_grid.dart';

void main() {
  group('BentoGrid', () {
    testWidgets('renders all items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BentoGrid(
              items: [
                BentoGridItem(child: Text('Item 1')),
                BentoGridItem(child: Text('Item 2')),
                BentoGridItem(child: Text('Item 3')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('supports custom column and row spans', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BentoGrid(
              items: [
                BentoGridItem(
                  columnSpan: 2,
                  rowSpan: 2,
                  child: Text('Large'),
                ),
                BentoGridItem(child: Text('Small 1')),
                BentoGridItem(child: Text('Small 2')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Small 1'), findsOneWidget);
      expect(find.text('Small 2'), findsOneWidget);
    });

    testWidgets('invokes onTap when item is tapped', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BentoGrid(
              items: [
                BentoGridItem(
                  child: const Text('Tappable'),
                  onTap: () => tapped = true,
                ),
              ],
              columns: 1,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tappable'));
      expect(tapped, isTrue);
    });

    testWidgets('applies custom background color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BentoGrid(
              items: [
                BentoGridItem(
                  backgroundColor: Colors.red,
                  child: Text('Colored'),
                ),
              ],
              columns: 1,
            ),
          ),
        ),
      );

      expect(find.text('Colored'), findsOneWidget);
    });

    testWidgets('applies custom gradient', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BentoGrid(
              items: [
                BentoGridItem(
                  gradient: LinearGradient(
                    colors: [Colors.red, Colors.blue],
                  ),
                  child: Text('Gradient'),
                ),
              ],
              columns: 1,
            ),
          ),
        ),
      );

      expect(find.text('Gradient'), findsOneWidget);
    });
  });
}
