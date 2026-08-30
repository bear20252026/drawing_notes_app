import 'dart:ui' show Color, Offset;

import 'package:drawing_notes_app/features/drawing/application/drawing_selection_session.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('矩形选区独立完成草稿并命中内部和穿越边界的笔画', () {
    final selectionSession = DrawingSelectionSession()
      ..setTool(SelectionTool.rect);
    final host = _SelectionInteractionHost(
      _documentWithStrokes(<Stroke>[
        _stroke(const Offset(10, 10), const Offset(20, 20)),
        _stroke(const Offset(-10, 50), const Offset(110, 50)),
        _stroke(const Offset(150, 150), const Offset(170, 170)),
      ]),
      selectionSession,
    );
    final session = StrokeSelectionInteractionSession(host);

    session.beginSelection(const Offset(0, 0));
    session.extendSelection(const Offset(100, 100));
    session.endSelection();

    expect(host.requestedFrames, 2);
    expect(host.changeNotifications, 1);
    expect(selectionSession.draft, isEmpty);
    expect(selectionSession.selection.polygon, hasLength(4));
    expect(selectionSession.selection.selectedStrokeIndices, <int>[0, 1]);
  });

  test('无效套索草稿清空选择但仍只在结束时发送状态通知', () {
    final selectionSession = DrawingSelectionSession()
      ..setTool(SelectionTool.lasso);
    final host = _SelectionInteractionHost(
      _documentWithStrokes(<Stroke>[
        _stroke(const Offset(5, 5), const Offset(8, 8)),
      ]),
      selectionSession,
    );
    final session = StrokeSelectionInteractionSession(host);

    session.beginSelection(const Offset(0, 0));
    session.extendSelection(const Offset(10, 0));
    session.endSelection();

    expect(host.requestedFrames, 2);
    expect(host.changeNotifications, 1);
    expect(selectionSession.selection.polygon, isEmpty);
    expect(selectionSession.selection.selectedStrokeIndices, isEmpty);
    expect(selectionSession.draft, isEmpty);
  });
}

DrawingDocument _documentWithStrokes(List<Stroke> strokes) => DrawingDocument(
  id: 'selection_interaction',
  title: '选区交互',
  infinite: true,
  layers: <Layer>[Layer(id: 'base', name: 'base', strokes: strokes)],
);

Stroke _stroke(Offset from, Offset to) => Stroke(
  points: <StrokePoint>[
    StrokePoint(from.dx, from.dy, 1),
    StrokePoint(to.dx, to.dy, 1),
  ],
  color: const Color(0xFF222222),
  width: 2,
  type: BrushType.pen,
);

class _SelectionInteractionHost implements StrokeSelectionInteractionHost {
  _SelectionInteractionHost(this.document, this.selectionSession);

  final DrawingDocument document;

  @override
  final DrawingSelectionSession selectionSession;

  int requestedFrames = 0;
  int changeNotifications = 0;

  @override
  Layer get currentLayer => document.layers.single;

  @override
  void notifyChanged() => changeNotifications++;

  @override
  void requestFrame() => requestedFrames++;
}
