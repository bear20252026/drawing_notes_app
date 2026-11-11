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
        // H2 性能优化（2026-10-14）：此前 6 处独立 ListenableBuilder 各自
        // 监听 frameTick，240Hz 采样下每帧 6 次 Element 重建。合并为单一
        // ListenableBuilder，在 builder 内一次构造整棵 overlay Stack。
        // 线性读数层（_buildCanvasLinearReadoutLayer）监听的是 _linearReadout
        // 而非 frameTick，保持独立。
        return ListenableBuilder(
          listenable: Listenable.merge([_controller, _controller.frameTick]),
          builder: (context, _) => Stack(
            children: [
              _buildCanvasPainterLayer(),
              if (_gridVisible) _buildCanvasGridLayer(),
              if (_shapeDraft != null) _buildCanvasShapeDraftLayer(),
              // 框选/轨迹/吸附参考线无条件渲染：此前挂在对象 overlay 层里
              // 被门控——独立画布（无文字块）框选生效但完全没有视觉反馈。
              _buildCanvasSelectionFeedbackLayer(),
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
          ),
        );
      },
    );
  }

  /// 按当前工具解析桌面端鼠标光标（P4，审计 2026-10-09：此前全工具
  /// 只有默认箭头，手型/吸管/文字/橡皮四种工具无一有光标暗示）。
  MouseCursor _cursorForCurrentTool() {
    if (_handToolActive) return SystemMouseCursors.grab;
    if (_eyedropperActive) return SystemMouseCursors.precise;
    if (_textToolActive) return SystemMouseCursors.text;
    if (_isObjectEraser) return SystemMouseCursors.precise;
    if (_controller.tool == BrushType.eraser) {
      return SystemMouseCursors.precise;
    }
    return MouseCursor.defer;
  }

  /// 画布层：CustomPainter + 双击插字 + 指针手势。
  Widget _buildCanvasPainterLayer() {
    return Positioned.fill(
      child: Semantics(
        label: AppLocalizations.of(context)?.canvasSemanticsLabel ?? '绘图画布',
        hint:
            AppLocalizations.of(context)?.canvasSemanticsHint ??
            '双击空白处插入文字；使用工具栏工具绘制',
        child: MouseRegion(
          cursor: _cursorForCurrentTool(),
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
    );
  }

  /// 网格显示层（借鉴 Excalidraw 画布导航）。
  ///
  /// H2：frameTick 监听已上提到 _buildCanvasArea 的单一 ListenableBuilder，
  /// 本层只负责构建 painter（手型平移/双指缩放/滚轮缩放都只 tick 画布——
  /// 此前网格层不监听，视口变换期间点阵与画布内容错位漂移，
  /// 直到下一次 setState 才纠正）。
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

  /// 框选反馈层：拖拽轨迹/吸附参考线/框选矩形。
  ///
  /// H2：frameTick 监听已上提到 _buildCanvasArea 的单一 ListenableBuilder。
  /// 与混排对象 overlay 解耦（独立画布无文字块时也要有框选视觉反馈）；
  /// 三个 painter 空数据时零绘制，常驻成本可忽略。
  Widget _buildCanvasSelectionFeedbackLayer() {
    if (_trailPoints.isEmpty && _snapGuides.isEmpty && _marqueeRect == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            if (_trailPoints.isNotEmpty)
              CustomPaint(
                painter: TrailPainter(
                  points: _trailPoints,
                  controller: _controller,
                ),
              ),
            if (_snapGuides.isNotEmpty)
              CustomPaint(
                painter: SnapGuidePainter(
                  guides: _snapGuides,
                  controller: _controller,
                ),
              ),
            if (_marqueeRect != null)
              CustomPaint(
                painter: MarqueePainter(
                  rect: _marqueeRect!,
                  controller: _controller,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 形状草稿层：所有工作区均可见，且不拦截正在创建形状的指针。
  ///
  /// H2：frameTick 监听已上提到 _buildCanvasArea 的单一 ListenableBuilder。
  /// 拖拽创建的高频指针移动只 tick 不 setState，草稿框由本层逐帧重算
  /// [_shapeDraft]（getter 现算）。出现/消失仍由起笔/收笔的 setState 驱动。
  Widget _buildCanvasShapeDraftLayer() {
    final draft = _shapeDraft;
    if (draft == null) return const SizedBox.shrink();
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

  /// 连接线 + 混排对象层（轨迹/参考线/框选已拆到独立反馈层）。
  ///
  /// H2：frameTick 监听已上提到 _buildCanvasArea 的单一 ListenableBuilder。
  Widget _buildCanvasObjectOverlayLayer() {
    final overlay = Stack(
      children: [
        if (_isNotebookMode) _buildCanvasConnectorLayer(),
        ..._buildOverlayItems(),
      ],
    );
    return Positioned.fill(
      child: _readingInverted
          ? ColorFiltered(
              colorFilter: _EditorPageState._readingInvertFilter,
              child: overlay,
            )
          : overlay,
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

  /// 独立画布：线性元素端点编辑手柄（审计二-2）。
  ///
  /// H2：controller + frameTick 监听已上提到 _buildCanvasArea 的单一
  /// ListenableBuilder。
  Widget _buildCanvasLinearEndpointLayer() {
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
          point: (isStart ? base.start : base.end) + _linearEndpointAccum,
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
    return Positioned.fill(
      child: Stack(children: [handle(true), handle(false)]),
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
    final doc = _controller.document;
    final miniScale = _miniMapWidth / doc.width;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppleRadius.xs),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      // H2：controller + frameTick 监听已上提到 _buildCanvasArea 的单一
      // ListenableBuilder，小地图随其一起重建（高频绘制/视口变化实时跟手）。
      child: Semantics(
        container: true,
        label: AppLocalizations.of(context)?.canvasMiniMap ?? '画布小地图',
        hint:
            AppLocalizations.of(context)?.canvasMiniMapHint ??
            '方向键平移视口，Shift 加速',
        child: Focus(
          onKeyEvent: _handleMiniMapKey,
          child: GestureDetector(
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
          ),
        ),
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
