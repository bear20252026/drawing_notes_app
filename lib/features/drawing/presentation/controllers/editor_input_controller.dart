/// 编辑器输入控制器 — 键盘/快捷键处理。
///
/// 从 editor_page_shortcuts.dart 和 editor_page_input 拆分出的独立控制器。
/// 负责：
/// - 键盘快捷键匹配与分发
/// - 多指手势状态跟踪
/// - 输入仲裁（触控笔/手指/手掌）
///
/// 架构原则：
/// - 单一职责：仅处理输入事件，不直接修改文档
/// - 通过回调与上层通信
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../application/command_registry.dart';
import 'editor_state.dart';

/// 编辑器输入控制器。
class EditorInputController {
  EditorInputController({
    required this.editorState,
    required this.commandRegistry,
    this.onUndo,
    this.onRedo,
    this.onShortcut,
  });

  /// 编辑器状态。
  final EditorState editorState;

  /// 命令注册表。
  final CommandRegistry commandRegistry;

  /// 撤销回调。
  final VoidCallback? onUndo;

  /// 重做回调。
  final VoidCallback? onRedo;

  /// 快捷键回调（通用）。
  final void Function(String commandId)? onShortcut;

  /// 当前按下的指针（pointerId -> 视口坐标）。
  final Map<int, Offset> activePointers = {};

  /// 多指手势状态。
  double? pinchDistance;
  double? pinchAngle;

  /// 是否处于多指手势中。
  bool get inPinch => activePointers.length >= 2;

  // ─── 键盘快捷键 ────────────────────────────────────────────

  /// 处理键盘快捷键。
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final isControl = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl+Z 撤销
    if (isControl && key == LogicalKeyboardKey.keyZ && !isShift) {
      onUndo?.call();
      return true;
    }

    // Ctrl+Y 或 Ctrl+Shift+Z 重做
    if (isControl &&
        (key == LogicalKeyboardKey.keyY ||
            (key == LogicalKeyboardKey.keyZ && isShift))) {
      onRedo?.call();
      return true;
    }

    // Ctrl+K 命令面板
    if (isControl && key == LogicalKeyboardKey.keyK) {
      onShortcut?.call('command_palette');
      return true;
    }

    // Escape 取消当前操作
    if (key == LogicalKeyboardKey.escape) {
      onShortcut?.call('escape');
      return true;
    }

    return false;
  }

  // ─── 指针事件 ──────────────────────────────────────────────

  /// 指针按下。
  void onPointerDown(PointerDownEvent event) {
    activePointers[event.pointer] = event.localPosition;
    _updatePinchState();
  }

  /// 指针移动。
  void onPointerMove(PointerMoveEvent event) {
    if (activePointers.containsKey(event.pointer)) {
      activePointers[event.pointer] = event.localPosition;
      _updatePinchState();
    }
  }

  /// 指针抬起。
  void onPointerUp(PointerUpEvent event) {
    activePointers.remove(event.pointer);
    if (activePointers.length < 2) {
      pinchDistance = null;
      pinchAngle = null;
    }
  }

  /// 指针取消。
  void onPointerCancel(PointerCancelEvent event) {
    activePointers.remove(event.pointer);
    if (activePointers.length < 2) {
      pinchDistance = null;
      pinchAngle = null;
    }
  }

  void _updatePinchState() {
    if (activePointers.length >= 2) {
      final points = activePointers.values.toList();
      final dx = points[0].dx - points[1].dx;
      final dy = points[0].dy - points[1].dy;
      pinchDistance = math.sqrt(dx * dx + dy * dy);
      pinchAngle = math.atan2(dy, dx);
    }
  }

  /// 处置资源。
  void dispose() {
    activePointers.clear();
  }
}
