import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('深色阅读只变换显示层，不修改文档数据', (tester) async {
    final document = DrawingDocument(id: 'reading_inversion', title: '深色阅读');
    document.layers.single.strokes.add(
      Stroke(
        points: [StrokePoint(10, 10, 1), StrokePoint(80, 30, 0.7)],
        color: Color(0xFF1A1A1A),
        width: 6,
        type: BrushType.pen,
      ),
    );
    final before = document.toJson();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(document: document)),
      ),
    );
    await tester.pump();

    expect(find.byType(ColorFiltered), findsNothing);
    await tester.tap(find.byTooltip('深色阅读（仅显示）'));
    await tester.pump();

    expect(find.byType(ColorFiltered), findsWidgets);
    expect(document.toJson(), before);

    await tester.tap(find.byTooltip('关闭深色阅读'));
    await tester.pump();
    expect(find.byType(ColorFiltered), findsNothing);
    expect(document.toJson(), before);
  });
}
