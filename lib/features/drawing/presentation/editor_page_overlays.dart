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
      document: _controller.document,
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
              child: Semantics(
                label: '绘图画布',
                hint: '双击空白处插入文字；使用工具栏工具绘制',
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
                            ResizeHandles(
                              shape: shape,
                              width: w,
                              height: h,
                              screenToCanvasDelta: _screenDeltaToCanvas,
                              onResize: (pos, delta, isCorner) {
                                _applyState(() {
                                  if (isCorner) {
                                    final left = pos.dx == 0;
                                    final top = pos.dy == 0;
                                    if (left) {
                                      shape.x += delta.dx;
                                      shape.width = (shape.width - delta.dx).clamp(20, 1000);
                                    } else {
                                      shape.width = (shape.width + delta.dx).clamp(20, 1000);
                                    }
                                    if (top) {
                                      shape.y += delta.dy;
                                      shape.height = (shape.height - delta.dy).clamp(20, 1000);
                                    } else {
                                      shape.height = (shape.height + delta.dy).clamp(20, 1000);
                                    }
                                  } else {
                                    final horizontal = pos.dx == 0 || pos.dx == w;
                                    if (horizontal) {
                                      if (pos.dx == 0) {
                                        shape.x += delta.dx;
                                        shape.width = (shape.width - delta.dx).clamp(20, 1000);
                                      } else {
                                        shape.width = (shape.width + delta.dx).clamp(20, 1000);
                                      }
                                    } else {
                                      if (pos.dy == 0) {
                                        shape.y += delta.dy;
                                        shape.height = (shape.height - delta.dy).clamp(20, 1000);
                                      } else {
                                        shape.height = (shape.height + delta.dy).clamp(20, 1000);
                                      }
                                    }
                                  }
                                });
                              },
                              onChanged: _notifyChanged,
                            ),
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

}
