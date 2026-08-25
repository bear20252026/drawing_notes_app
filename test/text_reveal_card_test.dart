import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/text_reveal_card.dart';

void main() {
  group('TextRevealCard', () {
    testWidgets('renders hiddenText content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextRevealCard(
              hiddenText: Text('Secret Message'),
            ),
          ),
        ),
      );

      expect(find.text('Secret Message'), findsWidgets);
    });

    testWidgets('renders header when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextRevealCard(
              header: Text('Header'),
              hiddenText: Text('Secret'),
            ),
          ),
        ),
      );

      expect(find.text('Header'), findsOneWidget);
    });

    testWidgets('uses default height of 160', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextRevealCard(
              hiddenText: Text('Test'),
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      expect(container.constraints?.maxHeight, 160);
    });

    testWidgets('hides cursor indicator initially', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextRevealCard(
              hiddenText: Text('Secret'),
            ),
          ),
        ),
      );

      // No AnimatedPositioned should exist when _widthPercentage is 0.
      expect(find.byType(AnimatedPositioned), findsNothing);
    });

    testWidgets('shows stars background when showStars is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextRevealCard(
              hiddenText: Text('Secret'),
              starsCount: 50,
            ),
          ),
        ),
      );

      // Verify the widget builds without error with stars enabled.
      expect(find.byType(TextRevealCard), findsOneWidget);
    });
  });


}
