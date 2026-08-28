import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('合法端点创建有方向的 PageConnector', () {
    final connector = EditorLinkMutation.createConnector(
      sourceId: 'source',
      targetId: 'target',
      connectorId: 'connector-1',
    );

    expect(connector, isNotNull);
    expect(connector!.id, 'connector-1');
    expect(connector.fromItemId, 'source');
    expect(connector.toItemId, 'target');
  });

  test('空起点、空目标和空连接 id 不创建连接', () {
    expect(
      EditorLinkMutation.createConnector(
        sourceId: null,
        targetId: 'target',
        connectorId: 'connector-1',
      ),
      isNull,
    );
    expect(
      EditorLinkMutation.createConnector(
        sourceId: 'source',
        targetId: '',
        connectorId: 'connector-1',
      ),
      isNull,
    );
    expect(
      EditorLinkMutation.createConnector(
        sourceId: 'source',
        targetId: 'target',
        connectorId: '',
      ),
      isNull,
    );
  });

  test('同一对象不能连接到自身', () {
    expect(
      EditorLinkMutation.createConnector(
        sourceId: 'same',
        targetId: 'same',
        connectorId: 'connector-1',
      ),
      isNull,
    );
  });
}
