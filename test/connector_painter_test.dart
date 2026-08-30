import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连接线画笔复制连接线与对象位置快照', () {
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

    connectors.clear();
    positions['text-1'] = const Offset(0, 0);

    expect(painter.connectors, hasLength(1));
    expect(painter.itemPositions['text-1'], const Offset(10, 20));
    expect(
      () => painter.connectors.add(
        PageConnector(id: 'c-2', fromItemId: 'a', toItemId: 'b'),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => painter.itemPositions['text-1'] = Offset.zero,
      throwsUnsupportedError,
    );
  });
}
