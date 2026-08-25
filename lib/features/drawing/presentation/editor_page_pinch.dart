part of 'editor_page.dart';

/// 捏合/缩放/旋转手势处理域（拆分自 editor_page_input.dart）。
extension _EditorPagePinch on _EditorPageState {
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

  /// 鼠标滚轮缩放（桌面端，借鉴 Excalidraw 缩放逻辑）。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final dy = event.scrollDelta.dy;
      if (dy == 0) return;
      // Ctrl+滚轮 = 缩放；普通滚轮 = 竖向平移（问题7：使外接鼠标与触控板一致）。
      if (HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        final factor = dy > 0 ? 0.95 : 1.05;
        final pos = event.localPosition;
        final oldScale = _controller.viewScale;
        final newScale = (oldScale * factor).clamp(0.05, 20.0);
        // 以鼠标位置为缩放锚点（对齐 Excalidraw）。
        final dx = pos.dx - (pos.dx - _controller.viewOffset.dx) * newScale / oldScale;
        final dy2 = pos.dy - (pos.dy - _controller.viewOffset.dy) * newScale / oldScale;
        _controller.viewScale = newScale;
        _controller.viewOffset = Offset(dx, dy2);
      } else {
        // 普通滚轮：纵向平移；Shift+滚轮：横向平移。
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        if (isShift) {
          _controller.viewOffset += Offset(-dy, 0);
        } else {
          _controller.viewOffset += Offset(0, -dy);
        }
      }
      _controller.tickFrame();
    }
  }
}
