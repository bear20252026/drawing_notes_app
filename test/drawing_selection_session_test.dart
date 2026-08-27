import 'package:drawing_notes_app/features/drawing/application/drawing_selection_session.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('矩形草稿保留起点和最新终点，完成后清理预览状态', () {
    final session = DrawingSelectionSession()..tool = SelectionTool.rect;

    session.beginDraft(const Offset(10, 20));
    session.extendDraft(const Offset(30, 40));
    session.extendDraft(const Offset(80, 90));

    expect(session.draft, <Offset>[const Offset(10, 20), const Offset(80, 90)]);
    session.completeDraft(
      const Selection(
        polygon: <Offset>[
          Offset(10, 20),
          Offset(80, 20),
          Offset(80, 90),
          Offset(10, 90),
        ],
        selectedStrokeIndices: <int>[1],
      ),
    );

    expect(session.draft, isEmpty);
    expect(session.hasSelection, isTrue);
    expect(session.hasSelectedStrokes, isTrue);
  });

  test('套索草稿累积采样点，切换工具仅清除选区和中心缓存', () {
    final session = DrawingSelectionSession()..tool = SelectionTool.lasso;

    session.beginDraft(const Offset(0, 0));
    session.extendDraft(const Offset(20, 0));
    session.extendDraft(const Offset(20, 20));
    expect(session.draft, hasLength(3));

    session.completeDraft(
      const Selection(
        polygon: <Offset>[Offset(0, 0), Offset(20, 0), Offset(20, 20)],
      ),
    );
    session.cacheCenter(const Offset(10, 10));
    session.clipboard = <Stroke>[];
    session.setTool(SelectionTool.rect);

    expect(session.tool, SelectionTool.rect);
    expect(session.selection, const Selection());
    expect(session.centerCache, isNull);
    expect(session.centerDirty, isTrue);
    expect(session.clipboard, isEmpty);
  });
}
