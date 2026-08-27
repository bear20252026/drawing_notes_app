import 'package:drawing_notes_app/features/drawing/presentation/editor_shape_resize_geometry.dart';
import 'package:drawing_notes_app/features/drawing/presentation/resize_handles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('八向手柄按展示顺序传递明确语义、画布增量和通知', (tester) async {
    final emitted = <(EditorShapeResizeHandle, Offset)>[];
    var notifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 160,
            child: ResizeHandles(
              width: 200,
              height: 160,
              screenToCanvasDelta: (delta) =>
                  Offset(delta.dx / 2, delta.dy / 2),
              onResize: (handle, canvasDelta) {
                emitted.add((handle, canvasDelta));
              },
              onChanged: () => notifications++,
            ),
          ),
        ),
      ),
    );

    final handleFinder = find.descendant(
      of: find.byType(ResizeHandles),
      matching: find.byType(GestureDetector),
    );
    expect(handleFinder, findsNWidgets(8));
    final gestures = tester.widgetList<GestureDetector>(handleFinder).toList();

    for (var index = 0; index < gestures.length; index++) {
      gestures[index].onPanUpdate!(
        DragUpdateDetails(
          globalPosition: Offset(index + 20.0, index + 40.0),
          delta: Offset(index + 2.0, index + 4.0),
        ),
      );
    }

    expect(
      emitted.map((entry) => entry.$1),
      orderedEquals(EditorShapeResizeHandle.values),
    );
    expect(
      emitted.first.$2,
      const Offset(1, 2),
      reason: '手柄只把宿主定义的屏幕到画布换算结果传出',
    );
    expect(notifications, 8, reason: '保持每次拖拽更新后的既有通知时序');
  });
}
