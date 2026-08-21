import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// fldraw 借鉴——NodeGraph 节点系统测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('NodeField：copyWith 不可变', () {
    const field = NodeField(id: 'f1', label: 'Name', type: NodeFieldType.text);
    final updated = field.copyWith(value: 'Alice');
    expect(field.value, ''); // 原实例不变。
    expect(updated.value, 'Alice');
  });

  test('NodeItem：copyWith + center + bounds', () {
    const node = NodeItem(id: 'n1', type: NodeType.card, x: 10, y: 20, width: 100, height: 80);
    expect(node.center.x, 60);
    expect(node.center.y, 60);
    expect(node.bounds.left, 10);
    expect(node.bounds.right, 110);
    final moved = node.copyWith(x: 50, y: 50);
    expect(node.x, 10); // 原实例不变。
    expect(moved.x, 50);
  });

  test('NodeItem：getFieldValue / updateField', () {
    const node = NodeItem(
      id: 'n1', type: NodeType.card,
      fields: [
        NodeField(id: 'name', label: 'Name', type: NodeFieldType.text, value: 'Alice'),
        NodeField(id: 'age', label: 'Age', type: NodeFieldType.number, value: '30'),
      ],
    );
    expect(node.getFieldValue('name'), 'Alice');
    expect(node.getFieldValue('age'), '30');
    expect(node.getFieldValue('unknown'), isNull);
    final updated = node.updateField('age', '31');
    expect(updated.getFieldValue('age'), '31');
    expect(node.getFieldValue('age'), '30'); // 原实例不变。
  });

  test('NodeConnection：copyWith 不可变', () {
    const conn = NodeConnection(id: 'c1', sourceId: 'n1', targetId: 'n2');
    final labeled = conn.copyWith(label: 'connects');
    expect(conn.label, ''); // 原实例不变。
    expect(labeled.label, 'connects');
  });

  test('NodeGraph：addNode/removeNode/updateNode', () {
    const graph = NodeGraph();
    final withNode = graph.addNode(const NodeItem(id: 'n1', type: NodeType.card));
    expect(withNode.nodeCount, 1);
    final updated = withNode.updateNode(const NodeItem(id: 'n1', type: NodeType.header, title: 'Title'));
    expect(updated.getNode('n1')!.title, 'Title');
    final removed = updated.removeNode('n1');
    expect(removed.nodeCount, 0);
  });

  test('NodeGraph：addConnection/removeConnection + getNodeConnections', () {
    final graph = NodeGraph(
      nodes: [
        const NodeItem(id: 'n1', type: NodeType.card),
        const NodeItem(id: 'n2', type: NodeType.card),
      ],
    );
    final withConn = graph.addConnection(const NodeConnection(id: 'c1', sourceId: 'n1', targetId: 'n2'));
    expect(withConn.connectionCount, 1);
    expect(withConn.getNodeConnections('n1').length, 1);
    expect(withConn.getNodeConnections('n2').length, 1);
    final removed = withConn.removeConnection('c1');
    expect(removed.connectionCount, 0);
  });

  test('NodeGraph：removeNode 同时移除相关连接', () {
    var graph = NodeGraph(
      nodes: [
        const NodeItem(id: 'n1', type: NodeType.card),
        const NodeItem(id: 'n2', type: NodeType.card),
        const NodeItem(id: 'n3', type: NodeType.card),
      ],
    );
    graph = graph.addConnection(const NodeConnection(id: 'c1', sourceId: 'n1', targetId: 'n2'));
    graph = graph.addConnection(const NodeConnection(id: 'c2', sourceId: 'n2', targetId: 'n3'));
    expect(graph.connectionCount, 2);
    final withoutN2 = graph.removeNode('n2');
    expect(withoutN2.nodeCount, 2);
    expect(withoutN2.connectionCount, 0); // 两个连接都涉及 n2——全部移除。
  });

  test('NodeGraph：isEmpty / nodeCount', () {
    expect(const NodeGraph().isEmpty, true);
    expect(const NodeGraph().nodeCount, 0);
  });

  test('NodeType 枚举', () {
    expect(NodeType.values.length, 6);
  });
}
