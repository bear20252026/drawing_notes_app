import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

/// 混排对象拖动/删除时的分组成员解析器。
///
/// 该协作者只读取对象 id 与 groupId，并返回不可变的扩展结果。它不修改页面对象，
/// 不处理坐标、网格吸附、动画、通知或持久化。
class EditorOverlayGroupResolver {
  const EditorOverlayGroupResolver._();

  static Set<String> expand({
    required Set<String> selectedIds,
    required Iterable<PageTextItem> textItems,
    required Iterable<PageImageItem> imageItems,
    required Iterable<PageShapeItem> shapes,
  }) {
    final selected = Set<String>.of(selectedIds);
    if (selected.isEmpty) return Set<String>.unmodifiable(selected);

    final groups = <String>{};
    void collect(String id, String? groupId) {
      if (selected.contains(id) && groupId != null) groups.add(groupId);
    }

    for (final text in textItems) {
      collect(text.id, text.groupId);
    }
    for (final image in imageItems) {
      collect(image.id, image.groupId);
    }
    for (final shape in shapes) {
      collect(shape.id, shape.groupId);
    }
    if (groups.isEmpty) return Set<String>.unmodifiable(selected);

    void include(String id, String? groupId) {
      if (groupId != null && groups.contains(groupId)) selected.add(id);
    }

    for (final text in textItems) {
      include(text.id, text.groupId);
    }
    for (final image in imageItems) {
      include(image.id, image.groupId);
    }
    for (final shape in shapes) {
      include(shape.id, shape.groupId);
    }
    return Set<String>.unmodifiable(selected);
  }
}
