import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/halo_search.dart';

void main() {
  group('HaloSearch', () {
    testWidgets('renders search field with hint text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HaloSearch(hintText: 'Search notes...'),
          ),
        ),
      );

      expect(find.text('Search notes...'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays search icon by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HaloSearch(),
          ),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('calls onChanged when text is typed', (tester) async {
      String? changedText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HaloSearch(
              onChanged: (text) => changedText = text,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'test query');
      expect(changedText, equals('test query'));
    });

    testWidgets('calls onSubmitted when text is submitted', (tester) async {
      String? submittedText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HaloSearch(
              onSubmitted: (text) => submittedText = text,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'submit test');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submittedText, equals('submit test'));
    });

    testWidgets('calls onFocusChanged when focus changes', (tester) async {
      bool? focused;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HaloSearch(
              onFocusChanged: (isFocused) => focused = isFocused,
            ),
          ),
        ),
      );

      // Tap the text field to request focus.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focused, isTrue);

      // Use FocusScope to unfocus.
      final context = tester.element(find.byType(TextField));
      FocusScope.of(context).unfocus();
      await tester.pump();
      expect(focused, isFalse);
    });
  });

  group('SimpleSearch', () {
    testWidgets('renders search field with hint text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleSearch(hintText: 'Simple search...'),
          ),
        ),
      );

      expect(find.text('Simple search...'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays search icon by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SimpleSearch(),
          ),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });
}
