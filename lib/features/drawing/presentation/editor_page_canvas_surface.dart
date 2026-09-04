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
                        if (_isNotebookMode)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: ConnectorPainter(
                                connectors: widget.session!.connectors,
                                itemPositions: {
                                  for (final text in widget.session!.textItems)
                                    text.id: text.position,
                                  for (final image
                                      in widget.session!.imageItems)
                                    image.id: image.position,
                                },
                                controller: _controller,
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
                        if (_snapGuides.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: SnapGuidePainter(
                                guides: _snapGuides,
                                controller: _controller,
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
