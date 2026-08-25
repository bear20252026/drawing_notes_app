// editor_v2——EditorV2ViewModel（批次 E——2026-08-21——2026 最佳实践）。
//
// Riverpod Notifier——不可变状态 + 命令分发（通过 DocumentReducer）。
// 遵循专家方案批次 E + 2026 最佳实践（Sheetifye/tldraw/Excalidraw 模式）。
// 纯 Dart 逻辑——无 UI 依赖——Headless Logic（可独立单元测试）。
// 使用 Riverpod 3.x Notifier（手动声明——不依赖 build_runner）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

/// Editor V2 不可变状态（Riverpod Provider 输出）。
///
/// 所有字段 final；修改通过 copyWith（返回新实例——原实例不变——
/// 历史/撤销基于不可变快照——2026 最佳实践）。
@immutable
class EditorV2State {
  const EditorV2State({
    required this.document,
    this.canUndo = false,
    this.canRedo = false,
    this.currentTool = 'draw',
    this.currentShapeType = 'line',
  });

  /// 当前文档（不可变）。
  final DocumentV2 document;

  /// 是否可撤销。
  final bool canUndo;

  /// 是否可重做。
  final bool canRedo;

  /// 当前工具（draw/select/pan/erase/text/line/rect/ellipse/arrow）。
  final String currentTool;

  /// 当前形状类型（line/rect/ellipse/arrow）。
  final String currentShapeType;

  /// 不可变拷贝：仅更新指定字段——原实例不变。
  EditorV2State copyWith({
    DocumentV2? document,
    bool? canUndo,
    bool? canRedo,
    String? currentTool,
    String? currentShapeType,
  }) {
    return EditorV2State(
      document: document ?? this.document,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      currentTool: currentTool ?? this.currentTool,
      currentShapeType: currentShapeType ?? this.currentShapeType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorV2State &&
          document == other.document &&
          canUndo == other.canUndo &&
          canRedo == other.canRedo &&
          currentTool == other.currentTool &&
          currentShapeType == other.currentShapeType;

  @override
  int get hashCode => Object.hash(document, canUndo, canRedo, currentTool, currentShapeType);
}

/// Editor V2 ViewModel（Riverpod 3.x Notifier——手动声明——不依赖 build_runner）。
///
/// 遵循：
/// - 命令模式（state + command → new state + inverse command）
/// - 不可变状态（EditorV2State — copyWith）
/// - Headless Logic（所有业务逻辑在此——可独立单元测试）
/// - 依赖单向（只依赖 editor_core——不依赖 legacy）
class EditorV2Notifier extends Notifier<EditorV2State> {
  late DocumentReducer _reducer;

  @override
  EditorV2State build() {
    const initialDoc = DocumentV2(id: 'new', pageCount: 1);
    _reducer = DocumentReducer(initialDoc);
    return EditorV2State(document: initialDoc);
  }

  // ──────────────────────────── 命令分发 ────────────────────────────

  /// 撤销栈（只读——历史面板显示用——委托 DocumentReducer）。
  List<HistoryEntry> get undoStack => _reducer.undoStack;

  /// 重做栈（只读——历史面板显示用——委托 DocumentReducer）。
  List<HistoryEntry> get redoStack => _reducer.redoStack;

  /// 执行命令（通过 DocumentReducer——不可变状态更新）。
  void execute(DocumentCommand command) {
    final newDoc = _reducer.execute(command);
    state = state.copyWith(
      document: newDoc,
      canUndo: _reducer.canUndo,
      canRedo: _reducer.canRedo,
    );
  }

  /// 撤销。
  void undo() {
    final newDoc = _reducer.undo();
    if (newDoc != null) {
      state = state.copyWith(
        document: newDoc,
        canUndo: _reducer.canUndo,
        canRedo: _reducer.canRedo,
      );
    }
  }

  /// 重做。
  void redo() {
    final newDoc = _reducer.redo();
    if (newDoc != null) {
      state = state.copyWith(
        document: newDoc,
        canUndo: _reducer.canUndo,
        canRedo: _reducer.canRedo,
      );
    }
  }

  // ──────────────────────────── CUJ-01 操作 ────────────────────────────

  /// 创建新文档（CUJ-01 创建）。
  void createDocument(String id, {int pageCount = 1}) {
    final doc = DocumentV2(id: id, pageCount: pageCount, layers: [
      const LayerV2(id: 'layer-1', name: 'Layer 1'),
    ]);
    _reducer = DocumentReducer(doc);
    state = EditorV2State(document: doc);
  }

  /// 添加笔画（CUJ-01 绘制）。
  void addStroke(List<Point> points, {String layerId = 'layer-1'}) {
    final stroke = LineItem(
      id: 'stroke-${DateTime.now().millisecondsSinceEpoch}',
      points: points,
    );
    execute(AddStrokeCommand(layerId: layerId, stroke: stroke));
  }

  /// 添加文本（画布 text 工具——修复打字崩溃——2026-08-22）。
  void addText(String content, double x, double y, {String layerId = 'layer-1'}) {
    final text = TextItem(
      id: 'text-${DateTime.now().millisecondsSinceEpoch}',
      content: content,
      x: x,
      y: y,
    );
    execute(CreateTextCommand(layerId: layerId, text: text));
  }

  // ──────────────────────────── 工具切换 ────────────────────────────

  void setTool(String tool) {
    state = state.copyWith(currentTool: tool);
  }

  void setShapeType(String type) {
    state = state.copyWith(currentShapeType: type);
  }
}

/// Riverpod Provider（手动声明——不依赖代码生成）。
final editorV2NotifierProvider =
    NotifierProvider<EditorV2Notifier, EditorV2State>(
  () => EditorV2Notifier(),
);
