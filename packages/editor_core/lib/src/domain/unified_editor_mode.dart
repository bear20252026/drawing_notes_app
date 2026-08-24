// editor_core——UnifiedEditorMode 统一编辑器模式（Saber Editor 借鉴——2026-08-22）。
//
// 用户需求：笔记端和画板端尽可能共用同样的功能——避免重复维护——
// 只有一部分功能更特殊（模式化——特殊功能按模式启用）。
//
// 借鉴 Saber：Editor 同时是笔记+画布（同一编辑器内核——两种用途）。
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

/// 统一编辑器模式（笔记端/画板端共用同一编辑器——特殊功能按模式）。
enum UnifiedEditorMode {
  /// 笔记模式（笔记端——分页文本 + 共用画布——Saber HomePage 笔记）。
  note,

  /// 画板模式（画板端——无限画布——Saber whiteboardSubpage）。
  whiteboard,
}

/// 统一编辑器状态（不可变——模式 + 特殊功能启用）。
class UnifiedEditorState {
  const UnifiedEditorState({
    this.mode = UnifiedEditorMode.note,
    this.pagedEnabled = true,
    this.infiniteCanvasEnabled = false,
    this.showSidebar = true,
    this.showLayerPanel = true,
  });

  /// 当前模式（note/whiteboard）。
  final UnifiedEditorMode mode;

  /// 分页启用（note 模式——PageV2 多页文本——特殊功能）。
  final bool pagedEnabled;

  /// 无限画布启用（whiteboard 模式——缩放平移——特殊功能）。
  final bool infiniteCanvasEnabled;

  /// 侧边栏显示（Saber ResponsiveNavbar——大屏侧边栏）。
  final bool showSidebar;

  /// 图层面板显示。
  final bool showLayerPanel;

  /// 切换模式（note ↔ whiteboard——特殊功能按模式切换）。
  UnifiedEditorState switchMode(UnifiedEditorMode newMode) {
    switch (newMode) {
      case UnifiedEditorMode.note:
        // 笔记模式：分页 + 共用画布（无无限画布）。
        return copyWith(
          mode: newMode,
          pagedEnabled: true,
          infiniteCanvasEnabled: false,
        );
      case UnifiedEditorMode.whiteboard:
        // 画板模式：无限画布（无分页）。
        return copyWith(
          mode: newMode,
          pagedEnabled: false,
          infiniteCanvasEnabled: true,
        );
    }
  }

  /// 是否笔记模式。
  bool get isNote => mode == UnifiedEditorMode.note;

  /// 是否画板模式。
  bool get isWhiteboard => mode == UnifiedEditorMode.whiteboard;

  UnifiedEditorState copyWith({
    UnifiedEditorMode? mode,
    bool? pagedEnabled,
    bool? infiniteCanvasEnabled,
    bool? showSidebar,
    bool? showLayerPanel,
  }) {
    return UnifiedEditorState(
      mode: mode ?? this.mode,
      pagedEnabled: pagedEnabled ?? this.pagedEnabled,
      infiniteCanvasEnabled: infiniteCanvasEnabled ?? this.infiniteCanvasEnabled,
      showSidebar: showSidebar ?? this.showSidebar,
      showLayerPanel: showLayerPanel ?? this.showLayerPanel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedEditorState && mode == other.mode;

  @override
  int get hashCode => mode.hashCode;
}

/// 统一编辑器服务（框架级——笔记/画板共用——特殊功能按模式）。
///
/// 用户核心要求：共用同样功能——避免重复维护——特殊功能按模式启用。
/// 共用：DocumentV2/Reducer/CanvasPainter/ToolEngine（editor_core + editor_v2）。
/// 特殊：note 分页 / whiteboard 无限画布（按模式启用）。
class UnifiedEditor {
  const UnifiedEditor();

  /// 创建笔记模式（分页——Saber 笔记）。
  static UnifiedEditorState note() =>
      const UnifiedEditorState(mode: UnifiedEditorMode.note);

  /// 创建画板模式（无限画布——Saber whiteboard）。
  static UnifiedEditorState whiteboard() =>
      const UnifiedEditorState(mode: UnifiedEditorMode.whiteboard)
          .switchMode(UnifiedEditorMode.whiteboard);

  /// 当前模式是否启用分页（特殊功能——note）。
  static bool isPaged(UnifiedEditorState state) => state.pagedEnabled;

  /// 当前模式是否启用无限画布（特殊功能——whiteboard）。
  static bool isInfinite(UnifiedEditorState state) => state.infiniteCanvasEnabled;

  /// 共用核心是否生效（所有模式——文档/渲染/工具/加密共用）。
  static bool sharesCore(UnifiedEditorState state) => true;
}
