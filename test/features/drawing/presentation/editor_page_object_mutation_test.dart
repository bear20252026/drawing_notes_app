import 'package:drawing_notes_app/features/drawing/domain/page_chart_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('分组标记覆盖文字、图片和形状且返回实际变更数量', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/image.png',
      x: 0,
      y: 0,
    );
    final shape = PageShapeItem(
      id: 'shape-1',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 40,
      height: 40,
    );

    final changed = EditorPageObjectMutation.setGroupId(
      ids: {'text-1', 'image-1', 'shape-1', 'missing'},
      groupId: 'group-1',
      textItems: [text],
      imageItems: [image],
      shapes: [shape],
    );

    expect(changed, 3);
    expect(text.groupId, 'group-1');
    expect(image.groupId, 'group-1');
    expect(shape.groupId, 'group-1');
  });

  test('删除跨混排对象集合只移除命中的对象并返回数量', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final keptText = PageTextItem(id: 'text-2', x: 0, y: 0, text: '保留');
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/image.png',
      x: 0,
      y: 0,
    );
    final shape = PageShapeItem(
      id: 'shape-1',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 40,
      height: 40,
    );
    final chart = PageChartItem(
      id: 'chart-1',
      chartType: ChartType.bar,
      data: [1, 2, 3],
    );

    final textItems = [text, keptText];
    final imageItems = [image];
    final shapes = [shape];
    final charts = [chart];

    final removed = EditorPageObjectMutation.remove(
      ids: {'text-1', 'image-1', 'shape-1', 'chart-1', 'missing'},
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );

    expect(removed, 4);
    expect(textItems, [keptText]);
    expect(imageItems, isEmpty);
    expect(shapes, isEmpty);
    expect(charts, isEmpty);
  });

  test('文字对象查找按 ID 返回原实例，缺失 ID 返回 null', () {
    final item = PageTextItem(id: 'found', x: 0, y: 0, text: '文字');
    final items = [item];

    expect(EditorTextMutation.findById(items: items, id: 'found'), same(item));
    expect(EditorTextMutation.findById(items: items, id: 'missing'), isNull);
  });

  test('文字命中按字号命中框返回首个对象，空白处返回 null', () {
    final first = PageTextItem(
      id: 'first',
      x: 10,
      y: 20,
      text: '第一段',
      fontSize: 30,
    );
    final overlapping = PageTextItem(
      id: 'second',
      x: 10,
      y: 20,
      text: '第二段',
      fontSize: 30,
    );

    expect(
      EditorTextMutation.hitTextId(items: [first, overlapping], x: 70, y: 50),
      'first',
    );
    expect(EditorTextMutation.hitTextId(items: [first], x: 71, y: 50), isNull);
    expect(EditorTextMutation.hitTextId(items: [first], x: 10, y: 51), isNull);
  });

  test('临时文字块创建保留调用方坐标和唯一 ID，默认不带文本', () {
    final draft = EditorTextMutation.createDraft(
      id: 'draft-1',
      x: 123.5,
      y: 456.5,
    );

    expect(draft.id, 'draft-1');
    expect(draft.position.dx, 123.5);
    expect(draft.position.dy, 456.5);
    expect(draft.text, isEmpty);
    expect(draft.fontSize, 24);
  });

  test('文字样式协作者保持字号边界并统一处理颜色', () {
    final first = PageTextItem(
      id: 'text-1',
      x: 0,
      y: 0,
      text: '第一段',
      fontSize: 24,
      color: 0xFF111111,
    );
    final second = PageTextItem(
      id: 'text-2',
      x: 10,
      y: 20,
      text: '第二段',
      fontSize: 36,
      color: 0xFF222222,
    );

    EditorTextStyleMutation.setFontSize(item: first, size: 2);
    expect(first.fontSize, 8);
    EditorTextStyleMutation.setFontSize(item: first, size: 240);
    expect(first.fontSize, 200);
    EditorTextStyleMutation.setFontSize(item: first, size: 48.5);
    expect(first.fontSize, 48.5);

    EditorTextStyleMutation.setColor(item: first, color: 0xFFAABBCC);
    expect(first.color, 0xFFAABBCC);

    final recolored = EditorTextStyleMutation.recolorAll(
      items: [first, second],
      color: 0xFFABCDEF,
    );
    expect(recolored, 2);
    expect(first.color, 0xFFABCDEF);
    expect(second.color, 0xFFABCDEF);
    expect(EditorTextStyleMutation.recolorAll(items: const [], color: 1), 0);
  });

  test('图片定位契约保留分页中心与独立文档尺寸偏移', () {
    final pagePosition = EditorImageMutation.pageImagePosition(
      centerX: 500,
      centerY: 400,
    );
    expect(pagePosition.x, 500);
    expect(pagePosition.y, 400);

    final documentPosition = EditorImageMutation.documentImagePosition(
      centerX: 500,
      centerY: 400,
    );
    expect(documentPosition.x, 400);
    expect(documentPosition.y, 325);
  });

  test('图片构造保留分页与独立文档的默认尺寸和调用方坐标', () {
    final pageImage = EditorImageMutation.createPageImage(
      id: 'page-image',
      x: 12,
      y: 34,
      filePath: '/offline/page.png',
    );
    final documentImage = EditorImageMutation.createDocumentImage(
      id: 'document-image',
      x: 56,
      y: 78,
      filePath: '/offline/document.png',
    );

    expect(pageImage.id, 'page-image');
    expect(pageImage.position.dx, 12);
    expect(pageImage.position.dy, 34);
    expect(pageImage.filePath, '/offline/page.png');
    expect(pageImage.width, 200);
    expect(pageImage.height, 150);
    expect(documentImage.id, 'document-image');
    expect(documentImage.position.dx, 56);
    expect(documentImage.position.dy, 78);
    expect(documentImage.filePath, '/offline/document.png');
    expect(documentImage.width, 200);
    expect(documentImage.height, 150);
  });

  test('超链接读写统一覆盖文字、图片和形状，缺失对象安全返回', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final image = PageImageItem(
      id: 'image-1',
      filePath: '/tmp/image.png',
      x: 0,
      y: 0,
    );
    final shape = PageShapeItem(
      id: 'shape-1',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 40,
      height: 40,
    );
    final textItems = [text];
    final imageItems = [image];
    final shapes = [shape];

    expect(
      EditorHyperlinkMutation.setHref(
        id: 'text-1',
        href: 'https://text.example',
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      isTrue,
    );
    expect(
      EditorHyperlinkMutation.setHref(
        id: 'image-1',
        href: 'mailto:image@example.com',
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      isTrue,
    );
    expect(
      EditorHyperlinkMutation.setHref(
        id: 'shape-1',
        href: null,
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      isTrue,
    );

    expect(
      EditorHyperlinkMutation.hrefOf(
        id: 'text-1',
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      'https://text.example',
    );
    expect(
      EditorHyperlinkMutation.hrefOf(
        id: 'image-1',
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      'mailto:image@example.com',
    );
    expect(
      EditorHyperlinkMutation.hrefOf(
        id: 'shape-1',
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      isNull,
    );
    expect(
      EditorHyperlinkMutation.setHref(
        id: 'missing',
        href: 'https://missing.example',
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
      ),
      isFalse,
    );
  });

  test('文字提交会 trim 并去重加入，空文本不会修改对象', () {
    final pending = PageTextItem(id: 'text-1', x: 0, y: 0, text: '旧内容');
    final existing = [pending];

    expect(
      EditorTextMutation.commit(
        pending: pending,
        rawText: '  新内容  ',
        items: existing,
      ),
      isTrue,
    );
    expect(pending.text, '新内容');
    expect(existing, hasLength(1));

    final fresh = PageTextItem(id: 'text-2', x: 10, y: 20, text: '');
    final target = <PageTextItem>[];
    expect(
      EditorTextMutation.commit(pending: fresh, rawText: '新文字', items: target),
      isTrue,
    );
    expect(target, [fresh]);

    expect(
      EditorTextMutation.commit(pending: fresh, rawText: '   ', items: target),
      isFalse,
    );
    expect(fresh.text, '新文字');
    expect(target, [fresh]);
  });

  test('空 id 集合不会修改任何对象', () {
    final text = PageTextItem(id: 'text-1', x: 0, y: 0, text: '文字');
    final textItems = [text];

    final changed = EditorPageObjectMutation.setGroupId(
      ids: const {},
      groupId: 'group-1',
      textItems: textItems,
      imageItems: const [],
      shapes: const [],
    );
    final removed = EditorPageObjectMutation.remove(
      ids: const {},
      textItems: textItems,
      imageItems: [],
      shapes: [],
      charts: [],
    );

    expect(changed, 0);
    expect(removed, 0);
    expect(text.groupId, isNull);
    expect(textItems, [text]);
  });
}
