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

  /// 构建画布上方的混排对象（文字块/图片块）。
  List<Widget> _buildOverlayItems() {
    final page = widget.session;
    final plan = page == null
        ? EditorOverlayItemPlan.forCanvas(_controller.document.textItems)
        : EditorOverlayItemPlan.forPage(
            textItems: page.textItems,
            imageItems: page.imageItems,
            shapes: page.shapes,
            charts: page.charts,
          );
    final items = <Widget>[];
    // 就地编辑中的临时文字块尚未加入页面，始终优先渲染在最上层。
    final pending = _pendingTextItem;
    if (pending != null && _editingItemId == pending.id) {
      items.add(_buildInlineEditor(pending));
    }
    for (final entry in plan) {
      if (entry.id == _editingItemId) {
        final text = entry.text;
        if (text != null) items.add(_buildInlineEditor(text));
        continue;
      }
      switch (entry.kind) {
        case EditorOverlayItemKind.text:
          items.add(_buildTextOverlay(entry.text!));
        case EditorOverlayItemKind.image:
          items.add(_buildImageOverlay(entry.image!));
        case EditorOverlayItemKind.shape:
          items.add(_buildShapeOverlay(entry.shape!));
        case EditorOverlayItemKind.chart:
          items.add(_buildChartOverlay(entry.chart!));
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
                // 线性元素已用 lineStart/lineEnd 保存真实方向端点，flip 镜像
                // 会把方向二次翻转（与 ShapeRenderer.drawDocumentShape 同规则）；
                // 仅端点缺失的旧文档保留 flip 兜底。
                transform: shape.lineStart != null && shape.lineEnd != null
                    ? Matrix4.identity()
                    : Matrix4.diagonal3Values(
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
                              width: w,
                              height: h,
                              screenToCanvasDelta: (delta) =>
                                  screenDeltaToCanvas(
                                    delta,
                                    _controller.viewRotation,
                                    _controller.viewScale,
                                  ),
                              onResize: (handle, canvasDelta) {
                                final resized =
                                    EditorShapeResizeGeometry.resize(
                                      bounds: EditorShapeBounds(
                                        x: shape.x,
                                        y: shape.y,
                                        width: shape.width,
                                        height: shape.height,
                                      ),
                                      handle: handle,
                                      canvasDelta: canvasDelta,
                                    );
                                _applyState(() {
                                  shape
                                    ..x = resized.x
                                    ..y = resized.y
                                    ..width = resized.width
                                    ..height = resized.height;
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
                  ? Image(
                      image: EncryptedFileImage(File(item.filePath)),
                      fit: BoxFit.contain,
                      // L-03 语义（专家审计 2026-08-15）：图片可读名。
                      semanticLabel: '笔记图片',
                    )
                  : const ColoredBox(color: Colors.grey),
            ),
            // 裁剪框 4 角手柄（对齐 Excalidraw 图片裁剪）：拖拽调整 _cropRect。
            if (cropping && _cropRect != null) ..._buildCropHandles(),
          ],
        ),
      ),
    );
  }

  /// 拖动混排对象：把屏幕位移换算为画布位移。
  /// 分组展开（借鉴 Excalidraw groupIds）：给定元素 id 集合，
  /// 返回包含同组元素的完整集合（整体移动/删除联动）。
}
