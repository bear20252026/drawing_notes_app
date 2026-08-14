import 'package:drawing_notes_app/ui/widgets/ambient_background.dart';
import 'package:drawing_notes_app/ui/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets(
    'GlassSurface clips and applies a local backdrop filter by default',
    (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 180,
            height: 60,
            child: GlassSurface(child: Text('工具层')),
          ),
        ),
      );

      expect(find.byType(GlassSurface), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('工具层'), findsOneWidget);
    },
  );

  testWidgets('GlassSurface can disable blur while retaining the surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 180,
          height: 60,
          child: GlassSurface(enabled: false, child: Text('可读降级')),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.text('可读降级'), findsOneWidget);
  });

  testWidgets(
    'AmbientBackground keeps content above a single decorative layer',
    (tester) async {
      await tester.pumpWidget(
        host(
          const AmbientBackground(
            child: Align(alignment: Alignment.topLeft, child: Text('资料库内容')),
          ),
        ),
      );

      expect(find.byType(AmbientBackground), findsOneWidget);
      expect(find.text('资料库内容'), findsOneWidget);
    },
  );
}
