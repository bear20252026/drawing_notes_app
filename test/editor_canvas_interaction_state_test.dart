import 'dart:ui' show Offset, Rect;

import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_canvas_interaction_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('框选会清空旧多选、更新草稿并在完成后保留既有单选语义', () {
    final state = EditorCanvasInteractionState()
      ..selectedItemId = 'already-selected';
    state.addToMultiSelection(<String>['old']);

    state.beginMarquee(const Offset(10, 20));
    state.updateMarquee(const Offset(45, 70));

    expect(state.multiSelectedIds, isEmpty);
    expect(state.marqueeStart, const Offset(10, 20));
    expect(
      state.marqueeRect,
      Rect.fromPoints(const Offset(10, 20), const Offset(45, 70)),
    );

    state.completeMarquee(<String>['text-1', 'image-2']);

    expect(state.multiSelectedIds, <String>{'text-1', 'image-2'});
    expect(state.selectedItemId, 'already-selected');
    expect(state.marqueeRect, isNull);
    expect(state.marqueeStart, isNull);
  });

  test('清理框选和对象选择遵循不同的状态范围', () {
    final state = EditorCanvasInteractionState()..selectedItemId = 'item-1';

    state.beginMarquee(Offset.zero);
    state.addToMultiSelection(<String>['item-2']);
    state.clearMarquee();

    expect(state.selectedItemId, 'item-1');
    expect(state.multiSelectedIds, <String>{'item-2'});
    expect(
      () => state.multiSelectedIds.add('cannot-mutate-view'),
      throwsUnsupportedError,
    );

    state.clearObjectSelection();

    expect(state.selectedItemId, isNull);
    expect(state.multiSelectedIds, isEmpty);
  });

  test('拖动轨迹有固定上限，对齐参考线可整体替换或清空', () {
    final state = EditorCanvasInteractionState();

    for (var i = 0; i < 10; i++) {
      state.recordTrail(Offset(i.toDouble(), 0));
    }
    state.replaceSnapGuides(<({bool vertical, double pos})>[
      (vertical: true, pos: 12),
      (vertical: false, pos: 24),
    ]);

    expect(state.trailPoints, hasLength(8));
    expect(state.trailPoints.first, const Offset(2, 0));
    expect(
      () => state.trailPoints.add(const Offset(99, 0)),
      throwsUnsupportedError,
    );
    expect(state.snapGuides, hasLength(2));

    state.clearSnapGuides();

    expect(state.snapGuides, isEmpty);
  });

  test('删除淡出状态只能通过明确命令更新', () {
    final state = EditorCanvasInteractionState();

    state.beginDeleting(<String>['text-1', 'image-2']);

    expect(state.deletingIds, <String>{'text-1', 'image-2'});
    expect(() => state.deletingIds.remove('text-1'), throwsUnsupportedError);

    state.finishDeleting(<String>['text-1']);

    expect(state.deletingIds, <String>{'image-2'});
  });

  test('图片裁剪状态以图片实际边界开始并可完整清理', () {
    final state = EditorCanvasInteractionState();
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/sample.png',
      x: 11,
      y: 22,
      width: 120,
      height: 80,
    );

    state.beginCrop(image);

    expect(state.cropItem, same(image));
    expect(state.cropRect, const Rect.fromLTWH(11, 22, 120, 80));
    expect(state.isCropping, isTrue);

    state.clearCrop();

    expect(state.cropItem, isNull);
    expect(state.cropRect, isNull);
    expect(state.isCropping, isFalse);
  });
}
