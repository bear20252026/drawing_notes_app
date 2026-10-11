// Operation Engine 等价性测试（内核 P0-2 第一阶段，2026-10-11）。
//
// 核心命题：**同一场景由命令驱动（文档 A）与由操作记录驱动（文档 B），
// 每一步之后两份文档的编解码快照逐字节相等；全量撤销（命令栈）与全量
// revert（操作逆序）的终点也相等**——这是「三系统共用一套操作语义」的
// 可证形式。另覆盖：JSON 往返、日志容量/JSONL、批原子性。
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/operation/document_operation.dart';
import 'package:drawing_notes_app/core/operation/operation_log.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/features/drawing/application/doc_command_context.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_edit_history.dart';

Stroke _stroke(String id, int seedShift) => Stroke(
  id: id,
  points: [
    StrokePoint(10 + seedShift.toDouble(), 20, 0.5),
    StrokePoint(60, 80 + seedShift.toDouble(), 0.75),
  ],
  color: const Color.fromARGB(255, 26, 26, 26),
  width: 2,
  type: BrushType.pen,
);

/// 最小命令上下文：文档 + 空回调（渲染缓存等历史副作用归控制器，
/// 本测试只验证命令与操作对**文档状态**的变换等价性）。
class _MinimalContext implements DocCommandContext {
  _MinimalContext(this.document);

  @override
  final DrawingDocument document;

  @override
  void restoreLayersSnapshot(_) {}

  @override
  void touchDocument() {}

  @override
  void afterLayerUndoRedo() {}

  @override
  Future<void> afterStrokeUndoRedo(int layerIndex) async {}

  @override
  void undoRecognizedShape(int layerIndex, Stroke stroke, shape) {}

  @override
  void redoRecognizedShape(int layerIndex, Stroke stroke, shape) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('命令流 vs 操作流：逐步快照相等 + 全量撤销/revert 终点相等', () async {
    // 时间戳固定：Windows 时钟精度粗（毫秒级），两文档同刻构造可能恰好
    // 相等；CI Linux 微秒级——默认 DateTime.now() 会差几微秒打碎逐字节断言。
    final stamp = DateTime.fromMillisecondsSinceEpoch(0);
    final docA = DrawingDocument(
      id: 'eq_doc',
      title: 'equivalence',
      layers: [Layer(id: 'l1', name: ''), Layer(id: 'l2', name: '')],
      createdAt: stamp,
      updatedAt: stamp,
    );
    final docB = DrawingDocument(
      id: 'eq_doc',
      title: 'equivalence',
      layers: [Layer(id: 'l1', name: ''), Layer(id: 'l2', name: '')],
      createdAt: stamp,
      updatedAt: stamp,
    );
    final context = _MinimalContext(docA);
    final history = DocumentEditHistory(maxEntries: 100);
    const codec = DocumentCodec();
    String snapshotOf(DrawingDocument d) => utf8.decode(codec.encode(d));

    final ops = <DocumentOperation>[]; // 与命令同序的操作流（文档 B 驱动）。

    // 步骤 1：两图层各加一笔。
    final s1 = _stroke('str_s1', 0);
    final s2 = _stroke('str_s2', 5);
    final cmds1 = [
      AddStrokeCommand(context, 0, s1),
      AddStrokeCommand(context, 1, s2),
    ];
    final ops1 = <DocumentOperation>[
      OpStrokeAdd(layerId: 'l1', stroke: s1.toJson()),
      OpStrokeAdd(layerId: 'l2', stroke: s2.toJson()),
    ];
    // 步骤 2：变换（放大 l1 笔画，id 保持）。
    final after = Stroke(
      id: s1.id,
      points: [
        for (final p in s1.points) StrokePoint(p.x * 2, p.y * 2, p.pressure),
      ],
      color: s1.color,
      width: s1.width,
      type: s1.type,
      opacity: s1.opacity,
      seed: s1.seed,
      version: s1.version + 1,
    );
    final cmds2 = [
      TransformStrokesCommand(context, 0, [(index: 0, before: s1, after: after)]),
    ];
    final ops2 = <DocumentOperation>[
      OpStrokeReplace(
        layerId: 'l1',
        entries: [(id: s1.id, before: s1.toJson(), after: after.toJson())],
      ),
    ];
    // 步骤 3：擦除 l2 笔画（原位记录）。
    final cmds3 = [
      EraseStrokesCommand(context, [(layerIndex: 1, index: 0, stroke: s2)]),
    ];
    final ops3 = <DocumentOperation>[
      OpStrokeRemove(entries: [(layerId: 'l2', index: 0, stroke: s2.toJson())]),
    ];
    // 步骤 4：图层显隐 / 透明度 / 换位。
    final cmds4 = [
      LayerVisibilityCommand(context, 0, true, false),
      LayerOpacityCommand(context, 1, 1.0, 0.6),
      LayerReorderCommand(context, 0, 1),
    ];
    final ops4 = <DocumentOperation>[
      OpLayerProp(
        layerId: 'l1',
        prop: OpLayerProp.propVisible,
        before: true,
        after: false,
      ),
      OpLayerProp(
        layerId: 'l2',
        prop: OpLayerProp.propOpacity,
        before: 1.0,
        after: 0.6,
      ),
      const OpLayerReorder(from: 0, to: 1),
    ];

    // 逐步推进：A 走命令栈，B 走操作流；每步后快照必须逐字节相等。
    for (final step in [
      (cmds1, ops1),
      (cmds2, ops2),
      (cmds3, ops3),
      (cmds4, ops4),
    ]) {
      for (final c in step.$1) {
        c.redo();
        history.push(c);
      }
      for (final o in step.$2) {
        o.apply(docB);
        ops.add(o);
      }
      expect(snapshotOf(docB), snapshotOf(docA), reason: '步骤后快照相等');
    }

    // 全量撤销（命令栈）vs 全量 revert（操作逆序）→ 终点相等。
    while (history.undo()) {}
    for (final o in ops.reversed) {
      o.revert(docB);
    }
    expect(snapshotOf(docB), snapshotOf(docA), reason: '全量回退后两文档回到空基线');
  });

  test('命令 operation 访问器：类型与载荷逐字段正确', () {
    final doc = DrawingDocument(
      id: 'acc_doc',
      title: 'accessors',
      layers: [Layer(id: 'lx', name: '')],
    );
    final context = _MinimalContext(doc);
    final stroke = _stroke('str_acc', 3);
    doc.layers.single.strokes.add(stroke);

    final eraseOp = EraseStrokesCommand(context, [
      (layerIndex: 0, index: 0, stroke: stroke),
    ]).operation;
    expect(eraseOp, isA<OpStrokeRemove>());
    final eraseJson = eraseOp!.toJson();
    expect(eraseJson['type'], 'stroke.remove');
    expect((eraseJson['entries'] as List).first, containsPair('layerId', 'lx'));

    final replaceOp = TransformStrokesCommand(context, 0, [
      (index: 0, before: stroke, after: _stroke('str_acc', 3)),
    ]).operation;
    expect(replaceOp, isA<OpStrokeReplace>());
    expect((replaceOp!.toJson())['layerId'], 'lx');

    // 形状替换命令未纳入操作流（作用域边界：返回 null）。
    expect(
      SnapshotCommand(context, doc.layers, doc.layers).operation,
      isNull,
    );
  });

  group('DocumentOperation JSON 往返', () {
    test('五类操作 + 批：JSON → 对象 → JSON 逐字段保真；未知类型拒绝', () {
      final add = OpStrokeAdd(
        layerId: 'l1',
        stroke: _stroke('str_j1', 1).toJson(),
      );
      final remove = OpStrokeRemove(
        entries: [(layerId: 'l1', index: 2, stroke: _stroke('str_j2', 2).toJson())],
      );
      final replace = OpStrokeReplace(
        layerId: 'l1',
        entries: [
          (
            id: 'str_j3',
            before: _stroke('str_j3', 3).toJson(),
            after: _stroke('str_j3', 4).toJson(),
          ),
        ],
      );
      final prop = OpLayerProp(
        layerId: 'l1',
        prop: OpLayerProp.propOpacity,
        before: 1.0,
        after: 0.5,
      );
      const reorder = OpLayerReorder(from: 0, to: 1);
      final batch = OpBatch(ops: [add, remove, replace, prop, reorder]);

      for (final op in [add, remove, replace, prop, reorder, batch]) {
        expect(
          DocumentOperation.fromJson(op.toJson()).toJson(),
          op.toJson(),
          reason: '${op.runtimeType} 往返保真',
        );
      }
      expect(
        () => DocumentOperation.fromJson({'type': 'mystery'}),
        throwsFormatException,
      );
    });

    test('apply/revert 语义：链式批的 LIFO 逆序与命令栈一致', () {
      final doc = DrawingDocument(
        id: 'sem_doc',
        title: 'semantics',
        layers: [Layer(id: 'l1', name: '')],
      );
      final s = _stroke('str_sem', 0);
      final after = _stroke('str_sem', 9).toJson();

      // 链 [add→replace→remove] 的批回退：与命令栈 LIFO 逆序同构——
      // remove 逆放回 after 实例、replace 逆写回 before、add 逆移除 before
      // 实例 ⇒ 净空（这就是「撤销到操作前」的正确含义）。
      final fullBatch = OpBatch(ops: [
        OpStrokeAdd(layerId: 'l1', stroke: s.toJson()),
        OpStrokeReplace(
          layerId: 'l1',
          entries: [(id: 'str_sem', before: s.toJson(), after: after)],
        ),
        OpStrokeRemove(entries: [(layerId: 'l1', index: 0, stroke: after)]),
      ]);
      fullBatch.apply(doc);
      expect(doc.layers.single.strokes, isEmpty);
      fullBatch.revert(doc);
      expect(doc.layers.single.strokes, isEmpty, reason: 'LIFO 逆序净空，与命令栈一致');
    });

    test('apply/revert 语义：独立 replace 的 revert 还原 before 版本（非 after）', () {
      // 文档预置笔画（不经 add 操作）——隔离「add 回退连坐移除」的 LIFO
      // 效应，单验 replace 自身的 before/after 语义。
      final doc = DrawingDocument(
        id: 'sem_doc2',
        title: 'semantics2',
        layers: [Layer(id: 'l1', name: '')],
      );
      final s = _stroke('str_sem2', 0);
      doc.layers.single.strokes.add(s);
      final after = _stroke('str_sem2', 9).toJson();
      final replace = OpStrokeReplace(
        layerId: 'l1',
        entries: [(id: 'str_sem2', before: s.toJson(), after: after)],
      );

      replace.apply(doc);
      expect(doc.layers.single.strokes.single.points.first.x, after['points'][0],
          reason: 'apply 后为 after 几何');
      replace.revert(doc);
      expect(doc.layers.single.strokes, hasLength(1));
      expect(doc.layers.single.strokes.single.id, 'str_sem2');
      expect(
        doc.layers.single.strokes.single.points.first.x,
        s.points.first.x,
        reason: 'revert 还原的是 before 版本（非 after）',
      );
    });
  });

  group('OperationLog', () {
    test('容量丢弃最旧；JSONL 往返逐条保真；clear', () {
      final log = OperationLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.record(
          OpStrokeAdd(layerId: 'l1', stroke: _stroke('str_cap$i', i).toJson()),
        );
      }
      expect(log.length, 3, reason: '容量 3，保留最近 3 条');
      final jsonl = log.toJsonl();
      expect(jsonl.split('\n'), hasLength(3));
      expect(jsonl, contains('str_cap4'), reason: '最近条目在');
      expect(jsonl, isNot(contains('str_cap0')), reason: '最旧条目已被挤出');

      final restored = OperationLog.fromJsonl(jsonl);
      expect(restored.length, 3);
      expect(
        restored.records.map((op) => op.toJson()).toList(),
        log.records.map((op) => op.toJson()).toList(),
      );

      restored.clear();
      expect(restored.length, 0);
    });
  });
}
