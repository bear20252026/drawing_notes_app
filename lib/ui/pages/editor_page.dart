import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../engine/brush_preset_store.dart';
import '../../engine/command_registry.dart';
import '../../engine/drawing_controller.dart';
import '../../engine/editor_input_arbiter.dart';
import '../../engine/eraser_mode.dart';
import '../../engine/eraser_mode_store.dart';
import '../../engine/gesture_math.dart';
import '../../engine/paged_note_rtf_exporter.dart';
import '../../engine/pdf_hybrid_exporter.dart';
import '../../engine/pencil_shader.dart';
import '../../engine/shape_binding_geometry.dart';
import '../../engine/shape_creation_geometry.dart';
import '../../engine/shape_library.dart';
import '../../engine/stylus_input.dart';
import '../../engine/view_transform_cache.dart';
import '../../models/document.dart';
import '../../models/document_image_item.dart';
import '../../models/notebook.dart';
import '../../models/selection.dart';
import '../../models/stroke.dart';
import '../../storage/notebook_storage.dart';
import '../../storage/storage_service.dart';
import '../canvas_painter.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/editor_components.dart';
import '../widgets/editor_context_bar.dart';
import '../widgets/editor_left_toolbar.dart';
import '../widgets/editor_statusbar.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/editor_viewmodel.dart';
import '../widgets/layer_panel.dart';
import '../widgets/properties_panel.dart';
import 'presentation_page.dart';

part 'editor_page_dialogs.dart';

/// 编辑器页面。
///
/// 两种使用场景：
/// 1. 独立画作模式：仅传 [document]（Phase 1-4，画布功能）；
/// 2. 笔记本页面模式：传 [notebook]/[page]/[storage]/[onChanged]，
///    在画布之上叠加文字块与图片块（Phase 5 混排）。
///
/// 职责：
/// - 手势采集：笔画 / 选区 / 吸管 / 文字与图片放置
/// - 工具面板：撤销、重做、清空、画笔/橡皮擦/吸管/选区/文字/图片
/// - 保存回调：任何变更后调用 [onChanged]（由上级页面负责落盘）
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    DrawingDocument? document,
    this.notebook,
    this.page,
    this.storage,
    this.docStorage,
    this.onChanged,
  }) : _initialDocument = document;

  /// 独立画作模式：初始文档（为空时创建默认空白文档）。
  final DrawingDocument? _initialDocument;

  /// 笔记本页面模式：所属笔记本与当前页面。
  final Notebook? notebook;
  final NotebookPage? page;

  /// 笔记本存储（插入图片时复制图片副本用）。
  final NotebookStorage? storage;

  /// 独立画作存储（Phase 6 自动保存用）。
  final StorageService? docStorage;

  /// 内容变更回调（自动保存由上级页面实现）。
  final VoidCallback? onChanged;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final DrawingController _controller;

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

  // Rec. 709 保亮度反相矩阵：与常规 RGB 反转相比，阅读彩色笔迹时层次更稳定。
  static const ColorFilter _readingInvertFilter = ColorFilter.matrix(<double>[
    0.5748,
    -1.4304,
    -0.1444,
    0,
    255,
    -0.4252,
    0.5696,
    -0.1444,
    0,
    255,
    -0.4252,
    -1.4304,
    0.8556,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  /// 图层与详细属性默认按需展开，避免在普通屏幕上长期挤压创作区域。
  bool _layersVisible = false;
  bool _inspectorVisible = false;

  /// 键盘快捷键监听焦点（Ctrl+Z/Ctrl+Y 撤销重做）。
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'editor_shortcuts');

  /// 命令注册表（B2，借鉴 Joplin CommandService）：
  /// 操作统一注册，快捷键面板从命令表自动生成。
  late final CommandRegistry _commands;

  /// 命令面板最近一次成功执行的命令（仅保留会话内记录）。
  String? _lastCommandId;

  /// 就地编辑（点击页面直接打字）状态：
  /// 正在编辑的文字块 id（null = 无就地编辑）。
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

  /// 对齐参考线（拖动元素时实时显示，借鉴 Excalidraw 对齐可视化）。
  /// 元素为 (vertical: 是否垂直线, pos: 画布坐标位置)。
  List<({bool vertical, double pos})> _snapGuides = [];

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

  /// 拖动轨迹点（对齐 Excalidraw animatedTrail：拖动元素显示轨迹动画）。
  final List<Offset> _trailPoints = [];

  /// 图片裁剪（对齐 Excalidraw 图片裁剪）：裁剪目标与裁剪矩形（画布坐标）。
  PageImageItem? _cropItem;
  Rect? _cropRect;

  /// 压感笔刷：上一采样点位置与时间（用于鼠标速度模拟压感，
  /// 对齐 Excalidraw：速度快 -> 笔画细，速度慢 -> 笔画粗）。
  Offset? _lastPenPos;
  DateTime? _lastPenTime;

  /// 压感解释、平滑与设备诊断。真实笔压与鼠标速度回退在同一策略中处理，
  /// 状态栏明确展示来源，避免把模拟效果误认为硬件压感。
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

  /// 确认裁剪：按裁剪矩形重新编码图片并写回文件（对齐 Excalidraw 图片裁剪）。
  Future<void> _confirmCrop() async {
    final img = _cropItem;
    final rect = _cropRect;
    if (img == null || rect == null || rect.width < 10 || rect.height < 10) {
      _showSnack('裁剪区域无效');
      return;
    }
    try {
      final file = File(img.filePath);
      if (!await file.exists()) {
        _showSnack('原图文件不存在');
        return;
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      // 按比例映射：裁剪矩形（画布坐标）-> 原图像素坐标。
      final scaleX = src.width / (img.width + 1);
      final scaleY = src.height / (img.height + 1);
      final srcRect = Rect.fromLTWH(
        (rect.left - img.x).clamp(0, img.width) * scaleX,
        (rect.top - img.y).clamp(0, img.height) * scaleY,
        rect.width.clamp(0, img.width) * scaleX,
        rect.height.clamp(0, img.height) * scaleY,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        srcRect,
        Rect.fromLTWH(0, 0, srcRect.width, srcRect.height),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(
        srcRect.width.round().clamp(1, 10000),
        srcRect.height.round().clamp(1, 10000),
      );
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      src.dispose();
      out.dispose();
      if (data == null) {
        _showSnack('裁剪编码失败');
        return;
      }
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      setState(() {
        img.x = rect.left;
        img.y = rect.top;
        img.width = rect.width;
        img.height = rect.height;
        _cropItem = null;
        _cropRect = null;
      });
      _notifyChanged();
      _showSnack('已裁剪图片');
    } catch (e) {
      _showSnack('裁剪失败：$e');
    }
  }

  /// 当前工作区的形状集合：笔记页使用分页混排集合，独立绘图使用文档集合。
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

  PageShapeItem? get _shapeDraft {
    final start = _shapeDraftStart;
    final current = _shapeDraftCurrent;
    final tool = _activeShapeTool;
    if (start == null || current == null || tool == null) return null;
    final dx = current.dx - start.dx;
    final dy = current.dy - start.dy;
    return PageShapeItem(
      id: '_shape_draft',
      shapeType: tool,
      x: math.min(start.dx, current.dx),
      y: math.min(start.dy, current.dy),
      width: dx.abs().clamp(2.0, 10000.0).toDouble(),
      height: dy.abs().clamp(2.0, 10000.0).toDouble(),
      color: _controller.color.toARGB32(),
      strokeWidth: _controller.brushSize.clamp(1, 20).toDouble(),
      flipX: dx < 0,
      flipY: dy < 0,
    );
  }

  /// 选择形状工具：激活后点击画布放置对应形状（借鉴 Excalidraw 图形工具）。
  void _selectShapeTool(ShapeType type) {
    setState(() {
      _handToolActive = false;
      _marqueeActive = false;
      _activeShapeTool = type;
      _viewModel.setLinkMode(false);
      _viewModel.setLinkSourceId(null);
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
    });
  }

  /// 适应画布（Fit to Screen）：缩放视图显示整个画布（借鉴 Excalidraw 导航）。
  void _fitToScreen() {
    final vp = _viewportSize ?? const Size(800, 600);
    final doc = _controller.document;
    final scale = (vp.width / doc.width).clamp(0.05, 1.0).toDouble();
    _controller.viewScale = scale;
    final center = doc.size.center(Offset.zero);
    final vc = Offset(vp.width / 2, vp.height / 2);
    // 中心对齐：offset = viewCenter - R(scale·(center-center)) - center = viewCenter - center
    _controller.viewOffset = vc - center;
    _controller.tickFrame();
  }

  /// 手型工具切换：激活后画布拖动 = 平移视口（对齐 Excalidraw hand）。
  void _toggleHandTool() {
    setState(() {
      _handToolActive = !_handToolActive;
      _marqueeActive = false;
      _activeShapeTool = null;
      _viewModel.setLinkMode(false);
      _viewModel.setLinkSourceId(null);
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      if (!_handToolActive) {
        _handDragLast = null;
      }
    });
  }

  /// 手型拖动起始点（视口坐标）。
  Offset? _handDragLast;

  /// 框选工具开关：激活后画布上拖动矩形框选多个混排对象
  /// （借鉴 Excalidraw 多选）。
  void _toggleMarqueeTool() {
    setState(() {
      _marqueeActive = !_marqueeActive;
      _handToolActive = false;
      _activeShapeTool = null;
      _viewModel.setLinkMode(false);
      _viewModel.setLinkSourceId(null);
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      if (!_marqueeActive) {
        _marqueeRect = null;
        _marqueeStart = null;
        _multiSelectedIds.clear();
      }
    });
  }

  /// 连线模式的第一个端点元素 id。
  String? get _linkSourceId => _viewModel.linkSourceId;

  /// 鼠标悬停/移动时的画布坐标（状态栏显示，借鉴 Joplin StatusBar）。
  final ValueNotifier<Offset?> _hoverPos = ValueNotifier<Offset?>(null);

  bool get _isNotebookMode => widget.page != null;

  @override
  void initState() {
    super.initState();
    // 笔记本页面模式使用页面自带文档；否则独立画布。
    final doc =
        widget.page?.document ??
        widget._initialDocument ??
        DrawingDocument(id: StorageService.newId(), title: '未命名画布');
    _controller = DrawingController(doc);
    unawaited(_loadBrushPresets());
    unawaited(_loadEraserMode());
    // 异步加载铅笔颗粒着色器；失败时渲染层自动回退到普通铅笔绘制。
    unawaited(PencilShader.init());
    // 修改文档标题显示为页面标题。
    if (widget.page != null && doc.title == '未命名画布') {
      doc.title = widget.page!.title;
    }
    // R4：实例化 ViewModel（防抖保存回调指向本页落盘逻辑）。
    _viewModel = EditorViewModel(controller: _controller, onSave: _doAutosave);
    // 首次进入时立即保存一次，确保新文档落盘（自动保存机制）。
    _scheduleAutosave();
    // 注册编辑器命令（B2：命令表驱动快捷键面板）。
    _commands = CommandRegistry();
    _registerCommands();
  }

  bool get _hasObjectSelection =>
      _selectedItemId != null || _multiSelectedIds.isNotEmpty;

  /// 注册编辑器命令（借鉴 Excalidraw ActionManager）。
  ///
  /// 每条命令声明同一个执行器、关键词、分类与可用性谓词；工具栏、主菜单、
  /// 快捷键和命令面板都应调用这里的 id，而不能各自复制业务逻辑。
  void _registerCommands() {
    _commands
      ..register(
        EditorCommand(
          id: 'undo',
          label: '撤销',
          category: EditorCommandCategory.edit,
          keywords: const ['history', '返回'],
          shortcut: 'Ctrl/Cmd+Z',
          isAvailable: () => _controller.canUndo,
          run: _controller.undo,
        ),
      )
      ..register(
        EditorCommand(
          id: 'redo',
          label: '重做',
          category: EditorCommandCategory.edit,
          keywords: const ['history', '恢复'],
          shortcut: 'Ctrl/Cmd+Y 或 Ctrl/Cmd+Shift+Z',
          isAvailable: () => _controller.canRedo,
          run: _controller.redo,
        ),
      )
      ..register(
        EditorCommand(
          id: 'copy',
          label: '复制选中对象',
          category: EditorCommandCategory.edit,
          keywords: const ['clipboard', '复制'],
          shortcut: 'Ctrl/Cmd+C',
          isAvailable: () => _hasObjectSelection,
          run: _copySelectedElement,
        ),
      )
      ..register(
        EditorCommand(
          id: 'paste',
          label: '从剪贴板粘贴',
          category: EditorCommandCategory.edit,
          keywords: const ['clipboard', '粘贴', '文本', '图片'],
          shortcut: 'Ctrl/Cmd+V',
          run: _pasteFromClipboard,
        ),
      )
      ..register(
        EditorCommand(
          id: 'duplicate',
          label: '复制并粘贴选中对象',
          category: EditorCommandCategory.edit,
          keywords: const ['duplicate', '副本'],
          shortcut: 'Ctrl/Cmd+D',
          isAvailable: () => _hasObjectSelection,
          run: () {
            _copySelectedElement();
            _pasteCopiedElement();
          },
        ),
      )
      ..register(
        EditorCommand(
          id: 'deleteSelection',
          label: '删除选中对象',
          category: EditorCommandCategory.edit,
          keywords: const ['delete', 'remove', '删除'],
          shortcut: 'Delete',
          isAvailable: () => _hasObjectSelection,
          run: _deleteSelectedItem,
        ),
      )
      ..register(
        EditorCommand(
          id: 'bold',
          label: '加粗选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '粗体'],
          shortcut: 'Ctrl/Cmd+B',
          isAvailable: () => _selectedTextItem != null,
          run: _toggleSelectedTextBold,
        ),
      )
      ..register(
        EditorCommand(
          id: 'italic',
          label: '斜体选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '斜体'],
          shortcut: 'Ctrl/Cmd+I',
          isAvailable: () => _selectedTextItem != null,
          run: _toggleSelectedTextItalic,
        ),
      )
      ..register(
        EditorCommand(
          id: 'underline',
          label: '下划线选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '下划线'],
          shortcut: 'Ctrl/Cmd+U',
          isAvailable: () => _selectedTextItem != null,
          run: () {
            final item = _selectedTextItem;
            if (item == null) return;
            setState(() => item.underline = !item.underline);
            _notifyChanged();
          },
        ),
      )
      ..register(
        EditorCommand(
          id: 'strikethrough',
          label: '删除线选中文字',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'font', '删除线'],
          shortcut: 'Ctrl/Cmd+Shift+X',
          isAvailable: () => _selectedTextItem != null,
          run: () {
            final item = _selectedTextItem;
            if (item == null) return;
            setState(() => item.strikethrough = !item.strikethrough);
            _notifyChanged();
          },
        ),
      )
      ..register(
        EditorCommand(
          id: 'alignText',
          label: '循环切换文本对齐',
          category: EditorCommandCategory.format,
          keywords: const ['text', 'alignment', '对齐'],
          shortcut: 'Ctrl/Cmd+E',
          isAvailable: () => _selectedTextItem != null,
          run: _cycleSelectedTextAlign,
        ),
      )
      ..register(
        EditorCommand(
          id: 'fitCanvas',
          label: '适应画布',
          category: EditorCommandCategory.view,
          keywords: const ['zoom', 'fit', '缩放'],
          shortcut: 'Shift+1',
          run: _fitToScreen,
        ),
      )
      ..register(
        EditorCommand(
          id: 'toggleGrid',
          label: '显示或隐藏网格',
          category: EditorCommandCategory.view,
          keywords: const ['grid', '网格'],
          run: () => setState(() => _gridVisible = !_gridVisible),
        ),
      )
      ..register(
        EditorCommand(
          id: 'toggleGridSnap',
          label: '切换网格吸附',
          category: EditorCommandCategory.view,
          keywords: const ['grid', 'snap', '吸附'],
          run: () => setState(() => _snapToGrid = !_snapToGrid),
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportPng',
          label: '导出 PNG',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'image', '图片'],
          run: _exportPng,
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportPdf',
          label: '导出 PDF',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'document', '文档'],
          run: _exportPdf,
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportSvg',
          label: '导出 SVG',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'vector', '矢量'],
          run: _exportSvg,
        ),
      )
      ..register(
        EditorCommand(
          id: 'exportWord',
          label: '导出 Word 兼容文档',
          category: EditorCommandCategory.export,
          keywords: const ['export', 'word', 'rtf', '文档'],
          isAvailable: () => _isNotebookMode,
          run: _exportWordCompatibleRtf,
        ),
      );
  }

  Future<void> _loadBrushPresets() async {
    try {
      final restored = await _brushPresetStore.load();
      if (!mounted) return;
      setState(() {
        _brushPresets = restored;
        _applyBrushPreset(_controller.tool);
      });
    } catch (_) {
      // 偏好存储不可用时继续使用内置安全默认值，不阻塞编辑器。
    }
  }

  Future<void> _loadEraserMode() async {
    try {
      final mode = await _eraserModeStore.load();
      if (!mounted) return;
      setState(() => _controller.eraserMode = mode);
    } catch (_) {
      // 偏好不可用时保留安全默认的整笔删除模式。
    }
  }

  void _applyBrushPreset(BrushType tool) {
    final preset = _brushPresets.forTool(tool);
    _controller.tool = tool;
    if (tool == BrushType.eraser) {
      _controller.eraserSize = preset.size;
    } else {
      _controller.color = preset.color;
      _controller.brushSize = preset.size;
    }
  }

  void _selectWritingTool(BrushType tool) {
    setState(() {
      _handToolActive = false;
      _activeShapeTool = null;
      _marqueeActive = false;
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      _applyBrushPreset(tool);
    });
  }

  void _updateCurrentBrushPreset({Color? color, double? size}) {
    final tool = _controller.tool;
    final updated = _brushPresets
        .forTool(tool)
        .copyWith(color: color, size: size);
    setState(() {
      _brushPresets = _brushPresets.update(updated);
      if (tool == BrushType.eraser) {
        _controller.eraserSize = updated.size;
      } else {
        _controller.color = updated.color;
        _controller.brushSize = updated.size;
      }
    });
    unawaited(_brushPresetStore.save(_brushPresets));
  }

  /// 正常返回编辑器前强制写入并等待落盘，防止 800ms 防抖尚未触发就退出。
  Future<bool> _flushBeforePop() async {
    await _viewModel.saveNow();
    return true;
  }

  @override
  void dispose() {
    // 保存当前视图变换，重开该文档/页面时恢复到上次位置（LRU）。
    ViewTransformCache.save(
      _viewCacheKey,
      _controller.viewScale,
      _controller.viewOffset,
    );
    // 极端场景（系统直接销毁窗口）无法等待 Future；仍先启动保存并标记关闭，
    // 使 _doAutosave 至少完成文档 JSON 写入而不再访问随后释放的渲染控制器。
    _closingEditor = true;
    unawaited(_viewModel.saveNow());
    _viewModel.dispose();
    _shortcutFocus.dispose();
    _editController.dispose();
    _editFocus.dispose();
    _hoverPos.dispose();
    _inkPressureSample.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 首次布局时把画布适配到视口（居中显示、按比例缩放）。
  ///
  /// 若该文档/笔记页在 LRU 视图缓存中有记录，则恢复上次的缩放与平移
  /// （重开笔记回到上次位置），否则首次进入时居中适配。
  void _initViewport(Size viewportSize) {
    if (_viewportInitialized) return;
    _viewportInitialized = true;

    final cached = ViewTransformCache.restore(_viewCacheKey);
    if (cached != null) {
      _controller.viewScale = cached.scale.clamp(0.05, 20.0);
      _controller.viewOffset = cached.offset;
      return;
    }

    final doc = _controller.document;
    final scaleW = viewportSize.width / doc.width;
    final scaleH = viewportSize.height / doc.height;
    _controller.viewScale = (scaleW < scaleH ? scaleW : scaleH).clamp(
      0.05,
      8.0,
    );
    // 画布中心对齐视口中心：缩放/旋转以画布中心为基准点，
    // 因此 offset = 视口中心 - 画布中心（不乘 scale）。
    _controller.viewOffset = Offset(
      viewportSize.width / 2 - doc.width / 2,
      viewportSize.height / 2 - doc.height / 2,
    );
  }

  /// 视图缓存的键：笔记本页面按页面 id，独立画布按文档 id。
  String get _viewCacheKey => widget.page != null
      ? 'page:${widget.page!.id}'
      : 'doc:${_controller.document.id}';

  // ---------------- 保存 ----------------

  /// 自动保存执行中标记与补写标记：任意一次保存期间又发生更改时，
  /// 当前保存结束后立即再保存最新快照，绝不因为“正在保存”而丢弃修改。
  bool _autosaving = false;
  bool _autosaveQueued = false;
  bool _closingEditor = false;
  bool _allowPopAfterSave = false;
  Completer<void>? _autosaveCompletion;

  void _notifyChanged() {
    // 页面标题跟随文档标题。
    final page = widget.page;
    if (page != null) {
      page.title = _controller.document.title;
      page.updatedAt = DateTime.now();
    }
    widget.onChanged?.call();
    _scheduleAutosave();
  }

  /// 安排一次防抖自动保存（R4：委托 ViewModel 调度，行为不变）。
  void _scheduleAutosave() {
    _viewModel.scheduleAutosave();
  }

  /// 执行自动保存：独立画作 → 工程文件 + 缩略图；笔记本页面 → 由上级回调落盘。
  Future<void> _doAutosave() async {
    // 笔记本页面模式：onChanged 已由 NotebookViewPage 负责保存。
    if (widget.page != null) return;
    final storage = widget.docStorage;
    final doc = _controller.document;
    if (storage == null) return;
    if (_autosaving) {
      _autosaveQueued = true;
      return _autosaveCompletion?.future ?? Future<void>.value();
    }

    _autosaving = true;
    final completion = Completer<void>();
    _autosaveCompletion = completion;
    try {
      do {
        _autosaveQueued = false;
        // StorageService 在调用时立即编码不可变快照；后续笔画不会改写此版本。
        await storage.save(doc);
        // 文档 JSON 是数据完整性的第一优先级。关闭中控制器可能已释放，
        // 因此只跳过可再生的缩略图，不跳过正文保存。
        if (!_closingEditor) {
          final png = await _controller.renderToPng(scale: 0.2);
          if (png != null) await storage.saveThumbnail(doc.id, png);
        }
      } while (_autosaveQueued);
      completion.complete();
    } catch (e, stackTrace) {
      debugPrint('自动保存失败: $e\n$stackTrace');
      // 将失败记录到日志但不向防抖 Timer 抛出未处理异常；后续一次内容变更
      // 仍可重新触发保存，避免单次 I/O 故障永久阻断该文档。
      completion.complete();
    } finally {
      _autosaving = false;
      if (identical(_autosaveCompletion, completion)) {
        _autosaveCompletion = null;
      }
    }
  }

  /// 导出当前画布为 PNG（用户选择保存位置）。
  /// 复制 PNG 到剪贴板（对齐 Excalidraw 剪贴板复制，平台通道）。
  ///
  /// 流程：渲染 PNG -> 解码为 RGBA 像素 -> 平台通道传给 C++/Android，
  /// 由平台写入剪贴板（Windows 用 CF_DIB 位图格式）。
  Future<void> _copyPngToClipboard() async {
    try {
      final png = await _controller.renderToPng();
      if (png == null) {
        _showSnack('复制失败：无法渲染画布');
        return;
      }
      // 解码 PNG 为 RGBA 像素（供平台构造 DIB 位图）。
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        _showSnack('复制失败：像素解码失败');
        return;
      }
      const channel = MethodChannel('gov.drawingnotes/clipboard');
      await channel.invokeMethod('copyPng', {
        'width': image.width,
        'height': image.height,
        'rgba': data.buffer.asUint8List(),
      });
      image.dispose();
      _showSnack('已复制 PNG 到剪贴板');
    } catch (e) {
      _showSnack('复制 PNG 需平台支持：$e');
    }
  }

  Future<void> _exportPng() async {
    try {
      final png = await _controller.renderToPng();
      if (png == null) {
        _showSnack('导出失败：无法渲染画布');
        return;
      }
      final suggested = '${_controller.document.title}.png';
      final location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PNG 图片', extensions: ['png']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(png, flush: true);
      _showSnack('已导出到：${location.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 导出当前画布为 PDF（D4，借鉴 ONLYOFFICE 保真打印与 Saber 混合导出）。
  ///
  /// 钢笔笔画以矢量路径写入（任意缩放清晰）；高亮笔/铅笔/图片/形状以
  /// 光栅位图嵌入，页面尺寸与画布导出区域一致，保证矢量与位图精确对齐。
  Future<void> _exportPdf() async {
    final page = widget.page;
    if (page != null) {
      await _exportNotebookPdf(page);
      return;
    }
    try {
      final bounds = _controller.document.infinite
          ? _controller.contentBounds()
          : Rect.fromLTWH(
              0,
              0,
              _controller.document.width.toDouble(),
              _controller.document.height.toDouble(),
            );
      final vectorStrokes = <Stroke>[
        for (final layer in _controller.document.layers)
          for (final stroke in layer.strokes)
            if (!PdfHybridExporter.shouldRasterize(stroke)) stroke,
      ];
      final png = await _controller.renderToPng(
        excludedTypes: const {BrushType.pen},
      );
      if (png == null) {
        _showSnack('导出失败：无法渲染画布');
        return;
      }
      final bytes = await PdfHybridExporter.export(
        bounds: bounds,
        rasterPng: png,
        vectorStrokes: vectorStrokes,
      );
      final location = await getSaveLocation(
        suggestedName: '${_controller.document.title}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF 文档', extensions: ['pdf']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
      _showSnack('已导出到：${location.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  /// 导出分页笔记为 A4 PDF：结构化文字以可检索 CJK 字体排版；同时附加
  /// 手写墨迹图层页，避免只导出文字而丢失原始书写内容。
  Future<void> _exportNotebookPdf(NotebookPage page) async {
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/DroidSansFallbackFull.ttf',
      );
      final cjk = pw.Font.ttf(fontData);
      final theme = pw.ThemeData.withFont(
        base: cjk,
        bold: cjk,
        italic: cjk,
        boldItalic: cjk,
      );
      final ordered = page.textItems.toList()
        ..sort((a, b) {
          final byY = a.y.compareTo(b.y);
          return byY == 0 ? a.x.compareTo(b.x) : byY;
        });
      final document = pw.Document(theme: theme);
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(52, 56, 52, 56),
          build: (context) => [
            pw.Text(
              page.title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 18),
            for (final item in ordered)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(
                  '${item.isTodo ? (item.todoChecked ? '[x] ' : '[ ] ') : ''}${item.text}',
                  style: pw.TextStyle(
                    fontSize: (item.fontSize * 0.72).clamp(10, 28),
                    fontWeight: item.bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    fontStyle: item.italic
                        ? pw.FontStyle.italic
                        : pw.FontStyle.normal,
                    decoration: item.strikethrough
                        ? pw.TextDecoration.lineThrough
                        : (item.underline
                              ? pw.TextDecoration.underline
                              : pw.TextDecoration.none),
                  ),
                ),
              ),
          ],
        ),
      );

      final inkPng = await _controller.renderToPng();
      if (inkPng != null) {
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            build: (context) => pw.Center(
              child: pw.Image(pw.MemoryImage(inkPng), fit: pw.BoxFit.contain),
            ),
          ),
        );
      }

      final location = await getSaveLocation(
        suggestedName: '${page.title}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF 文档', extensions: ['pdf']),
        ],
      );
      if (location == null) return;
      await File(
        location.path,
      ).writeAsBytes(await document.save(), flush: true);
      _showSnack('已导出分页笔记 PDF：${location.path}');
    } catch (e) {
      _showSnack('导出分页笔记 PDF 失败：$e');
    }
  }

  /// 导出画布为 SVG（借鉴 Excalidraw 开放矢量格式）。
  ///
  /// 矢量导出：笔画转 SVG path 元素（Catmull-Rom 平滑曲线），
  /// 文字块转 SVG text 元素，白纸底 + viewBox 自适应；
  /// SVG 可无损缩放、供政府公文/网页嵌入。
  Future<void> _exportSvg() async {
    try {
      final doc = _controller.document;
      final w = doc.width.toDouble();
      final h = doc.height.toDouble();
      final buf = StringBuffer()
        ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
        ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
          'viewBox="0 0 $w $h">',
        )
        ..writeln('<rect width="$w" height="$h" fill="white"/>');

      // 各图层笔画（可见层，按顺序绘制）。
      for (final layer in doc.layers) {
        if (!layer.visible || layer.opacity <= 0) continue;
        for (final stroke in layer.strokes) {
          buf.write(_strokeToSvgPath(stroke));
        }
      }
      // 文字块（笔记本模式）。
      final page = widget.page;
      if (page != null) {
        for (final t in page.textItems) {
          buf.write(_textToSvgText(t));
        }
      }
      buf.writeln('</svg>');

      final location = await getSaveLocation(
        suggestedName: '${doc.title}.svg',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SVG 矢量图', extensions: ['svg']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsString(buf.toString(), flush: true);
      _showSnack('已导出 SVG 到：${location.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  /// 笔画 -> SVG path（用采样点折线 + 线宽 stroke，与画布视觉一致）。
  String _strokeToSvgPath(Stroke stroke) {
    if (stroke.points.isEmpty) return '';
    final w = stroke.width.toDouble();
    final argb = stroke.color.toARGB32();
    // 颜色格式：#RRGGBB，透明 alpha 用 stroke-opacity。
    final hex = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final alpha = ((argb >> 24) & 0xFF) / 255;
    final d = StringBuffer()
      ..write('M${stroke.points.first.x},${stroke.points.first.y}');
    for (final p in stroke.points.skip(1)) {
      d.write(' L${p.x},${p.y}');
    }
    return '<path d="$d" fill="none" stroke="#$hex" '
        'stroke-width="$w" stroke-linecap="round" stroke-linejoin="round" '
        'stroke-opacity="${alpha.toStringAsFixed(3)}"/>\n';
  }

  /// 文字块 -> SVG text（字号/颜色/粗斜体/对齐）。
  String _textToSvgText(PageTextItem t) {
    final hex = (t.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final bold = t.bold ? ' font-weight="bold"' : '';
    final italic = t.italic ? ' font-style="italic"' : '';
    // XML 转义，防止特殊字符破坏 SVG。
    final text = t.text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    return '<text x="${t.x}" y="${t.y + t.fontSize}" '
        'font-size="${t.fontSize}" fill="#$hex"$bold$italic '
        'font-family="sans-serif">$text</text>\n';
  }

  /// 导出分页笔记为可由 Microsoft Word、WPS 等直接打开的 RTF 文档。
  ///
  /// 手写、图片和形状属于版面内容，推荐以 PDF/PNG/SVG 导出保真；此处导出
  /// 的是可继续编辑的结构化文字流，按页面坐标从上到下排序。
  Future<void> _exportWordCompatibleRtf() async {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅分页笔记支持导出 Word 兼容文档');
      return;
    }
    if (page.textItems.isEmpty) {
      _showSnack('本页还没有可导出的文字内容');
      return;
    }
    try {
      final rtf = PagedNoteRtfExporter.build(
        title: page.title,
        textItems: page.textItems,
      );
      final location = await getSaveLocation(
        suggestedName: '${page.title}.rtf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Word 兼容文档', extensions: ['rtf']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsString(rtf, flush: true);
      _showSnack('已导出 Word 兼容文档：${location.path}');
    } catch (e) {
      _showSnack('导出 Word 兼容文档失败：$e');
    }
  }

  /// 导出页面文字块内容为 Markdown/TXT（借鉴 nb/Joplin）。
  ///
  /// 样式映射：待办 -> `- [ ]/[x]`；粗体 -> `**`；斜体 -> `*`；
  /// 便利贴 -> 引用块 `>`；其余为纯文本行。
  Future<void> _exportText() async {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅笔记本页面支持导出文本');
      return;
    }
    if (page.textItems.isEmpty) {
      _showSnack('本页还没有文字内容');
      return;
    }

    final lines = <String>[];
    for (final t in page.textItems) {
      var text = t.text;
      if (t.bold) text = '**$text**';
      if (t.italic) text = '*$text*';
      if (t.isTodo) text = '- [${t.todoChecked ? 'x' : ' '}] $text';
      if (t.isSticky) text = '> $text';
      lines.add(text);
    }
    final content = '# ${page.title}\n\n${lines.join('\n\n')}\n';

    try {
      final location = await getSaveLocation(
        suggestedName: '${page.title}.md',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Markdown / 文本', extensions: ['md', 'txt']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsString(content, flush: true);
      _showSnack('已导出文本到：${location.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  // ---------------- 手势处理 ----------------

  /// 当前按下且经输入仲裁器接受的指针（pointerId -> 视口坐标），用于多指缩放/旋转。
  final Map<int, Offset> _activePointers = {};

  /// 触控笔优先、手掌拒绝和双指视图手势的无状态决策器。
  final EditorInputArbiter _inputArbiter = EditorInputArbiter();

  /// 保持既有 Android 单指书写体验；触控笔接触时仍自动拒绝手掌触控。
  /// 后续由工具预设设置页暴露为用户可配置项。
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
    // 非自由书写工具也需要获得首个指针以执行选区、手型或形状操作；
    // 此处的 allowInk 只表示“单指事件可继续下传”，并不创建实际墨迹。
    allowInk: true,
    allowFingerDrawing: _isDirectInkMode ? _fingerDrawingEnabled : true,
  );

  /// 多指手势状态：上次两指距离与角度。
  double? _pinchDistance;
  double? _pinchAngle;

  /// 是否处于多指手势（缩放/旋转画布）中。
  bool get _inPinch => _activePointers.length >= 2;

  /// 指针落下：跟踪指针，必要时进入绘制/选区流程。
  void _onPointerDown(PointerDownEvent event, Offset local) {
    final disposition = _inputArbiter.onDown(event, policy: _inputPolicy);
    if (disposition == EditorPointerDisposition.ignore) return;
    _activePointers[event.pointer] = local;

    // 第二个非手掌指针意味着用户明确开始视图手势；取消尚未提交的第一笔，
    // 防止缩放后在笔记中留下短促的误触笔画。
    if (disposition == EditorPointerDisposition.cancelInkForViewportGesture) {
      _controller.cancelActiveStroke();
    }
    if (_inPinch ||
        disposition == EditorPointerDisposition.beginViewportGesture ||
        disposition == EditorPointerDisposition.cancelInkForViewportGesture) {
      _initPinch();
      return;
    }

    final canvasPoint = _controller.viewToCanvas(local);

    // 吸管模式：点击取色，取色后切回画笔。
    if (_eyedropperActive) {
      _pickColor(canvasPoint);
      return;
    }

    // 文字工具模式：点击放置文字。
    if (_textToolActive) {
      _addTextItem(canvasPoint);
      return;
    }

    // 选区模式：独立绘图先命中最上层图片；未命中时保持既有笔画矩形/套索逻辑。
    if (_controller.selectionTool != SelectionTool.none) {
      if (!_isNotebookMode) {
        final shape = _controller.selectDocumentShapeAt(canvasPoint);
        if (shape != null) {
          _viewModel.setSelectionDone(true);
          _lastDragCanvas = canvasPoint;
          return;
        }
        final image = _controller.selectDocumentImageAt(canvasPoint);
        if (image != null) {
          _viewModel.setSelectionDone(true);
          _lastDragCanvas = canvasPoint;
          return;
        }
      }
      if (_selectionDone && _controller.hasSelectedStrokes) {
        _lastDragCanvas = canvasPoint;
      } else {
        _viewModel.setSelectionDone(false);
        _controller.beginSelection(canvasPoint);
      }
      return;
    }

    // 手型工具：记录拖动起点（平移画布）。
    if (_handToolActive) {
      _handDragLast = local;
      return;
    }

    // 形状工具：按下创建草稿，移动决定尺寸；不进入手写笔画。
    if (_activeShapeTool != null) {
      setState(() {
        _shapeDraftStart = canvasPoint;
        _shapeDraftCurrent = canvasPoint;
      });
      return;
    }

    // 框选工具：记录框选起点（不进入绘制，借鉴 Excalidraw 多选）。
    if (_marqueeActive) {
      setState(() {
        _marqueeStart = canvasPoint;
        _marqueeRect = Rect.fromPoints(canvasPoint, canvasPoint);
        _multiSelectedIds.clear();
      });
      return;
    }

    // 对象橡皮擦不创建伪笔画：命中哪一条就从对象模型中删除哪一条。
    if (_isObjectEraser) {
      _controller.beginObjectErase();
      _controller.eraseStrokesAt(canvasPoint);
      return;
    }

    // 起笔也采集压力；此前固定为 1.0 会让每一笔的笔尖突变为最粗。
    _stylusInput.resetStroke();
    final sample = _stylusInput.process(event);
    _inkPressureSample.value = sample;
    _lastPenPos = canvasPoint;
    _lastPenTime = DateTime.now();
    _controller.startStroke(
      canvasPoint,
      pressure: _controller.tool == BrushType.eraser ? 1.0 : sample.value,
    );
  }

  void _onPointerMove(PointerMoveEvent event, Offset local) {
    // 更新状态栏坐标（所有模式都记录，供状态栏显示）。
    _hoverPos.value = _controller.viewToCanvas(local);
    final disposition = _inputArbiter.onMove(event);
    if (disposition == EditorPointerDisposition.ignore) return;
    final wasPinch = _inPinch;
    _activePointers[event.pointer] = local;

    // 多指手势：缩放/旋转画布。
    if (_inPinch ||
        disposition == EditorPointerDisposition.updateViewportGesture) {
      _updatePinch();
      return;
    }
    // 从多指手势退出到单指：丢弃当前笔画（避免画布旋转后误画一笔）。
    if (wasPinch) return;

    if (_eyedropperActive || _textToolActive) return;
    final canvasPoint = _controller.viewToCanvas(local);

    // 选区模式
    if (_controller.selectionTool != SelectionTool.none) {
      if (!_isNotebookMode &&
          _selectionDone &&
          _controller.selectedDocumentObjectCount > 1) {
        final last = _lastDragCanvas;
        if (last != null) {
          final delta = canvasPoint - last;
          if (delta.distance > 0.001) {
            _controller.moveSelectedDocumentObjects(delta);
            _lastDragCanvas = canvasPoint;
          }
        }
      } else if (_selectionDone && _controller.hasSelectedDocumentShape) {
        final last = _lastDragCanvas;
        if (last != null) {
          final delta = canvasPoint - last;
          if (delta.distance > 0.001) {
            _controller.moveSelectedDocumentImage(delta);
            _lastDragCanvas = canvasPoint;
          }
        }
      } else if (_selectionDone && _controller.hasSelectedStrokes) {
        final last = _lastDragCanvas;
        if (last != null) {
          final delta = canvasPoint - last;
          if (delta.distance > 0.001) {
            _controller.moveSelectedStrokes(delta);
            _lastDragCanvas = canvasPoint;
          }
        }
      } else {
        _controller.extendSelection(canvasPoint);
      }
      return;
    }

    // 手型工具：拖动平移视口（对齐 Excalidraw hand）。
    if (_handToolActive) {
      final last = _handDragLast;
      if (last != null) {
        _controller.viewOffset += local - last;
        _handDragLast = local;
        _controller.tickFrame();
      }
      return;
    }

    // 形状工具：实时更新草稿外接框，提供拖拽创建的即时视觉反馈。
    if (_activeShapeTool != null && _shapeDraftStart != null) {
      setState(() => _shapeDraftCurrent = canvasPoint);
      return;
    }

    // 框选工具：更新框选矩形（借鉴 Excalidraw 多选）。
    if (_marqueeActive && _marqueeStart != null) {
      setState(() {
        _marqueeRect = Rect.fromPoints(_marqueeStart!, canvasPoint);
      });
      return;
    }

    if (_isObjectEraser) {
      _controller.eraseStrokesAt(canvasPoint);
      return;
    }

    // 无真实压感的鼠标才使用受限速度回退；触控笔范围由处理器正规化。
    double? fallbackPressure;
    final last = _lastPenPos;
    final lastTime = _lastPenTime;
    if (_controller.tool == BrushType.eraser) {
      fallbackPressure = 1.0;
    } else if (last != null && lastTime != null) {
      final dt = DateTime.now().difference(lastTime).inMilliseconds;
      final distance = (canvasPoint - last).distance;
      final speed = dt > 0 ? distance / dt : 0;
      fallbackPressure = (1.0 - speed / 10.0).clamp(0.6, 1.0);
    }
    final sample = _stylusInput.process(
      event,
      fallbackPressure: fallbackPressure,
    );
    _inkPressureSample.value = sample;
    _lastPenPos = canvasPoint;
    _lastPenTime = DateTime.now();
    _controller.extendStroke(
      canvasPoint,
      pressure: _controller.tool == BrushType.eraser ? 1.0 : sample.value,
    );
  }

  /// 初始化捏合参数：以当前两指距离/角度为基准。
  void _initPinch() {
    final pts = _activePointers.values.toList();
    if (pts.length < 2) return;
    final d = (pts[0] - pts[1]).distance;
    final a = (pts[1] - pts[0]).direction;
    _pinchDistance = d;
    _pinchAngle = a;
  }

  /// 更新捏合：根据两指距离/角度变化调整画布缩放与旋转。
  void _updatePinch() {
    final pts = _activePointers.values.toList();
    if (pts.length < 2 || _pinchDistance == null || _pinchAngle == null) return;
    final d = (pts[0] - pts[1]).distance;
    final a = (pts[1] - pts[0]).direction;
    if (d < 1e-3) return;

    // 缩放：距离比（限制在合理范围，防止画布被缩放得不可用）。
    final scaleFactor = d / _pinchDistance!;
    _controller.viewScale = (_controller.viewScale * scaleFactor).clamp(
      0.05,
      20.0,
    );

    // 旋转：角度差（弧度），归一化到 [-π, π] 避免跨越边界时翻转。
    var angleDelta = a - _pinchAngle!;
    const pi = 3.141592653589793;
    while (angleDelta > pi) {
      angleDelta -= 2 * pi;
    }
    while (angleDelta < -pi) {
      angleDelta += 2 * pi;
    }
    _controller.viewRotation += angleDelta;

    _pinchDistance = d;
    _pinchAngle = a;
    _controller.tickFrame(); // 视口变换高频更新：只重绘画布。
  }

  void _onPointerUp(PointerUpEvent event) {
    final wasTracked = _activePointers.containsKey(event.pointer);
    final disposition = _inputArbiter.onUp(event);
    if (!wasTracked) return;
    // 按 pointerId 精确移除，避免多指手势中抬起一指误清全部状态。
    _activePointers.remove(event.pointer);
    if (_activePointers.length >= 2) {
      // 仍处于多指：以剩余手指重新校准捏合基准。
      _initPinch();
    } else {
      _pinchDistance = null;
      _pinchAngle = null;
    }

    // 只有实际完成首个单指操作时，才允许后续工具结算。多指视图手势中
    // 的抬起仅清理状态，不能提交笔画、放置形状或结束选区。
    if (disposition != EditorPointerDisposition.finishInk) return;
    if (_eyedropperActive || _textToolActive) return;

    // 框选工具：结算框选，把矩形内的混排对象加入多选（借鉴 Excalidraw）。
    if (_marqueeActive && _marqueeRect != null) {
      final page = widget.page;
      if (page != null) {
        final rect = _marqueeRect!;
        setState(() {
          _multiSelectedIds.clear();
          for (final t in page.textItems) {
            if (rect.overlaps(
              Rect.fromLTWH(t.x, t.y, t.fontSize * 2, t.fontSize),
            )) {
              _multiSelectedIds.add(t.id);
            }
          }
          for (final i in page.imageItems) {
            if (rect.overlaps(Rect.fromLTWH(i.x, i.y, i.width, i.height))) {
              _multiSelectedIds.add(i.id);
            }
          }
          for (final s in page.shapes) {
            if (rect.overlaps(Rect.fromLTWH(s.x, s.y, s.width, s.height))) {
              _multiSelectedIds.add(s.id);
            }
          }
          _marqueeRect = null;
          _marqueeStart = null;
        });
        _notifyChanged();
      }
      return;
    }

    // 形状工具：按实际拖拽范围提交到笔记页或独立绘图文档。
    if (_activeShapeTool != null) {
      final start = _shapeDraftStart;
      final end =
          _shapeDraftCurrent ?? _controller.viewToCanvas(event.localPosition);
      if (start != null) {
        final geometry = ShapeCreationGeometry.fromDrag(start, end);
        final page = widget.page;
        final snapId = page == null ? null : _findSnapTargetId(end);
        final shape = geometry.createShape(
          id: NotebookStorage.newId('shp'),
          shapeType: _activeShapeTool!,
          color: _controller.color.toARGB32(),
          strokeWidth: _controller.brushSize,
          boundElementId: snapId,
        );
        // 独立画布的箭头在起终点落入既有形状时自动建立双端关系。
        // 分页笔记保持原有轻量 `boundElementId` 行为，避免改变其旧格式语义。
        if (page == null && shape.shapeType == ShapeType.arrow) {
          ShapeBindingGeometry.bindArrowAtEndpoints(
            shape,
            _controller.document.shapes,
            start: start,
            end: end,
          );
        }
        setState(() {
          _shapeItems.add(shape);
          _selectedItemId = shape.id;
          _shapeDraftStart = null;
          _shapeDraftCurrent = null;
        });
        _controller.document.touch();
        _notifyChanged();
      }
      return;
    }

    // 选区模式
    if (_controller.selectionTool != SelectionTool.none) {
      if (!_isNotebookMode &&
          _selectionDone &&
          _controller.selectedDocumentObjectCount > 1) {
        _lastDragCanvas = null;
        _controller.endDocumentObjectsTransform();
        _notifyChanged();
      } else if (_selectionDone && _controller.hasSelectedDocumentShape) {
        _lastDragCanvas = null;
        _controller.endDocumentShapeTransform();
        _notifyChanged();
      } else if (_selectionDone && _controller.hasSelectedStrokes) {
        _lastDragCanvas = null;
        _controller.endTransform();
        _notifyChanged();
      } else {
        _controller.endSelection();
        final polygon = _controller.selection.polygon;
        if (!_isNotebookMode && polygon.length >= 3) {
          _controller.selectDocumentObjectsInPolygon(polygon);
        }
        if (_controller.hasSelection ||
            (!_isNotebookMode && _controller.hasMixedDocumentObjectSelection)) {
          _viewModel.setSelectionDone(true);
        }
        // 分页笔记保留既有的混排对象套索；独立绘图文档由控制器统一维护
        // 笔画、形状和图片选择，避免 UI 侧临时 ID 与历史事务脱节。
        if (_isNotebookMode && polygon.length >= 3) {
          final path = Path()..addPolygon(polygon, true);
          final page = widget.page;
          if (page != null) {
            setState(() {
              for (final t in page.textItems) {
                final c = t.position + Offset(t.fontSize, t.fontSize / 2);
                if (path.contains(c)) _multiSelectedIds.add(t.id);
              }
              for (final i in page.imageItems) {
                final c = i.position + Offset(i.width / 2, i.height / 2);
                if (path.contains(c)) _multiSelectedIds.add(i.id);
              }
              for (final sh in page.shapes) {
                final c = sh.position + Offset(sh.width / 2, sh.height / 2);
                if (path.contains(c)) _multiSelectedIds.add(sh.id);
              }
            });
          }
        }
      }
      return;
    }
    if (_isObjectEraser) {
      _controller.endObjectErase();
      _notifyChanged();
      return;
    }
    _controller.endStroke();
    _notifyChanged();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final wasTracked = _activePointers.containsKey(event.pointer);
    _inputArbiter.onCancel(event);
    if (!wasTracked) return;
    _activePointers.remove(event.pointer);
    _pinchDistance = null;
    _pinchAngle = null;
    if (_activeShapeTool != null) {
      setState(() {
        _shapeDraftStart = null;
        _shapeDraftCurrent = null;
      });
      return;
    }
    if (_eyedropperActive || _textToolActive) return;
    if (_controller.selectionTool != SelectionTool.none) {
      _lastDragCanvas = null;
      if (!_isNotebookMode && _controller.selectedDocumentObjectCount > 1) {
        _controller.cancelDocumentObjectsTransform();
      } else {
        _controller.cancelDocumentShapeTransform();
        _controller.cancelDocumentImageTransform();
      }
      return;
    }
    if (_isObjectEraser) {
      _controller.cancelObjectErase();
      return;
    }
    _controller.cancelActiveStroke();
  }

  /// 滚轮缩放画布：以鼠标当前位置为锚点（桌面端标准交互）。
  ///
  /// 滚轮向上（dy < 0）放大，向下（dy > 0）缩小；
  /// 缩放后鼠标指向的画布位置保持不变（锚点不漂移）。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 每格滚轮缩放 10%（factor>1 放大，<1 缩小）。
    final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
    _zoomAt(event.localPosition, factor);
  }

  /// 以视口坐标 [viewPoint] 为锚点缩放画布 [factor] 倍。
  void _zoomAt(Offset viewPoint, double factor) {
    final oldScale = _controller.viewScale;
    final newScale = (oldScale * factor).clamp(0.05, 20.0);
    if ((newScale - oldScale).abs() < 1e-9) return;

    // 保持锚点不动：缩放前后锚点对应的画布坐标必须一致。
    // 由变换模型 view = R·(scale·(p - center)) + center + offset 推导：
    //   offset' = view - R·(newScale·(p - center)) - center
    // 其中 p = viewToCanvas(viewPoint)（缩放前）。
    final c = _controller.document.size.center(Offset.zero);
    final canvasPoint = _controller.viewToCanvas(viewPoint);
    final rotated = rotatePoint2(
      (canvasPoint - c) * newScale,
      _controller.viewRotation,
    );
    _controller.viewOffset = viewPoint - rotated - c;
    _controller.viewScale = newScale;
    _controller.tickFrame(); // 高频重绘：仅画布。
  }

  /// 在画布坐标处取色并更新当前画笔颜色。
  Future<void> _pickColor(Offset canvasPoint) async {
    final color = await _controller.pickColorAt(canvasPoint);
    if (color == null) return;
    _updateCurrentBrushPreset(color: color);
    setState(() => _viewModel.setEyedropperActive(false));
  }

  /// 打开颜色选择对话框，应用用户选择的颜色。
  Future<void> _showColorPicker() async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initialColor: _controller.color),
    );
    if (color != null) {
      _updateCurrentBrushPreset(color: color);
    }
  }

  // ---------------- 文字 / 图片混排（Phase 5） ----------------

  /// 文字工具：点击画布后在该位置直接就地输入文字（借鉴 OneNote/Word，
  /// 不再弹窗输入）。文字块先创建为空文本并进入编辑状态，回车/失焦提交。
  void _addTextItem(Offset canvasPoint) {
    final page = widget.page;
    if (page == null) {
      _showSnack('文字框当前用于分页笔记；无限画布文字对象将在资料工作流阶段开放');
      return;
    }

    // 先完成上一项，再开始新项，避免 setState 内再次 setState 造成输入框失焦。
    _commitTextEditing();
    setState(() {
      // 创建临时文字块（尚未加入页面，提交时才加入）。
      final item = PageTextItem(
        id: NotebookStorage.newId('txt'),
        x: canvasPoint.dx,
        y: canvasPoint.dy,
        text: '',
      );
      _editingItemId = item.id;
      _editController.clear();
      _viewModel.setTextToolActive(false);
      // 保存临时项供 overlay 渲染与提交。
      _pendingTextItem = item;
      _selectedItemId = null;
    });
    // 下一帧把焦点交给就地编辑框。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  /// 画布双击（对齐 Excalidraw 双击插入文字）：
  /// 双击空白处 -> 新建文字块并立即进入就地编辑；
  /// 双击已有文字块 -> 进入该文字块的编辑。
  void _onCanvasDoubleTap(TapDownDetails details) {
    final page = widget.page;
    if (page == null) return;
    final canvasPoint = _controller.viewToCanvas(details.localPosition);
    // 查找双击位置命中的文字块（取其编辑框）。
    for (final t in page.textItems) {
      final w = t.fontSize * 2;
      if (Rect.fromLTWH(t.x, t.y, w, t.fontSize).contains(canvasPoint)) {
        setState(() => _selectedItemId = t.id);
        _editTextItem();
        return;
      }
    }
    // 空白处：新建文字并编辑（Excalidraw 同款顺滑插入）。
    _addTextItem(canvasPoint);
  }

  /// 提交就地编辑的文字块：空文本则丢弃，非空则加入页面并保存。
  ///
  /// 注意：编辑"已有"文字块时，[pending] 已在 [page.textItems] 中，
  /// 不能重复添加（评审发现 P1：重复项会被持久化并叠加渲染）。
  void _commitTextEditing() {
    final page = widget.page;
    final pending = _pendingTextItem;
    if (page == null || pending == null || _editingItemId == null) return;

    final text = _editController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        pending.text = text;
        if (!page.textItems.any((t) => t.id == pending.id)) {
          page.textItems.add(pending); // 仅新文字块才加入
        }
        _selectedItemId = pending.id;
      });
      _notifyChanged();
    }
    _editingItemId = null;
    _pendingTextItem = null;
    _slashOpen = false;
    _editFocus.unfocus();
  }

  /// 结束就地编辑（点画布其他位置/切换工具时调用）。
  void _cancelTextEditing() {
    _commitTextEditing();
    _editingItemId = null;
    _pendingTextItem = null;
  }

  /// 添加"特殊标签"（便利贴样式文字块，弹窗输入，可拖动移动）。
  ///
  /// 与就地编辑并存：就地编辑用于快速文字，标签用于醒目分类标注。
  Future<void> _addStickyNote() async {
    final page = widget.page;
    if (page == null) return;

    // 先结束可能存在的就地编辑。
    _cancelTextEditing();

    final result = await showDialog<_TextDialogResult>(
      context: context,
      builder: (_) => const _TextInputDialog(),
    );
    if (result == null || result.text.trim().isEmpty) return;

    setState(() {
      page.textItems.add(
        PageTextItem(
          id: NotebookStorage.newId('txt'),
          x: _controller.document.width / 2 - 100,
          y: _controller.document.height / 2 - 40,
          text: result.text.trim(),
          fontSize: result.fontSize,
          color: 0xFFFFF59D, // 便利贴黄底，文字用深色
          isSticky: true,
        ),
      );
      _selectedItemId = page.textItems.last.id;
    });
    _notifyChanged();
  }

  /// 调节选中文字块的字号（工具栏滑块调用）。
  void _setSelectedTextFontSize(double size) {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final item = page.textItems.where((t) => t.id == id).firstOrNull;
    if (item == null) return;
    setState(() {
      item.fontSize = size.clamp(8, 200);
    });
    _notifyChanged();
  }

  /// 分页预览（D3：长笔记多页预览，借鉴 Umo Editor 分页模式）。
  ///
  /// 把页面文字块按 A4 页面高度（逻辑像素）分页渲染到预览对话框，
  /// 便于查看长笔记的分页效果（导出 PDF 时的版式）。
  void _showPaginationPreview() {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅笔记本页面支持分页预览');
      return;
    }
    if (page.textItems.isEmpty) {
      _showSnack('本页还没有文字内容');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('分页预览 · ${page.title}'),
        content: SizedBox(
          width: 480,
          height: 560,
          child: PaginationPreview(textItems: page.textItems),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 修改选中文字块的颜色（复用颜色选择对话框）。
  Future<void> _changeSelectedTextColor() async {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final item = page.textItems.where((t) => t.id == id).firstOrNull;
    if (item == null) return;

    final color = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initialColor: Color(item.color)),
    );
    if (color == null) return;
    setState(() {
      item.color = color.toARGB32();
    });
    _notifyChanged();
  }

  /// 宏：批量改色（B1，借鉴 Trilium 脚本自动化）——
  /// 把页面所有文字块的颜色统一改为当前画笔颜色。
  void _macroRecolorAllText() {
    final page = widget.page;
    if (page == null) return;
    if (page.textItems.isEmpty) {
      _showSnack('本页没有文字块');
      return;
    }
    final target = _controller.color.toARGB32();
    setState(() {
      for (final t in page.textItems) {
        t.color = target;
      }
    });
    _notifyChanged();
    _showSnack('已批量改色 ${page.textItems.length} 个文字块');
  }

  /// 图片工具：选择本地图片、复制为应用管理的离线副本后放置到画布中心。
  ///
  /// 分页笔记与独立绘图文档均支持导入；两者分别使用各自存储服务，避免
  /// 关闭或移动原文件后出现“图片图标存在但内容丢失”。
  Future<void> _insertImage() async {
    try {
      // file_selector：Flutter 官方文件选择器，跨 Windows/Android 一致，
      // 且已适配 AGP 9 的 built-in Kotlin（file_picker 存在兼容问题）。
      const typeGroup = XTypeGroup(
        label: '图片',
        extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      );
      final XFile? result = await openFile(acceptedTypeGroups: [typeGroup]);
      if (result == null || result.path.isEmpty) return;

      final center = Offset(
        _controller.document.width / 2,
        _controller.document.height / 2,
      );
      final page = widget.page;
      if (page != null) {
        final storage = widget.storage;
        if (storage == null) {
          _showSnack('笔记页图片存储不可用');
          return;
        }
        final storedPath = await storage.storeImage(result.path, page.id);
        setState(() {
          page.imageItems.add(
            PageImageItem(
              id: NotebookStorage.newId('img'),
              x: center.dx,
              y: center.dy,
              filePath: storedPath,
            ),
          );
          _selectedItemId = page.imageItems.last.id;
        });
      } else {
        final storage = widget.docStorage;
        if (storage == null) {
          _showSnack('绘图文档图片存储不可用');
          return;
        }
        final storedPath = await storage.storeImage(
          result.path,
          _controller.document.id,
        );
        setState(() {
          _controller.document.imageItems.add(
            DocumentImageItem(
              id: StorageService.newId(),
              x: center.dx - 100,
              y: center.dy - 75,
              filePath: storedPath,
            ),
          );
          _controller.document.touch();
          _selectedItemId = _controller.document.imageItems.last.id;
        });
      }
      _notifyChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('插入图片失败：$e')));
      }
    }
  }

  /// 连线工具（D1）：连线模式下依次点选两个元素，创建连接线。
  void _toggleLinkMode() {
    setState(() {
      _handToolActive = false;
      _marqueeActive = false;
      _activeShapeTool = null;
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _controller.selectionTool = SelectionTool.none;
      _viewModel.setLinkMode(!_viewModel.linkMode);
      _viewModel.setLinkSourceId(null);
    });
  }

  /// 元素被选中：连线模式下作为连线端点；否则普通选中。
  void _onItemTap(String itemId) {
    // 元素超链接（借鉴 Excalidraw hyperlink）：有 href 的元素点击时
    // 用系统默认浏览器打开（Windows 用 start 命令）。
    final page = widget.page;
    if (page != null) {
      String? href;
      for (final t in page.textItems) {
        if (t.id == itemId) href = t.href;
      }
      for (final i in page.imageItems) {
        if (i.id == itemId) href = i.href;
      }
      for (final sh in page.shapes) {
        if (sh.id == itemId) href = sh.href;
      }
      if (href != null && href.isNotEmpty) {
        _openHref(href);
        return;
      }
    }
    if (_linkMode) {
      if (_linkSourceId == null) {
        setState(() => _viewModel.setLinkSourceId(itemId));
        _showSnack('已选择起点，再点击另一个元素完成连线');
      } else if (_linkSourceId != itemId) {
        final page = widget.page;
        if (page != null) {
          setState(() {
            page.connectors.add(
              PageConnector(
                id: NotebookStorage.newId('cn'),
                fromItemId: _linkSourceId!,
                toItemId: itemId,
              ),
            );
            _viewModel.setLinkSourceId(null);
            _viewModel.setLinkMode(false);
          });
          _notifyChanged();
          _showSnack('已创建连接');
        }
      }
      return;
    }
    setState(() => _selectedItemId = itemId);
  }

  /// 图层顺序操作（置顶/置底/上移/下移，借鉴 Excalidraw 图层操作）。
  /// 通过调整混排对象的 zOrder 实现；当前作用于选中/多选元素。
  void _reorderSelected(int mode) {
    final page = widget.page;
    if (page == null) return;
    final ids = _expandGroup(
      _multiSelectedIds.isNotEmpty
          ? _multiSelectedIds
          : <String>{?_selectedItemId},
    );
    if (ids.isEmpty) return;

    // 收集目标元素（文字/图片/形状）。
    final targets = <({int z, String id})>[];
    for (final t in page.textItems) {
      if (ids.contains(t.id)) targets.add((z: t.zOrder, id: t.id));
    }
    for (final i in page.imageItems) {
      if (ids.contains(i.id)) targets.add((z: i.zOrder, id: i.id));
    }
    for (final s in page.shapes) {
      if (ids.contains(s.id)) targets.add((z: s.zOrder, id: s.id));
    }
    if (targets.isEmpty) return;

    // 收集全部元素的最大/最小 zOrder（用于置顶/置底）。
    var maxZ = 0;
    var minZ = 0;
    bool any = false;
    void scan(int z) {
      any = true;
      if (z > maxZ) maxZ = z;
      if (z < minZ) minZ = z;
    }

    for (final t in page.textItems) {
      scan(t.zOrder);
    }
    for (final i in page.imageItems) {
      scan(i.zOrder);
    }
    for (final s in page.shapes) {
      scan(s.zOrder);
    }
    if (!any) return;

    setState(() {
      for (final t in page.textItems) {
        if (ids.contains(t.id)) {
          t.zOrder = switch (mode) {
            0 => maxZ + 1, // 置顶
            1 => minZ - 1, // 置底
            2 => t.zOrder + 1, // 上移
            _ => t.zOrder - 1, // 下移
          };
        }
      }
      for (final i in page.imageItems) {
        if (ids.contains(i.id)) {
          i.zOrder = switch (mode) {
            0 => maxZ + 1,
            1 => minZ - 1,
            2 => i.zOrder + 1,
            _ => i.zOrder - 1,
          };
        }
      }
      for (final s in page.shapes) {
        if (ids.contains(s.id)) {
          s.zOrder = switch (mode) {
            0 => maxZ + 1,
            1 => minZ - 1,
            2 => s.zOrder + 1,
            _ => s.zOrder - 1,
          };
        }
      }
    });
    _notifyChanged();
  }

  /// 右键上下文菜单（借鉴 Excalidraw 菜单）：复制样式/删除/置顶/置底。
  void _showItemContextMenu(String itemId) {
    setState(() => _selectedItemId = itemId);
    showMenu<_CtxAction>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 0, 0),
      items: const [
        PopupMenuItem(value: _CtxAction.copyStyle, child: Text('复制样式')),
        PopupMenuItem(value: _CtxAction.group, child: Text('分组')),
        PopupMenuItem(value: _CtxAction.link, child: Text('设置链接…')),
        PopupMenuItem(value: _CtxAction.ungroup, child: Text('取消分组')),
        PopupMenuItem(value: _CtxAction.delete, child: Text('删除')),
        PopupMenuItem(value: _CtxAction.bringToFront, child: Text('置顶')),
        PopupMenuItem(value: _CtxAction.sendToBack, child: Text('置底')),
      ],
    ).then((action) {
      switch (action) {
        case _CtxAction.copyStyle:
          _copySelectedStyle();
        case _CtxAction.group:
          _groupSelected();
        case _CtxAction.link:
          _setLink();
        case _CtxAction.ungroup:
          _ungroupSelected();
        case _CtxAction.delete:
          _deleteSelectedItem();
        case _CtxAction.bringToFront:
          _reorderSelected(0);
        case _CtxAction.sendToBack:
          _reorderSelected(1);
        case null:
          break;
      }
    });
  }

  /// 删除选中的混排对象。
  /// 打开超链接（Windows 用 start 命令调默认浏览器；其他平台提示）。
  void _openHref(String href) {
    try {
      if (Platform.isWindows) {
        Process.start('cmd', ['/c', 'start', '', href]);
      } else {
        Process.start('xdg-open', [href]);
      }
      _showSnack('已打开链接');
    } catch (e) {
      _showSnack('无法打开链接：$e');
    }
  }

  /// 设置元素超链接（借鉴 Excalidraw hyperlink）：输入 URL 绑定到选中元素，
  /// 元素点击时用系统默认浏览器打开。
  Future<void> _setLink() async {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    // 找到当前 href（若有）。
    String? current;
    for (final t in page.textItems) {
      if (t.id == id) current = t.href;
    }
    for (final i in page.imageItems) {
      if (i.id == id) current = i.href;
    }
    for (final sh in page.shapes) {
      if (sh.id == id) current = sh.href;
    }
    final controller = TextEditingController(text: current ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (url == null) return;
    final link = url.trim().isEmpty ? null : url.trim();
    setState(() {
      for (final t in page.textItems) {
        if (t.id == id) t.href = link;
      }
      for (final i in page.imageItems) {
        if (i.id == id) i.href = link;
      }
      for (final sh in page.shapes) {
        if (sh.id == id) sh.href = link;
      }
    });
    _notifyChanged();
    _showSnack(link == null ? '已清除链接' : '已设置链接');
  }

  /// 分组：给选中的多个元素设置相同 groupId（借鉴 Excalidraw groupIds）。
  void _groupSelected() {
    final page = widget.page;
    if (page == null) return;
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    if (ids.length < 2) {
      _showSnack('请先框选/多选至少 2 个元素再分组');
      return;
    }
    final groupId = NotebookStorage.newId('grp');
    setState(() {
      for (final t in page.textItems) {
        if (ids.contains(t.id)) t.groupId = groupId;
      }
      for (final i in page.imageItems) {
        if (ids.contains(i.id)) i.groupId = groupId;
      }
      for (final sh in page.shapes) {
        if (ids.contains(sh.id)) sh.groupId = groupId;
      }
    });
    _notifyChanged();
    _showSnack('已分组 ${ids.length} 个元素');
  }

  /// 取消分组：清空选中元素的 groupId。
  void _ungroupSelected() {
    final page = widget.page;
    if (page == null) return;
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    setState(() {
      for (final t in page.textItems) {
        if (ids.contains(t.id)) t.groupId = null;
      }
      for (final i in page.imageItems) {
        if (ids.contains(i.id)) i.groupId = null;
      }
      for (final sh in page.shapes) {
        if (ids.contains(sh.id)) sh.groupId = null;
      }
    });
    _notifyChanged();
    _showSnack('已取消分组');
  }

  void _deleteSelectedItem() {
    final page = widget.page;
    if (page == null) return;
    // 多选删除：删除全部选中的混排对象（文字/图片/形状，借鉴 Excalidraw 多选）。
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    if (ids.isEmpty) return;
    // 删除淡出动画：先标记为删除中，180ms 后真正移除（借鉴 Excalidraw）。
    setState(() {
      _deletingIds.addAll(ids);
      _multiSelectedIds.clear();
      _selectedItemId = null;
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        page.textItems.removeWhere((t) => ids.contains(t.id));
        page.imageItems.removeWhere((i) => ids.contains(i.id));
        page.shapes.removeWhere((s) => ids.contains(s.id));
        page.charts.removeWhere((c) => ids.contains(c.id));
        _deletingIds.removeAll(ids);
      });
      _notifyChanged();
    });
  }

  /// 缩放控件：放大（借鉴 Excalidraw 缩放导航）。
  void _zoomIn() {
    _controller.viewScale = (_controller.viewScale * 1.25).clamp(0.05, 20.0);
    _controller.tickFrame();
  }

  /// 缩放控件：缩小。
  void _zoomOut() {
    _controller.viewScale = (_controller.viewScale / 1.25).clamp(0.05, 20.0);
    _controller.tickFrame();
  }

  /// 缩放控件：恢复 100%。
  void _zoomReset() {
    _controller.viewScale = 1.0;
    _controller.tickFrame();
  }

  /// 编辑选中的文字块：双击/工具栏进入就地编辑（直接打字修改，
  /// 借鉴 OneNote/Word，替代弹窗输入）。
  void _editTextItem() {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final item = page.textItems.where((t) => t.id == id).firstOrNull;
    if (item == null) return;

    setState(() {
      // 清理上一个未提交的就地编辑。
      _commitTextEditing();
      _editingItemId = item.id;
      _editController.text = item.text;
      _pendingTextItem = item;
    });
    // 下一帧把焦点交给就地编辑框，并把光标移到末尾。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocus.requestFocus();
      _editController.selection = TextSelection.collapsed(
        offset: _editController.text.length,
      );
    });
  }

  /// 处理键盘动作。
  ///
  /// 借鉴 Excalidraw ActionManager：快捷键只负责匹配和分发，真正的
  /// 可用性与副作用始终收敛在 [_commands]。这样当同一动作在菜单或
  /// 命令面板中呈现时，不会出现“快捷键能用但按钮不可用”的分叉。
  KeyEventResult _onShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final hw = HardwareKeyboard.instance;
    final isCtrlOrMeta = hw.isControlPressed || hw.isMetaPressed;
    final isShift = hw.isShiftPressed;
    final isAlt = hw.isAltPressed;
    final key = event.logicalKey;

    // 数字键 1-9 切换工具，保留符合绘图软件惯例的直接路径。
    if (!isCtrlOrMeta && !isAlt) {
      if (key == LogicalKeyboardKey.digit1) {
        _selectBrushTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2) {
        _selectEraserTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit3) {
        _selectRectSelectTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit4) {
        if (!_marqueeActive) _toggleMarqueeTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit5) {
        _selectTextTool();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit6) {
        _selectShapeTool(ShapeType.rect);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit7) {
        _selectShapeTool(ShapeType.ellipse);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit8) {
        _selectShapeTool(ShapeType.arrow);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit9) {
        _selectShapeTool(ShapeType.line);
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.delete ||
              key == LogicalKeyboardKey.backspace) &&
          _commands.run('deleteSelection')) {
        return KeyEventResult.handled;
      }
    }

    // Alt+方向键微调选中元素位置（对齐 Excalidraw nudge，1px 步进）。
    if (isAlt && !isCtrlOrMeta && _selectedItemId != null) {
      switch (key) {
        case LogicalKeyboardKey.arrowLeft:
          _nudgeSelected(-1, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _nudgeSelected(1, 0);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _nudgeSelected(0, -1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _nudgeSelected(0, 1);
          return KeyEventResult.handled;
        default:
          break;
      }
    }

    if (!isCtrlOrMeta) return KeyEventResult.ignored;

    bool run(String id) => _commands.run(id);
    switch (key) {
      case LogicalKeyboardKey.keyZ:
        return (isShift ? run('redo') : run('undo'))
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyY:
        return run('redo') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyB:
        return run('bold') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyI:
        return run('italic') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyU:
        return run('underline')
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyE:
        return run('alignText')
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyC:
        if (isShift) {
          if (!_hasObjectSelection) return KeyEventResult.ignored;
          _copySelectedStyle();
          return KeyEventResult.handled;
        }
        return run('copy') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyV:
        if (isShift) {
          if (!_hasObjectSelection) return KeyEventResult.ignored;
          _pasteStyleToSelected();
          return KeyEventResult.handled;
        }
        return run('paste') ? KeyEventResult.handled : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyD:
        return run('duplicate')
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.keyK:
        _showCommandPalette();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        if (isShift) {
          _showCommandPalette();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// 右上角主菜单选择处理（对齐 Excalidraw main-menu）。
  void _onMainMenuSelected(_MainMenuItem item) {
    switch (item) {
      case _MainMenuItem.clearCanvas:
        _controller.clearAll();
      case _MainMenuItem.copyPng:
        _copyPngToClipboard();
      case _MainMenuItem.exportPng:
        _exportPng();
      case _MainMenuItem.exportSvg:
        _exportSvg();
      case _MainMenuItem.exportPdf:
        _exportPdf();
      case _MainMenuItem.exportJson:
        _exportJson();
      case _MainMenuItem.exportPptx:
        _exportPptx();
      case _MainMenuItem.exportText:
        _exportText();
      case _MainMenuItem.exportWord:
        _exportWordCompatibleRtf();
      case _MainMenuItem.commandPalette:
        _showCommandPalette();
      case _MainMenuItem.chart:
        _createChart();
      case _MainMenuItem.presentation:
        _startPresentation();
      case _MainMenuItem.stats:
        _showStats();
      case _MainMenuItem.library:
        _openShapeLibrary();
      case _MainMenuItem.shortcuts:
        _showShortcutHelp();
    }
  }

  /// 导出画布为 PPTX（对齐 Excalidraw PPTX 导出）。
  ///
  /// 用 archive 包手动构造最小 OOXML PPTX：一张幻灯片嵌入画布 PNG 图片，
  /// 可在 PowerPoint/WPS 中打开编辑。
  Future<void> _exportPptx() async {
    try {
      final png = await _controller.renderToPng();
      if (png == null) {
        _showSnack('导出失败：无法渲染画布');
        return;
      }
      final doc = _controller.document;
      final w = doc.width.toDouble();
      final h = doc.height.toDouble();

      // OOXML PPTX 文件结构（最小可打开）。
      final files = <String, List<int>>{
        '[Content_Types].xml': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
</Types>''',
        ),
        '_rels/.rels': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''',
        ),
        'ppt/presentation.xml': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
<p:sldSz cx="${(w * 9525).round()}" cy="${(h * 9525).round()}"/>
</p:presentation>''',
        ),
        'ppt/_rels/presentation.xml.rels': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
</Relationships>''',
        ),
        'ppt/slides/slide1.xml': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
<p:pic>
<p:nvPicPr><p:cNvPr id="2" name="Canvas"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>
<p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${(w * 9525).round()}" cy="${(h * 9525).round()}"/></a:xfrm>
<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
</p:pic>
</p:spTree></p:cSld>
</p:sld>''',
        ),
        'ppt/slides/_rels/slide1.xml.rels': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
</Relationships>''',
        ),
        'ppt/media/image1.png': png,
      };

      // 打包 ZIP（PPTX = OOXML ZIP 容器）。
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final bytes = ZipEncoder().encode(archive);
      if (bytes.isEmpty) {
        _showSnack('导出失败：PPTX 打包失败');
        return;
      }

      final location = await getSaveLocation(
        suggestedName: '${doc.title}.pptx',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PPTX 演示文稿', extensions: ['pptx']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
      _showSnack('已导出 PPTX 到：${location.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  /// 导出画布为 JSON（Excalidraw 开放格式对齐：.excalidraw 语义）。
  Future<void> _exportJson() async {
    try {
      final doc = _controller.document;
      final page = widget.page;
      final data = {
        'type': 'drawing-notes',
        'version': 1,
        'title': doc.title,
        'width': doc.width,
        'height': doc.height,
        'layers': doc.layers.map((l) => l.toJson()).toList(),
        if (page != null)
          'textItems': page.textItems.map((t) => t.toJson()).toList(),
        if (page != null)
          'imageItems': page.imageItems.map((i) => i.toJson()).toList(),
        if (page != null) 'shapes': page.shapes.map((s) => s.toJson()).toList(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final location = await getSaveLocation(
        suggestedName: '${doc.title}.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON 工程文件', extensions: ['json']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsString(json, flush: true);
      _showSnack('已导出 JSON 到：${location.path}');
    } catch (e) {
      _showSnack('导出失败：$e');
    }
  }

  /// 图表生成（借鉴 Excalidraw charts）：粘贴数值（逗号/空格/换行分隔），
  /// 自动生成柱状图/折线图元素并放入画布中心。
  Future<void> _createChart() async {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅笔记本页面支持图表');
      return;
    }
    final input = TextEditingController();
    var chartType = ChartType.bar;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('生成图表'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<ChartType>(
                  segments: const [
                    ButtonSegment(
                      value: ChartType.bar,
                      label: Text('柱状图'),
                      icon: Icon(Icons.bar_chart),
                    ),
                    ButtonSegment(
                      value: ChartType.line,
                      label: Text('折线图'),
                      icon: Icon(Icons.show_chart),
                    ),
                  ],
                  selected: {chartType},
                  onSelectionChanged: (v) =>
                      setDialogState(() => chartType = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  autofocus: true,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: '粘贴数值，用逗号/空格/换行分隔，例如：10, 25, 18, 42, 30',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('ok'),
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    // 解析数值（逗号/空格/换行分隔）。
    final data = input.text
        .split(RegExp(r'[, ]+'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => double.tryParse(e.trim()))
        .whereType<double>()
        .toList();
    if (data.isEmpty) {
      _showSnack('未解析到有效数值');
      return;
    }
    final center = _controller.document.size.center(Offset.zero);
    setState(() {
      page.charts.add(
        PageChartItem(
          id: NotebookStorage.newId('cht'),
          chartType: chartType,
          data: data,
          x: center.dx - 160,
          y: center.dy - 100,
        ),
      );
      _selectedItemId = page.charts.last.id;
    });
    _notifyChanged();
    _showSnack('已生成图表（${data.length} 个数据点）');
  }

  /// 幻灯片演示（对齐 Excalidraw presentation）：全屏逐元素展示。
  void _startPresentation() {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅笔记本页面支持幻灯片演示');
      return;
    }
    if (page.textItems.isEmpty &&
        page.imageItems.isEmpty &&
        page.shapes.isEmpty) {
      _showSnack('本页还没有可演示的内容');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PresentationPage(
          textItems: page.textItems,
          imageItems: page.imageItems,
          shapes: page.shapes,
        ),
      ),
    );
  }

  /// 统计面板（对齐 Excalidraw Stats）：显示元素数量/类型统计。
  Future<void> _showStats() async {
    final page = widget.page;
    final doc = _controller.document;
    var strokes = 0;
    for (final layer in doc.layers) {
      strokes += layer.strokes.length;
    }
    final textN = page?.textItems.length ?? 0;
    final imgN = page?.imageItems.length ?? 0;
    final shapeN = page?.shapes.length ?? 0;
    final chartN = page?.charts.length ?? 0;
    final total = textN + imgN + shapeN + chartN + strokes;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('画布统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statRow('手写笔画', strokes),
            _statRow('文字块', textN),
            _statRow('图片', imgN),
            _statRow('形状', shapeN),
            _statRow('图表', chartN),
            const Divider(),
            _statRow('合计元素', total),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 统计面板行。
  Widget _statRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 形状库/图书馆（对齐 Excalidraw libraries）：浏览/检索/插入形状。
  /// 个人收藏（收藏到库）保存在会话内。
  Future<void> _openShapeLibrary() async {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅笔记本页面支持形状库');
      return;
    }
    final library = _shapeLibrary;
    await showDialog<void>(
      context: context,
      builder: (ctx) => ShapeLibraryDialog(
        library: library,
        onInsert: (template) {
          // 插入到画布中心（带偏移，避免与库预览重叠）。
          final center = _controller.document.size.center(Offset.zero);
          final shape = PageShapeItem.fromJson(template.toJson())
            ..x = center.dx - template.width / 2
            ..y = center.dy - template.height / 2;
          setState(() {
            page.shapes.add(shape);
            _selectedItemId = shape.id;
          });
          _notifyChanged();
          _showSnack('已插入「${shapeTypeName(shape.shapeType)}」');
        },
      ),
    );
  }

  /// 会话内形状库（个人收藏）。
  late final ShapeLibrary _shapeLibrary = ShapeLibrary();

  /// 命令面板（Ctrl/Cmd+K，对齐 Excalidraw CommandPalette）。
  ///
  /// 条目完全来自统一命令注册表；只显示当前可执行的动作，并按类别、
  /// 关键词和最近执行状态组织。这样不会再出现菜单中展示无法完成的命令。
  Future<void> _showCommandPalette() async {
    final queryController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = queryController.text;
          final commands = _commands.search(query);
          final grouped = <EditorCommandCategory, List<EditorCommand>>{};
          for (final command in commands) {
            grouped.putIfAbsent(command.category, () => []).add(command);
          }
          final recent = query.trim().isEmpty
              ? _commands.find(_lastCommandId ?? '')
              : null;
          final showRecent = recent != null && recent.available;

          Widget commandTile(EditorCommand command, {bool recentItem = false}) {
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(_commandCategoryIcon(command.category), size: 19),
              title: Text(command.label),
              subtitle: recentItem ? const Text('最近使用') : null,
              trailing: command.shortcut.isEmpty
                  ? null
                  : Text(
                      command.shortcut,
                      style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
              onTap: () => Navigator.of(ctx).pop(command.id),
            );
          }

          return AlertDialog(
            title: const Text('命令面板'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) {
                      if (commands.isNotEmpty) {
                        Navigator.of(ctx).pop(commands.first.id);
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: '搜索操作、工具或导出格式…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: commands.isEmpty
                        ? const Center(child: Text('没有可执行的匹配命令'))
                        : ListView(
                            children: [
                              if (showRecent) ...[
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(8, 4, 8, 2),
                                  child: Text('最近使用'),
                                ),
                                commandTile(recent, recentItem: true),
                                const Divider(),
                              ],
                              for (final category
                                  in EditorCommandCategory.values)
                                if (grouped[category]?.isNotEmpty ?? false) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      8,
                                      2,
                                    ),
                                    child: Text(
                                      category.label,
                                      style: Theme.of(
                                        ctx,
                                      ).textTheme.labelMedium,
                                    ),
                                  ),
                                  for (final command in grouped[category]!)
                                    if (!showRecent || command.id != recent.id)
                                      commandTile(command),
                                ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    queryController.dispose();
    if (result == null) return;
    if (_commands.run(result)) {
      setState(() => _lastCommandId = result);
    }
  }

  IconData _commandCategoryIcon(EditorCommandCategory category) {
    return switch (category) {
      EditorCommandCategory.edit => Icons.edit_outlined,
      EditorCommandCategory.format => Icons.format_size_rounded,
      EditorCommandCategory.insert => Icons.add_box_outlined,
      EditorCommandCategory.arrange => Icons.layers_outlined,
      EditorCommandCategory.view => Icons.visibility_outlined,
      EditorCommandCategory.export => Icons.ios_share_rounded,
    };
  }

  /// 剪贴板元素（复制/粘贴的元素，借鉴 Excalidraw 元素复制）。
  /// 结构：kind + 序列化 JSON，粘贴时反序列化并偏移位置。
  List<Map<String, dynamic>> _copiedElements = [];

  /// 复制选中元素（文字/图片/形状，借鉴 Excalidraw 元素复制）。
  void _copySelectedElement() {
    final page = widget.page;
    if (page == null) return;
    _copiedElements = [];
    // 多选优先，其次单选。
    final ids = _multiSelectedIds.isNotEmpty
        ? _multiSelectedIds
        : <String>{?_selectedItemId};
    for (final t in page.textItems) {
      if (ids.contains(t.id)) {
        _copiedElements.add({'kind': 'text', 'data': t.toJson()});
      }
    }
    for (final i in page.imageItems) {
      if (ids.contains(i.id)) {
        _copiedElements.add({'kind': 'image', 'data': i.toJson()});
      }
    }
    for (final s in page.shapes) {
      if (ids.contains(s.id)) {
        _copiedElements.add({'kind': 'shape', 'data': s.toJson()});
      }
    }
    if (_copiedElements.isNotEmpty) {
      _showSnack('已复制 ${_copiedElements.length} 个元素');
    } else {
      _showSnack('请先选中要复制的元素');
    }
  }

  /// 粘贴复制的元素（偏移 24px，避免与原位置重叠，借鉴 Excalidraw）。
  void _pasteCopiedElement() {
    final page = widget.page;
    if (page == null || _copiedElements.isEmpty) {
      _showSnack('请先复制元素（Ctrl+C）');
      return;
    }
    setState(() {
      _multiSelectedIds.clear();
      for (final entry in _copiedElements) {
        final kind = entry['kind'] as String;
        final data = entry['data'] as Map<String, dynamic>;
        final dx = 24.0, dy = 24.0;
        if (kind == 'text') {
          final t = PageTextItem.fromJson(data);
          t.x += dx;
          t.y += dy;
          page.textItems.add(t);
          _multiSelectedIds.add(t.id);
        } else if (kind == 'image') {
          final img = PageImageItem.fromJson(data);
          img.x += dx;
          img.y += dy;
          page.imageItems.add(img);
          _multiSelectedIds.add(img.id);
        } else if (kind == 'shape') {
          final s = PageShapeItem.fromJson(data);
          s.x += dx;
          s.y += dy;
          page.shapes.add(s);
          _multiSelectedIds.add(s.id);
        }
      }
    });
    _notifyChanged();
    _showSnack('已粘贴 ${_copiedElements.length} 个元素');
  }

  /// 复制的样式（颜色/字号/粗斜体/线宽，供样式刷粘贴）。
  Map<String, dynamic>? _copiedStyle;

  /// 快捷键：切到画笔工具。
  void _selectBrushTool() => _selectWritingTool(BrushType.pen);

  /// 快捷键：切到橡皮擦工具。
  void _selectEraserTool() => _selectWritingTool(BrushType.eraser);

  /// 快捷键：切到矩形选区工具。
  void _selectRectSelectTool() {
    setState(() {
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(false);
      _viewModel.setSelectionDone(false);
      _controller.selectionTool = SelectionTool.rect;
    });
  }

  /// 快捷键：切到文字工具。
  void _selectTextTool() {
    setState(() {
      _viewModel.setEyedropperActive(false);
      _viewModel.setTextToolActive(true);
    });
  }

  /// Alt+方向键微调：选中元素按画布像素微移（对齐 Excalidraw nudge）。
  void _nudgeSelected(double dx, double dy) {
    final page = widget.page;
    if (page == null) return;
    final id = _selectedItemId;
    if (id == null) return;
    setState(() {
      for (final t in page.textItems) {
        if (t.id == id) {
          t.x += dx;
          t.y += dy;
        }
      }
      for (final i in page.imageItems) {
        if (i.id == id) {
          i.x += dx;
          i.y += dy;
        }
      }
      for (final sh in page.shapes) {
        if (sh.id == id) {
          sh.x += dx;
          sh.y += dy;
        }
      }
    });
    _notifyChanged();
  }

  /// 复制选中元素样式（文字块或形状，借鉴 Excalidraw 样式刷）。
  void _copySelectedStyle() {
    final page = widget.page;
    final id = _selectedItemId;
    if (page == null || id == null) return;
    final t = page.textItems.where((x) => x.id == id).firstOrNull;
    if (t != null) {
      _copiedStyle = {
        'kind': 'text',
        'color': t.color,
        'fontSize': t.fontSize,
        'bold': t.bold,
        'italic': t.italic,
        'underline': t.underline,
        'strikethrough': t.strikethrough,
      };
      _showSnack('已复制文字样式');
      return;
    }
    final s = page.shapes.where((x) => x.id == id).firstOrNull;
    if (s != null) {
      _copiedStyle = {
        'kind': 'shape',
        'color': s.color,
        'fillColor': s.fillColor,
        'strokeWidth': s.strokeWidth,
      };
      _showSnack('已复制形状样式');
      return;
    }
    _showSnack('请先选中文字块或形状');
  }

  /// 粘贴样式到选中元素（借鉴 Excalidraw 样式刷）。
  void _pasteStyleToSelected() {
    final style = _copiedStyle;
    final page = widget.page;
    final id = _selectedItemId;
    if (style == null || page == null || id == null) {
      _showSnack('请先复制样式（Ctrl+Shift+C）再粘贴');
      return;
    }
    setState(() {
      final t = page.textItems.where((x) => x.id == id).firstOrNull;
      if (t != null && style['kind'] == 'text') {
        t.color = style['color'] as int;
        t.fontSize = style['fontSize'] as double;
        t.bold = style['bold'] as bool;
        t.italic = style['italic'] as bool;
        t.underline = style['underline'] as bool;
        t.strikethrough = style['strikethrough'] as bool;
      }
      final s = page.shapes.where((x) => x.id == id).firstOrNull;
      if (s != null && style['kind'] == 'shape') {
        s.color = style['color'] as int;
        s.fillColor = style['fillColor'] as int?;
        s.strokeWidth = style['strokeWidth'] as double;
      }
    });
    _notifyChanged();
    _showSnack('已粘贴样式');
  }

  /// 剪贴板智能粘贴（借鉴 Excalidraw 粘贴识别）：
  /// 文本内容创建文字块，PNG 图片创建图片块，置于画布中心。
  Future<void> _pasteFromClipboard() async {
    final page = widget.page;
    if (page == null) {
      _showSnack('仅笔记本页面支持粘贴');
      return;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.trim().isNotEmpty) {
        // 文本 -> 文字块（画布中心）。
        final center = _controller.document.size.center(Offset.zero);
        setState(() {
          page.textItems.add(
            PageTextItem(
              id: NotebookStorage.newId('txt'),
              x: center.dx - text.length * 3,
              y: center.dy - 12,
              text: text.trim(),
            ),
          );
          _selectedItemId = page.textItems.last.id;
        });
        _notifyChanged();
        return;
      }
      // 图片：当前 Flutter 桌面端 ClipboardData 无图片字段，
      // 图片粘贴需平台通道（后续增强），此处明确提示。
      _showSnack('剪贴板没有可粘贴的文本');
    } catch (e) {
      _showSnack('粘贴失败：$e');
    }
  }

  /// 切换选中文字块的加粗状态。
  void _toggleSelectedTextBold() {
    final item = _selectedTextItem;
    if (item == null) return;
    setState(() => item.bold = !item.bold);
    _notifyChanged();
  }

  /// 切换选中文字块的斜体状态。
  void _toggleSelectedTextItalic() {
    final item = _selectedTextItem;
    if (item == null) return;
    setState(() => item.italic = !item.italic);
    _notifyChanged();
  }

  /// 循环切换选中文字块的对齐方式。
  void _cycleSelectedTextAlign() {
    final item = _selectedTextItem;
    if (item == null) return;
    setState(() {
      item.align = TextAlignType
          .values[(item.align.index + 1) % TextAlignType.values.length];
    });
    _notifyChanged();
  }

  /// 快捷键帮助对话框（B2：从命令注册表自动生成，借鉴 Notes 快捷键文档化）。
  void _showShortcutHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('快捷键'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in _commands.commands)
                if (c.shortcut.isNotEmpty)
                  ShortcutRow(shortcut: c.shortcut, action: c.label),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 键盘快捷键（桌面标准）：Ctrl+Z 撤销、Ctrl+Y / Ctrl+Shift+Z 重做。
    return PopScope<Object?>(
      canPop: _allowPopAfterSave,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _allowPopAfterSave) return;
        final navigator = Navigator.of(context);
        await _flushBeforePop();
        if (!mounted) return;
        setState(() => _allowPopAfterSave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) navigator.pop(result);
        });
      },
      child: KeyboardListener(
        focusNode: _shortcutFocus,
        autofocus: true,
        onKeyEvent: _onShortcutKey,
        child: Scaffold(
          appBar: AppBar(
            title: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final isNote = _isNotebookMode;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        _controller.document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        isNote ? Icons.article_outlined : Icons.all_out,
                        size: 16,
                      ),
                      label: Text(isNote ? '分页笔记' : '无限画布'),
                    ),
                  ],
                );
              },
            ),
            actions: [
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => IconButton(
                  tooltip: '撤销',
                  icon: const Icon(Icons.undo),
                  onPressed: _commands.find('undo')?.available ?? false
                      ? () => _commands.run('undo')
                      : null,
                ),
              ),
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => IconButton(
                  tooltip: '重做',
                  icon: const Icon(Icons.redo),
                  onPressed: _commands.find('redo')?.available ?? false
                      ? () => _commands.run('redo')
                      : null,
                ),
              ),

              // 画布空间与侧栏控制：将低频管理面板改为按需展开。
              IconButton(
                tooltip: _layersVisible ? '隐藏图层' : '显示图层',
                icon: Icon(
                  _layersVisible ? Icons.layers : Icons.layers_outlined,
                ),
                isSelected: _layersVisible,
                onPressed: () =>
                    setState(() => _layersVisible = !_layersVisible),
              ),
              IconButton(
                tooltip: _inspectorVisible ? '隐藏属性' : '显示属性',
                icon: Icon(
                  _inspectorVisible ? Icons.tune : Icons.tune_outlined,
                ),
                isSelected: _inspectorVisible,
                onPressed: () =>
                    setState(() => _inspectorVisible = !_inspectorVisible),
              ),
              IconButton(
                tooltip: _fullscreen ? '退出全屏' : '全屏模式',
                icon: Icon(
                  _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                onPressed: () => setState(() => _fullscreen = !_fullscreen),
              ),
              IconButton(
                tooltip: _readingInverted ? '关闭深色阅读' : '深色阅读（仅显示）',
                icon: Icon(
                  _readingInverted
                      ? Icons.invert_colors_on_outlined
                      : Icons.invert_colors_off_outlined,
                ),
                isSelected: _readingInverted,
                onPressed: () =>
                    setState(() => _readingInverted = !_readingInverted),
              ),
              // 快捷键帮助面板（借鉴 Notes 快捷键文档化）
              IconButton(
                tooltip: '快捷键帮助',
                icon: const Icon(Icons.help_outline),
                onPressed: _showShortcutHelp,
              ),
              // 右上角汉堡菜单（对齐 Excalidraw main-menu）
              PopupMenuButton<_MainMenuItem>(
                tooltip: '主菜单',
                icon: const Icon(Icons.menu),
                onSelected: _onMainMenuSelected,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _MainMenuItem.clearCanvas,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_sweep_outlined),
                      title: Text('清空画布'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _MainMenuItem.copyPng,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.content_copy),
                      title: Text('复制 PNG 到剪贴板'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.exportPng,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.image_outlined),
                      title: Text('导出 PNG'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.exportSvg,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share),
                      title: Text('导出 SVG'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.exportPdf,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('导出 PDF'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.exportJson,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.data_object),
                      title: Text('导出 JSON'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.exportPptx,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.slideshow_outlined),
                      title: Text('导出 PPTX'),
                    ),
                  ),
                  if (_isNotebookMode)
                    const PopupMenuItem(
                      value: _MainMenuItem.exportWord,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.article_outlined),
                        title: Text('导出 Word 兼容文档'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: _MainMenuItem.exportText,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined),
                      title: Text('导出文本'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _MainMenuItem.commandPalette,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.keyboard_command_key),
                      title: Text('命令面板'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.chart,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.bar_chart),
                      title: Text('图表（粘贴数据）'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.presentation,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.slideshow),
                      title: Text('幻灯片演示'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.stats,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.query_stats),
                      title: Text('统计'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _MainMenuItem.library,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.library_books_outlined),
                      title: Text('形状库（图书馆）'),
                    ),
                  ),

                  const PopupMenuItem(
                    value: _MainMenuItem.shortcuts,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.keyboard),
                      title: Text('快捷键帮助'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: _fullscreen
              // 全屏模式：只保留画布区域。
              ? _buildCanvasArea()
              : Row(
                  children: [
                    // 左侧垂直工具条（对齐 Excalidraw LayerUI 布局）。
                    EditorLeftToolbar(
                      controller: _controller,
                      eyedropperActive: _eyedropperActive,
                      textToolActive: _textToolActive,
                      marqueeActive: _marqueeActive,
                      linkMode: _linkMode,
                      handActive: _handToolActive,
                      onHand: _toggleHandTool,
                      activeShape: _activeShapeTool,
                      onBrush: () => _selectWritingTool(BrushType.pen),
                      onPencil: () => _selectWritingTool(BrushType.pencil),
                      onHighlighter: () => _selectWritingTool(BrushType.marker),
                      onLaser: () => _selectWritingTool(BrushType.laser),
                      onEraser: () => _selectWritingTool(BrushType.eraser),
                      onEyedropper: () => setState(() {
                        _handToolActive = false;
                        _activeShapeTool = null;
                        _marqueeActive = false;
                        _controller.selectionTool = SelectionTool.none;
                        _viewModel.setEyedropperActive(true);
                        _viewModel.setTextToolActive(false);
                      }),
                      onRectSelect: () => setState(() {
                        _handToolActive = false;
                        _activeShapeTool = null;
                        _marqueeActive = false;
                        _viewModel.setEyedropperActive(false);
                        _viewModel.setTextToolActive(false);
                        _viewModel.setSelectionDone(false);
                        _controller.selectionTool = SelectionTool.rect;
                      }),
                      onMarquee: _toggleMarqueeTool,
                      onText: () => setState(() {
                        _handToolActive = false;
                        _activeShapeTool = null;
                        _marqueeActive = false;
                        _controller.selectionTool = SelectionTool.none;
                        _viewModel.setEyedropperActive(false);
                        _viewModel.setTextToolActive(true);
                      }),
                      onShape: _selectShapeTool,
                      onLink: _toggleLinkMode,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _buildContextBar(),
                          _buildSelectionBar(),
                          Expanded(child: _buildCanvasArea()),
                        ],
                      ),
                    ),
                    // 图层与详细属性仅在用户需要时展开，画布默认保持居中和宽阔。
                    if (_layersVisible) LayerPanel(controller: _controller),
                    if (_inspectorVisible)
                      PropertiesPanel(
                        controller: _controller,
                        selectedShape: _selectedShapeItem,
                        selectedText: _selectedTextItem,
                        selectedImage: _selectedImageItem,
                        onPickColor: _showColorPicker,
                        onBrushSizeChanged: (v) =>
                            _updateCurrentBrushPreset(size: v),
                        onShapeStrokeWidth: (v) {
                          final s = _selectedShapeItem;
                          if (s == null) return;
                          setState(() => s.strokeWidth = v.clamp(1, 20));
                          _notifyChanged();
                        },
                        onShapeOpacity: (v) {
                          final s = _selectedShapeItem;
                          if (s == null) return;
                          setState(() {
                            if (v > 0.5) {
                              s.fillColor = s.fillColor ?? 0x66A5D6A7;
                            } else {
                              s.fillColor = null;
                            }
                          });
                          _notifyChanged();
                        },
                        onShapeFill: () {
                          final s = _selectedShapeItem;
                          if (s == null) return;
                          setState(() {
                            s.fillColor = s.fillColor == null
                                ? 0x66A5D6A7
                                : null;
                          });
                          _notifyChanged();
                        },
                        onShapeDash: () {
                          final s = _selectedShapeItem;
                          if (s == null) return;
                          setState(() => s.dash = !s.dash);
                          _notifyChanged();
                        },
                        onShapeRough: () {
                          final s = _selectedShapeItem;
                          if (s == null) return;
                          setState(() => s.rough = !s.rough);
                          _notifyChanged();
                        },
                        onTextColor: _changeSelectedTextColor,
                        onTextFontSize: _setSelectedTextFontSize,
                        onCropImage: () {
                          // 已在裁剪模式：确认裁剪；否则进入裁剪模式。
                          if (_cropItem != null) {
                            _confirmCrop();
                            return;
                          }
                          final img = _selectedImageItem;
                          if (img == null) return;
                          setState(() {
                            _cropItem = img;
                            _cropRect = Rect.fromLTWH(
                              img.x,
                              img.y,
                              img.width,
                              img.height,
                            );
                          });
                          _showSnack('拖动图片四角调整裁剪区域，再点裁剪按钮确认');
                        },
                        onCycleFont: () {
                          final t = _selectedTextItem;
                          if (t == null) return;
                          setState(() {
                            t.fontFamily = switch (t.fontFamily) {
                              null => 'serif',
                              'serif' => 'monospace',
                              'monospace' => 'handwriting',
                              _ => null,
                            };
                          });
                          _notifyChanged();
                        },
                      ),
                  ],
                ),
          // 底部状态栏（借鉴 Joplin StatusBar）：显示缩放/工具/坐标。
          bottomNavigationBar: _buildStatusBar(),
        ),
      ),
    );
  }

  /// 底部状态栏：缩放比例、当前工具粗细、鼠标画布坐标。
  Widget _buildStatusBar() {
    // 状态栏为纯展示组件（架构重构 R3）：监听 controller + hoverPos 渲染，
    // 不承载业务逻辑（见 editor_statusbar.dart）。
    return EditorStatusBar(
      controller: _controller,
      hoverPos: _hoverPos,
      inkPressureSample: _inkPressureSample,
    );
  }

  /// 画布区域（全屏/普通模式共用）。
  Widget _buildCanvasArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initViewport(constraints.biggest);
        // 记录画布视口尺寸（小地图导航需要）。
        _viewportSize = constraints.biggest;
        return Stack(
          children: [
            // 画布层：CustomPainter 通过 repaint 监听 controller + frameTick，
            // 笔触/选区/视口变换期间仅局部重绘画布，不重建低频 UI。
            // 外包 GestureDetector 识别双击（双击空白插入文字，对齐 Excalidraw）。
            Positioned.fill(
              child: GestureDetector(
                onDoubleTapDown: _onCanvasDoubleTap,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _onPointerDown(e, e.localPosition),
                  onPointerMove: (e) => _onPointerMove(e, e.localPosition),
                  onPointerUp: (e) => _onPointerUp(e),
                  onPointerCancel: (e) => _onPointerCancel(e),
                  onPointerSignal: _onPointerSignal, // 滚轮缩放画布
                  child: _readingInverted
                      ? ColorFiltered(
                          colorFilter: _readingInvertFilter,
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: CanvasPainter(controller: _controller),
                              size: Size.infinite,
                            ),
                          ),
                        )
                      : RepaintBoundary(
                          child: CustomPaint(
                            painter: CanvasPainter(controller: _controller),
                            size: Size.infinite,
                          ),
                        ),
                ),
              ),
            ),
            // 网格显示层（借鉴 Excalidraw 画布导航）
            if (_gridVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: _readingInverted
                      ? ColorFiltered(
                          colorFilter: _readingInvertFilter,
                          child: CustomPaint(
                            painter: GridPainter(controller: _controller),
                          ),
                        )
                      : CustomPaint(
                          painter: GridPainter(controller: _controller),
                        ),
                ),
              ),
            // 形状草稿层：所有工作区均可见，且不拦截正在创建形状的指针。
            if (_shapeDraft != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _readingInverted
                      ? ColorFiltered(
                          colorFilter: _readingInvertFilter,
                          child: Stack(
                            children: [_buildShapeOverlay(_shapeDraft!)],
                          ),
                        )
                      : Stack(children: [_buildShapeOverlay(_shapeDraft!)]),
                ),
              ),
            // 混排对象层（文字/图片，仅笔记本模式）：
            // 监听 frameTick，使双指缩放/旋转画布时文字/图片位置同步刷新。
            if (_isNotebookMode)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _controller.frameTick,
                  builder: (context, _) {
                    final overlay = Stack(
                      children: [
                        // 连接线层（D1：节点关联标注，借鉴 Relatum 连线）
                        Positioned.fill(
                          child: CustomPaint(
                            painter: ConnectorPainter(
                              page: widget.page!,
                              controller: _controller,
                            ),
                          ),
                        ),
                        ..._buildOverlayItems(),
                        // 拖动轨迹动画层（对齐 Excalidraw animatedTrail）
                        if (_trailPoints.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: TrailPainter(
                                  points: _trailPoints,
                                  controller: _controller,
                                ),
                              ),
                            ),
                          ),
                        // 对齐参考线（拖动元素时实时显示，借鉴 Excalidraw）
                        if (_snapGuides.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: SnapGuidePainter(
                                guides: _snapGuides,
                                controller: _controller,
                              ),
                            ),
                          ),
                        // 框选矩形（多选时可视化，借鉴 Excalidraw 多选）
                        if (_marqueeRect != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: MarqueePainter(
                                  rect: _marqueeRect!,
                                  controller: _controller,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                    return _readingInverted
                        ? ColorFiltered(
                            colorFilter: _readingInvertFilter,
                            child: overlay,
                          )
                        : overlay;
                  },
                ),
              ),
            // 画布小地图（借鉴 Relatum：放大后快速导航定位）
            Positioned(right: 8, bottom: 8, child: _buildMiniMap()),
            // 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）
            Positioned(right: 8, top: 8, child: _buildPomodoro()),
          ],
        );
      },
    );
  }

  /// 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）。
  Widget _buildPomodoro() {
    return PomodoroTimer(
      onFinished: () {
        _showSnack('番茄钟结束：休息一下吧');
      },
    );
  }

  /// 画布视口尺寸（小地图导航用，由布局回调更新）。
  Size? _viewportSize;

  /// 小地图宽高。
  static const double _miniMapWidth = 160;
  static const double _miniMapHeight = 120;

  /// 画布小地图：整幅缩略图 + 当前视口框 + 点击/拖动导航。
  Widget _buildMiniMap() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      color: const Color(0xE6FFFFFF),
      // 可用性修复：同时监听 frameTick（高频绘制/视口变化），
      // 否则小地图仅在低频状态变化时刷新，绘制中/缩放时不跟手。
      child: ListenableBuilder(
        listenable: Listenable.merge([_controller, _controller.frameTick]),
        builder: (context, _) {
          final doc = _controller.document;
          final miniScale = _miniMapWidth / doc.width;
          return GestureDetector(
            onTapDown: (d) => _navigateMiniMap(d.localPosition, miniScale),
            onPanUpdate: (d) => _navigateMiniMap(d.localPosition, miniScale),
            child: SizedBox(
              width: _miniMapWidth,
              height: _miniMapHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(
                  painter: MiniMapPainter(
                    controller: _controller,
                    miniScale: miniScale,
                    viewport: _viewportSize ?? const Size(800, 600),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 小地图点击/拖动导航：把点击处移动到视口中心。
  void _navigateMiniMap(Offset local, double miniScale) {
    // 小地图坐标 -> 画布坐标。
    final canvasPoint = Offset(local.dx / miniScale, local.dy / miniScale);
    final c = _controller.document.size.center(Offset.zero);
    final vc = _viewportSize ?? const Size(800, 600);
    final viewCenter = Offset(vc.width / 2, vc.height / 2);
    // 逆变换：offset = viewCenter - c - R(scale·(canvasPoint - c))
    final rotated = rotatePoint2(
      (canvasPoint - c) * _controller.viewScale,
      _controller.viewRotation,
    );
    _controller.viewOffset = viewCenter - rotated - c;
    _controller.tickFrame();
  }

  /// 构建画布上方的混排对象（文字块/图片块）。
  List<Widget> _buildOverlayItems() {
    final page = widget.page!;
    final items = <Widget>[];
    // 就地编辑中的临时文字块（尚未加入页面，优先渲染在最上层）。
    final pending = _pendingTextItem;
    if (pending != null && _editingItemId == pending.id) {
      items.add(_buildInlineEditor(pending));
    }
    // 按 zOrder 排序渲染混排对象（图层顺序，借鉴 Excalidraw 图层操作）。
    final ordered = <({String id, int z, Object item})>[];
    for (final t in page.textItems) {
      ordered.add((id: t.id, z: t.zOrder, item: t));
    }
    for (final img in page.imageItems) {
      ordered.add((id: img.id, z: img.zOrder, item: img));
    }
    for (final shape in page.shapes) {
      ordered.add((id: shape.id, z: shape.zOrder, item: shape));
    }
    for (final chart in page.charts) {
      ordered.add((id: chart.id, z: chart.zOrder, item: chart));
    }
    ordered.sort((a, b) => a.z.compareTo(b.z));
    for (final entry in ordered) {
      final id = entry.id;
      if (id == _editingItemId) {
        final t = page.textItems.where((x) => x.id == id).firstOrNull;
        if (t != null) items.add(_buildInlineEditor(t));
      } else {
        final t = page.textItems.where((x) => x.id == id).firstOrNull;
        final img = page.imageItems.where((x) => x.id == id).firstOrNull;
        final shape = page.shapes.where((x) => x.id == id).firstOrNull;
        final chart = page.charts.where((x) => x.id == id).firstOrNull;
        if (t != null) {
          items.add(_buildTextOverlay(t));
        } else if (img != null) {
          items.add(_buildImageOverlay(img));
        } else if (shape != null) {
          items.add(_buildShapeOverlay(shape));
        } else if (chart != null) {
          items.add(_buildChartOverlay(chart));
        }
      }
    }
    return items;
  }

  /// 图表叠加层（借鉴 Excalidraw charts）。
  Widget _buildChartOverlay(PageChartItem chart) {
    final viewPos = _controller.canvasToView(chart.position);
    final selected =
        _selectedItemId == chart.id || _multiSelectedIds.contains(chart.id);
    final w = chart.width * _controller.viewScale;
    final h = chart.height * _controller.viewScale;
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: GestureDetector(
        onTap: () => _onItemTap(chart.id),
        onPanUpdate: (d) => _dragItem(chart.id, d.delta),
        onPanEnd: (_) => _notifyChanged(),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            border: selected
                ? Border.all(color: const Color(0xFF42A5F5), width: 1.5)
                : null,
          ),
          child: CustomPaint(painter: ChartPainter(chart: chart, viewScale: 1)),
        ),
      ),
    );
  }

  /// 形状元素叠加层（借鉴 Excalidraw 图形工具）。
  Widget _buildShapeOverlay(PageShapeItem shape) {
    final viewPos = _controller.canvasToView(shape.position);
    final selected =
        _selectedItemId == shape.id || _multiSelectedIds.contains(shape.id);
    // 箭头/直线不随画布缩放而改变线宽视觉，其余形状按 viewScale 换算。
    final w = shape.width * _controller.viewScale;
    final h = shape.height * _controller.viewScale;
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: AnimatedOpacity(
        opacity: _deletingIds.contains(shape.id) ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: GestureDetector(
          onTap: () => _onItemTap(shape.id),
          onSecondaryTapDown: (d) => _showItemContextMenu(shape.id),
          onPanUpdate: (d) => _dragItem(shape.id, d.delta),
          onPanEnd: (_) => _notifyChanged(),
          child: SizedBox(
            width: w,
            height: h,
            // 旋转渲染：按 shape.rotation 旋转形状（借鉴 Excalidraw 旋转手柄）。
            child: Transform.rotate(
              angle: shape.rotation,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(
                  shape.flipX ? -1 : 1,
                  shape.flipY ? -1 : 1,
                  1,
                ),
                child: CustomPaint(
                  painter: ShapePainter(
                    shape: shape,
                    viewScale: _controller.viewScale,
                  ),
                  child: selected
                      ? Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFF42A5F5),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            // 旋转手柄（顶部中间，拖拽旋转，借鉴 Excalidraw）。
                            Positioned(
                              top: -18,
                              left: w / 2 - 5,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (d) {
                                  final center = Offset(w / 2, h / 2);
                                  final local =
                                      d.localPosition + Offset(w / 2, h / 2);
                                  final angle = (local - center).direction;
                                  setState(() => shape.rotation = angle);
                                  _notifyChanged();
                                },
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF42A5F5),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // 8 向缩放手柄（四角 + 四边中点，借鉴 Excalidraw）。
                            ..._buildResizeHandles(shape, w, h),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 就地编辑框（点击页面直接打字，回车提交、失焦提交、Esc 取消）。
  /// 输入 `/` 弹出斜杠命令菜单（D5，借鉴 Lokus 斜杠命令）。
  Widget _buildInlineEditor(PageTextItem item) {
    final viewPos = _controller.canvasToView(item.position);
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: Stack(
        children: [
          SizedBox(
            width: 320, // 固定编辑宽度，避免布局跳动
            child: TextField(
              controller: _editController,
              focusNode: _editFocus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              maxLines: null,
              minLines: 1,
              style: TextStyle(
                fontSize: item.fontSize * _controller.viewScale,
                color: Color(item.color),
              ),
              decoration: InputDecoration(
                isCollapsed: false,
                // 可见文本框（对齐 Excalidraw 打字体验）：
                // 空文本时也显示明显边框+背景，用户能清楚看到输入位置。
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.92),
                border: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF42A5F5), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF42A5F5), width: 2),
                ),
                hintText: '输入文字…（回车结束）',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onChanged: (_) {
                // D5 斜杠命令：输入 / 展开快捷菜单，继续输入则收起。
                final text = _editController.text;
                final showSlash =
                    text == '/' ||
                    (text.endsWith('/') &&
                        !text.substring(0, text.length - 1).contains('/'));
                if (showSlash != _slashOpen) {
                  setState(() => _slashOpen = showSlash);
                }
              },
              onSubmitted: (_) {
                _commitTextEditing();
              },
              onTapOutside: (_) {
                _commitTextEditing();
              },
            ),
          ),
          // 斜杠命令菜单（D5，借鉴 Lokus）：输入 / 时弹出
          if (_slashOpen)
            Positioned(
              top: 26,
              left: 0,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _slashCommand(
                      label: '加粗',
                      onTap: () => _applySlashCommand((it) => it.bold = true),
                    ),
                    _slashCommand(
                      label: '斜体',
                      onTap: () => _applySlashCommand((it) => it.italic = true),
                    ),
                    _slashCommand(
                      label: '待办',
                      onTap: () => _applySlashCommand((it) => it.isTodo = true),
                    ),
                    _slashCommand(
                      label: '居中',
                      onTap: () => _applySlashCommand(
                        (it) => it.align = TextAlignType.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slashCommand({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  /// 应用斜杠命令：给当前文字块设置样式，并清除 '/' 与菜单。
  void _applySlashCommand(void Function(PageTextItem) apply) {
    final item = _pendingTextItem;
    if (item != null) {
      apply(item);
    }
    // 移除末尾的 '/'。
    final t = _editController.text;
    if (t.endsWith('/')) {
      _editController.text = t.substring(0, t.length - 1);
    }
    setState(() => _slashOpen = false);
    _notifyChanged();
  }

  /// 文字块叠加层（可拖动、点击选中、双击编辑）。
  /// [item.isSticky] 为 true 时以便利贴（标签）样式渲染：色块背景 + 圆角。
  Widget _buildTextOverlay(PageTextItem item) {
    final viewPos = _controller.canvasToView(item.position);
    final selected =
        _selectedItemId == item.id || _multiSelectedIds.contains(item.id);
    // 连线模式下的起点高亮（橙色）：让用户看到已选中的端点。
    final linkSource = _linkMode && _linkSourceId == item.id;
    // 放置过渡动画：新元素淡入（借鉴 Excalidraw 克制的微交互）。
    // 删除淡出：删除中的元素透明度渐变为 0（_deletingIds 标记）。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: AnimatedOpacity(
        opacity: _deletingIds.contains(item.id) ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: _buildTextOverlayInner(item, viewPos, selected, linkSource),
      ),
    );
  }

  Widget _buildTextOverlayInner(
    PageTextItem item,
    Offset viewPos,
    bool selected,
    bool linkSource,
  ) {
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: GestureDetector(
        onTap: () => _onItemTap(item.id),
        onDoubleTap: _editTextItem,
        onSecondaryTapDown: (d) => _showItemContextMenu(item.id),
        onPanUpdate: (d) => _dragItem(item.id, d.delta),
        onPanEnd: (_) => _notifyChanged(),
        child: Stack(
          children: [
            Container(
              constraints: item.isSticky
                  ? const BoxConstraints(minWidth: 120, minHeight: 40)
                  : null,
              padding: item.isSticky
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                  : EdgeInsets.zero,
              decoration: item.isSticky
                  ? BoxDecoration(
                      color: Color(item.color),
                      borderRadius: BorderRadius.circular(6),
                      border: selected || linkSource
                          ? Border.all(
                              color: linkSource
                                  ? const Color(0xFFFF9800)
                                  : const Color(0xFF42A5F5),
                              width: 1.5,
                            )
                          : null,
                    )
                  : (selected || linkSource
                        ? BoxDecoration(
                            border: Border.all(
                              color: linkSource
                                  ? const Color(0xFFFF9800)
                                  : const Color(0xFF42A5F5),
                              width: 1.5,
                            ),
                          )
                        : null),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 待办 checkbox（借鉴 QOwnNotes：点击切换勾选状态）
                  if (item.isTodo)
                    InkWell(
                      onTap: () {
                        setState(() => item.todoChecked = !item.todoChecked);
                        _notifyChanged();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          item.todoChecked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: item.fontSize * _controller.viewScale * 0.9,
                          color: Color(item.color),
                        ),
                      ),
                    ),
                  // 多行文本（对齐 Excalidraw 文本框）：width 非 null 时
                  // 约束宽度 + softWrap 自动换行，可拖拽右侧手柄调整。
                  Flexible(
                    child: ConstrainedBox(
                      constraints: item.width != null
                          ? BoxConstraints(
                              maxWidth: item.width! * _controller.viewScale,
                            )
                          : const BoxConstraints(),
                      child: Text(
                        item.text,
                        softWrap: item.width != null,
                        textAlign: switch (item.align) {
                          TextAlignType.left => TextAlign.left,
                          TextAlignType.center => TextAlign.center,
                          TextAlignType.right => TextAlign.right,
                        },
                        style: TextStyle(
                          fontSize: item.fontSize * _controller.viewScale,
                          // 字体族（借鉴 Excalidraw FontPicker）。
                          fontFamily: switch (item.fontFamily) {
                            'serif' => 'serif',
                            'monospace' => 'monospace',
                            'handwriting' => 'cursive',
                            _ => null,
                          },
                          // 颜色：已勾选待办淡化；便利贴默认黄底用深色文字。
                          color: item.isTodo && item.todoChecked
                              ? Color(item.color).withValues(alpha: 0.45)
                              : (item.isSticky && item.color == 0xFFFFF59D
                                    ? const Color(0xFF3E2723)
                                    : Color(item.color)),
                          fontWeight: item.bold
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontStyle: item.italic
                              ? FontStyle.italic
                              : FontStyle.normal,
                          decoration: item.underline && item.strikethrough
                              ? TextDecoration.combine([
                                  TextDecoration.underline,
                                  TextDecoration.lineThrough,
                                ])
                              : (item.underline
                                    ? TextDecoration.underline
                                    : (item.strikethrough
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 宽度拖拽手柄（对齐 Excalidraw 文本框宽度拖拽）：选中且有宽度时，
            // 右下角手柄拖拽调整文本框宽度。
            if (selected && item.width != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    final delta = _screenDeltaToCanvas(d.delta);
                    setState(() {
                      item.width = (item.width! + delta.dx).clamp(40, 2000);
                    });
                    _notifyChanged();
                  },
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: const Color(0xFF42A5F5),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 图片块叠加层（可拖动、点击选中）。
  Widget _buildImageOverlay(PageImageItem item) {
    final viewPos = _controller.canvasToView(item.position);
    final selected =
        _selectedItemId == item.id || _multiSelectedIds.contains(item.id);
    // 连线模式下的起点高亮（橙色）：让用户看到已选中的端点。
    final linkSource = _linkMode && _linkSourceId == item.id;
    final w = item.width * _controller.viewScale;
    final h = item.height * _controller.viewScale;
    // 裁剪模式：显示可拖动裁剪框（4 角手柄调整 _cropRect）。
    final cropping = _cropItem?.id == item.id;
    return Positioned(
      left: viewPos.dx,
      top: viewPos.dy,
      child: GestureDetector(
        onTap: () => _onItemTap(item.id),
        onPanUpdate: (d) => _dragItem(item.id, d.delta),
        onPanEnd: (_) => _notifyChanged(),
        child: Stack(
          children: [
            Container(
              width: w,
              height: h,
              decoration: selected || linkSource
                  ? BoxDecoration(
                      border: Border.all(
                        color: linkSource
                            ? const Color(0xFFFF9800)
                            : const Color(0xFF42A5F5),
                        width: 1.5,
                      ),
                    )
                  : null,
              child: item.filePath.isNotEmpty
                  ? Image.file(File(item.filePath), fit: BoxFit.contain)
                  : const ColoredBox(color: Colors.grey),
            ),
            // 裁剪框 4 角手柄（对齐 Excalidraw 图片裁剪）：拖拽调整 _cropRect。
            if (cropping && _cropRect != null) ..._buildCropHandles(item),
          ],
        ),
      ),
    );
  }

  /// 拖动混排对象：把屏幕位移换算为画布位移。
  /// 分组展开（借鉴 Excalidraw groupIds）：给定元素 id 集合，
  /// 返回包含同组元素的完整集合（整体移动/删除联动）。
  Set<String> _expandGroup(Set<String> ids) {
    final page = widget.page;
    if (page == null || ids.isEmpty) return ids;
    // 收集 ids 涉及的所有 groupId。
    final groups = <String>{};
    for (final t in page.textItems) {
      if (ids.contains(t.id) && t.groupId != null) groups.add(t.groupId!);
    }
    for (final i in page.imageItems) {
      if (ids.contains(i.id) && i.groupId != null) groups.add(i.groupId!);
    }
    for (final sh in page.shapes) {
      if (ids.contains(sh.id) && sh.groupId != null) groups.add(sh.groupId!);
    }
    if (groups.isEmpty) return ids;
    // 展开：把同组元素全部加入。
    final result = {...ids};
    for (final t in page.textItems) {
      if (t.groupId != null && groups.contains(t.groupId)) result.add(t.id);
    }
    for (final i in page.imageItems) {
      if (i.groupId != null && groups.contains(i.groupId)) result.add(i.id);
    }
    for (final sh in page.shapes) {
      if (sh.groupId != null && groups.contains(sh.groupId)) result.add(sh.id);
    }
    return result;
  }

  void _dragItem(String id, Offset screenDelta) {
    final page = widget.page;
    if (page == null) return;
    // 屏幕位移 -> 画布位移（除以缩放、反向旋转）。
    final canvasDelta = _screenDeltaToCanvas(screenDelta);
    // 动画尾迹（借鉴 Excalidraw animatedTrail）：记录最近拖动点。
    _trailPoints.add(canvasDelta);
    if (_trailPoints.length > 8) {
      _trailPoints.removeAt(0);
    }
    // 多选：拖动任一选中元素时整体移动所有选中元素（借鉴 Excalidraw 多选）。
    final moveIds = _expandGroup(
      _multiSelectedIds.isNotEmpty ? {..._multiSelectedIds, id} : <String>{id},
    );
    setState(() {
      const grid = 20.0;
      double snap(double v) => _snapToGrid ? (v / grid).round() * grid : v;
      for (final t in page.textItems) {
        if (moveIds.contains(t.id)) {
          t.x = snap(
            t.x + canvasDelta.dx,
          ).clamp(0, _controller.document.width.toDouble());
          t.y = snap(
            t.y + canvasDelta.dy,
          ).clamp(0, _controller.document.height.toDouble());
        }
      }
      for (final i in page.imageItems) {
        if (moveIds.contains(i.id)) {
          i.x = (i.x + canvasDelta.dx).clamp(
            0,
            _controller.document.width.toDouble(),
          );
          i.y = (i.y + canvasDelta.dy).clamp(
            0,
            _controller.document.height.toDouble(),
          );
        }
      }
      // 形状元素（借鉴 Excalidraw 图形工具）：拖动移动位置。
      for (final s in page.shapes) {
        if (moveIds.contains(s.id)) {
          s.x = (s.x + canvasDelta.dx).clamp(
            0,
            _controller.document.width.toDouble(),
          );
          s.y = (s.y + canvasDelta.dy).clamp(
            0,
            _controller.document.height.toDouble(),
          );
        }
      }
      // 箭头绑定（借鉴 Excalidraw boundElements）：目标元素移动时，
      // 绑定到该元素的箭头同步跟随（引用关联而非坐标快照）。
      for (final targetId in moveIds) {
        for (final s in page.shapes) {
          if (s.boundElementId == targetId) {
            s.x = (s.x + canvasDelta.dx).clamp(
              0,
              _controller.document.width.toDouble(),
            );
            s.y = (s.y + canvasDelta.dy).clamp(
              0,
              _controller.document.height.toDouble(),
            );
          }
        }
      }
      // 对齐吸附（借鉴 Excalidraw 对齐参考线）：拖动结束后吸附到
      // 其他混排对象的左/中/右 或 上/中/下 边（容差 10px）。
      _snapDragItemToAlign(id);
    });
  }

  /// 拖动后对齐吸附：把 [id] 元素吸附到其他元素的边/中心对齐线。
  ///
  /// 容差 [snapTol]（画布坐标）；仅当拖动对象与任一参考线足够近时吸附，
  /// 视觉上形成"对齐参考线"的体验（借鉴 Excalidraw）。
  void _snapDragItemToAlign(String id) {
    final page = widget.page;
    if (page == null) return;
    const snapTol = 10.0;

    // 收集所有混排对象的边界（左/右/上/下/水平中心/垂直中心）。
    final refs =
        <({double l, double r, double t, double b, double cx, double cy})>[];
    for (final t in page.textItems) {
      if (t.id == id) continue;
      final w = t.fontSize * 2.0;
      refs.add((
        l: t.x,
        r: t.x + w,
        t: t.y,
        b: t.y + t.fontSize,
        cx: t.x + w / 2,
        cy: t.y + t.fontSize / 2,
      ));
    }
    for (final i in page.imageItems) {
      if (i.id == id) continue;
      refs.add((
        l: i.x,
        r: i.x + i.width,
        t: i.y,
        b: i.y + i.height,
        cx: i.x + i.width / 2,
        cy: i.y + i.height / 2,
      ));
    }
    for (final s in page.shapes) {
      if (s.id == id) continue;
      refs.add((
        l: s.x,
        r: s.x + s.width,
        t: s.y,
        b: s.y + s.height,
        cx: s.x + s.width / 2,
        cy: s.y + s.height / 2,
      ));
    }
    if (refs.isEmpty) return;

    // 当前拖动元素边界。
    double l = 0, r = 0, top = 0, bottom = 0;
    for (final t in page.textItems) {
      if (t.id == id) {
        l = t.x;
        r = t.x + t.fontSize * 2;
        top = t.y;
        bottom = t.y + t.fontSize;
      }
    }
    for (final i in page.imageItems) {
      if (i.id == id) {
        l = i.x;
        r = i.x + i.width;
        top = i.y;
        bottom = i.y + i.height;
      }
    }
    for (final s in page.shapes) {
      if (s.id == id) {
        l = s.x;
        r = s.x + s.width;
        top = s.y;
        bottom = s.y + s.height;
      }
    }
    final cx = (l + r) / 2;
    final cy = (top + bottom) / 2;

    // 水平对齐（X 轴）：左/中/右。
    var dx = 0.0;
    var bestDx = snapTol;
    void snapX(double target) {
      final d = target - l;
      if (d.abs() < bestDx) {
        bestDx = d.abs();
        dx = d;
      }
    }

    void snapCx(double target) {
      final d = target - cx;
      if (d.abs() < bestDx) {
        bestDx = d.abs();
        dx = d;
      }
    }

    for (final ref in refs) {
      snapX(ref.l);
      snapX(ref.r);
      snapCx(ref.cx);
    }
    // 垂直对齐（Y 轴）：上/中/下。
    var dy = 0.0;
    var bestDy = snapTol;
    void snapY(double target) {
      final d = target - top;
      if (d.abs() < bestDy) {
        bestDy = d.abs();
        dy = d;
      }
    }

    void snapCy(double target) {
      final d = target - cy;
      if (d.abs() < bestDy) {
        bestDy = d.abs();
        dy = d;
      }
    }

    for (final ref in refs) {
      snapY(ref.t);
      snapY(ref.b);
      snapCy(ref.cy);
    }

    if (dx != 0 || dy != 0) {
      // 记录对齐参考线（实时显示，借鉴 Excalidraw 对齐可视化）。
      final guides = <({bool vertical, double pos})>[];
      if (dx != 0) guides.add((vertical: true, pos: l + dx));
      if (dy != 0) guides.add((vertical: false, pos: top + dy));
      _snapGuides = guides;
      for (final t in page.textItems) {
        if (t.id == id) {
          t.x += dx;
          t.y += dy;
        }
      }
      for (final i in page.imageItems) {
        if (i.id == id) {
          i.x += dx;
          i.y += dy;
        }
      }
      for (final s in page.shapes) {
        if (s.id == id) {
          s.x += dx;
          s.y += dy;
        }
      }
    } else {
      _snapGuides = const [];
    }
  }

  /// 等间距分布：把页面全部混排对象（文字/图片/形状）按水平或垂直
  /// 等间距排列（借鉴 Excalidraw 对齐/分布工具）。
  void _distributeItems(bool horizontal) {
    final page = widget.page;
    if (page == null) return;
    final items = <({double pos, double size})>[];
    // 收集所有对象的中心位置与尺寸。
    for (final t in page.textItems) {
      items.add((pos: t.x + t.fontSize, size: t.fontSize * 2));
    }
    for (final i in page.imageItems) {
      items.add((pos: i.x + i.width / 2, size: i.width));
    }
    for (final s in page.shapes) {
      items.add((pos: s.x + s.width / 2, size: s.width));
    }
    if (items.length < 3) {
      _showSnack('至少需要 3 个元素才能分布');
      return;
    }
    // 水平分布：按中心 X 排序，重排到首尾之间等间距。
    if (horizontal) {
      items.sort((a, b) => a.pos.compareTo(b.pos));
      final first = items.first.pos;
      final last = items.last.pos;
      final step = (last - first) / (items.length - 1);
      var idx = 0;
      for (final t in page.textItems) {
        final target = first + step * (idx++);
        t.x = target - t.fontSize;
      }
      for (final i in page.imageItems) {
        final target = first + step * (idx++);
        i.x = target - i.width / 2;
      }
      for (final s in page.shapes) {
        final target = first + step * (idx++);
        s.x = target - s.width / 2;
      }
    } else {
      // 垂直分布：按中心 Y 排序。
      final vItems = <({double pos, double size})>[];
      for (final t in page.textItems) {
        vItems.add((pos: t.y + t.fontSize / 2, size: t.fontSize));
      }
      for (final i in page.imageItems) {
        vItems.add((pos: i.y + i.height / 2, size: i.height));
      }
      for (final s in page.shapes) {
        vItems.add((pos: s.y + s.height / 2, size: s.height));
      }
      vItems.sort((a, b) => a.pos.compareTo(b.pos));
      final first = vItems.first.pos;
      final last = vItems.last.pos;
      final step = (last - first) / (vItems.length - 1);
      var idx = 0;
      for (final t in page.textItems) {
        final target = first + step * (idx++);
        t.y = target - t.fontSize / 2;
      }
      for (final i in page.imageItems) {
        final target = first + step * (idx++);
        i.y = target - i.height / 2;
      }
      for (final s in page.shapes) {
        final target = first + step * (idx++);
        s.y = target - s.height / 2;
      }
    }
    setState(() {});
    _notifyChanged();
    _showSnack(horizontal ? '已水平等间距分布' : '已垂直等间距分布');
  }

  /// 8 向缩放手柄（四角调宽高、四边调单边，借鉴 Excalidraw 选中编辑）。
  List<Widget> _buildResizeHandles(PageShapeItem shape, double w, double h) {
    // 手柄位置（相对元素外接框，画布坐标经 viewScale 换算）。
    const size = 10.0;
    final corners = <Offset>[
      Offset(0, 0), // 左上
      Offset(w, 0), // 右上
      Offset(0, h), // 左下
      Offset(w, h), // 右下
    ];
    final edges = <({Offset pos, bool horizontal})>[
      (pos: Offset(w / 2, 0), horizontal: false), // 上
      (pos: Offset(w / 2, h), horizontal: false), // 下
      (pos: Offset(0, h / 2), horizontal: true), // 左
      (pos: Offset(w, h / 2), horizontal: true), // 右
    ];
    return [
      for (final c in corners)
        _resizeHandle(
          shape: shape,
          pos: c,
          size: size,
          onResize: (dx, dy) {
            // 角手柄：按角位置调整宽高。
            final left = c.dx == 0;
            final top = c.dy == 0;
            setState(() {
              if (left) {
                shape.x += dx;
                shape.width = (shape.width - dx).clamp(20, 1000);
              } else {
                shape.width = (shape.width + dx).clamp(20, 1000);
              }
              if (top) {
                shape.y += dy;
                shape.height = (shape.height - dy).clamp(20, 1000);
              } else {
                shape.height = (shape.height + dy).clamp(20, 1000);
              }
            });
          },
        ),
      for (final e in edges)
        _resizeHandle(
          shape: shape,
          pos: e.pos,
          size: size,
          onResize: (dx, dy) {
            // 边手柄：只调单边（上/下调高，左/右调宽）。
            final horizontal = e.horizontal;
            setState(() {
              if (horizontal) {
                if (e.pos.dx == 0) {
                  shape.x += dx;
                  shape.width = (shape.width - dx).clamp(20, 1000);
                } else {
                  shape.width = (shape.width + dx).clamp(20, 1000);
                }
              } else {
                if (e.pos.dy == 0) {
                  shape.y += dy;
                  shape.height = (shape.height - dy).clamp(20, 1000);
                } else {
                  shape.height = (shape.height + dy).clamp(20, 1000);
                }
              }
            });
          },
        ),
    ];
  }

  /// 单个缩放手柄。
  Widget _resizeHandle({
    required PageShapeItem shape,
    required Offset pos,
    required double size,
    required void Function(double dx, double dy) onResize,
  }) {
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          final delta = _screenDeltaToCanvas(d.delta);
          onResize(delta.dx, delta.dy);
          _notifyChanged();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ),
    );
  }

  /// 图片裁剪 4 角手柄（拖拽调整 _cropRect，画布坐标）。
  List<Widget> _buildCropHandles(PageImageItem item) {
    final rect = _cropRect!;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    return [
      for (final c in corners)
        Positioned(
          left: _controller.canvasToView(c).dx - 5,
          top: _controller.canvasToView(c).dy - 5,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) {
              final delta = _screenDeltaToCanvas(d.delta);
              setState(() {
                // 按角位置调整 _cropRect 的对应边（限制在图片区域内）。
                final img = _cropItem!;
                if (c == rect.topLeft) {
                  _cropRect = Rect.fromLTRB(
                    (rect.left + delta.dx).clamp(img.x, rect.right - 10),
                    (rect.top + delta.dy).clamp(img.y, rect.bottom - 10),
                    rect.right,
                    rect.bottom,
                  );
                } else if (c == rect.topRight) {
                  _cropRect = Rect.fromLTRB(
                    rect.left,
                    (rect.top + delta.dy).clamp(img.y, rect.bottom - 10),
                    (rect.right + delta.dx).clamp(
                      rect.left + 10,
                      img.x + img.width,
                    ),
                    rect.bottom,
                  );
                } else if (c == rect.bottomLeft) {
                  _cropRect = Rect.fromLTRB(
                    (rect.left + delta.dx).clamp(img.x, rect.right - 10),
                    rect.top,
                    rect.right,
                    (rect.bottom + delta.dy).clamp(
                      rect.top + 10,
                      img.y + img.height,
                    ),
                  );
                } else {
                  _cropRect = Rect.fromLTRB(
                    rect.left,
                    rect.top,
                    (rect.right + delta.dx).clamp(
                      rect.left + 10,
                      img.x + img.width,
                    ),
                    (rect.bottom + delta.dy).clamp(
                      rect.top + 10,
                      img.y + img.height,
                    ),
                  );
                }
              });
            },
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF42A5F5),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ),
    ];
  }

  /// 返回 [canvasPoint] 附近（50px 内）吸附命中的混排对象 id。
  ///
  /// 与 [_findSnapTarget] 同逻辑但返回元素 id（供箭头绑定 boundElementId 使用）；
  /// 无命中返回 null。
  String? _findSnapTargetId(Offset canvasPoint) {
    final page = widget.page;
    if (page == null) return null;
    const snapDist = 50.0;
    String? best;
    var bestDist = snapDist;
    void consider(String id, Offset center) {
      final d = (center - canvasPoint).distance;
      if (d < bestDist) {
        bestDist = d;
        best = id;
      }
    }

    for (final t in page.textItems) {
      consider(t.id, t.position + Offset(t.fontSize * 2, t.fontSize / 2));
    }
    for (final i in page.imageItems) {
      consider(i.id, i.position + Offset(i.width / 2, i.height / 2));
    }
    for (final s in page.shapes) {
      consider(s.id, s.position + Offset(s.width / 2, s.height / 2));
    }
    return best;
  }

  Offset _screenDeltaToCanvas(Offset screenDelta) {
    final rot = -_controller.viewRotation;
    final cosA = math.cos(rot);
    final sinA = math.sin(rot);
    final vx = screenDelta.dx * cosA - screenDelta.dy * sinA;
    final vy = screenDelta.dx * sinA + screenDelta.dy * cosA;
    return Offset(vx / _controller.viewScale, vy / _controller.viewScale);
  }

  // ---------------- 工具条 ----------------

  /// 选区操作条：完成选区后显示（复制/粘贴/删除/清除 + 缩放/旋转滑块）。
  Widget _buildSelectionBar() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final hasMixed =
            !_isNotebookMode && _controller.hasMixedDocumentObjectSelection;
        final hasSel = _controller.hasSelection || hasMixed;
        final hasStrokes = _controller.hasSelectedStrokes;
        final hasImage = _controller.hasSelectedDocumentImage;
        final hasShape = _controller.hasSelectedDocumentShape;
        final imageLocked = _controller.selectedDocumentImage?.locked ?? false;
        final shapeLocked = _controller.selectedDocumentShape?.locked ?? false;
        final hasLockedObjects =
            _controller.mixedDocumentSelectionHasLockedObjects;
        final hasEditable = hasMixed
            ? hasStrokes || !hasLockedObjects
            : hasStrokes ||
                  (hasImage && !imageLocked) ||
                  (hasShape && !shapeLocked);
        if (!hasSel && !hasImage && !hasShape) return const SizedBox.shrink();

        return Material(
          elevation: 1,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                _selectionAction(
                  icon: Icons.copy,
                  tooltip: '复制选中内容',
                  onTap: hasStrokes ? _controller.copySelectedStrokes : null,
                ),
                _selectionAction(
                  icon: Icons.content_paste,
                  tooltip: '粘贴',
                  onTap: _controller.pasteClipboard,
                ),
                if (hasMixed)
                  _selectionAction(
                    icon: hasLockedObjects ? Icons.lock : Icons.lock_open,
                    tooltip: hasLockedObjects ? '解锁选中对象' : '锁定选中对象，防止误触编辑',
                    onTap: _controller.toggleSelectedDocumentObjectsLock,
                  )
                else ...[
                  if (hasImage)
                    _selectionAction(
                      icon: imageLocked ? Icons.lock : Icons.lock_open,
                      tooltip: imageLocked ? '解除图片锁定' : '锁定图片，防止误触编辑',
                      onTap: _controller.toggleSelectedDocumentImageLock,
                    ),
                  if (hasShape)
                    _selectionAction(
                      icon: shapeLocked ? Icons.lock : Icons.lock_open,
                      tooltip: shapeLocked ? '解除形状锁定' : '锁定形状，防止误触编辑',
                      onTap: _controller.toggleSelectedDocumentShapeLock,
                    ),
                ],
                _selectionAction(
                  icon: Icons.delete_outline,
                  tooltip: hasMixed
                      ? hasLockedObjects
                            ? '删除未锁定对象；锁定对象会保留'
                            : '删除选中对象'
                      : hasShape && shapeLocked
                      ? '形状已锁定，无法删除'
                      : imageLocked
                      ? '图片已锁定，无法删除'
                      : '删除选中内容',
                  onTap: hasMixed
                      ? _controller.deleteSelectedDocumentObjects
                      : hasShape && !shapeLocked
                      ? _controller.deleteSelectedDocumentShape
                      : hasImage && !imageLocked
                      ? _controller.deleteSelectedDocumentImage
                      : hasStrokes
                      ? _controller.deleteSelectedStrokes
                      : null,
                ),
                _selectionAction(
                  icon: Icons.close,
                  tooltip: '清除选区',
                  onTap: () => setState(() {
                    _viewModel.setSelectionDone(false);
                    _controller.clearDocumentObjectSelection();
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_in, size: 18),
                      Expanded(
                        child: Slider(
                          value: _scaleValue.clamp(0.1, 5.0),
                          min: 0.1,
                          max: 5.0,
                          onChanged: hasEditable
                              ? (v) {
                                  setState(() {
                                    final factor = v / _scaleValue;
                                    _scaleValue = v;
                                    if (hasMixed) {
                                      _controller.scaleSelectedDocumentObjects(
                                        factor,
                                      );
                                    } else if (hasShape) {
                                      _controller.scaleSelectedDocumentShape(
                                        factor,
                                      );
                                    } else if (hasImage) {
                                      _controller.scaleSelectedDocumentImage(
                                        factor,
                                      );
                                    } else {
                                      _controller.scaleSelectedStrokes(factor);
                                    }
                                  });
                                }
                              : null,
                          onChangeEnd: hasMixed
                              ? (_) {
                                  _controller.endDocumentObjectsTransform();
                                  _notifyChanged();
                                }
                              : hasShape
                              ? (_) {
                                  _controller.endDocumentShapeTransform();
                                  _notifyChanged();
                                }
                              : hasImage
                              ? (_) {
                                  _controller.endDocumentImageTransform();
                                  _notifyChanged();
                                }
                              : null,
                        ),
                      ),
                      const Icon(Icons.zoom_out, size: 18),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.rotate_left, size: 18),
                      Expanded(
                        child: Slider(
                          value: _rotateDegrees.clamp(0, 360),
                          min: 0,
                          max: 360,
                          onChanged: hasStrokes
                              ? (v) {
                                  setState(() {
                                    final delta =
                                        (v - _rotateDegrees) * 3.14159265 / 180;
                                    _rotateDegrees = v;
                                    _controller.rotateSelectedStrokes(delta);
                                  });
                                }
                              : null,
                        ),
                      ),
                      const Icon(Icons.rotate_right, size: 18),
                    ],
                  ),
                ),
                Text(
                  hasMixed && _controller.selectedDocumentObjectCount > 1
                      ? '已选中 ${_controller.selectedDocumentObjectCount} 个对象${hasLockedObjects ? '（含锁定对象）' : ''}'
                      : hasShape
                      ? shapeLocked
                            ? '形状已锁定：解除锁定后可编辑'
                            : '已选中形状：可拖动、缩放、锁定或删除'
                      : hasImage
                      ? imageLocked
                            ? '图片已锁定：解除锁定后可编辑'
                            : '已选中图片：可拖动、缩放、锁定或删除'
                      : hasStrokes
                      ? '已选中 ${_controller.selection.selectedStrokeIndices.length} 笔'
                      : '选区未命中内容（可拖动画布重新框选）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _selectionAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildContextBar() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isEraser = _controller.tool == BrushType.eraser;
        return EditorContextBar(
          state: EditorToolbarState(
            isEraser: isEraser,
            isHighlighter: _controller.tool == BrushType.marker,
            isLaser: _controller.tool == BrushType.laser,
            temporaryMarkerEnabled: _controller.temporaryMarkerEnabled,
            activeSize: isEraser
                ? _controller.eraserSize
                : _controller.brushSize,
            showNoteTools: _isNotebookMode,
            eyedropperActive: _eyedropperActive,
            textToolActive: _textToolActive,
            selectionTool: _controller.selectionTool,
            linkMode: _linkMode,
            color: _controller.color,
            paperType: _controller.document.paperType,
            selectedItemId: _selectedItemId,
            selectedTextItem: _selectedTextItem,
            activeShape: _activeShapeTool,
            selectedShape: _selectedShapeItem,
            marqueeActive: _marqueeActive,
            pixelEraser: _controller.eraserMode == EraserMode.pixel,
            gridVisible: _gridVisible,
            snapToGrid: _snapToGrid,
          ),
          actions: EditorToolbarActions(
            onToggleGrid: () => setState(() => _gridVisible = !_gridVisible),
            onToggleSnap: () => setState(() => _snapToGrid = !_snapToGrid),
            onFitToScreen: _fitToScreen,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onZoomReset: _zoomReset,
            onToggleDash: () {
              final s = _selectedShapeItem;
              if (s == null) return;
              setState(() => s.dash = !s.dash);
              _notifyChanged();
            },
            onToggleMarquee: _toggleMarqueeTool,
            onReorder: _reorderSelected,
            onSelectShape: _selectShapeTool,
            onDistribute: _distributeItems,
            onShapeStrokeWidth: (v) {
              final s = _selectedShapeItem;
              if (s == null) return;
              setState(() => s.strokeWidth = v.clamp(1, 20));
              _notifyChanged();
            },
            onShapeOpacity: (v) {
              final s = _selectedShapeItem;
              if (s == null) return;
              // 透明度滑块：>0 时启用填充色，=0 时清除填充。
              setState(() {
                if (v > 0.5) {
                  s.fillColor = s.fillColor ?? 0x66A5D6A7;
                } else {
                  s.fillColor = null;
                }
              });
              _notifyChanged();
            },
            onShapeFillColor: () {
              final s = _selectedShapeItem;
              if (s == null) return;
              setState(() {
                s.fillColor = s.fillColor == null ? 0x66A5D6A7 : null;
              });
              _notifyChanged();
            },
            selectBrush: () => _selectWritingTool(BrushType.pen),
            selectEraser: () => _selectWritingTool(BrushType.eraser),
            setPixelEraserMode: (pixel) {
              final mode = pixel ? EraserMode.pixel : EraserMode.stroke;
              setState(() => _controller.eraserMode = mode);
              unawaited(_eraserModeStore.save(mode));
            },
            setTemporaryMarkerEnabled: (enabled) =>
                setState(() => _controller.temporaryMarkerEnabled = enabled),
            selectEyedropper: () => setState(() {
              _viewModel.setEyedropperActive(true);
              _viewModel.setTextToolActive(false);
            }),
            selectRect: () => setState(() {
              _viewModel.setEyedropperActive(false);
              _viewModel.setTextToolActive(false);
              _viewModel.setSelectionDone(false);
              _controller.selectionTool = SelectionTool.rect;
            }),
            selectLasso: () => setState(() {
              _viewModel.setEyedropperActive(false);
              _viewModel.setTextToolActive(false);
              _viewModel.setSelectionDone(false);
              _controller.selectionTool = SelectionTool.lasso;
            }),
            selectText: () => setState(() {
              _viewModel.setTextToolActive(true);
              _viewModel.setEyedropperActive(false);
              _controller.selectionTool = SelectionTool.none;
            }),
            recolorAllText: _macroRecolorAllText,
            toggleLink: _toggleLinkMode,
            showPagination: _showPaginationPreview,
            addStickyNote: _addStickyNote,
            cyclePaper: () => setState(() {
              final next =
                  PaperType.values[(_controller.document.paperType.index + 1) %
                      PaperType.values.length];
              _controller.document.paperType = next;
              _controller.tickFrame();
              _notifyChanged();
            }),
            insertImage: _insertImage,
            showColorPicker: _showColorPicker,
            onSizeChanged: (v) => _updateCurrentBrushPreset(size: v),
            onSelectedFontSize: _setSelectedTextFontSize,
            changeTextColor: _changeSelectedTextColor,
            toggleBold: () => setState(() {
              _selectedTextItem!.bold = !_selectedTextItem!.bold;
              _notifyChanged();
            }),
            toggleItalic: () => setState(() {
              _selectedTextItem!.italic = !_selectedTextItem!.italic;
              _notifyChanged();
            }),
            toggleUnderline: () => setState(() {
              _selectedTextItem!.underline = !_selectedTextItem!.underline;
              _notifyChanged();
            }),
            toggleStrikethrough: () => setState(() {
              _selectedTextItem!.strikethrough =
                  !_selectedTextItem!.strikethrough;
              _notifyChanged();
            }),
            cycleAlign: () => setState(() {
              final next =
                  TextAlignType.values[(_selectedTextItem!.align.index + 1) %
                      TextAlignType.values.length];
              _selectedTextItem!.align = next;
              _notifyChanged();
            }),
            editText: _editTextItem,
            deleteSelected: _deleteSelectedItem,
            onBrushSelected: (id) {
              if (id == 'pen') _selectWritingTool(BrushType.pen);
            },
          ),
        );
      },
    );
  }
}
