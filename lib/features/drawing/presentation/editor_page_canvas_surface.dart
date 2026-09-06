part of 'editor_page.dart';

/// 编辑器画布表面组合域。
///
/// 此 extension 仅负责画布、网格、形状草稿、混排对象容器、小地图及番茄钟的
/// Widget 组合；它保留既有事件委托和控制器调用，不拥有文档或交互状态。
extension _EditorPageCanvasSurface on _EditorPageState {
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
            // 网格显示层（借鉴 Excalidraw 画布导航）。
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
            // 混排对象层（文字/图片）。笔记本模式渲染页面文字、图片、形状和图表；
            // 画布模式渲染文档文字块。监听 frameTick 使视口变换时位置同步刷新。
            if (_isNotebookMode ||
                _controller.document.textItems.isNotEmpty ||
                _pendingTextItem != null)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _controller.frameTick,
                  builder: (context, _) {
                    final overlay = Stack(
                      children: [
                        // 连接线层（D1：节点关联标注，借鉴 Relatum 连线）。
                        // IgnorePointer 必需：CustomPainter.hitTest 默认
                        // 返回 true，这层 Positioned.fill 若参与命中会盖住
                        // 整块画布、吞掉全部指针事件（2026-09-07 分页画布
                        // 「白纸无法作画」根因——独立画布无此层故不受影响）。
                        if (_isNotebookMode)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: ConnectorPainter(
                                  connectors: widget.session!.connectors,
                                  itemPositions: {
                                    for (final text
                                        in widget.session!.textItems)
                                      text.id: text.position,
                                    for (final image
                                        in widget.session!.imageItems)
                                      image.id: image.position,
                                  },
                                  controller: _controller,
                                ),
                              ),
                            ),
                          ),
                        ..._buildOverlayItems(),
                        // 拖动轨迹动画层（对齐 Excalidraw animatedTrail）。
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
                        // 对齐参考线（拖动元素时实时显示，借鉴 Excalidraw）。
                        // IgnorePointer：参考线是纯视觉反馈，且裸 CustomPaint
                        // 的默认 hitTest 会吞掉拖动中的指针（同连线层教训）。
                        if (_snapGuides.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: SnapGuidePainter(
                                  guides: _snapGuides,
                                  controller: _controller,
                                ),
                              ),
                            ),
                          ),
                        // 框选矩形（多选时可视化，借鉴 Excalidraw 多选）。
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
            // 独立画布：选中线性元素（直线/箭头）的端点编辑手柄（审计二-2）。
            // 与画布 Listener 分层命中：手柄 44px 热区在上层，画布手势不受影响。
            if (!_isNotebookMode)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _controller,
                    _controller.frameTick,
                  ]),
                  builder: (context, _) {
                    final shape = _controller.selectedDocumentShape;
                    if (shape == null ||
                        !ShapeBindingGeometry.isLinear(shape) ||
                        shape.locked) {
                      return const SizedBox.shrink();
                    }
                    final endpoints = shape.shapeType == ShapeType.arrow
                        ? ShapeBindingGeometry.resolvedArrowEndpoints(
                            shape,
                            _controller.document.shapes,
                          )
                        : ShapeBindingGeometry.linearEndpoints(shape);
                    EndpointHandle handle(bool isStart) => EndpointHandle(
                      position: _controller.canvasToView(
                        isStart ? endpoints.start : endpoints.end,
                      ),
                      onPanStart: () {
                        _linearEndpointDragBase = endpoints;
                        _linearEndpointAccum = Offset.zero;
                        _controller.beginLinearEndpointEdit();
                      },
                      onPanUpdate: (screenDelta) {
                        _linearEndpointAccum += screenDeltaToCanvas(
                          screenDelta,
                          _controller.viewRotation,
                          _controller.viewScale,
                        );
                        final base = _linearEndpointDragBase;
                        if (base == null) return;
                        _controller.updateSelectedLinearEndpoint(
                          isStart: isStart,
                          point:
                              (isStart ? base.start : base.end) +
                              _linearEndpointAccum,
                          snapToGrid: _snapToGrid,
                        );
                        final current = _controller.selectedDocumentShape;
                        if (current != null) {
                          _updateLinearReadoutFromShape(current, isStart);
                        }
                      },
                      onPanEnd: () {
                        _controller.endLinearEndpointEdit();
                        _linearEndpointDragBase = null;
                        _linearEndpointAccum = Offset.zero;
                        _linearReadout.value = null;
                        _notifyChanged();
                      },
                    );
                    return Stack(children: [handle(true), handle(false)]);
                  },
                ),
              ),
            // 线性元素拖拽读数气泡（长度/角度，审计二-6）：触屏遮挡落点时
            // 至少「看得见」正在画的线。浮层材质，不拦截指针。
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<LinearDraftReadout?>(
                  valueListenable: _linearReadout,
                  builder: (context, readout, _) {
                    if (readout == null) return const SizedBox.shrink();
                    var degrees = readout.angleDeg.round();
                    if (degrees < 0) degrees += 360;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: readout.viewPos.dx + 14,
                          top: readout.viewPos.dy - 34,
                          child: LinearReadoutBubble(
                            length: readout.length,
                            angleDeg: degrees.toDouble(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // 左侧浮动玻璃工具岛（审计三-1）：垂直居中、离边 12px 的浮层
            // 材质（DESIGN_SYSTEM §5 分层规则——工具条属浮层，可用玻璃）。
            // Align 提供松约束：ConstrainedBox 的限宽/限高才能生效——不限宽
            // 会让玻璃板横铺整块画布、挡住画布手势；工具项多于可视高度时
            // 在岛内滚动。岛宽 56 = 48px 按钮 + 2×4px 内边距。
            if (!_fullscreen)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppleSpacing.sm),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 56,
                        maxHeight: constraints.biggest.height - AppleSpacing.sm,
                      ),
                      child: _buildLeftToolbar(),
                    ),
                  ),
                ),
              ),
            // 画布小地图（借鉴 Relatum：放大后快速导航定位）。
            Positioned(right: 8, bottom: 8, child: _buildMiniMap()),
            // 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）。
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
      borderRadius: BorderRadius.circular(AppleRadius.xs),
      color: const Color(0xE6FFFFFF),
      // 同时监听 frameTick（高频绘制/视口变化），使小地图可实时跟手。
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
                borderRadius: BorderRadius.circular(AppleRadius.xs),
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
    // 逆变换：offset = viewCenter - c - R(scale·(canvasPoint - c))。
    final rotated = rotatePoint2(
      (canvasPoint - c) * _controller.viewScale,
      _controller.viewRotation,
    );
    _controller.viewOffset = viewCenter - rotated - c;
    _controller.tickFrame();
  }
}
