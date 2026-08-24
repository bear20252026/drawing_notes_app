// editor_core——NodeBasedSystem 节点系统（fldraw 借鉴——2026-08-21）。
//
// fldraw（Flutter tldraw 替代品）本地化——自定义节点系统。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// fldraw 原版参考：
// - 节点头（header）+ 内容（content）+ 可编辑字段（editable fields）
// - 智能附件（箭头自动吸附到节点/形状边缘——Smart Attachments）
// - 节点连接（connections between nodes）
library;

/// 节点字段类型（fldraw editable fields 借鉴）。
enum NodeFieldType {
  text,
  number,
  boolean,
  select,
  color,
}

/// 节点字段定义（fldraw editable field 本地化——不可变）。
class NodeField {
  const NodeField({
    required this.id,
    required this.label,
    required this.type,
    this.value = '',
    this.options = const [],
    this.required = false,
  });

  final String id;
  final String label;
  final NodeFieldType type;
  final String value;
  final List<String> options; // select 类型的选项列表。
  final bool required;

  NodeField copyWith({String? label, String? value, List<String>? options, bool? required}) {
    return NodeField(
      id: id,
      label: label ?? this.label,
      type: type,
      value: value ?? this.value,
      options: options ?? this.options,
      required: required ?? this.required,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NodeField && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 节点类型（fldraw node types 借鉴）。
enum NodeType {
  /// 普通节点（矩形卡片）。
  card,

  /// 标题节点（只有标题）。
  header,

  /// 图片节点。
  image,

  /// 代码节点。
  code,

  /// 列表节点。
  list,

  /// 自定义节点。
  custom,
}

/// 节点（fldraw Node 本地化——不可变）。
///
/// 每个节点是一个自包含的卡片/块——包含标题/内容/字段/位置/尺寸。
/// 与 ShapeItem 不同：ShapeItem 是纯图形（矩形/椭圆），Node 是带内容的数据块。
class NodeItem {
  const NodeItem({
    required this.id,
    required this.type,
    this.title = '',
    this.content = '',
    this.fields = const [],
    this.x = 0,
    this.y = 0,
    this.width = 200,
    this.height = 150,
    this.color = '#FFFFFF',
    this.borderColor = '#000000',
    this.rotation = 0,
  });

  final String id;
  final NodeType type;
  final String title;
  final String content;
  final List<NodeField> fields;
  final double x;
  final double y;
  final double width;
  final double height;
  final String color;
  final String borderColor;
  final double rotation;

  /// 获取字段值。
  String? getFieldValue(String fieldId) {
    return fields.where((f) => f.id == fieldId).firstOrNull?.value;
  }

  /// 更新字段值。
  NodeItem updateField(String fieldId, String value) {
    return copyWith(
      fields: fields.map((f) => f.id == fieldId ? f.copyWith(value: value) : f).toList(),
    );
  }

  /// 中心点。
  ({double x, double y}) get center => (x: x + width / 2, y: y + height / 2);

  /// 边界。
  ({double left, double top, double right, double bottom}) get bounds =>
      (left: x, top: y, right: x + width, bottom: y + height);

  NodeItem copyWith({
    NodeType? type,
    String? title,
    String? content,
    List<NodeField>? fields,
    double? x,
    double? y,
    double? width,
    double? height,
    String? color,
    String? borderColor,
    double? rotation,
  }) {
    return NodeItem(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      fields: fields ?? this.fields,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      color: color ?? this.color,
      borderColor: borderColor ?? this.borderColor,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NodeItem && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 节点连接（fldraw Smart Attachments 借鉴——不可变）。
///
/// 两个节点之间的连接线（起点节点 + 终点节点 + 标签）。
class NodeConnection {
  const NodeConnection({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.label = '',
    this.sourcePort = '',
    this.targetPort = '',
  });

  final String id;
  final String sourceId;
  final String targetId;
  final String label;
  final String sourcePort;
  final String targetPort;

  NodeConnection copyWith({String? label, String? sourcePort, String? targetPort}) {
    return NodeConnection(
      id: id,
      sourceId: sourceId,
      targetId: targetId,
      label: label ?? this.label,
      sourcePort: sourcePort ?? this.sourcePort,
      targetPort: targetPort ?? this.targetPort,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NodeConnection && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 节点图（fldraw NodeGraph 本地化——不可变）。
///
/// 管理节点集合 + 连接集合——积木式独立。
class NodeGraph {
  const NodeGraph({
    this.nodes = const [],
    this.connections = const [],
  });

  final List<NodeItem> nodes;
  final List<NodeConnection> connections;

  bool get isEmpty => nodes.isEmpty;
  int get nodeCount => nodes.length;
  int get connectionCount => connections.length;

  /// 获取节点。
  NodeItem? getNode(String nodeId) {
    return nodes.where((n) => n.id == nodeId).firstOrNull;
  }

  /// 获取节点的连接。
  List<NodeConnection> getNodeConnections(String nodeId) {
    return connections.where((c) => c.sourceId == nodeId || c.targetId == nodeId).toList();
  }

  /// 添加节点。
  NodeGraph addNode(NodeItem node) {
    return NodeGraph(nodes: [...nodes, node], connections: connections);
  }

  /// 移除节点（同时移除相关连接）。
  NodeGraph removeNode(String nodeId) {
    return NodeGraph(
      nodes: nodes.where((n) => n.id != nodeId).toList(),
      connections: connections.where((c) => c.sourceId != nodeId && c.targetId != nodeId).toList(),
    );
  }

  /// 更新节点。
  NodeGraph updateNode(NodeItem node) {
    return NodeGraph(
      nodes: nodes.map((n) => n.id == node.id ? node : n).toList(),
      connections: connections,
    );
  }

  /// 添加连接。
  NodeGraph addConnection(NodeConnection connection) {
    return NodeGraph(nodes: nodes, connections: [...connections, connection]);
  }

  /// 移除连接。
  NodeGraph removeConnection(String connectionId) {
    return NodeGraph(
      nodes: nodes,
      connections: connections.where((c) => c.id != connectionId).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NodeGraph && nodeCount == other.nodeCount;

  @override
  int get hashCode => nodeCount.hashCode;
}
