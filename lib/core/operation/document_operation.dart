import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 文档操作记录（内核 P0-2 Operation Engine 第一阶段，2026-10-11）。
///
/// 与 `DocCommand` 体系的分工（双轨原则，见整改清单 §七风险控制）：
/// - **命令**（document_commands.dart）：持有对象引用与回调的行为闭包，
///   会话内驱动撤销/重做——权威执行路径，本轮起继续保留；
/// - **操作**（本文件）：按 id 寻址、可 JSON 序列化的**语义记录**，与命令
///   在相同提交点成对产生（影子记录）。消费方：历史压缩（Level 2/3）、
///   会话日志导出、未来的增量同步——三系统共用同一套操作语义。
///
/// 寻址：图层按 `layerId`、笔画按 stroke `id`（格式 v3 落地的持久身份）。
/// apply/revert 直接变换 [DrawingDocument]，**不触发渲染缓存失效**——
/// 本阶段操作是记录/语义层，缓存协调仍归命令路径的控制器钩子（第二阶段
/// 接管执行权时一并迁移）。
///
/// 索引快照的 LIFO 假设与 `TransformStrokesCommand`/`EraseStrokesCommand`
/// 注释同一依据：操作栈按序回放，回放时文档必处于记录时的状态。
sealed class DocumentOperation {
  const DocumentOperation();

  Map<String, dynamic> toJson();

  /// 前进：把操作施加到文档（等价于对应命令的 redo）。
  void apply(DrawingDocument doc);

  /// 逆退：撤销操作的效果（等价于对应命令的 undo）。
  void revert(DrawingDocument doc);

  static DocumentOperation fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case OpStrokeAdd.typeKey:
        return OpStrokeAdd.fromJson(json);
      case OpStrokeRemove.typeKey:
        return OpStrokeRemove.fromJson(json);
      case OpStrokeReplace.typeKey:
        return OpStrokeReplace.fromJson(json);
      case OpLayerProp.typeKey:
        return OpLayerProp.fromJson(json);
      case OpLayerReorder.typeKey:
        return OpLayerReorder.fromJson(json);
      case OpBatch.typeKey:
        return OpBatch.fromJson(json);
      default:
        throw FormatException('未知操作类型: ${json['type']}');
    }
  }
}

/// 擦除条目：图层 id + 删除时位置 + 笔画完整 JSON。
typedef StrokeRemoveEntry = ({String layerId, int index, Map<String, dynamic> stroke});

/// 追加一笔（对应 AddStrokeCommand）。
final class OpStrokeAdd extends DocumentOperation {
  const OpStrokeAdd({required this.layerId, required this.stroke});

  static const String typeKey = 'stroke.add';

  final String layerId;
  final Map<String, dynamic> stroke;

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'layerId': layerId,
    'stroke': stroke,
  };

  factory OpStrokeAdd.fromJson(Map<String, dynamic> json) => OpStrokeAdd(
    layerId: json['layerId'] as String,
    stroke: Map<String, dynamic>.from(json['stroke'] as Map),
  );

  @override
  void apply(DrawingDocument doc) {
    _layer(doc, layerId).strokes.add(Stroke.fromJson(stroke));
  }

  @override
  void revert(DrawingDocument doc) {
    final payloadId = stroke['id'];
    final strokes = _layer(doc, layerId).strokes;
    strokes.removeWhere((s) => payloadId is String && s.id == payloadId);
  }
}

/// 一次擦除手势移除的一批笔画（对应 EraseStrokesCommand；形状部分本阶段
/// 仍由命令体系管理——对应命令的 [DocumentOperation.operation] 返回 null）。
final class OpStrokeRemove extends DocumentOperation {
  const OpStrokeRemove({required this.entries});

  static const String typeKey = 'stroke.remove';

  /// 按删除顺序记录；`index` 为删除时图层内位置（回退按原位插回）。
  final List<StrokeRemoveEntry> entries;

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'entries': [
      for (final e in entries)
        {'layerId': e.layerId, 'index': e.index, 'stroke': e.stroke},
    ],
  };

  factory OpStrokeRemove.fromJson(Map<String, dynamic> json) => OpStrokeRemove(
    entries: [
      for (final e in json['entries'] as List)
        (
          layerId: (e as Map)['layerId'] as String,
          index: (e['index'] as num).toInt(),
          stroke: Map<String, dynamic>.from(e['stroke'] as Map),
        ),
    ],
  );

  @override
  void apply(DrawingDocument doc) {
    for (final e in entries) {
      final payloadId = e.stroke['id'];
      _layer(doc, e.layerId).strokes.removeWhere(
        (s) => payloadId is String && s.id == payloadId,
      );
    }
  }

  @override
  void revert(DrawingDocument doc) {
    // 按图层分组、组内按原序号升序逐条插回——与 EraseStrokesCommand.undo
    // 同一算法（存活笔画相对序不变，逐次 insert 恰好还原手势起始次序）。
    final byLayer = <String, List<StrokeRemoveEntry>>{};
    for (final e in entries) {
      byLayer.putIfAbsent(e.layerId, () => []).add(e);
    }
    for (final entry in byLayer.entries) {
      final strokes = _layer(doc, entry.key).strokes;
      final ordered = [...entry.value]..sort((a, b) => a.index - b.index);
      for (final e in ordered) {
        strokes.insert(e.index.clamp(0, strokes.length), Stroke.fromJson(e.stroke));
      }
    }
  }
}

/// 一批笔画被替换为新版本（对应 TransformStrokesCommand；按 id 寻址）。
final class OpStrokeReplace extends DocumentOperation {
  const OpStrokeReplace({required this.layerId, required this.entries});

  static const String typeKey = 'stroke.replace';

  /// 操作目标图层。
  final String layerId;

  /// (id, 变换前, 变换后)。before/after 均为完整笔画 JSON。
  final List<({String id, Map<String, dynamic> before, Map<String, dynamic> after})>
  entries;

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'layerId': layerId,
    'entries': [
      for (final e in entries)
        {'id': e.id, 'before': e.before, 'after': e.after},
    ],
  };

  factory OpStrokeReplace.fromJson(Map<String, dynamic> json) =>
      OpStrokeReplace(
        layerId: json['layerId'] as String,
        entries: [
          for (final e in json['entries'] as List)
            (
              id: (e as Map)['id'] as String,
              before: Map<String, dynamic>.from(e['before'] as Map),
              after: Map<String, dynamic>.from(e['after'] as Map),
            ),
        ],
      );

  @override
  void apply(DrawingDocument doc) => _replaceWith(doc, entries.map((e) => e.after));

  @override
  void revert(DrawingDocument doc) => _replaceWith(doc, entries.map((e) => e.before));

  void _replaceWith(DrawingDocument doc, Iterable<Map<String, dynamic>> jsons) {
    final strokes = _layer(doc, layerId).strokes;
    var cursor = 0;
    for (final json in jsons) {
      final id = json['id'] as String?;
      final index = strokes.indexWhere((s) => s.id == id);
      if (index < 0) {
        throw StateError('OpStrokeReplace: 笔画 $id 不存在于图层 $layerId');
      }
      // 条目按原位互异；id 寻址下 cursor 单调校验保持与命令的 LIFO 假设一致。
      if (index < cursor) {
        throw StateError('OpStrokeReplace: 条目顺序错乱（$index < $cursor）');
      }
      cursor = index;
      strokes[index] = Stroke.fromJson(json);
    }
  }
}

/// 图层标量属性变更（对应 LayerVisibilityCommand / LayerOpacityCommand）。
final class OpLayerProp extends DocumentOperation {
  const OpLayerProp({
    required this.layerId,
    required this.prop,
    required this.before,
    required this.after,
  });

  static const String typeKey = 'layer.prop';

  static const String propVisible = 'visible';
  static const String propOpacity = 'opacity';

  final String layerId;
  final String prop;
  final Object before;
  final Object after;

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'layerId': layerId,
    'prop': prop,
    'before': before,
    'after': after,
  };

  factory OpLayerProp.fromJson(Map<String, dynamic> json) => OpLayerProp(
    layerId: json['layerId'] as String,
    prop: json['prop'] as String,
    before: json['before'] as Object,
    after: json['after'] as Object,
  );

  @override
  void apply(DrawingDocument doc) => _set(doc, after);

  @override
  void revert(DrawingDocument doc) => _set(doc, before);

  void _set(DrawingDocument doc, Object value) {
    final layer = _layer(doc, layerId);
    switch (prop) {
      case propVisible:
        layer.visible = value as bool;
      case propOpacity:
        layer.opacity = (value as num).toDouble();
      default:
        throw FormatException('未知图层属性: $prop');
    }
  }
}

/// 图层相邻换位（对应 LayerReorderCommand）。
final class OpLayerReorder extends DocumentOperation {
  const OpLayerReorder({required this.from, required this.to});

  static const String typeKey = 'layer.reorder';

  final int from;
  final int to;

  @override
  Map<String, dynamic> toJson() => {'type': typeKey, 'from': from, 'to': to};

  factory OpLayerReorder.fromJson(Map<String, dynamic> json) => OpLayerReorder(
    from: (json['from'] as num).toInt(),
    to: (json['to'] as num).toInt(),
  );

  @override
  void apply(DrawingDocument doc) {
    final l = doc.layers.removeAt(from);
    doc.layers.insert(to, l);
  }

  @override
  void revert(DrawingDocument doc) {
    final l = doc.layers.removeAt(to);
    doc.layers.insert(from, l);
  }
}

/// 批量原子操作（对应 DocumentTransaction）：apply 按序、revert 逆序。
final class OpBatch extends DocumentOperation {
  const OpBatch({required this.ops});

  static const String typeKey = 'batch';

  final List<DocumentOperation> ops;

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'ops': [for (final op in ops) op.toJson()],
  };

  factory OpBatch.fromJson(Map<String, dynamic> json) => OpBatch(
    ops: [
      for (final op in json['ops'] as List)
        DocumentOperation.fromJson(Map<String, dynamic>.from(op as Map)),
    ],
  );

  @override
  void apply(DrawingDocument doc) {
    for (final op in ops) {
      op.apply(doc);
    }
  }

  @override
  void revert(DrawingDocument doc) {
    for (final op in ops.reversed) {
      op.revert(doc);
    }
  }
}

Layer _layer(DrawingDocument doc, String layerId) {
  for (final layer in doc.layers) {
    if (layer.id == layerId) return layer;
  }
  throw StateError('Operation: 图层 $layerId 不存在');
}
