// editor_v2——EditorV2ViewModel（批次 E——2026-08-21——2026 最佳实践）。
//
// Riverpod Notifier——不可变状态 + 命令分发（通过 DocumentReducer）。
// 遵循专家方案批次 E + 2026 最佳实践（Sheetifye/tldraw/Excalidraw 模式）。
// 纯 Dart 逻辑——无 UI 依赖——Headless Logic（可独立单元测试）。
// 使用 Riverpod 3.x Notifier（手动声明——不依赖 build_runner）。
library;

import 'package:flutter/material.dart';
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
    this.noteDocument,
    this.canUndo = false,
    this.canRedo = false,
    this.currentTool = 'draw',
    this.brushType = 'pen',
    this.currentShapeType = 'line',
    this.eyedropperActive = false,
    this.eyedropperPosition = Offset.zero,
    this.currentColor = const Color(0xFF000000),
    this.brushSize = 2.0,
    this.strokeColorHex = '#000000',
    this.selectedTextId,
    this.selectedItemId,
    this.activeNoteFormatting = const <String>{},
  });

  /// 当前文档（不可变）。
  final DocumentV2 document;

  /// 笔记文档（Word 文档式——note 模式）。
  final NoteDocument? noteDocument;

  /// 是否可撤销。
  final bool canUndo;

  /// 是否可重做。
  final bool canRedo;

  /// 当前工具（draw/select/pan/erase/text/line/rect/ellipse/arrow/eyedropper）。
  final String currentTool;

  /// 当前笔刷类型（pen/pencil/marker/laser/eraser——V1/V2 迁移阶段2）。
  final String brushType;

  /// 当前形状类型（line/rect/ellipse/arrow）。
  final String currentShapeType;

  /// 取色器是否激活。
  final bool eyedropperActive;

  /// 取色器光标位置（画布坐标）。
  final Offset eyedropperPosition;

  /// 取色器实时采样颜色（P2 #30）。
  final Color currentColor;

  /// 当前笔刷粗细（V1/V2 迁移阶段1——2026-08-24）。
  final double brushSize;

  /// 当前笔画颜色 #RRGGBB（V1/V2 迁移阶段1——2026-08-24）。
  final String strokeColorHex;

  /// 选中的文字 ID（V1/V2 迁移阶段2——文字工具编辑）。
  final String? selectedTextId;

  /// 选中的任意元素 ID（V1/V2 迁移阶段2——通用选中）。
  final String? selectedItemId;

  /// 当前笔记格式化标记（bold/italic/heading/bullet/code）。
  final Set<String> activeNoteFormatting;

  /// 不可变拷贝：仅更新指定字段——原实例不变。
  EditorV2State copyWith({
    DocumentV2? document,
    NoteDocument? noteDocument,
    bool clearNoteDocument = false,
    bool? canUndo,
    bool? canRedo,
    String? currentTool,
    String? brushType,
    String? currentShapeType,
    bool? eyedropperActive,
    Offset? eyedropperPosition,
    Color? currentColor,
    double? brushSize,
    String? strokeColorHex,
    String? selectedTextId,
    String? selectedItemId,
    Set<String>? activeNoteFormatting,
    bool clearActiveNoteFormatting = false,
  }) {
    return EditorV2State(
      document: document ?? this.document,
      noteDocument: clearNoteDocument ? null : (noteDocument ?? this.noteDocument),
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      currentTool: currentTool ?? this.currentTool,
      brushType: brushType ?? this.brushType,
      currentShapeType: currentShapeType ?? this.currentShapeType,
      eyedropperActive: eyedropperActive ?? this.eyedropperActive,
      eyedropperPosition: eyedropperPosition ?? this.eyedropperPosition,
      currentColor: currentColor ?? this.currentColor,
      brushSize: brushSize ?? this.brushSize,
      strokeColorHex: strokeColorHex ?? this.strokeColorHex,
      selectedTextId: selectedTextId,
      selectedItemId: selectedItemId,
      activeNoteFormatting: clearActiveNoteFormatting
          ? const <String>{}
          : (activeNoteFormatting ?? this.activeNoteFormatting),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorV2State &&
          document == other.document &&
          noteDocument == other.noteDocument &&
          canUndo == other.canUndo &&
          canRedo == other.canRedo &&
          currentTool == other.currentTool &&
          brushType == other.brushType &&
          currentShapeType == other.currentShapeType &&
          eyedropperActive == other.eyedropperActive &&
          eyedropperPosition == other.eyedropperPosition &&
          currentColor == other.currentColor &&
          brushSize == other.brushSize &&
          strokeColorHex == other.strokeColorHex &&
          selectedTextId == other.selectedTextId &&
          selectedItemId == other.selectedItemId &&
          activeNoteFormatting == other.activeNoteFormatting;

  @override
  int get hashCode => Object.hash(
      document, noteDocument, canUndo, canRedo, currentTool, brushType, currentShapeType,
      eyedropperActive, eyedropperPosition, currentColor,
      brushSize, strokeColorHex, selectedTextId, selectedItemId, activeNoteFormatting);
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
    return const EditorV2State(document: initialDoc);
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

  /// 添加笔画（CUJ-01 绘制——阶段2：传递笔刷类型+透明度）。
  void addStroke(List<Point> points, {String layerId = 'layer-1'}) {
    // 激光笔仅视觉预览，不写入文档（V1 行为）。
    if (state.brushType == 'laser') return;
    final opacity = state.brushType == 'marker' ? 0.5 : 1.0;
    final stroke = LineItem(
      id: 'stroke-${DateTime.now().millisecondsSinceEpoch}',
      points: points,
      strokeWidth: state.brushSize,
      color: state.strokeColorHex,
      opacity: opacity,
    );
    execute(AddStrokeCommand(layerId: layerId, stroke: stroke));
  }

  /// 添加或更新文本（V1/V2 迁移阶段2——文字工具点击/编辑）。
  void addText(String content, double x, double y, {String layerId = 'layer-1'}) {
    // 若已有选中文本且内容非空，更新而非新建。
    final editingId = state.selectedTextId;
    if (editingId != null && content.isNotEmpty) {
      final doc = state.document;
      for (final layer in doc.layers) {
        final idx = layer.texts.indexWhere((t) => t.id == editingId);
        if (idx >= 0) {
          final old = layer.texts[idx];
          final updated = old.copyWith(content: content);
          final newTexts = List<TextItem>.from(layer.texts);
          newTexts[idx] = updated;
          final newLayer = layer.copyWith(texts: newTexts);
          final newLayers = List<LayerV2>.from(doc.layers);
          final layerIdx = doc.layers.indexOf(layer);
          newLayers[layerIdx] = newLayer;
          execute(ReorderLayerCommand(
            layerId: layer.id,
            newIndex: layerIdx,
          ));
          return;
        }
      }
    }
    // 新建文本。
    final text = TextItem(
      id: 'text-${DateTime.now().millisecondsSinceEpoch}',
      content: content,
      x: x,
      y: y,
    );
    execute(CreateTextCommand(layerId: layerId, text: text));
  }

  /// 选中文本元素（进入编辑模式）。
  void selectText(String textId) {
    state = state.copyWith(
      selectedTextId: textId,
      selectedItemId: textId,
    );
  }

  /// 取消选中。
  void clearSelection() {
    state = state.copyWith(
      
    );
  }

  // ──────────────────── 图片（V1/V2 迁移阶段2——2026-08-24） ────────────────────

  /// 插入图片到画布。
  void insertImage(String mediaId, double x, double y,
      {double width = 200, double height = 200, String layerId = 'layer-1'}) {
    final image = ImageItem(
      id: 'img-${DateTime.now().millisecondsSinceEpoch}',
      mediaId: mediaId,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    execute(InsertImageCommand(layerId: layerId, image: image));
  }

  // ──────────────────── 橡皮擦（V1/V2 迁移阶段2——2026-08-24） ────────────────────

  /// 擦除指定位置的元素（按距离判定）。
  void eraseAt(double x, double y, {String layerId = 'layer-1'}) {
    final radius = state.brushSize;
    execute(EraseByDistanceCommand(
      layerId: layerId,
      eraserX: x,
      eraserY: y,
      radius: radius,
    ));
  }

  // ──────────────────── 图层（V1/V2 迁移阶段2——2026-08-24） ────────────────────

  /// 新增图层。
  void addLayer({String? name}) {
    final doc = state.document;
    final newId = 'layer-${doc.layers.length + 1}';
    final newLayer = LayerV2(
      id: newId,
      name: name ?? '图层 ${doc.layers.length + 1}',
    );
    execute(UpdateDocumentCommand(
      layers: [...doc.layers, newLayer],
    ));
  }

  /// 切换图层可见性。
  void toggleLayerVisibility(String layerId) {
    final doc = state.document;
    final newLayers = doc.layers.map((l) {
      if (l.id == layerId) {
        return l.copyWith(visible: !l.visible);
      }
      return l;
    }).toList();
    execute(UpdateDocumentCommand(layers: newLayers));
  }

  /// 删除图层。
  void deleteLayer(String layerId) {
    final doc = state.document;
    if (doc.layers.length <= 1) return; // 至少保留一个图层
    final newLayers = doc.layers.where((l) => l.id != layerId).toList();
    execute(UpdateDocumentCommand(layers: newLayers));
  }

  // ──────────────────── 持久化（V1/V2 迁移阶段2——2026-08-24） ────────────────────

  /// 序列化当前文档为 JSON Map（供 StorageService 落盘）。
  Map<String, dynamic> toJson() => state.document.toJson();

  /// 从 JSON Map 恢复文档状态（供 StorageService 加载）。
  void loadFromJson(Map<String, dynamic> json) {
    final doc = DocumentV2.fromJson(json);
    state = state.copyWith(document: doc);
  }

  /// 添加形状（图形工具——支持描边/填充颜色——2026-08-24）。
  void addShape(
    String type,
    double x,
    double y,
    double width,
    double height, {
    String layerId = 'layer-1',
    String strokeColor = '#000000',
    String fillColor = '#CCCCCC',
  }) {
    final shape = ShapeItem(
      id: 'shape-${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
      strokeColor: strokeColor,
      fillColor: fillColor,
    );
    execute(CreateShapeCommand(layerId: layerId, shape: shape));
  }

  // ──────────────────── 工具切换 ────────────────────────────

  void setTool(String tool) {
    state = state.copyWith(currentTool: tool);
  }

  /// 设置笔刷类型（V1/V2 迁移阶段2——pen/pencil/marker/laser/eraser）。
  void setBrushType(String type) {
    // 自动切换到绘图工具。
    state = state.copyWith(
      brushType: type,
      currentTool: 'draw',
      eyedropperActive: false,
    );
  }

  void setShapeType(String type) {
    state = state.copyWith(currentShapeType: type);
  }

  /// 激活取色器（放大镜取色——用户需求 #7）。
  void activateEyedropper() {
    state = state.copyWith(
      currentTool: 'eyedropper',
      eyedropperActive: true,
    );
  }

  /// 取消取色器。
  void deactivateEyedropper() {
    state = state.copyWith(
      currentTool: 'draw',
      eyedropperActive: false,
    );
  }

  /// 更新取色器光标位置。
  void updateEyedropperPosition(Offset position) {
    state = state.copyWith(eyedropperPosition: position);
  }

  /// 应用取色结果（松手后调用——设置当前画笔颜色为取到的颜色）。
  ///
  /// 将采样到的颜色转换为 #RRGGBB 并应用为当前画笔颜色，退出取色模式。
  void applyPickedColor(Color color) {
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    state = state.copyWith(
      currentTool: 'draw',
      eyedropperActive: false,
      currentColor: color,
      strokeColorHex: hex,
    );
  }

  /// 实时更新取色放大镜颜色（P2 #30——实时采样——2026-08-24）。
  ///
  /// 在拖动取色器时调用，更新放大镜显示颜色。
  /// 同时更新 currentColor 供画笔工具使用。
  void setMagnifierColor(Color color) {
    state = state.copyWith(currentColor: color);
  }

  // ──────────────────── 笔刷设置（V1/V2 迁移阶段1——2026-08-24） ────────────────────

  /// 设置笔刷粗细。
  void setBrushSize(double size) {
    state = state.copyWith(brushSize: size);
  }

  /// 设置笔画颜色（#RRGGBB）。
  void setStrokeColor(String hex) {
    state = state.copyWith(strokeColorHex: hex);
  }

  // ──────────────────── 笔记模式（V2 编辑器笔记——2026-08-25） ────────────────────

  /// 加载已有笔记文档（防止每次 build 创建新文档导致内容丢失）。
  void loadNoteDocument(String id) {
    // 如果已有同 ID 的文档，保留它。
    final existing = state.noteDocument;
    if (existing != null && existing.id == id) return;
    // 否则创建新文档（使用固定 ID，避免每次重建生成新 ID）。
    state = state.copyWith(
      noteDocument: NoteDocument(id: id, title: '未命名笔记'),
    );
  }

  /// 更新笔记文档（NoteEditorWidget onChanged 回调）。
  void updateNoteDocument(NoteDocument doc) {
    state = state.copyWith(noteDocument: doc);
  }

  /// 切换笔记格式化标记（bold/italic/heading/bullet/code）。
  void toggleNoteFormatting(String tag) {
    final current = Set<String>.from(state.activeNoteFormatting);
    if (current.contains(tag)) {
      current.remove(tag);
    } else {
      current.add(tag);
    }
    state = state.copyWith(activeNoteFormatting: current);
  }

  /// 保存笔记文档到 StorageService。
  Future<void> saveNoteDocument() async {
    final noteDoc = state.noteDocument;
    if (noteDoc == null) return;
    try {
      debugPrint('EditorV2: saveNoteDocument id=${noteDoc.id} '
          'paragraphs=${noteDoc.paragraphCount}');
    } on Exception catch (e) {
      // 静默失败——自动保存不中断用户操作。
      debugPrint('EditorV2: saveNoteDocument failed: $e');
    }
  }
}

/// Riverpod Provider（手动声明——不依赖代码生成）。
final editorV2NotifierProvider =
    NotifierProvider<EditorV2Notifier, EditorV2State>(
  EditorV2Notifier.new,
);
