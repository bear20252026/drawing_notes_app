part of 'editor_page.dart';

// V-01（审计 2026-09-27）：键盘选中画布对象专项——Tab / Shift+Tab 轮选。
//
// 交互设计（Excalidraw 同款 + 本项目三输入纪律）：
// - 无选中 → Tab 选中 z 序第一个对象；继续 Tab 前进、Shift+Tab 后退，
//   到边界循环；无对象时忽略（放行焦点遍历）。Esc 清除选中。
// - 轮选即激活既有键盘链路：Delete/Backspace 删除、Alt+方向键微调、
//   Menu/Shift+F10 上下文菜单（editor_page_shortcuts 既有分支此前全部
//   依赖指针先选中——键盘用户无法删除画布对象的本缺口就此闭合）。
// - 选中滚入视口：对象中心在视图外时平移视口至可见（旋转视图跳过——
//   旋转空间平移换算留待真实使用场景；rotation=0 为主路径）。
// - 不复用 _onItemTap：其含超链接打开与连线模式副作用，键盘轮选不应
//   触发浏览器打开或进入连线状态——走纯选中路径。
// - 轮选顺序与覆盖层渲染同源（EditorOverlayItemPlan，z-order 排序），
//   保证「选中的顺序 = 看到的叠放顺序」。

/// 编辑器键盘选中域（V-01 专项）。
extension _EditorPageKeyboardSelect on _EditorPageState {
  /// 当前可选对象计划（画布模式仅文字块；笔记页模式混排四类，
  /// 与 _buildOverlayItems 同一数据源）。
  List<EditorOverlayItemPlanEntry> get _selectablePlan {
    final page = widget.session;
    return page == null
        ? EditorOverlayItemPlan.forCanvas(_controller.document.textItems)
        : EditorOverlayItemPlan.forPage(
            textItems: page.textItems,
            imageItems: page.imageItems,
            shapes: page.shapes,
            charts: page.charts,
          );
  }

  /// Tab（reverse=false）/ Shift+Tab（reverse=true）轮选下一个对象。
  ///
  /// 返回是否处理（无对象返回 false——放行焦点遍历）。
  bool _selectNextObject({required bool reverse}) {
    final plan = _selectablePlan;
    if (plan.isEmpty) return false;

    final currentId = _selectedItemId;
    final count = plan.length;
    final index = currentId == null
        ? -1
        : plan.indexWhere((e) => e.id == currentId);
    // 无选中 → 第一个（reverse 则最后一个）；有选中 → 前进/后退循环。
    final nextIndex = reverse
        ? (index <= 0 ? count - 1 : index - 1)
        : (index < 0 ? 0 : (index + 1) % count);
    final next = plan[nextIndex];

    _applyState(() {
      _canvasInteraction.clearObjectSelection();
      _canvasInteraction.selectedItemId = next.id;
    });
    _ensureObjectVisible(next);
    return true;
  }

  /// 清除键盘选中（Esc）：与指针路径的「点空白处取消」等价。
  bool _clearKeyboardSelection() {
    if (_selectedItemId == null && !_canvasInteraction.hasMultiSelection) {
      return false;
    }
    _applyState(_canvasInteraction.clearObjectSelection);
    return true;
  }

  /// 键盘选中滚入视口：对象中心落在视图外（含边缘余量）时平移视口，
  /// 使对象中心移到视口中央。rotation ≠ 0 时跳过（旋转空间平移换算
  /// 留待真实场景；rotation = 0 为主路径）。
  void _ensureObjectVisible(EditorOverlayItemPlanEntry entry) {
    final viewportSize = _viewportSize;
    if (viewportSize == null || _controller.viewRotation != 0) return;
    final bounds = _entryCanvasBounds(entry);
    if (bounds == null) return;

    final center = bounds.center;
    final viewPos = _controller.canvasToView(center);
    final margin = 48.0;
    final visible = Rect.fromLTWH(
      margin,
      margin,
      (viewportSize.width - margin * 2).clamp(0, double.infinity),
      (viewportSize.height - margin * 2).clamp(0, double.infinity),
    );
    if (visible.contains(viewPos)) return;

    // rotation = 0：view = (canvas − center)·scale + center + offset，
    // 视口平移与画布平移同空间——把对象视图位对齐视口中心即可。
    final viewCenter = viewportSize.center(Offset.zero);
    final delta = viewCenter - viewPos;
    _applyState(() => _controller.viewOffset += delta);
  }

  /// 计划条目的画布坐标包围盒（各类型均以左上角 + 宽高存储）。
  Rect? _entryCanvasBounds(EditorOverlayItemPlanEntry entry) {
    final text = entry.text;
    if (text != null) {
      return Rect.fromLTWH(text.x, text.y, text.width ?? 120, 32);
    }
    final image = entry.image;
    if (image != null) {
      return Rect.fromLTWH(image.x, image.y, image.width, image.height);
    }
    final shape = entry.shape;
    if (shape != null) {
      return Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
    }
    final chart = entry.chart;
    if (chart != null) {
      return Rect.fromLTWH(
        chart.position.dx,
        chart.position.dy,
        chart.width,
        chart.height,
      );
    }
    return null;
  }
}
