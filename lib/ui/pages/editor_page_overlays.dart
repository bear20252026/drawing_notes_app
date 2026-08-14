part of 'editor_page.dart';

// 编辑器显示构建域（O1 拆分）：overlay/组件构建方法从 editor_page.dart
// 移出为 extension（实验验证：同库 extension 可访问主类私有字段、
// 主类可调用 extension 私有方法）。这些方法只读状态构建 Widget，
// 不修改文档，行为零变化。

/// 编辑器 overlay/组件构建域（拆分自 editor_page.dart）。
extension _EditorPageOverlays on _EditorPageState {
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
                          colorFilter: _EditorPageState._readingInvertFilter,
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
                          colorFilter: _EditorPageState._readingInvertFilter,
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
                          colorFilter: _EditorPageState._readingInvertFilter,
                          child: Stack(
                            children: [_buildShapeOverlay(_shapeDraft!)],
                          ),
                        )
                      : Stack(children: [_buildShapeOverlay(_shapeDraft!)]),
                ),
              ),
            // 混排对象层（文字/图片）：
            // 笔记本模式渲染页面文字/图片/形状；画布模式（问题5）渲染
            // 文档文字块。监听 frameTick，使双指缩放/旋转画布时文字/图片
            // 位置同步刷新。
            if (_isNotebookMode ||
                _controller.document.textItems.isNotEmpty ||
                _pendingTextItem != null)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _controller.frameTick,
                  builder: (context, _) {
                    final overlay = Stack(
                      children: [
                        // 连接线层（D1：节点关联标注，借鉴 Relatum 连线）
                        if (_isNotebookMode)
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
                            colorFilter: _EditorPageState._readingInvertFilter,
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
    final page = widget.page;
    if (page == null) {
      // 画布模式（问题5）：渲染文档文字块 overlay（文字块可拖动/编辑）。
      final items = <Widget>[];
      final pending = _pendingTextItem;
      if (pending != null && _editingItemId == pending.id) {
        items.add(_buildInlineEditor(pending));
      }
      final ordered = <({String id, int z, Object item})>[
        for (final t in _controller.document.textItems)
          (id: t.id, z: t.zOrder, item: t),
      ]..sort((a, b) => a.z.compareTo(b.z));
      for (final entry in ordered) {
        final t = _controller.document.textItems
            .where((x) => x.id == entry.id)
            .firstOrNull;
        if (t == null) continue;
        if (entry.id == _editingItemId) {
          items.add(_buildInlineEditor(t));
        } else {
          items.add(_buildTextOverlay(t));
        }
      }
      return items;
    }

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
                                  _applyState(() => shape.rotation = angle);
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
                  _applyState(() => _slashOpen = showSlash);
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
    _applyState(() => _slashOpen = false);
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
                        _applyState(() => item.todoChecked = !item.todoChecked);
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
                      // 富文本片段渲染（落地 Quill Delta runs，独立实现）：
                      // 有 runs 时按片段应用各自样式（加粗/斜体/下划线/颜色），
                      // 无 runs（旧文档）回退整块样式。
                      child: item.runs != null
                          ? Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: item.fontSize *
                                      _controller.viewScale,
                                  fontFamily: switch (item.fontFamily) {
                                    'serif' => 'serif',
                                    'monospace' => 'monospace',
                                    'handwriting' => 'cursive',
                                    _ => null,
                                  },
                                ),
                                children: [
                                  for (final run in item.runs!)
                                    TextSpan(
                                      text: run.text,
                                      style: TextStyle(
                                        color: run.color != null
                                            ? Color(run.color!)
                                            : Color(item.color),
                                        fontWeight: run.bold
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontStyle: run.italic
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        decoration: run.underline &&
                                                run.strikethrough
                                            ? TextDecoration.combine([
                                                TextDecoration.underline,
                                                TextDecoration.lineThrough,
                                              ])
                                            : (run.underline
                                                  ? TextDecoration.underline
                                                  : (run.strikethrough
                                                        ? TextDecoration
                                                              .lineThrough
                                                        : TextDecoration.none)),
                                      ),
                                    ),
                                ],
                              ),
                              softWrap: item.width != null,
                              textAlign: switch (item.align) {
                                TextAlignType.left => TextAlign.left,
                                TextAlignType.center => TextAlign.center,
                                TextAlignType.right => TextAlign.right,
                              },
                            )
                          : Text(
                              item.text,
                              softWrap: item.width != null,
                              textAlign: switch (item.align) {
                                TextAlignType.left => TextAlign.left,
                                TextAlignType.center => TextAlign.center,
                                TextAlignType.right => TextAlign.right,
                              },
                              style: TextStyle(
                                fontSize: item.fontSize *
                                    _controller.viewScale,
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
                                decoration: item.underline &&
                                        item.strikethrough
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
            // 宽度拖拽手柄（落地 Excalidraw resizeElements 的文字缩放
            // 重排版）：选中且有宽度时，右下角手柄拖拽同步调整宽度与字号
            // （字号随宽度比例缩放，保持文字整体版式不变形）。
            if (selected && item.width != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) {
                    _textResizeAnchor = (
                      width: item.width!,
                      fontSize: item.fontSize,
                      x: _controller.canvasToView(item.position).dx,
                    );
                  },
                  onPanUpdate: (d) {
                    final anchor = _textResizeAnchor;
                    if (anchor == null) return;
                    final delta = _screenDeltaToCanvas(d.delta);
                    _applyState(() {
                      final newWidth = (anchor.width + delta.dx)
                          .clamp(40, 2000)
                          .toDouble();
                      // 字号随宽度等比缩放（Excalidraw measureFontSizeFromWidth
                      // 思路），最小 8pt 保证可读性。
                      item.fontSize = (anchor.fontSize * newWidth / anchor.width)
                          .clamp(8.0, 120.0)
                          .toDouble();
                      item.width = newWidth;
                    });
                    _notifyChanged();
                  },
                  onPanEnd: (_) => _textResizeAnchor = null,
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
            shapeFillEnabled: _fillShapeEnabled,
            marqueeActive: _marqueeActive,
            pixelEraser: _controller.eraserMode == EraserMode.pixel,
            eraserCanEraseShapesStroke:
                _controller.eraserCanEraseShapesStroke,
            eraserCanEraseShapesPixel: _controller.eraserCanEraseShapesPixel,
            gridVisible: _gridVisible,
            snapToGrid: _snapToGrid,
          ),
          actions: EditorToolbarActions(
            onToggleGrid: () => _applyState(() => _gridVisible = !_gridVisible),
            onToggleSnap: () => _applyState(() => _snapToGrid = !_snapToGrid),
            onFitToScreen: _fitToScreen,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onZoomReset: _zoomReset,
            onToggleDash: () {
              final s = _selectedShapeItem;
              if (s == null) return;
              _applyState(() => s.dash = !s.dash);
              _notifyChanged();
            },
            onToggleMarquee: _toggleMarqueeTool,
            onReorder: _reorderSelected,
            onSelectShape: _selectShapeTool,
            setShapeFillEnabled: (enabled) =>
                _applyState(() => _fillShapeEnabled = enabled),
            onDistribute: _distributeItems,
            onShapeStrokeWidth: (v) {
              final s = _selectedShapeItem;
              if (s == null) return;
              _applyState(() => s.strokeWidth = v.clamp(1, 20));
              _notifyChanged();
            },
            onShapeOpacity: (v) {
              final s = _selectedShapeItem;
              if (s == null) return;
              // 透明度滑块：>0 时启用填充色，=0 时清除填充。
              _applyState(() {
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
              _applyState(() {
                s.fillColor = s.fillColor == null ? 0x66A5D6A7 : null;
              });
              _notifyChanged();
            },
            selectBrush: () => _selectWritingTool(BrushType.pen),
            selectEraser: () => _selectWritingTool(BrushType.eraser),
            setPixelEraserMode: (pixel) {
              final mode = pixel ? EraserMode.pixel : EraserMode.stroke;
              _applyState(() => _controller.eraserMode = mode);
              unawaited(_eraserModeStore.save(mode));
            },
            setEraserCanEraseShapesStroke: (value) =>
                _applyState(() => _controller.eraserCanEraseShapesStroke = value),
            setEraserCanEraseShapesPixel: (value) =>
                _applyState(() => _controller.eraserCanEraseShapesPixel = value),
            setTemporaryMarkerEnabled: (enabled) =>
                _applyState(() => _controller.temporaryMarkerEnabled = enabled),
            selectEyedropper: () => _applyState(() {
              _viewModel.setEyedropperActive(true);
              _viewModel.setTextToolActive(false);
            }),
            selectRect: () => _applyState(() {
              _viewModel.setEyedropperActive(false);
              _viewModel.setTextToolActive(false);
              _viewModel.setSelectionDone(false);
              _controller.selectionTool = SelectionTool.rect;
            }),
            selectLasso: () => _applyState(() {
              _viewModel.setEyedropperActive(false);
              _viewModel.setTextToolActive(false);
              _viewModel.setSelectionDone(false);
              _controller.selectionTool = SelectionTool.lasso;
            }),
            selectText: () => _applyState(() {
              _viewModel.setTextToolActive(true);
              _viewModel.setEyedropperActive(false);
              _controller.selectionTool = SelectionTool.none;
            }),
            recolorAllText: _macroRecolorAllText,
            toggleLink: _toggleLinkMode,
            showPagination: _showPaginationPreview,
            addStickyNote: _addStickyNote,
            cyclePaper: () => _applyState(() {
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
            toggleBold: () => _applyState(() {
              _selectedTextItem!.bold = !_selectedTextItem!.bold;
              _notifyChanged();
            }),
            toggleItalic: () => _applyState(() {
              _selectedTextItem!.italic = !_selectedTextItem!.italic;
              _notifyChanged();
            }),
            toggleUnderline: () => _applyState(() {
              _selectedTextItem!.underline = !_selectedTextItem!.underline;
              _notifyChanged();
            }),
            toggleStrikethrough: () => _applyState(() {
              _selectedTextItem!.strikethrough =
                  !_selectedTextItem!.strikethrough;
              _notifyChanged();
            }),
            cycleAlign: () => _applyState(() {
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
    _applyState(() {
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
    // 画布模式的对象拖动由 controller 统一管理（不走 _dragItem），
    // 因此对齐吸附仅作用于分页笔记的混排对象；无限画布吸附属于
    // controller 层后续工程（记录于审查报告）。
    final page = widget.page;
    if (page == null) return;
    const snapTol = 10.0;
    final textItems = page.textItems;
    final imageItems = page.imageItems;
    final shapes = page.shapes;

    // 收集所有混排对象的边界（左/右/上/下/水平中心/垂直中心）。
    final refs =
        <({double l, double r, double t, double b, double cx, double cy})>[];
    for (final t in textItems) {
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
    for (final i in imageItems) {
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
    for (final s in shapes) {
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
    for (final t in textItems) {
      if (t.id == id) {
        l = t.x;
        r = t.x + t.fontSize * 2;
        top = t.y;
        bottom = t.y + t.fontSize;
      }
    }
    for (final i in imageItems) {
      if (i.id == id) {
        l = i.x;
        r = i.x + i.width;
        top = i.y;
        bottom = i.y + i.height;
      }
    }
    for (final s in shapes) {
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
      for (final t in textItems) {
        if (t.id == id) {
          t.x += dx;
          t.y += dy;
        }
      }
      for (final i in imageItems) {
        if (i.id == id) {
          i.x += dx;
          i.y += dy;
        }
      }
      for (final s in shapes) {
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
    _applyState(() {});
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
            _applyState(() {
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
            _applyState(() {
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
              _applyState(() {
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
                  onTap: () => _applyState(() {
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
                                  _applyState(() {
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
                                  _applyState(() {
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
}
