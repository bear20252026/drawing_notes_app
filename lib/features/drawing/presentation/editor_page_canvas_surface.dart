part of 'editor_page.dart';

/// 编辑器画布表面组合域。
///
/// 此 extension 仅负责画布、网格、形状草稿、混排对象容器、小地图及番茄钟的
/// Widget 组合；它保留既有事件委托和控制器调用，不拥有文档或交互状态。
extension _EditorPageCanvasSurface on _EditorPageState {
  /// 画布区域（全屏/普通模式共用）。
  ///
  /// 组合层拆到 `_buildCanvas*Layer` 助手，避免 DCM long-method 反模式
  /// （quality_gate `metrics analyze lib` 门禁）。
  Widget _buildCanvasArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initViewport(constraints.biggest);
        // 记录画布视口尺寸（小地图导航需要）。
        _viewportSize = constraints.biggest;
        return Stack(
          children: [
            _buildCanvasPainterLayer(),
            if (_gridVisible) _buildCanvasGridLayer(),
            if (_shapeDraft != null) _buildCanvasShapeDraftLayer(),
            if (_isNotebookMode ||
                _controller.document.textItems.isNotEmpty ||
                _pendingTextItem != null)
              _buildCanvasObjectOverlayLayer(),
            if (!_isNotebookMode) _buildCanvasLinearEndpointLayer(),
            _buildCanvasLinearReadoutLayer(),
            if (!_fullscreen) _buildCanvasLeftToolbarLayer(constraints),
            // 画布小地图（借鉴 Relatum：放大后快速导航定位）。
            Positioned(right: 8, bottom: 8, child: _buildMiniMap()),
            // 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）。
            Positioned(right: 8, top: 8, child: _buildPomodoro()),
          ],
        );
      },
    );
  }

  /// 画布层：CustomPainter + 双击插字 + 指针手势。
  Widget _buildCanvasPainterLayer() {
    return Positioned.fill(
      child: Semantics(
        label: AppLocalizations.of(context)?.canvasSemanticsLabel ?? '绘图画布',
        hint:
            AppLocalizations.of(context)?.canvasSemanticsHint ??
            '双击空白处插入文字；使用工具栏工具绘制',
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
    );
  }

  /// 网格显示层（借鉴 Excalidraw 画布导航）。
  Widget _buildCanvasGridLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: _readingInverted
            ? ColorFiltered(
                colorFilter: _EditorPageState._readingInvertFilter,
                child: CustomPaint(
                  painter: GridPainter(controller: _controller),
                ),
              )
            : CustomPaint(painter: GridPainter(controller: _controller)),
      ),
    );
  }

  /// 形状草稿层：所有工作区均可见，且不拦截正在创建形状的指针。
  Widget _buildCanvasShapeDraftLayer() {
    final draft = _shapeDraft!;
    return Positioned.fill(
      child: IgnorePointer(
        child: _readingInverted
            ? ColorFiltered(
                colorFilter: _EditorPageState._readingInvertFilter,
                child: Stack(children: [_buildShapeOverlay(draft)]),
              )
            : Stack(children: [_buildShapeOverlay(draft)]),
      ),
    );
  }

  /// 连接线 + 混排对象 + 轨迹/参考线/框选层。
  Widget _buildCanvasObjectOverlayLayer() {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: _controller.frameTick,
        builder: (context, _) {
          final overlay = Stack(
            children: [
              if (_isNotebookMode) _buildCanvasConnectorLayer(),
              ..._buildOverlayItems(),
              if (_trailPoints.isNotEmpty)
                _buildCanvasIgnorePointerPaint(
                  TrailPainter(points: _trailPoints, controller: _controller),
                ),
              if (_snapGuides.isNotEmpty)
                _buildCanvasIgnorePointerPaint(
                  SnapGuidePainter(
                    guides: _snapGuides,
                    controller: _controller,
                  ),
                ),
              if (_marqueeRect != null)
                _buildCanvasIgnorePointerPaint(
                  MarqueePainter(rect: _marqueeRect!, controller: _controller),
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
    );
  }

  /// 连接线层（D1：节点关联标注）。IgnorePointer 防 CustomPaint 吞指针。
  Widget _buildCanvasConnectorLayer() {
    final session = widget.session!;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: ConnectorPainter(
            connectors: session.connectors,
            itemPositions: {
              for (final text in session.textItems) text.id: text.position,
              for (final image in session.imageItems) image.id: image.position,
            },
            controller: _controller,
          ),
        ),
      ),
    );
  }

  /// 覆盖层纯视觉 CustomPaint：IgnorePointer + 不命中。
  Widget _buildCanvasIgnorePointerPaint(CustomPainter painter) {
    return Positioned.fill(
      child: IgnorePointer(child: CustomPaint(painter: painter)),
    );
  }

  /// 独立画布：线性元素端点编辑手柄（审计二-2）。
  Widget _buildCanvasLinearEndpointLayer() {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: Listenable.merge([_controller, _controller.frameTick]),
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
                    (isStart ? base.start : base.end) + _linearEndpointAccum,
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
    );
  }

  /// 线性元素拖拽读数气泡（长度/角度，审计二-6）。
  Widget _buildCanvasLinearReadoutLayer() {
    return Positioned.fill(
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
    );
  }

  /// 左侧浮动玻璃工具岛（审计三-1）：浮层材质，岛宽 56。
  Widget _buildCanvasLeftToolbarLayer(BoxConstraints constraints) {
    return Positioned.fill(
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
    );
  }

  /// 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）。
  Widget _buildPomodoro() {
    return PomodoroTimer(
      onFinished: () {
        _showSnack(_l10nSafe?.pomodoroFinish ?? '番茄钟结束：休息一下吧');
      },
    );
  }

  /// 小地图宽高。
  static const double _miniMapWidth = 160;
  static const double _miniMapHeight = 120;

  /// 画布小地图：整幅缩略图 + 当前视口框 + 点击/拖动导航。
  /// B3：聚焦后方向键平移视口（键盘等价入口），Shift 加速。
  Widget _buildMiniMap() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppleRadius.xs),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      // 同时监听 frameTick（高频绘制/视口变化），使小地图可实时跟手。
      child: ListenableBuilder(
        listenable: Listenable.merge([_controller, _controller.frameTick]),
        builder: (context, _) {
          final doc = _controller.document;
          final miniScale = _miniMapWidth / doc.width;
          return Semantics(
            container: true,
            label: '画布小地图',
            hint: '方向键平移视口，Shift 加速',
            child: Focus(
              onKeyEvent: _handleMiniMapKey,
              child: GestureDetector(
                onTapDown: (d) => _navigateMiniMap(d.localPosition, miniScale),
                onPanUpdate: (d) =>
                    _navigateMiniMap(d.localPosition, miniScale),
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
              ),
            ),
          );
        },
      ),
    );
  }

  /// B3：小地图键盘平移视口（方向键 24 逻辑像素 / Shift 96）。
  ///
  /// [node] 为 Focus 回调签名所需，本处理不依赖焦点节点自身。
  // ignore: avoid-unused-parameters
  KeyEventResult _handleMiniMapKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final step = shift ? 96.0 : 24.0;
    // 视口向某方向移动 = 内容反向平移（见 CanvasPainter 视口变换）。
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => Offset.zero,
    };
    if (delta == Offset.zero) return KeyEventResult.ignored;
    _controller.viewOffset += -delta;
    _controller.tickFrame();
    return KeyEventResult.handled;
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
