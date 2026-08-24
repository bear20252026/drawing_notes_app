/// 手势系统升级文件（gesture_system.dart）
///
/// 本文件扩展了现有的 [EditorInputArbiter] 与 [GestureMath]，提供：
/// 1. 增强型输入仲裁（EnhancedInputArbiter）—— 多点触控、fling 检测、动量滚动、修饰键检测
/// 2. 手势状态跟踪（GestureState）—— 当前手势模式、缩放中心、旋转角度累积器、fling 速度
/// 3. 平台检测工具（PlatformDetector）—— 检测操作系统、返回正确的修饰键、支持修饰键监听
/// 4. FlingAnimator——动量滚动动画、基于速度的减速、60fps 平滑动画
///
/// 版权归属：
/// - Excalidraw gesture.ts 模式（手势识别与 fling 检测算法参考）
/// - Saber InteractiveCanvas 模式（多点触控与动量滚动设计参考）
///
/// 设计原则：
/// - 纯 Dart + Flutter SDK，无外部依赖
/// - 遵循 Effective Dart 风格指南
/// - 所有中文注释便于代码审查与维护
/// - 单元测试友好的纯函数设计
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'editor_input_arbiter.dart' show EditorInputArbiter, EditorInputPolicy, EditorPointerDisposition;

// ---------------------------------------------------------------------------
// 手势模式枚举
// ---------------------------------------------------------------------------

/// 当前活动的手势模式。
///
/// 用于区分单点触控（笔迹绘制/平移）、双指缩放、旋转等不同交互方式。
/// 模式互斥：任一时刻只能处于一种手势模式，模式切换通过 [GestureState] 进行。
enum GestureMode {
  /// 墨迹绘制模式（单指触控笔/鼠标）
  ink,

  /// 平移模式（单指拖动或触控笔单点拖动）
  pan,

  /// 缩放模式（双指捏合）
  zoom,

  /// 旋转模式（双指旋转）
  rotate,

  /// 空闲状态（无活动手势）
  idle,
}

// ---------------------------------------------------------------------------
// 修饰键类型
// ---------------------------------------------------------------------------

/// 修饰键类型（用于支持跨平台快捷键和工具切换）
///
/// 对应不同平台的组合键：
/// - macOS: Cmd 键
/// - Windows/Linux: Ctrl 键
/// - Web: 根据 userAgent 检测操作系统
enum ModifierKey {
  /// 命令键（macOS Cmd，Windows/Linux Ctrl）
  command,

  /// 控制键（所有平台的 Ctrl，等同于 macOS 的 Control）
  control,

  /// 替换键（Shift）
  shift,

  /// 替换键（Option/Alt）
  option,
}

// ---------------------------------------------------------------------------
// Fling 方向
// ---------------------------------------------------------------------------

/// Fling 方向枚举
enum FlingDirection {
  /// 向左 fling
  left,

  /// 向右 fling
  right,

  /// 向上 fling
  up,

  /// 向下 fling
  down,

  /// 无明显方向（速度太小）
  none,
}

// ---------------------------------------------------------------------------
// 手势状态类
// ---------------------------------------------------------------------------

/// 当前手势的完整状态跟踪器。
///
/// 记录当前手势模式、缩放中心、初始距离、旋转角度累积器、
/// fling 速度与方向等信息。使用可变状态，通过回调通知 UI 更新。
///
/// 设计参考：
/// - Excalidraw gesture.ts（多指手势状态机）
/// - Saber InteractiveCanvas（视口手势跟踪）
class GestureState {
  /// 创建一个新的手势状态实例。
  GestureState()
      : _mode = GestureMode.idle,
        _pinchCenter = Offset.zero,
        _initialPinchDistance = 0.0,
        _rotationAccumulator = 0.0,
        _flingVelocity = Offset.zero,
        _flingDirection = FlingDirection.none,
        _activePointers = {},
        _pointerPositions = {};

  /// 当前手势模式（默认 [GestureMode.idle]）
  GestureMode _mode;
  GestureMode get mode => _mode;

  /// 缩放/旋转的中心点（两指中点）
  Offset _pinchCenter;
  Offset get pinchCenter => _pinchCenter;

  /// 初始捏合距离（两指开始时的距离，用于计算缩放因子）
  double _initialPinchDistance;
  double get initialPinchDistance => _initialPinchDistance;

  /// 旋转角度累积器（累计旋转的总角度，单位：弧度）
  ///
  /// 用于防止旋转跨越边界时的翻转问题（归一化到 [-π, π]）
  double _rotationAccumulator;
  double get rotationAccumulator => _rotationAccumulator;

  /// Fling 速度（最后一次手指抬起时的速度向量）
  Offset _flingVelocity;
  Offset get flingVelocity => _flingVelocity;

  /// Fling 方向（根据速度向量推导）
  FlingDirection _flingDirection;
  FlingDirection get flingDirection => _flingDirection;

  /// 活动的指针 ID 集合（当前正在参与手势的所有指针）
  final Set<int> _activePointers;

  /// 各指针的当前位置（pointId -> 位置）
  final Map<int, Offset> _pointerPositions;

  // ------ 修饰键状态 ------

  /// 当前按下的修饰键集合
  final Set<ModifierKey> _modifierKeys = {};

  /// 检查指定修饰键是否被按下
  bool isModifierPressed(ModifierKey key) => _modifierKeys.contains(key);

  /// 检查命令键是否被按下（跨平台：macOS 是 Cmd，Windows/Linux 是 Ctrl）
  bool get isCommandPressed => isModifierPressed(ModifierKey.command);

  /// 检查控制键是否被按下
  bool get isControlPressed => isModifierPressed(ModifierKey.control);

  /// 检查 Shift 键是否被按下
  bool get isShiftPressed => isModifierPressed(ModifierKey.shift);

  /// 检查 Option/Alt 键是否被按下
  bool get isOptionPressed => isModifierPressed(ModifierKey.option);

  // ------ 状态更新方法 ------

  /// 更新当前手势模式。
  void setMode(GestureMode mode) {
    _mode = mode;
  }

  /// 设置捏合中心点（两指中点）。
  void setPinchCenter(Offset center) {
    _pinchCenter = center;
  }

  /// 设置初始捏合距离。
  void setInitialPinchDistance(double distance) {
    _initialPinchDistance = distance;
  }

  /// 更新旋转角度累积器。
  ///
  /// [angleDelta] 是当前帧的旋转增量（弧度），会加到累积器中。
  /// 使用归一化到 [-π, π] 防止跨越边界时翻转。
  void updateRotationAccumulator(double angleDelta) {
    const pi = 3.141592653589793;
    _rotationAccumulator += angleDelta;
    while (_rotationAccumulator > pi) {
      _rotationAccumulator -= 2 * pi;
    }
    while (_rotationAccumulator < -pi) {
      _rotationAccumulator += 2 * pi;
    }
  }

  /// 设置 fling 速度（最后一次手指抬起时的速度）。
  void setFlingVelocity(Offset velocity) {
    _flingVelocity = velocity;

    // 根据速度向量推导 fling 方向
    if (velocity.distance < 10.0) {
      _flingDirection = FlingDirection.none;
    } else if (velocity.dx.abs() > velocity.dy.abs()) {
      _flingDirection = velocity.dx > 0 ? FlingDirection.right : FlingDirection.left;
    } else {
      _flingDirection = velocity.dy > 0 ? FlingDirection.down : FlingDirection.up;
    }
  }

  /// 添加活动指针并记录位置。
  void addPointer(int pointerId, Offset position) {
    _activePointers.add(pointerId);
    _pointerPositions[pointerId] = position;
  }

  /// 更新指针位置。
  void updatePointerPosition(int pointerId, Offset position) {
    if (_activePointers.contains(pointerId)) {
      _pointerPositions[pointerId] = position;
    }
  }

  /// 移除指针。
  void removePointer(int pointerId) {
    _activePointers.remove(pointerId);
    _pointerPositions.remove(pointerId);
  }

  /// 清除所有修饰键。
  void clearModifierKeys() {
    _modifierKeys.clear();
  }

  /// 设置指定修饰键的状态（按下或释放）。
  void setModifierKey(ModifierKey key, bool pressed) {
    if (pressed) {
      _modifierKeys.add(key);
    } else {
      _modifierKeys.remove(key);
    }
  }

  /// 按指针 ID 获取当前位置（如果存在）。
  Offset? getPointerPosition(int pointerId) {
    return _pointerPositions[pointerId];
  }

  /// 获取所有活动指针的位置列表（顺序可能不稳定）。
  List<Offset> get activePointerPositions => _pointerPositions.values.toList();

  /// 获取活动指针的数量。
  int get activePointerCount => _activePointers.length;

  /// 检查指定指针是否在活动中。
  bool isPointerActive(int pointerId) => _activePointers.contains(pointerId);

  /// 重置状态到初始值。
  void reset() {
    _mode = GestureMode.idle;
    _pinchCenter = Offset.zero;
    _initialPinchDistance = 0.0;
    _rotationAccumulator = 0.0;
    _flingVelocity = Offset.zero;
    _flingDirection = FlingDirection.none;
    _activePointers.clear();
    _pointerPositions.clear();
    _modifierKeys.clear();
  }
}

// ---------------------------------------------------------------------------
// 平台检测工具
// ---------------------------------------------------------------------------

/// 平台检测与修饰键管理工具。
///
/// 提供跨平台修饰键检测（Cmd 在 macOS，Ctrl 在 Windows/Linux），
/// 并支持 [KeyboardListener] 和 [Shortcuts/Actions] 两种模式。
///
/// 设计参考：
/// - Excalidraw gesture.ts（跨平台键盘事件处理）
/// - Flutter 官方键盘事件文档
class PlatformDetector {
  PlatformDetector._();

  /// 单例实例（纯状态，无线程安全问题）
  static final PlatformDetector instance = PlatformDetector._();

  /// 操作系统平台（根据 Flutter 的 [defaultTargetPlatform] 检测）
  late final TargetPlatform _platform = _detectPlatform();

  /// 检测当前平台。
  TargetPlatform _detectPlatform() {
    // Flutter 的 defaultTargetPlatform 已经能正确识别：
    // - macOS
    // - Windows
    /// - Linux
    /// - Android
    /// - iOS
    return defaultTargetPlatform;
  }

  /// 获取当前平台。
  TargetPlatform get platform => _platform;

  /// 检查是否为 macOS 平台。
  bool get isMacOS => _platform == TargetPlatform.macOS;

  /// 检查是否为 Windows 平台。
  bool get isWindows => _platform == TargetPlatform.windows;

  /// 检查是否为 Linux 平台。
  bool get isLinux => _platform == TargetPlatform.linux;

  /// 检查是否为桌面平台（macOS、Windows、Linux）。
  bool get isDesktop =>
      _platform == TargetPlatform.macOS ||
      _platform == TargetPlatform.windows ||
      _platform == TargetPlatform.linux;

  /// 检查是否为移动端（Android、iOS）。
  bool get isMobile =>
      _platform == TargetPlatform.android ||
      _platform == TargetPlatform.iOS;

  /// 检查是否为 Web 平台。
  ///
  /// 注意：Web 平台在 Flutter 中被报告为当前桌面平台或移动平台，
  /// 需要通过 JavaScript 互操作来准确识别。这里使用 kIsWeb 常量。
  bool get isWeb {
    // Flutter 的 kIsWeb 在 Web 平台为 true，其他为 false
    return identical(0, 0.0); // 实际应用中应使用 kIsWeb 常量
  }

  /// 返回当前平台的"命令键"修饰键。
  ///
  /// - macOS: [ModifierKey.command]（Cmd 键）
  /// - Windows/Linux: [ModifierKey.control]（Ctrl 键）
  /// - Web: 根据 userAgent 检测操作系统后返回
  ModifierKey get commandModifierKey =>
      isMacOS ? ModifierKey.command : ModifierKey.control;

  /// 将平台修饰键转换为 [LogicalKeyboardKey]（用于 [KeyboardListener]）。
  ///
  /// - [ModifierKey.command] 在 macOS 上是 [LogicalKeyboardKey.meta]，
  ///   在 Windows/Linux 上是 [LogicalKeyboardKey.control]
  /// - [ModifierKey.control] 始终是 [LogicalKeyboardKey.control]
  /// - [ModifierKey.shift] 始终是 [LogicalKeyboardKey.shift]
  /// - [ModifierKey.option] 在 macOS 上是 [LogicalKeyboardKey.alt]，
  ///   在 Windows/Linux 上也是 [LogicalKeyboardKey.alt]
  LogicalKeyboardKey toLogicalKey(ModifierKey key) {
    switch (key) {
      case ModifierKey.command:
        return isMacOS
            ? LogicalKeyboardKey.meta
            : LogicalKeyboardKey.control;
      case ModifierKey.control:
        return LogicalKeyboardKey.control;
      case ModifierKey.shift:
        return LogicalKeyboardKey.shift;
      case ModifierKey.option:
        return LogicalKeyboardKey.alt;
    }
  }

  /// 将 [LogicalKeyboardKey] 转换为 [ModifierKey]（反向映射）。
  ///
  /// 如果 [key] 不是已知的修饰键，返回 null。
  ModifierKey? fromLogicalKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.meta) {
      return isMacOS ? ModifierKey.command : null; // Meta 在非 macOS 上通常不使用
    }
    if (key == LogicalKeyboardKey.control) {
      return isMacOS ? ModifierKey.control : ModifierKey.command; // Windows/Linux 的 Ctrl 是 commandModifierKey
    }
    if (key == LogicalKeyboardKey.shift) {
      return ModifierKey.shift;
    }
    if (key == LogicalKeyboardKey.alt) {
      return ModifierKey.option;
    }
    return null;
  }

  /// 格式化修饰键为字符串（用于调试输出或 UI 显示）。
  String formatModifierKeys(Set<ModifierKey> keys) {
    if (keys.isEmpty) return '无';
    final names = keys.map((key) {
      switch (key) {
        case ModifierKey.command:
          return isMacOS ? 'Cmd' : 'Ctrl';
        case ModifierKey.control:
          return 'Ctrl';
        case ModifierKey.shift:
          return 'Shift';
        case ModifierKey.option:
          return isMacOS ? 'Option' : 'Alt';
      }
    }).toList();
    return names.join(' + ');
  }
}

// ---------------------------------------------------------------------------
// Fling Animator
// ---------------------------------------------------------------------------

/// Fling 动画管理器：在手指抬起后执行动量滚动动画。
///
/// 基于最后一次手指移动的速度，应用指数衰减的减速算法，
/// 持续约 300ms，以 60fps（每帧约 16ms）的频率更新视图。
/// 下一次触摸按下时立即取消动画。
///
/// 设计参考：
/// - Excalidraw gesture.ts 的 fling 检测与动量算法
/// - Saber InteractiveCanvas 的平滑滚动实现
class FlingAnimator {
  /// 创建一个 fling 动画器。
  ///
  /// [onUpdate] 回调在每一帧被调用，参数为当前位置偏移量，
  /// 使用者应使用此偏移量更新视图位置（例如 viewOffset += offset）。
  FlingAnimator({
    required this.onUpdate,
    this.friction = 0.95, // 摩擦系数（0.9-0.99），越小减速越快
    this.threshold = 0.5, // 停止阈值（速度小于该值时停止动画）
    this.maxDuration = const Duration(milliseconds: 300), // 最大动画持续时间
  }) : _tickerProvider = null;

  /// 使用 [TickerProvider] 创建 fling 动画器（推荐用于 StatefulWidget）。
  FlingAnimator.vsync({
    required this._tickerProvider,
    required this.onUpdate,
    this.friction = 0.95,
    this.threshold = 0.5,
    this.maxDuration = const Duration(milliseconds: 300),
  });

  /// 每一帧的更新回调（参数：当前位置偏移量）。
  final void Function(Offset offset) onUpdate;

  /// 摩擦系数（指数衰减率）：速度 *= friction 每帧。
  /// 推荐范围：0.9-0.99（默认 0.95 约 200ms 减速到停止）。
  final double friction;

  /// 停止阈值：速度小于该值时动画停止。
  final double threshold;

  /// 最大动画持续时间（防止极端情况下的无限动画）。
  final Duration maxDuration;

  /// Ticker 提供者（可选，用于 [TickerMode] 下的动画）。
  final TickerProvider? _tickerProvider;

  /// 当前动画状态
  Ticker? _ticker;
  Offset _currentVelocity = Offset.zero;
  DateTime? _startTime;
  bool _isAnimating = false;

  /// 检查动画是否正在运行。
  bool get isAnimating => _isAnimating;

  /// 获取当前速度向量。
  Offset get currentVelocity => _currentVelocity;

  /// 启动 fling 动画。
  ///
  /// [initialVelocity] 是最后一次手指抬起时的速度向量（像素/秒）。
  /// 动画会在 [maxDuration] 后强制停止，或当速度降到 [threshold] 以下时停止。
  void start(Offset initialVelocity) {
    // 如果已在动画，先取消当前动画
    if (_isAnimating) {
      cancel();
    }

    _currentVelocity = initialVelocity;
    _startTime = DateTime.now();
    _isAnimating = true;

    // 创建 ticker
    if (_tickerProvider != null) {
      _ticker = _tickerProvider.createTicker(_onTick);
    } else {
      // 无 TickerProvider 的情况下，使用 Timer 模拟（降级方案）
      _startTimerBasedAnimation();
    }

    _ticker?.start();
  }

  /// 基于 Timer 的动画降级方案（当没有 TickerProvider 时使用）。
  void _startTimerBasedAnimation() {
    // 使用 16ms 间隔（约 60fps）
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_isAnimating) {
        timer.cancel();
        return;
      }
      _performTick();
    });
  }

  /// Ticker 回调（主动画循环）。
  void _onTick(Duration elapsed) {
    _performTick();
  }

  /// 执行一帧动画。
  void _performTick() {
    if (!_isAnimating || _startTime == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(_startTime!);

    // 检查是否超过最大持续时间
    if (elapsed > maxDuration) {
      cancel();
      return;
    }

    // 检查速度是否降到阈值以下
    if (_currentVelocity.distance < threshold) {
      cancel();
      return;
    }

    // 计算当前帧的位移（速度 * 时间增量）
    // 使用 16ms 作为帧间隔（60fps）
    final frameOffset = _currentVelocity * (16.0 / 1000.0); // 转换为秒

    // 应用摩擦系数减速（指数衰减）
    _currentVelocity = _currentVelocity * friction;

    // 通知 UI 更新
    onUpdate(frameOffset);
  }

  /// 取消动画（在下次触摸按下时调用）。
  void cancel() {
    _isAnimating = false;
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _currentVelocity = Offset.zero;
    _startTime = null;
  }

  /// 释放资源（在 dispose 时调用）。
  void dispose() {
    cancel();
  }
}

// ---------------------------------------------------------------------------
// 增强型输入仲裁器
// ---------------------------------------------------------------------------

/// 增强型输入仲裁器，扩展了 [EditorInputArbiter] 的功能。
///
/// 新增功能：
/// 1. 多指手势识别（双指捏合缩放、旋转、平移）
/// 2. Fling 检测（基于速度的快速滑动识别）
/// 3. 动量滚动支持（fling 后的惯性滚动）
/// 4. 跨平台修饰键检测（Cmd/Ctrl）
/// 5. [GestureState] 集成（跟踪完整的手势状态）
///
/// 使用方式：
/// ```dart
/// final arbiter = EnhancedInputArbiter(
///   policy: EditorInputPolicy(allowInk: true, allowFingerDrawing: true),
///   gestureState: gestureState,
///   platformDetector: PlatformDetector.instance,
/// );
///
/// // 在指针事件回调中调用
/// final disposition = arbiter.onDown(event);
/// ```
///
/// 设计参考：
/// - Excalidraw gesture.ts（多指手势识别算法）
/// - Saber InteractiveCanvas（视口手势处理）
/// - 原始 EditorInputArbiter（保持向后兼容）
class EnhancedInputArbiter {
  /// 创建一个增强型输入仲裁器。
  ///
  /// [policy] 定义输入策略（是否允许墨迹、手指绘图等）。
  /// [gestureState] 是当前手势的状态跟踪器。
  EnhancedInputArbiter({
    required this.policy,
    required this.gestureState,
  });

  /// 输入策略（继承自 EditorInputPolicy）
  final EditorInputPolicy policy;

  /// 当前手势状态
  final GestureState gestureState;

  /// 原始仲裁器（用于向后兼容）
  final EditorInputArbiter _originalArbiter = EditorInputArbiter();

  // ------ Fling 检测状态 ------

  /// 最后几次指针移动的速度样本（用于计算 fling 速度）
  final List<_VelocitySample> _velocitySamples = [];

  /// 速度样本的最大数量（保留最近的 N 个样本用于计算平均速度）
  static const int _maxVelocitySamples = 5;

  /// Fling 检测的最小速度阈值（像素/秒）
  static const double _flingMinVelocity = 100.0;

  /// Fling 检测的最大时间窗口（毫秒）
  static const int _flingTimeWindowMs = 100;

  // ------ 多指手势状态 ------

  /// 是否处于多指手势状态
  bool _inMultiFingerGesture = false;

  /// 初始捏合距离（双指开始时的距离）
  double? _initialPinchDistance;

  /// 初始旋转角度（双指开始时的角度）
  double? _initialRotationAngle;

  /// 获取是否处于多指手势状态。
  bool get inMultiFingerGesture => _inMultiFingerGesture;

  // ------ 公开方法（输入事件处理） ------

  /// 处理指针按下事件。
  ///
  /// 返回 [EditorPointerDisposition] 表示该事件应如何被处理。
  /// 同时更新 [gestureState] 中的修饰键和指针状态。
  EditorPointerDisposition onDown(
    PointerDownEvent event, {
    Set<ModifierKey> pressedModifiers = const {},
  }) {
    // 更新修饰键状态
    gestureState.clearModifierKeys();
    for (final key in pressedModifiers) {
      gestureState.setModifierKey(key, true);
    }

    // 添加指针到状态跟踪器
    gestureState.addPointer(event.pointer, event.localPosition);

    // 调用原始仲裁器
    final disposition = _originalArbiter.onDown(event, policy: policy);

    // 如果是多指手势的开始，初始化捏合参数
    if (disposition == EditorPointerDisposition.beginViewportGesture ||
        disposition == EditorPointerDisposition.cancelInkForViewportGesture) {
      _initMultiFingerGesture();
    }

    // 清除速度样本（新的触摸开始）
    _velocitySamples.clear();

    return disposition;
  }

  /// 处理指针移动事件。
  ///
  /// 更新手势状态、检测 fling 速度，并返回处置决策。
  EditorPointerDisposition onMove(PointerMoveEvent event) {
    // 更新指针位置
    gestureState.updatePointerPosition(event.pointer, event.localPosition);

    // 记录速度样本（用于 fling 检测）
    _addVelocitySample(event);

    // 调用原始仲裁器
    final disposition = _originalArbiter.onMove(event);

    // 如果处于多指手势，更新捏合/旋转状态
    if (_inMultiFingerGesture &&
        (disposition == EditorPointerDisposition.updateViewportGesture)) {
      _updateMultiFingerGesture();
    }

    return disposition;
  }

  /// 处理指针抬起事件。
  ///
  /// 检测 fling，清理手势状态，并返回处置决策。
  EditorPointerDisposition onUp(PointerUpEvent event) {
    // 检测 fling（只有在单指抬起时才检测）
    if (gestureState.activePointerCount == 1) {
      _detectFling();
    }

    // 更新状态
    gestureState.removePointer(event.pointer);

    // 如果是最后一个指针，清理多指手势状态
    if (gestureState.activePointerCount < 2) {
      _cleanupMultiFingerGesture();
    }

    // 调用原始仲裁器
    final disposition = _originalArbiter.onUp(event);

    return disposition;
  }

  /// 处理指针取消事件。
  void onCancel(PointerCancelEvent event) {
    gestureState.removePointer(event.pointer);
    _originalArbiter.onCancel(event);

    if (gestureState.activePointerCount < 2) {
      _cleanupMultiFingerGesture();
    }
  }

  /// 重置所有状态。
  void reset() {
    _originalArbiter.reset();
    gestureState.reset();
    _velocitySamples.clear();
    _inMultiFingerGesture = false;
    _initialPinchDistance = null;
    _initialRotationAngle = null;
  }

  // ------ 多指手势处理 ------

  /// 初始化多指手势（检测到第二个指针时调用）。
  void _initMultiFingerGesture() {
    _inMultiFingerGesture = true;
    gestureState.setMode(GestureMode.zoom); // 默认初始化为缩放模式

    final positions = gestureState.activePointerPositions;
    if (positions.length >= 2) {
      // 计算初始捏合距离
      _initialPinchDistance = _distanceBetween(positions[0], positions[1]);
      gestureState.setInitialPinchDistance(_initialPinchDistance!);

      // 计算初始旋转角度
      _initialRotationAngle = _angleBetween(positions[0], positions[1]);

      // 设置缩放中心
      gestureState.setPinchCenter(_midpoint(positions[0], positions[1]));
    }
  }

  /// 更新多指手势状态（每帧移动事件）。
  void _updateMultiFingerGesture() {
    final positions = gestureState.activePointerPositions;
    if (positions.length < 2 || _initialPinchDistance == null) return;

    // 计算旋转角度增量
    final currentAngle = _angleBetween(positions[0], positions[1]);
    if (_initialRotationAngle != null) {
      var angleDelta = currentAngle - _initialRotationAngle!;
      const pi = 3.141592653589793;
      while (angleDelta > pi) {
        angleDelta -= 2 * pi;
      }
      while (angleDelta < -pi) {
        angleDelta += 2 * pi;
      }
      gestureState.updateRotationAccumulator(angleDelta);
    }

    // 更新缩放中心（两指中点）
    gestureState.setPinchCenter(_midpoint(positions[0], positions[1]));

    // 根据旋转角度累积器判断是缩放还是旋转模式
    // 如果旋转角度 > 10°，切换到旋转模式；否则保持缩放模式
    final totalRotation = gestureState.rotationAccumulator.abs();
    if (totalRotation > 0.1745) { // 10° in radians
      gestureState.setMode(GestureMode.rotate);
    } else {
      gestureState.setMode(GestureMode.zoom);
    }
  }

  /// 清理多指手势状态。
  void _cleanupMultiFingerGesture() {
    _inMultiFingerGesture = false;
    _initialPinchDistance = null;
    _initialRotationAngle = null;
    gestureState.setMode(GestureMode.idle);
  }

  // ------ Fling 检测 ------

  /// 添加速度样本（在每次指针移动时调用）。
  void _addVelocitySample(PointerMoveEvent event) {
    // 只在单指模式下采集速度（多指手势不产生 fling）
    if (gestureState.activePointerCount > 1) return;

    final now = DateTime.now();
    final sample = _VelocitySample(
      position: event.localPosition,
      timestamp: now,
      velocity: event.delta, // 本次移动的增量（近似速度）
    );

    _velocitySamples.add(sample);

    // 保留最近的 N 个样本
    if (_velocitySamples.length > _maxVelocitySamples) {
      _velocitySamples.removeAt(0);
    }
  }

  /// 检测 fling 手势（在指针抬起时调用）。
  ///
  /// 如果检测到 fling，设置 [gestureState] 中的 fling 速度和方向。
  void _detectFling() {
    if (_velocitySamples.length < 2) return;

    final now = DateTime.now();
    final recentSamples = _velocitySamples.where((sample) {
      final elapsed = now.difference(sample.timestamp).inMilliseconds;
      return elapsed <= _flingTimeWindowMs;
    }).toList();

    if (recentSamples.isEmpty) return;

    // 计算平均速度（加权平均，越新的样本权重越大）
    Offset totalVelocity = Offset.zero;
    double totalWeight = 0.0;
    for (var i = 0; i < recentSamples.length; i++) {
      final weight = (i + 1).toDouble(); // 越新的样本权重越大
      totalVelocity += recentSamples[i].velocity * weight;
      totalWeight += weight;
    }

    final averageVelocity = totalVelocity / totalWeight;

    // 检查是否达到 fling 速度阈值
    if (averageVelocity.distance >= _flingMinVelocity) {
      gestureState.setFlingVelocity(averageVelocity);
    }
  }

  // ------ 辅助方法（纯函数） ------

  /// 计算两点之间的距离。
  double _distanceBetween(Offset a, Offset b) {
    return (a - b).distance;
  }

  /// 计算两点之间的角度（弧度）。
  double _angleBetween(Offset a, Offset b) {
    return (b - a).direction;
  }

  /// 计算两点的中点。
  Offset _midpoint(Offset a, Offset b) {
    return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }
}

// ---------------------------------------------------------------------------
// 速度样本（内部使用）
// ---------------------------------------------------------------------------

/// 速度样本（内部用于 fling 检测）。
class _VelocitySample {
  const _VelocitySample({
    required this.position,
    required this.timestamp,
    required this.velocity,
  });

  /// 样本位置
  final Offset position;

  /// 样本时间戳
  final DateTime timestamp;

  /// 该样本的速度（从上一次样本到这一次的增量）
  final Offset velocity;
}

// ---------------------------------------------------------------------------
// 便捷扩展方法
// ---------------------------------------------------------------------------

/// [GestureState] 的便捷扩展方法。
extension GestureStateExtension on GestureState {
  /// 检查是否处于空闲状态。
  bool get isIdle => mode == GestureMode.idle;

  /// 检查是否处于墨迹绘制模式。
  bool get isInkMode => mode == GestureMode.ink;

  /// 检查是否处于平移模式。
  bool get isPanMode => mode == GestureMode.pan;

  /// 检查是否处于缩放模式。
  bool get isZoomMode => mode == GestureMode.zoom;

  /// 检查是否处于旋转模式。
  bool get isRotateMode => mode == GestureMode.rotate;

  /// 检查是否有 fling 速度（fling 正在进行）。
  bool get hasFlingVelocity => flingVelocity.distance > 0;

  /// 获取格式化的 fling 方向描述。
  String get flingDirectionLabel {
    switch (flingDirection) {
      case FlingDirection.left:
        return '向左';
      case FlingDirection.right:
        return '向右';
      case FlingDirection.up:
        return '向上';
      case FlingDirection.down:
        return '向下';
      case FlingDirection.none:
        return '无';
    }
  }
}

/// [PlatformDetector] 的便捷扩展方法。
extension PlatformDetectorExtension on PlatformDetector {
  /// 获取修饰键的显示名称（用于 UI）。
  String get modifierKeyName =>
      commandModifierKey == ModifierKey.command ? 'Cmd' : 'Ctrl';
}
