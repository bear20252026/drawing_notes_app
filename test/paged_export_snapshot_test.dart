import 'package:drawing_notes_app/features/drawing/application/paged_export_snapshot.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('导出快照复制文字与 JSON 负载，避免持有可变笔记页面状态', () {
    final textItem = PageTextItem(id: 'text-1', x: 8, y: 16, text: '原始内容');
    final imageItem = <String, dynamic>{'id': 'image-1', 'x': 12};
    final shapeItem = <String, dynamic>{'id': 'shape-1', 'type': 'rect'};

    final snapshot = PagedExportSnapshot(
      title: '会议记录',
      textItems: [textItem],
      imageItems: [imageItem],
      shapes: [shapeItem],
    );

    textItem.text = '后续编辑';
    imageItem['x'] = 99;
    shapeItem['type'] = 'arrow';

    expect(snapshot.title, '会议记录');
    expect(snapshot.textItems.single.text, '原始内容');
    expect(snapshot.imageItems.single['x'], 12);
    expect(snapshot.shapes.single['type'], 'rect');
    expect(
      () => snapshot.textItems.add(
        PageTextItem(id: 'text-2', x: 0, y: 0, text: '不应加入'),
      ),
      throwsUnsupportedError,
    );
    expect(() => snapshot.imageItems.single['x'] = 100, throwsUnsupportedError);
  });
}
