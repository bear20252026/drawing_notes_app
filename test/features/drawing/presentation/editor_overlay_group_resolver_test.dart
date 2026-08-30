import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_overlay_group_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PageTextItem text(String id, {String? groupId}) =>
      PageTextItem(id: id, x: 0, y: 0, text: id, groupId: groupId);

  PageImageItem image(String id, {String? groupId}) => PageImageItem(
    id: id,
    x: 0,
    y: 0,
    filePath: '/assets/$id.png',
    groupId: groupId,
  );

  PageShapeItem shape(String id, {String? groupId}) => PageShapeItem(
    id: id,
    shapeType: ShapeType.rect,
    x: 0,
    y: 0,
    groupId: groupId,
  );

  test('选中任意分组成员会跨对象类型展开同组元素', () {
    final result = EditorOverlayGroupResolver.expand(
      selectedIds: <String>{'image'},
      textItems: <PageTextItem>[text('text', groupId: 'g1')],
      imageItems: <PageImageItem>[
        image('image', groupId: 'g1'),
        image('other', groupId: 'g2'),
      ],
      shapes: <PageShapeItem>[
        shape('shape', groupId: 'g1'),
        shape('ungrouped'),
      ],
    );

    expect(result, <String>{'text', 'image', 'shape'});
  });

  test('没有分组或空选择时保留选择语义且不修改输入集合', () {
    final selected = <String>{'ungrouped'};
    final noGroup = EditorOverlayGroupResolver.expand(
      selectedIds: selected,
      textItems: <PageTextItem>[text('ungrouped')],
      imageItems: const <PageImageItem>[],
      shapes: const <PageShapeItem>[],
    );
    final empty = EditorOverlayGroupResolver.expand(
      selectedIds: const <String>{},
      textItems: const <PageTextItem>[],
      imageItems: const <PageImageItem>[],
      shapes: const <PageShapeItem>[],
    );

    expect(noGroup, <String>{'ungrouped'});
    expect(empty, isEmpty);
    expect(selected, <String>{'ungrouped'});
  });

  test('解析结果是只读集合', () {
    final result = EditorOverlayGroupResolver.expand(
      selectedIds: <String>{'text'},
      textItems: <PageTextItem>[text('text', groupId: 'g1')],
      imageItems: const <PageImageItem>[],
      shapes: const <PageShapeItem>[],
    );

    expect(() => result.add('unexpected'), throwsUnsupportedError);
  });
}
