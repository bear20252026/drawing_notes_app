import 'dart:async';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/features/drawing/application/brush_preset_store.dart';
import 'package:drawing_notes_app/features/drawing/application/command_registry.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_input_arbiter.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/features/drawing/application/paged_export_snapshot.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode_store.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_exporter.dart';
import 'package:drawing_notes_app/features/drawing/domain/fractional_index.dart';
import 'package:drawing_notes_app/features/drawing/application/gesture_math.dart';
import 'package:drawing_notes_app/core/rendering/pencil_shader.dart';
import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/shape_creation_geometry.dart';
import 'package:drawing_notes_app/features/drawing/presentation/shape_library.dart';
import 'package:drawing_notes_app/core/utils/safe_url.dart';
import 'package:drawing_notes_app/features/drawing/application/stylus_input.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/view_transform_cache.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_chart_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_connector.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/presentation/canvas_painter.dart';
import 'package:drawing_notes_app/features/drawing/presentation/encrypted_file_image.dart';
import 'package:drawing_notes_app/shared/widgets/color_picker_dialog.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_components.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_canvas_interaction_state.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_context_bar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_left_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_overlay_group_resolver.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_overlay_item_plan.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_selection_transform_state.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_shape_resize_geometry.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_tool_mode_state.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_statusbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar_action_factory.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_viewmodel.dart';
import 'package:drawing_notes_app/features/drawing/presentation/layer_panel.dart';
import 'package:drawing_notes_app/features/drawing/presentation/properties_panel.dart';
import 'package:drawing_notes_app/features/drawing/presentation/resize_handles.dart';
import 'package:drawing_notes_app/features/drawing/presentation/selection_bar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/toolbar_state_mapper.dart';

part 'editor_page_dialogs.dart';
part 'editor_page_overlays.dart';
part 'editor_page_text_overlays.dart';
part 'editor_page_canvas_surface.dart';
part 'editor_page_drag_ops.dart';
part 'editor_page_input.dart';
part 'editor_page_editing.dart';
part 'editor_page_actions.dart';
part 'editor_page_tools.dart';
part 'editor_page_commands.dart';
part 'editor_page_shortcuts.dart';
part 'editor_page_persistence.dart';
part 'editor_page_toolbar_actions.dart';

/// 编辑器页面。
///
/// 两种使用场景：
/// 1. 独立画作模式：仅传 [document]（Phase 1-4，画布功能）；
/// 2. 笔记本页面模式：传 [session]/[storage]/[onChanged]，
///    在画布之上叠加文字块与图片块（Phase 5 混排）。
///
/// 职责：
/// - 手势采集：笔画 / 选区 / 吸管 / 文字与图片放置
/// - 工具面板：撤销、重做、清空、画笔/橡皮擦/吸管/选区/文字/图片
/// - 保存回调：任何变更后调用 [onChanged]（由上级页面负责落盘）
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({
    super.key,
    DrawingDocument? document,
    this.session,
    this.storage,
    this.docStorage,
    this.onChanged,
    this.openPresentation,
  }) : _initialDocument = document;

  /// 独立画作模式：初始文档（为空时创建默认空白文档）。
  final DrawingDocument? _initialDocument;

  /// 笔记本页面模式：由 notes 在组合边界提供的当前页面编辑会话。
  final EditorPageSession? session;

  /// 笔记侧存储契约（插入图片时复制图片副本用）。
  final INotebookAccessor? storage;

  /// 独立画作存储（Phase 6 自动保存用）。
  final StorageService? docStorage;

  /// 打开放映页的回调（跨 feature 页面跳转契约，S4b 接口化）：
  /// 由笔记侧注入实现（跳转 PresentationPage），drawing 不直接依赖
  /// notes 的 presentation UI；null 时演示功能提示不可用。
  final Future<void> Function(BuildContext context)? openPresentation;

  /// 内容变更回调（自动保存由上级页面实现）。
  final VoidCallback? onChanged;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  late final DrawingController _controller;

  /// 画布导出域（参考 Saber editor_exporter 模块化）：PNG/PDF/SVG/RTF/
  /// TXT/PPTX/JSON 与剪贴板复制集中在独立模块，本页只负责调用。
  late final EditorExporter _exporter;

  /// 编辑器 ViewModel 胶水层（R4）：工具状态 + 防抖保存调度，
  /// editor_page 只通过它读写工具状态与触发保存（见 editor_viewmodel.dart）。
  late final EditorViewModel _viewModel;

  /// 混排对象的框选、多选、裁剪、对齐与拖动反馈暂态集中在独立协作者中。
  final EditorCanvasInteractionState _canvasInteraction =
      EditorCanvasInteractionState();

  bool _viewportInitialized = false;

  /// 吸管模式：激活时点击画布取色，取色后自动退出。
  bool get _eyedropperActive => _viewModel.eyedropperActive;

  /// 文字工具模式：激活时点击画布弹出文字输入框。
  bool get _textToolActive => _viewModel.textToolActive;

  /// 选区是否已完成（完成后再拖动 = 移动选中内容，而非新建选区）。
  bool get _selectionDone => _viewModel.selectionDone;

  /// 上次拖动位置（画布坐标），用于计算移动增量。
  Offset? _lastDragCanvas;

  /// 选区缩放/旋转滑块的短生命周期显示值与增量换算。
  final EditorSelectionTransformState _selectionTransform =
      EditorSelectionTransformState();
  double get _scaleValue => _selectionTransform.scaleValue;
  double get _rotateDegrees => _selectionTransform.rotationDegrees;

  /// 当前选中的混排对象 id（null = 无选中），用于显示编辑/删除按钮。
  String? get _selectedItemId => _canvasInteraction.selectedItemId;
  set _selectedItemId(String? value) =>
      _canvasInteraction.selectedItemId = value;

  /// 当前选中的文字块（null = 未选中文字块），供工具栏字号滑块使用。
  PageTextItem? get _selectedTextItem {
    final page = widget.session;
    final id = _selectedItemId;
    if (page == null || id == null) return null;
    return page.textItems.where((t) => t.id == id).firstOrNull;
  }

  /// 全屏模式：隐藏应用框架，只保留画布。
  bool _fullscreen = false;

  /// 阅读反相仅作用于当前编辑器显示层；不修改页面颜色、资源字节、导出或保存。
  bool _readingInverted = false;

  // 深色阅读反相矩阵（问题9修复）。
  //
  // 原 Rec.709 保亮度矩阵系数误算：白色 (255,255,255) 经其作用后变为
  // (0,255,0) 纯绿色，即用户实测的"一片绿幕"。标准 RGB 反相矩阵保证
  // 白色背景 → 黑色、黑色墨迹 → 白色，实现真正的深色阅读（仅显示层
  // 反相，不修改文档数据）。
  static const ColorFilter _readingInvertFilter = ColorFilter.matrix(<double>[
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
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

  /// 手型、框选和形状工具的互斥展示状态。
  final EditorToolModeState _toolMode = EditorToolModeState();
  bool get _handToolActive => _toolMode.handActive;
  bool get _marqueeActive => _toolMode.marqueeActive;
  ShapeType? get _activeShapeTool => _toolMode.activeShape;

  /// 画布视口尺寸（小地图导航用，由布局回调更新）。
  /// 声明在主类（extension 不能声明实例字段，拆分专用）。
  Size? _viewportSize;

  /// 对齐参考线（拖动元素时实时显示，借鉴 Excalidraw 对齐可视化）。
  /// 元素为 (vertical: 是否垂直线, pos: 画布坐标位置)。
  List<({bool vertical, double pos})> get _snapGuides =>
      _canvasInteraction.snapGuides;

  /// 文字缩放手柄的拖拽基准（落地 Excalidraw resizeElements）：
  /// 记录手势开始时的宽度/字号，供缩放联动字号计算；null = 无进行中手势。
  ({double width, double fontSize, double x})? get _textResizeAnchor =>
      _canvasInteraction.textResizeAnchor;
  set _textResizeAnchor(({double width, double fontSize, double x})? value) =>
      _canvasInteraction.textResizeAnchor = value;

  /// 框选矩形（画布坐标；null = 未在框选中）。
  Rect? get _marqueeRect => _canvasInteraction.marqueeRect;

  /// 框选起点（画布坐标）。
  Offset? get _marqueeStart => _canvasInteraction.marqueeStart;

  /// 多选元素 id 集合（框选结果，可整体拖动/删除）。
  Set<String> get _multiSelectedIds => _canvasInteraction.multiSelectedIds;

  /// 网格显示开关（借鉴 Excalidraw 画布导航）。
  bool _gridVisible = false;

  /// 网格吸附开关（拖动元素吸附到 20px 网格，借鉴 Excalidraw）。
  bool _snapToGrid = false;

  /// 正在播放删除淡出动画的元素 id 集合（借鉴 Excalidraw 删除动画）。
  Set<String> get _deletingIds => _canvasInteraction.deletingIds;

  /// 上次取色时间（P-2 修复 2026-08-15）：pickColorAt 每次完整重绘文档
  /// 到图片（极重操作），取色做 200ms 冷却节流防连续触发卡顿。
  DateTime? _lastPickColorAt;

  /// 拖动轨迹点（对齐 Excalidraw animatedTrail：拖动元素显示轨迹动画）。
  List<Offset> get _trailPoints => _canvasInteraction.trailPoints;

  /// 图片裁剪（对齐 Excalidraw 图片裁剪）：裁剪目标与裁剪矩形（画布坐标）。
  PageImageItem? get _cropItem => _canvasInteraction.cropItem;
  Rect? get _cropRect => _canvasInteraction.cropRect;
  set _cropRect(Rect? value) => _canvasInteraction.cropRect = value;

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
    final page = widget.session;
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
        _canvasInteraction.clearCrop();
      });
      _notifyChanged();
      _showSnack('已裁剪图片');
    } catch (e) {
      _showSnack('裁剪失败：$e');
    }
  }

  /// 当前工作区的形状集合：笔记页使用分页混排集合，独立绘图使用文档集合。
  List<PageShapeItem> get _shapeItems =>
      widget.session?.shapes ?? _controller.document.shapes;

  /// 当前选中的形状元素。
  PageShapeItem? get _selectedShapeItem {
    final id = _selectedItemId;
    if (id == null) return null;
    return _shapeItems.where((shape) => shape.id == id).firstOrNull;
  }

  /// 形状拖拽创建的起点和当前点（画布坐标）。
  Offset? _shapeDraftStart;
  Offset? _shapeDraftCurrent;

  /// 形状填充模式开关（问题4）：开启后新建形状默认带填充色。
  bool _fillShapeEnabled = false;

  /// 形状填充色（ARGB，默认半透明绿，与样式面板一致）。
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
      // 线性元素预览也保存真实端点（审查发现 P1：预览与落定方向
      // 不一致——落定走 ShapeCreationGeometry.fromDrag 的真实端点，
      // 而预览此前仅靠 flipX/flipY 对角线，用户会看到方向跳动）。
      lineStart: start - Offset(left, top),
      lineEnd: current - Offset(left, top),
      // 填充模式开启时预览也带填充色，所见即所得（问题4）。
      fillColor: _fillShapeEnabled ? _shapeFillColor : null,
    );
  }

  /// 选择形状工具：激活后点击画布放置对应形状（借鉴 Excalidraw 图形工具）。

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
    // _controller 生命周期由 drawingControllerProvider(ref.onDispose) 管理。
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
  String get _viewCacheKey => widget.session != null
      ? 'page:${widget.session!.id}'
      : 'doc:${_controller.document.id}';

  // ---------------- 保存 ----------------

  /// 自动保存执行中标记与补写标记：任意一次保存期间又发生更改时，
  /// 当前保存结束后立即再保存最新快照，绝不因为“正在保存”而丢弃修改。
  bool _autosaving = false;
  bool _autosaveQueued = false;
  bool _closingEditor = false;
  bool _allowPopAfterSave = false;
  Completer<void>? _autosaveCompletion;

  /// 状态刷新薄包装（供 overlays extension 使用）：
  /// extension 不是 State 子类，不能直接调用受保护的 [setState]，
  /// 通过本实例方法转发（行为零变化，拆分专用）。
  String? get _linkSourceId => _viewModel.linkSourceId;

  /// 鼠标悬停/移动时的画布坐标（状态栏显示，借鉴 Joplin StatusBar）。
  final ValueNotifier<Offset?> _hoverPos = ValueNotifier<Offset?>(null);

  bool get _isNotebookMode => widget.session != null;

  @override
  void initState() {
    super.initState();
    // 笔记本页面模式使用页面自带文档；否则独立画布。
    final doc =
        widget.session?.document ??
        widget._initialDocument ??
        DrawingDocument(id: StorageService.newId(), title: '未命名画布');
    _controller = ref.read(drawingControllerProvider(doc));
    _exporter = EditorExporter(
      controller: _controller,
      pageProvider: () {
        final page = widget.session;
        if (page == null) return null;
        return PagedExportSnapshot(
          title: page.title,
          textItems: page.textItems,
          imageItems: page.imageItems.map((item) => item.toJson()),
          shapes: page.shapes.map((shape) => shape.toJson()),
        );
      },
      showSnack: _showSnack,
    );
    unawaited(_loadBrushPresets());
    unawaited(_loadEraserMode());
    // 异步加载铅笔颗粒着色器；失败时渲染层自动回退到普通铅笔绘制。
    unawaited(PencilShader.init());
    // 修改文档标题显示为页面标题。
    if (widget.session != null && doc.title == '未命名画布') {
      doc.title = widget.session!.title;
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
  void _applyState(VoidCallback fn) => setState(fn);

  /// 剪贴板元素（复制/粘贴的元素，借鉴 Excalidraw 元素复制）。
  /// 结构：kind + 序列化 JSON，粘贴时反序列化并偏移位置。
  List<Map<String, dynamic>> _copiedElements = [];

  /// 复制的样式（颜色/字号/粗斜体/线宽，供样式刷粘贴）。
  Map<String, dynamic>? _copiedStyle;

  /// 会话内形状库（个人收藏）。
  late final ShapeLibrary _shapeLibrary = ShapeLibrary();

  /// 手型工具最近一次拖动位置（供平移视口使用）。
  Offset? _handDragLast;

  void _notifyChanged() {
    // 页面标题跟随文档标题。
    final page = widget.session;
    if (page != null) {
      page.title = _controller.document.title;
      page.updatedAt = DateTime.now();
    }
    widget.onChanged?.call();
    _scheduleAutosave();
  }

  /// 安排一次防抖自动保存（R4：委托 ViewModel 调度，行为不变）。
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

  // ---------------- 文字 / 图片混排（Phase 5） ----------------

  /// 文字工具：点击画布后在该位置直接就地输入文字（借鉴 OneNote/Word，
  /// 不再弹窗输入）。文字块先创建为空文本并进入编辑状态，回车/失焦提交。

  /// 处理键盘动作。
  ///
  /// 借鉴 Excalidraw ActionManager：快捷键只负责匹配和分发，真正的
  /// 可用性与副作用始终收敛在 [_commands]。这样当同一动作在菜单或
  /// 命令面板中呈现时，不会出现“快捷键能用但按钮不可用”的分叉。
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
                  tooltip: AppLocalizations.of(context)?.editorUndo ?? '撤销',
                  icon: const Icon(Icons.undo),
                  onPressed: _commands.find('undo')?.available ?? false
                      ? () => _commands.run('undo')
                      : null,
                ),
              ),
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => IconButton(
                  tooltip: AppLocalizations.of(context)?.editorRedo ?? '重做',
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
                tooltip:
                    AppLocalizations.of(context)?.editorShortcutsHelp ??
                    '快捷键帮助',
                icon: const Icon(Icons.help_outline),
                onPressed: _showShortcutHelp,
              ),
              // 右上角汉堡菜单（对齐 Excalidraw main-menu）
              PopupMenuButton<_MainMenuItem>(
                tooltip: AppLocalizations.of(context)?.editorMenu ?? '主菜单',
                icon: const Icon(Icons.menu),
                onSelected: _onMainMenuSelected,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _MainMenuItem.clearCanvas,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_sweep_outlined),
                      title: Text(
                        AppLocalizations.of(context)?.editorClearCanvas ??
                            '清空画布',
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _MainMenuItem.copyPng,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.content_copy),
                      title: Text(
                        AppLocalizations.of(context)?.editorCopyPng ??
                            '复制 PNG 到剪贴板',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.exportPng,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.image_outlined),
                      title: Text(
                        AppLocalizations.of(context)?.editorExportPng ??
                            '导出 PNG',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.exportSvg,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.ios_share),
                      title: Text(
                        AppLocalizations.of(context)?.editorExportSvg ??
                            '导出 SVG',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.exportPdf,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                        AppLocalizations.of(context)?.editorExportPdf ??
                            '导出 PDF',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.exportJson,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.data_object),
                      title: Text(
                        AppLocalizations.of(context)?.editorExportJson ??
                            '导出 JSON',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.exportPptx,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.slideshow_outlined),
                      title: Text(
                        AppLocalizations.of(context)?.editorExportPptx ??
                            '导出 PPTX',
                      ),
                    ),
                  ),
                  if (_isNotebookMode)
                    PopupMenuItem(
                      value: _MainMenuItem.exportWord,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.article_outlined),
                        title: Text(
                          AppLocalizations.of(context)?.editorExportWord ??
                              '导出 Word 兼容文档',
                        ),
                      ),
                    ),
                  PopupMenuItem(
                    value: _MainMenuItem.exportText,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined),
                      title: Text('导出文本'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _MainMenuItem.commandPalette,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.keyboard_command_key),
                      title: Text('命令面板'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.chart,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.bar_chart),
                      title: Text('图表（粘贴数据）'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.presentation,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.slideshow),
                      title: Text('幻灯片演示'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.stats,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.query_stats),
                      title: Text('统计'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MainMenuItem.library,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.library_books_outlined),
                      title: Text('形状库（图书馆）'),
                    ),
                  ),

                  PopupMenuItem(
                    value: _MainMenuItem.shortcuts,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.keyboard),
                      title: Text('快捷键帮助'),
                    ),
                  ),
                  // 切换无限画布（问题8）：仅独立画布可用。
                  if (!_isNotebookMode)
                    PopupMenuItem(
                      value: _MainMenuItem.toggleInfinite,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _controller.document.infinite
                              ? Icons.all_out
                              : Icons.crop_free,
                        ),
                        title: Text(
                          _controller.document.infinite ? '切换为固定纸张' : '切换为无限画布',
                        ),
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
                        _toolMode.clearPointerModes();
                        _controller.selectionTool = SelectionTool.none;
                        _viewModel.setEyedropperActive(true);
                        _viewModel.setTextToolActive(false);
                      }),
                      onRectSelect: () => setState(() {
                        _toolMode.clearPointerModes();
                        _viewModel.setEyedropperActive(false);
                        _viewModel.setTextToolActive(false);
                        _viewModel.setSelectionDone(false);
                        _controller.selectionTool = SelectionTool.rect;
                      }),
                      onMarquee: _toggleMarqueeTool,
                      onText: () => setState(() {
                        _toolMode.clearPointerModes();
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
                          SelectionBar(
                            controller: _controller,
                            isNotebookMode: _isNotebookMode,
                            scaleValue: _scaleValue,
                            rotateDegrees: _rotateDegrees,
                            onScaleChanged: (v) {
                              _applyState(() {
                                final factor = _selectionTransform.updateScale(
                                  v,
                                );
                                final c = _controller;
                                if (_isNotebookMode &&
                                    c.hasMixedDocumentObjectSelection) {
                                  c.scaleSelectedDocumentObjects(factor);
                                } else if (c.hasSelectedDocumentShape) {
                                  c.scaleSelectedDocumentShape(factor);
                                } else if (c.hasSelectedDocumentImage) {
                                  c.scaleSelectedDocumentImage(factor);
                                } else {
                                  c.scaleSelectedStrokes(factor);
                                }
                              });
                            },
                            onRotateChanged: (v) {
                              _applyState(() {
                                final delta = _selectionTransform
                                    .updateRotationDegrees(v);
                                _controller.rotateSelectedStrokes(delta);
                              });
                            },
                            onClearSelection: () => _applyState(() {
                              _viewModel.setSelectionDone(false);
                              _controller.clearDocumentObjectSelection();
                            }),
                            onTransformEnd: () {
                              final c = _controller;
                              if (_isNotebookMode &&
                                  c.hasMixedDocumentObjectSelection) {
                                c.endDocumentObjectsTransform();
                              } else if (c.hasSelectedDocumentShape) {
                                c.endDocumentShapeTransform();
                              } else if (c.hasSelectedDocumentImage) {
                                c.endDocumentImageTransform();
                              }
                              _notifyChanged();
                            },
                          ),
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
                          setState(() => _canvasInteraction.beginCrop(img));
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
}
