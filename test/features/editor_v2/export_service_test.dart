import 'package:flutter_test/flutter_test.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/editor_v2/application/export_service.dart';

/// 批次 F-6：导出服务测试（JSON/SVG——纯逻辑——不依赖 UI）。
void main() {
  late DocumentV2 doc;

  setUp(() {
    doc = const DocumentV2(
      id: 'doc1',
      pageCount: 1,
      revision: 1,
      layers: [
        LayerV2(
          id: 'layer-1',
          name: 'Layer 1',
          strokes: [LineItem(id: 's1', points: [Point(0, 0), Point(10, 10)])],
          shapes: [
            ShapeItem(id: 'sh1', type: 'rect', x: 10, y: 20, width: 100, height: 80),
          ],
          texts: [TextItem(id: 't1', content: 'Hello', x: 50, y: 50)],
        ),
      ],
    );
  });

  test('toJson：序列化文档', () {
    final json = ExportService.toJson(doc);
    // jsonEncode 无空格格式。
    expect(json, contains('"type":"excalidraw"'));
    expect(json, contains('"version":2'));
    expect(json, contains('"documentId":"doc1"'));
    expect(json, contains('"revision":1'));
    expect(json, contains('"layers"'));
    expect(json, contains('"strokes"'));
    expect(json, contains('"shapes"'));
    expect(json, contains('"texts"'));
  });

  test('toSvg：生成 SVG', () {
    final svg = ExportService.toSvg(doc);
    expect(svg, contains('<svg'));
    expect(svg, contains('</svg>'));
    // 笔画 path（double toString 带 .0）。
    expect(svg, contains('<path d="M0.0,0.0'));
    // 形状 rect（double toString 带 .0）。
    expect(svg, contains('<rect x="10.0" y="20.0" width="100.0" height="80.0"'));
    // 文本（double toString 带 .0）。
    expect(svg, contains('<text x="50.0" y="50.0"'));
    expect(svg, contains('Hello'));
  });

  test('toSvg：XML 转义', () {
    const docWithSpecial = DocumentV2(
      id: 'doc2',
      pageCount: 1,
      layers: [
        LayerV2(
          id: 'layer-1',
          name: 'Layer 1',
          texts: [TextItem(id: 't1', content: '<b>&"\'', x: 0, y: 0)],
        ),
      ],
    );
    final svg = ExportService.toSvg(docWithSpecial);
    expect(svg, contains('&lt;b&gt;'));
    expect(svg, contains('&amp;'));
  });
}
