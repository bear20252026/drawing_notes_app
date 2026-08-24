part of 'editor_page.dart';

/// 编辑器状态字段声明（拆分自 editor_page.dart）。
///
/// 将 [_EditorPageState] 的 ~330 行字段声明与计算属性提取为 mixin，
/// 使主文件从 483 行降至 ~180 行（目标 <300）。
mixin _EditorPageStateFields on ConsumerState<EditorPage> {
  late final DrawingController _controller;

  /// 画布导出域（参考 Saber editor_exporter 模块化）：PNG/PDF/SVG/RTF/
  /// TXT/PPTX/JSON 与剪贴板复制集中在独立模块，本页只负责调用。
  late final EditorExporter _exporter;

  /// 编辑器 ViewModel 胶水层（R4）：工具状态 + 防抖保存调度，
  /// editor_page 只通过它读写工具状态与触发保存（见 editor_viewmodel.dart）。
  late final EditorViewModel _viewModel;
  bool _viewportInitialized = false;

  /// 吸管模式：激活时点击画布取色，取色后自动退出。
  bool get _eyedropperActive => _viewModel.eyedropperActive;

  /// 文字工具模式：激活时点击画布弹出文字输入框。
  bool get _textToolActive => _viewModel.textToolActive;

  /// 选区是否已完成（完成后再拖动 = 移动选中内容，而非新建选区）。
  bool get _selectionDone => _viewModel.selectionDone;

  /// 上次拖动位置（画布坐标），用于计算移动增量。
  Offset? _lastDragCanvas;

  /// 缩放滑块当前值（1.0 = 原始大小）。
  double _scaleValue = 1.0;

  /// 旋转滑块当前值（度）。
  double _rotateDegrees = 0.0;

  /// 当前选中的混排对象 id（null = 无选中），用于显示编辑/删除按钮。
  String? _selectedItemId;

  /// 当前选中的文字块（null = 未选中文字块），供工具栏字号滑块使用。
  PageTextItem? get _selectedTextItem {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return null;
    return page.textItems.where((t) => t.id == id).firstOrNull;
  }

  /// 全屏模式：隐藏应用框架，只保留画布。
  bool _fullscreen = false;

  /// 阅读反相仅作用于当前编辑器显示层；不修改页面颜色、资源字节、导出或保存。
  bool _readingInverted = false;

  // 深色阅读反相矩阵（问题9修复）。
  static const ColorFilter _readingInvertFilter = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  /// 图层与详细属性默认按需展开，避免在普通屏幕上长期挤压创作区域。
  bool _layersVisible = false;
  bool _inspectorVisible = false;

  /// 键盘快捷键监听焦点（Ctrl+Z/Ctrl+Y 撤销重做）。
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'editor_shortcuts');

  /// 命令注册表（B2，借鉴 Joplin CommandService）：
  late final CommandRegistry _commands;

  /// 命令面板最近一次成功执行的命令（仅保留会话内记录）。
  String? _lastCommandId;

  /// 就地编辑（点击页面直接打字）状态：
  String? _editingItemId;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocus = FocusNode();

  /// 就地编辑中的临时文字块（提交时才加入页面）。
  PageTextItem? _pendingTextItem;

  /// 斜杠命令菜单是否展开（D5，借鉴 Lokus 斜杠命令）。
  bool _slashOpen = false;

  /// 连线模式（D1）：开启后依次点选两个元素创建连接线。
  bool get _linkMode => _viewModel.linkMode;

  /// 当前激活的形状工具（借鉴 Excalidraw 图形工具；null = 未激活）。
  ShapeType? _activeShapeTool;

  /// 画布视口尺寸（小地图导航用，由布局回调更新）。
  Size? _viewportSize;

  /// 对齐参考线（拖动元素时实时显示，借鉴 Excalidraw 对齐可视化）。
  List<({bool vertical, double pos})> _snapGuides = [];

  /// 文字缩放手柄的拖拽基准（落地 Excalidraw resizeElements）：
  ({double width, double fontSize, double x})? _textResizeAnchor;

  /// 框选工具激活（借鉴 Excalidraw 多选：矩形框选多个混排对象）。
  bool _marqueeActive = false;

  /// 框选矩形（画布坐标；null = 未在框选中）。
  Rect? _marqueeRect;

  /// 框选起点（画布坐标）。
  Offset? _marqueeStart;

  /// 多选元素 id 集合（框选结果，可整体拖动/删除）。
  final Set<String> _multiSelectedIds = {};

  /// 网格显示开关（借鉴 Excalidraw 画布导航）。
  bool _gridVisible = false;

  /// 网格吸附开关（拖动元素吸附到 20px 网格，借鉴 Excalidraw）。
  bool _snapToGrid = false;

  /// 正在播放删除淡出动画的元素 id 集合（借鉴 Excalidraw 删除动画）。
  final Set<String> _deletingIds = {};

  /// 手型工具激活（对齐 Excalidraw hand：拖动画布平移）。
  bool _handToolActive = false;

  /// 上次取色时间（P-2 修复 2026-08-15）。
  DateTime? _lastPickColorAt;

  /// 拖动轨迹点（对齐 Excalidraw animatedTrail）。
  final List<Offset> _trailPoints = [];

  /// 图片裁剪（对齐 Excalidraw 图片裁剪）。
  PageImageItem? _cropItem;
  Rect? _cropRect;

  /// 压感笔刷：上一采样点位置与时间。
  Offset? _lastPenPos;
  DateTime? _lastPenTime;

  /// 压感解释、平滑与设备诊断。
  final StylusInputProcessor _stylusInput = StylusInputProcessor();
  final ValueNotifier<InkPressureSample?> _inkPressureSample =
      ValueNotifier<InkPressureSample?>(null);

  /// 每种书写工具独立的颜色与尺寸，跨启动持久化。
  final BrushPresetStore _brushPresetStore = BrushPresetStore();
  final EraserModeStore _eraserModeStore = EraserModeStore();
  BrushPresetBook _brushPresets = BrushPresetBook.defaults();

  /// 当前选中的图片元素。
  PageImageItem? get _selectedImageItem {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return null;
    return page.imageItems.where((i) => i.id == id).firstOrNull;
  }

  /// 当前工作区的形状集合。
  List<PageShapeItem> get _shapeItems =>
      widget.page?.shapes ?? _controller.document.shapes;

  /// 当前选中的形状元素。
  PageShapeItem? get _selectedShapeItem {
    final id = _selectedItemId;
    if (id == null) return null;
    return _shapeItems.where((shape) => shape.id == id).firstOrNull;
  }

  /// 形状拖拽创建的起点和当前点（画布坐标）。
  Offset? _shapeDraftStart;
  Offset? _shapeDraftCurrent;

  /// 形状填充模式开关（问题4）。
  bool _fillShapeEnabled = false;

  /// 形状填充色（ARGB，默认半透明绿）。
  final int _shapeFillColor = 0x66A5D6A7;

  PageShapeItem? get _shapeDraft {
    final start = _shapeDraftStart;
    final current = _shapeDraftCurrent;
    final tool = _activeShapeTool;
    if (start == null || current == null || tool == null) return null;
    final dx = current.dx - start.dx;
    final dy = current.dy - start.dy;
    final left = math.min(start.dx, current.dx);
    final top = math.min(start.dy, current.dy);
    return PageShapeItem(
      id: '_shape_draft',
      shapeType: tool,
      x: left,
      y: top,
      width: dx.abs().clamp(2.0, 10000.0).toDouble(),
      height: dy.abs().clamp(2.0, 10000.0).toDouble(),
      color: _controller.color.toARGB32(),
      strokeWidth: _controller.brushSize.clamp(1, 20).toDouble(),
      flipX: dx < 0,
      flipY: dy < 0,
      lineStart: start - Offset(left, top),
      lineEnd: current - Offset(left, top),
      fillColor: _fillShapeEnabled ? _shapeFillColor : null,
    );
  }

  // ---------------- 保存 ----------------

  /// 自动保存执行中标记与补写标记。
  bool _autosaving = false;
  bool _autosaveQueued = false;
  bool _closingEditor = false;
  bool _allowPopAfterSave = false;
  Completer<void>? _autosaveCompletion;

  /// 状态刷新薄包装（供 overlays extension 使用）。
  String? get _linkSourceId => _viewModel.linkSourceId;

  /// 鼠标悬停/移动时的画布坐标（状态栏显示）。
  final ValueNotifier<Offset?> _hoverPos = ValueNotifier<Offset?>(null);

  bool get _isNotebookMode => widget.page != null;

  bool get _hasObjectSelection =>
      _selectedItemId != null || _multiSelectedIds.isNotEmpty;

  /// 剪贴板元素（复制/粘贴的元素）。
  List<Map<String, dynamic>> _copiedElements = [];

  /// 复制的样式（颜色/字号/粗斜体/线宽）。
  Map<String, dynamic>? _copiedStyle;

  /// 会话内形状库（个人收藏）。
  late final ShapeLibrary _shapeLibrary = ShapeLibrary();

  /// 手型工具最近一次拖动位置。
  Offset? _handDragLast;

  // ---------------- 手势处理 ----------------

  /// 当前按下且经输入仲裁器接受的指针。
  final Map<int, Offset> _activePointers = {};

  /// 触控笔优先、手掌拒绝和双指视图手势的无状态决策器。
  final EditorInputArbiter _inputArbiter = EditorInputArbiter();

  /// 保持既有 Android 单指书写体验。
  final bool _fingerDrawingEnabled = true;

  bool get _isObjectEraser =>
      _controller.tool == BrushType.eraser &&
      _controller.eraserMode == EraserMode.stroke;

  bool get _isDirectInkMode =>
      !_eyedropperActive &&
      !_textToolActive &&
      _controller.selectionTool == SelectionTool.none &&
      !_handToolActive &&
      _activeShapeTool == null &&
      !_marqueeActive;

  EditorInputPolicy get _inputPolicy => EditorInputPolicy(
    allowInk: true,
    allowFingerDrawing: _isDirectInkMode ? _fingerDrawingEnabled : true,
  );

  /// 多指手势状态：上次两指距离与角度。
  double? _pinchDistance;
  double? _pinchAngle;

  /// 是否处于多指手势（缩放/旋转画布）中。
  bool get _inPinch => _activePointers.length >= 2;
}
