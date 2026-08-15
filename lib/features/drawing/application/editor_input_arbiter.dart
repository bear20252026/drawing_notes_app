import 'package:flutter/gestures.dart';

/// 指针被编辑器解释后的高层行为。
enum EditorPointerDisposition {
  startInk,
  continueInk,
  finishInk,
  beginViewportGesture,
  updateViewportGesture,
  cancelInkForViewportGesture,
  ignore,
}

/// 编辑器输入策略。
///
/// 使用触控笔时默认拒绝新增 touch 指针，避免手掌或第二根手指产生墨迹。
/// 鼠标始终可以作为桌面创作回退输入；手指墨迹则必须由用户明确启用。
///
/// 仲裁规则（专家审查文档补充 2026-08-15）：
/// 1. 指针事件先经 [EditorInputPolicy] 判定 → [EditorPointerDisposition]；
/// 2. 墨迹与视口手势两类高层行为互斥：beginViewportGesture 会取消进行中
///    的墨迹（cancelInkForViewportGesture），避免双指捏合缩放与笔画冲突；
/// 3. 触控笔优先：stylus 事件始终允许墨迹，touch 受 allowInk 约束。
class EditorInputPolicy {
  const EditorInputPolicy({
    required this.allowInk,
    this.allowFingerDrawing = false,
    this.enablePalmRejection = true,
  });

  final bool allowInk;
  final bool allowFingerDrawing;
  final bool enablePalmRejection;
}

/// 把原始 PointerEvent 转换为可被编辑器安全消费的输入决策。
///
/// 该对象不操作画布、不创建笔画，也不持有 Widget 状态。页面只需要按
/// [disposition] 触发自己的绘制或视图逻辑，因此它可以用单元测试覆盖。
class EditorInputArbiter {
  final Map<int, PointerDeviceKind> _activePointers = {};
  int? _inkPointer;

  bool get hasStylusContact => _activePointers.values.any(_isStylus);
  int get activePointerCount => _activePointers.length;

  EditorPointerDisposition onDown(
    PointerDownEvent event, {
    required EditorInputPolicy policy,
  }) {
    final kind = event.kind;

    // 手掌拒绝必须发生在将 touch 纳入多点手势之前。否则笔正在书写时
    // 落下的手掌会被错误解释为双指缩放，导致笔画被取消。
    if (kind == PointerDeviceKind.touch &&
        policy.enablePalmRejection &&
        hasStylusContact) {
      return EditorPointerDisposition.ignore;
    }

    _activePointers[event.pointer] = kind;

    if (_activePointers.length >= 2) {
      final hadInk = _inkPointer != null;
      _inkPointer = null;
      return hadInk
          ? EditorPointerDisposition.cancelInkForViewportGesture
          : EditorPointerDisposition.beginViewportGesture;
    }

    if (!policy.allowInk) {
      return EditorPointerDisposition.beginViewportGesture;
    }
    if (kind == PointerDeviceKind.touch && !policy.allowFingerDrawing) {
      return EditorPointerDisposition.beginViewportGesture;
    }

    _inkPointer = event.pointer;
    return EditorPointerDisposition.startInk;
  }

  EditorPointerDisposition onMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) {
      return EditorPointerDisposition.ignore;
    }
    if (_activePointers.length >= 2) {
      return EditorPointerDisposition.updateViewportGesture;
    }
    return _inkPointer == event.pointer
        ? EditorPointerDisposition.continueInk
        : EditorPointerDisposition.updateViewportGesture;
  }

  EditorPointerDisposition onUp(PointerUpEvent event) {
    final wasInk = _inkPointer == event.pointer;
    _activePointers.remove(event.pointer);
    if (wasInk) _inkPointer = null;
    if (wasInk) return EditorPointerDisposition.finishInk;
    return _activePointers.length >= 2
        ? EditorPointerDisposition.updateViewportGesture
        : EditorPointerDisposition.ignore;
  }

  void onCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_inkPointer == event.pointer) _inkPointer = null;
  }

  void reset() {
    _activePointers.clear();
    _inkPointer = null;
  }

  static bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;
}
