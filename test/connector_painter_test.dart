import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 渲染性能调整（2026-09-07）：ConnectorPainter 不再逐次
  // List/Map.unmodifiable 防御性拷贝（frameTick 高频重建下纯浪费），
  // 改为直接持有调用方集合引用。前提：调用方传入的是只读 session
  // 列表与每次 build 新建的快照 map，本测试钉住「零拷贝」新契约。
  test('连接线画笔直接持有调用方集合引用（零拷贝）', () {
    final connectors = [
      PageConnector(id: 'c-1', fromItemId: 'text-1', toItemId: 'image-1'),
    ];
    final positions = <String, Offset>{
      'text-1': const Offset(10, 20),
      'image-1': const Offset(80, 120),
    };
    final painter = ConnectorPainter(
      connectors: connectors,
      itemPositions: positions,
      controller: DrawingController(DrawingDocument(id: 'doc', title: '连接线')),
    );

    expect(painter.connectors, same(connectors));
    expect(painter.itemPositions, same(positions));
    expect(painter.connectors, hasLength(1));
    expect(painter.itemPositions['text-1'], const Offset(10, 20));
  });
}
