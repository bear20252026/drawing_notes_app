import 'package:drawing_notes_app/features/drawing/application/editor_input_arbiter.dart'
    show EditorInputPolicy;
import 'package:drawing_notes_app/features/drawing/application/gesture_system.dart'
    as gesture;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // GestureMode / FlingDirection / ModifierKey 枚举
  // ---------------------------------------------------------------------------
  group('枚举类型', () {
    test('GestureMode 有 5 个值', () {
      expect(gesture.GestureMode.values.length, 5);
      expect(gesture.GestureMode.values, contains(gesture.GestureMode.ink));
      expect(gesture.GestureMode.values, contains(gesture.GestureMode.pan));
      expect(gesture.GestureMode.values, contains(gesture.GestureMode.zoom));
      expect(gesture.GestureMode.values, contains(gesture.GestureMode.rotate));
      expect(gesture.GestureMode.values, contains(gesture.GestureMode.idle));
    });

    test('FlingDirection 有 5 个值', () {
      expect(gesture.FlingDirection.values.length, 5);
      expect(gesture.FlingDirection.values, contains(gesture.FlingDirection.left));
      expect(
          gesture.FlingDirection.values, contains(gesture.FlingDirection.right));
      expect(gesture.FlingDirection.values, contains(gesture.FlingDirection.up));
      expect(gesture.FlingDirection.values, contains(gesture.FlingDirection.down));
      expect(
          gesture.FlingDirection.values, contains(gesture.FlingDirection.none));
    });

    test('ModifierKey 有 4 个值', () {
      expect(gesture.ModifierKey.values.length, 4);
      expect(gesture.ModifierKey.values, contains(gesture.ModifierKey.command));
      expect(gesture.ModifierKey.values, contains(gesture.ModifierKey.control));
      expect(gesture.ModifierKey.values, contains(gesture.ModifierKey.shift));
      expect(gesture.ModifierKey.values, contains(gesture.ModifierKey.option));
    });
  });

  // ---------------------------------------------------------------------------
  // GestureState
  // ---------------------------------------------------------------------------
  group('GestureState', () {
    test('初始状态为 idle', () {
      final state = gesture.GestureState();
      expect(state.mode, gesture.GestureMode.idle);
      expect(state.pinchCenter, Offset.zero);
      expect(state.initialPinchDistance, 0.0);
      expect(state.rotationAccumulator, 0.0);
      expect(state.flingVelocity, Offset.zero);
      expect(state.flingDirection, gesture.FlingDirection.none);
      expect(state.activePointerCount, 0);
    });

    test('setMode 更新手势模式', () {
      final state = gesture.GestureState();
      state.setMode(gesture.GestureMode.zoom);
      expect(state.mode, gesture.GestureMode.zoom);
      state.setMode(gesture.GestureMode.pan);
      expect(state.mode, gesture.GestureMode.pan);
    });

    test('setPinchCenter / setInitialPinchDistance', () {
      final state = gesture.GestureState();
      state.setPinchCenter(const Offset(100, 200));
      expect(state.pinchCenter, const Offset(100, 200));

      state.setInitialPinchDistance(150.0);
      expect(state.initialPinchDistance, 150.0);
    });

    test('updateRotationAccumulator 归一化到 [-π, π]', () {
      final state = gesture.GestureState();

      state.updateRotationAccumulator(1.0);
      expect(state.rotationAccumulator, closeTo(1.0, 0.001));

      // 超过 π 时归一化
      state.updateRotationAccumulator(3.0);
      expect(state.rotationAccumulator, lessThanOrEqualTo(3.14159));
      expect(state.rotationAccumulator, greaterThan(-3.14159));

      // 负向累积
      final state2 = gesture.GestureState();
      state2.updateRotationAccumulator(-4.0);
      expect(state2.rotationAccumulator, greaterThanOrEqualTo(-3.14159));
      expect(state2.rotationAccumulator, lessThan(3.14159));
    });

    test('setFlingVelocity 推导方向：右', () {
      final state = gesture.GestureState();
      state.setFlingVelocity(const Offset(100, 10));
      expect(state.flingDirection, gesture.FlingDirection.right);
    });

    test('setFlingVelocity 推导方向：左', () {
      final state = gesture.GestureState();
      state.setFlingVelocity(const Offset(-100, 10));
      expect(state.flingDirection, gesture.FlingDirection.left);
    });

    test('setFlingVelocity 推导方向：上', () {
      final state = gesture.GestureState();
      state.setFlingVelocity(const Offset(10, -100));
      expect(state.flingDirection, gesture.FlingDirection.up);
    });

    test('setFlingVelocity 推导方向：下', () {
      final state = gesture.GestureState();
      state.setFlingVelocity(const Offset(10, 100));
      expect(state.flingDirection, gesture.FlingDirection.down);
    });

    test('setFlingVelocity 速度过小 → none', () {
      final state = gesture.GestureState();
      state.setFlingVelocity(const Offset(1, 1));
      expect(state.flingDirection, gesture.FlingDirection.none);
    });

    test('addPointer / updatePointerPosition / removePointer', () {
      final state = gesture.GestureState();

      state.addPointer(1, const Offset(10, 20));
      expect(state.activePointerCount, 1);
      expect(state.isPointerActive(1), isTrue);
      expect(state.getPointerPosition(1), const Offset(10, 20));

      state.updatePointerPosition(1, const Offset(30, 40));
      expect(state.getPointerPosition(1), const Offset(30, 40));

      state.removePointer(1);
      expect(state.activePointerCount, 0);
      expect(state.isPointerActive(1), isFalse);
      expect(state.getPointerPosition(1), isNull);
    });

    test('updatePointerPosition 不更新未注册的指针', () {
      final state = gesture.GestureState();
      state.updatePointerPosition(99, const Offset(50, 60));
      expect(state.isPointerActive(99), isFalse);
    });

    test('activePointerPositions 返回所有活动指针位置', () {
      final state = gesture.GestureState();
      state.addPointer(1, const Offset(10, 20));
      state.addPointer(2, const Offset(30, 40));
      final positions = state.activePointerPositions;
      expect(positions.length, 2);
      expect(positions, contains(const Offset(10, 20)));
      expect(positions, contains(const Offset(30, 40)));
    });

    test('修饰键状态管理', () {
      final state = gesture.GestureState();
      expect(state.isCommandPressed, isFalse);
      expect(state.isControlPressed, isFalse);
      expect(state.isShiftPressed, isFalse);
      expect(state.isOptionPressed, isFalse);

      state.setModifierKey(gesture.ModifierKey.command, true);
      expect(state.isCommandPressed, isTrue);
      expect(
          state.isModifierPressed(gesture.ModifierKey.command), isTrue);

      state.setModifierKey(gesture.ModifierKey.shift, true);
      expect(state.isShiftPressed, isTrue);

      state.setModifierKey(gesture.ModifierKey.command, false);
      expect(state.isCommandPressed, isFalse);

      state.clearModifierKeys();
      expect(state.isShiftPressed, isFalse);
    });

    test('reset 清除所有状态', () {
      final state = gesture.GestureState();
      state.setMode(gesture.GestureMode.zoom);
      state.setPinchCenter(const Offset(100, 200));
      state.setInitialPinchDistance(150.0);
      state.updateRotationAccumulator(1.0);
      state.setFlingVelocity(const Offset(100, 10));
      state.addPointer(1, const Offset(10, 20));
      state.setModifierKey(gesture.ModifierKey.command, true);

      state.reset();

      expect(state.mode, gesture.GestureMode.idle);
      expect(state.pinchCenter, Offset.zero);
      expect(state.initialPinchDistance, 0.0);
      expect(state.rotationAccumulator, 0.0);
      expect(state.flingVelocity, Offset.zero);
      expect(state.flingDirection, gesture.FlingDirection.none);
      expect(state.activePointerCount, 0);
      expect(state.isCommandPressed, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // PlatformDetector
  // ---------------------------------------------------------------------------
  group('PlatformDetector', () {
    test('单例实例可访问', () {
      final detector = gesture.PlatformDetector.instance;
      expect(detector, isNotNull);
      expect(detector.platform, isA<TargetPlatform>());
    });

    test('isMacOS / isWindows / isLinux 最多一个为 true', () {
      final detector = gesture.PlatformDetector.instance;
      final desktopCount = [
        detector.isMacOS,
        detector.isWindows,
        detector.isLinux,
      ].where((b) => b).length;
      // 桌面环境下恰好一个为 true；移动环境下全部为 false
      expect(desktopCount, lessThanOrEqualTo(1));
    });

    test('isDesktop / isMobile 互斥', () {
      final detector = gesture.PlatformDetector.instance;
      expect(detector.isDesktop || detector.isMobile, isTrue);
      expect(detector.isDesktop && detector.isMobile, isFalse);
    });

    test('commandModifierKey 返回正确修饰键', () {
      final detector = gesture.PlatformDetector.instance;
      final key = detector.commandModifierKey;
      if (detector.isMacOS) {
        expect(key, gesture.ModifierKey.command);
      } else {
        expect(key, gesture.ModifierKey.control);
      }
    });

    test('toLogicalKey 映射正确', () {
      final detector = gesture.PlatformDetector.instance;

      expect(detector.toLogicalKey(gesture.ModifierKey.control),
          LogicalKeyboardKey.control);
      expect(detector.toLogicalKey(gesture.ModifierKey.shift),
          LogicalKeyboardKey.shift);
      expect(detector.toLogicalKey(gesture.ModifierKey.option),
          LogicalKeyboardKey.alt);

      if (detector.isMacOS) {
        expect(detector.toLogicalKey(gesture.ModifierKey.command),
            LogicalKeyboardKey.meta);
      } else {
        expect(detector.toLogicalKey(gesture.ModifierKey.command),
            LogicalKeyboardKey.control);
      }
    });

    test('fromLogicalKey 反向映射正确', () {
      final detector = gesture.PlatformDetector.instance;

      expect(detector.fromLogicalKey(LogicalKeyboardKey.shift),
          gesture.ModifierKey.shift);
      expect(detector.fromLogicalKey(LogicalKeyboardKey.alt),
          gesture.ModifierKey.option);

      expect(detector.fromLogicalKey(LogicalKeyboardKey.keyA), isNull);
    });

    test('formatModifierKeys 格式化空集合', () {
      final detector = gesture.PlatformDetector.instance;
      expect(detector.formatModifierKeys({}), '无');
    });

    test('formatModifierKeys 格式化多个修饰键', () {
      final detector = gesture.PlatformDetector.instance;
      final formatted = detector.formatModifierKeys(
          {gesture.ModifierKey.shift, gesture.ModifierKey.control});
      expect(formatted, contains('Shift'));
      expect(formatted, contains('Ctrl'));
    });
  });

  // ---------------------------------------------------------------------------
  // FlingAnimator
  // ---------------------------------------------------------------------------
  group('FlingAnimator', () {
    test('初始状态不动画', () {
      final animator = gesture.FlingAnimator(onUpdate: (_) {});
      expect(animator.isAnimating, isFalse);
      expect(animator.currentVelocity, Offset.zero);
    });

    test('start 启动动画', () {
      final animator = gesture.FlingAnimator(onUpdate: (_) {});
      animator.start(const Offset(100, 0));
      expect(animator.isAnimating, isTrue);
      expect(animator.currentVelocity, const Offset(100, 0));
    });

    test('cancel 停止动画', () {
      final animator = gesture.FlingAnimator(onUpdate: (_) {});
      animator.start(const Offset(100, 0));
      animator.cancel();
      expect(animator.isAnimating, isFalse);
    });

    test('start 两次会取消前一次', () {
      final animator = gesture.FlingAnimator(onUpdate: (_) {});
      animator.start(const Offset(100, 0));
      animator.start(const Offset(200, 0));
      expect(animator.isAnimating, isTrue);
      expect(animator.currentVelocity, const Offset(200, 0));
    });

    test('摩擦系数在有效范围内', () {
      final animator =
          gesture.FlingAnimator(onUpdate: (_) {}, friction: 0.95);
      expect(animator.friction, closeTo(0.95, 0.001));
    });

    test('阈值在有效范围内', () {
      final animator =
          gesture.FlingAnimator(onUpdate: (_) {}, threshold: 0.5);
      expect(animator.threshold, closeTo(0.5, 0.001));
    });

    test('最大持续时间默认 300ms', () {
      final animator = gesture.FlingAnimator(onUpdate: (_) {});
      expect(animator.maxDuration, const Duration(milliseconds: 300));
    });
  });

  // ---------------------------------------------------------------------------
  // EnhancedInputArbiter
  // ---------------------------------------------------------------------------
  group('EnhancedInputArbiter', () {
    test('构造后初始状态正确', () {
      final state = gesture.GestureState();
      final policy = EditorInputPolicy(allowInk: true, allowFingerDrawing: true);
      final arbiter = gesture.EnhancedInputArbiter(
        policy: policy,
        gestureState: state,
      );

      expect(arbiter.inMultiFingerGesture, isFalse);
      expect(arbiter.policy, same(policy));
      expect(arbiter.gestureState, same(state));
    });

    test('reset 清除所有内部状态', () {
      final state = gesture.GestureState();
      final policy = EditorInputPolicy(allowInk: true, allowFingerDrawing: true);
      final arbiter = gesture.EnhancedInputArbiter(
        policy: policy,
        gestureState: state,
      );

      state.setMode(gesture.GestureMode.zoom);
      state.addPointer(1, const Offset(10, 20));
      arbiter.reset();

      expect(state.mode, gesture.GestureMode.idle);
      expect(state.activePointerCount, 0);
      expect(arbiter.inMultiFingerGesture, isFalse);
    });

    test('多指手势状态初始为 false', () {
      final state = gesture.GestureState();
      final policy = EditorInputPolicy(allowInk: true, allowFingerDrawing: false);
      final arbiter = gesture.EnhancedInputArbiter(
        policy: policy,
        gestureState: state,
      );
      expect(arbiter.inMultiFingerGesture, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // GestureState 边界条件
  // ---------------------------------------------------------------------------
  group('GestureState 边界条件', () {
    test('多次 setMode 后模式保持最新', () {
      final state = gesture.GestureState();
      state.setMode(gesture.GestureMode.ink);
      state.setMode(gesture.GestureMode.pan);
      state.setMode(gesture.GestureMode.rotate);
      expect(state.mode, gesture.GestureMode.rotate);
    });

    test('updateRotationAccumulator 精确归一化到 [-π, π]', () {
      final state = gesture.GestureState();

      // 正好等于 2π 应归一化到接近 0
      state.updateRotationAccumulator(2 * 3.141592653589793);
      expect(state.rotationAccumulator, closeTo(0, 0.001));

      // 正好等于 -2π 应归一化到接近 0
      final state2 = gesture.GestureState();
      state2.updateRotationAccumulator(-2 * 3.141592653589793);
      expect(state2.rotationAccumulator, closeTo(0, 0.001));
    });

    test('activePointerPositions 返回空列表当无指针', () {
      final state = gesture.GestureState();
      expect(state.activePointerPositions, isEmpty);
    });

    test('addPointer 使用相同 ID 覆盖', () {
      final state = gesture.GestureState();
      state.addPointer(1, const Offset(10, 20));
      state.addPointer(1, const Offset(50, 60));
      expect(state.activePointerCount, 1);
      expect(state.getPointerPosition(1), const Offset(50, 60));
    });

    test('removePointer 不存在的指针不抛异常', () {
      final state = gesture.GestureState();
      expect(() => state.removePointer(999), returnsNormally);
    });

    test('setFlingVelocity 精确 45 度方向判定', () {
      final state = gesture.GestureState();
      // x 和 y 速度相等 → 实现先检查 dy，dy.abs() >= dx.abs() 时取垂直方向
      state.setFlingVelocity(const Offset(100, 100));
      expect(state.flingDirection, gesture.FlingDirection.down);

      final state2 = gesture.GestureState();
      state2.setFlingVelocity(const Offset(-100, -100));
      expect(state2.flingDirection, gesture.FlingDirection.up);

      final state3 = gesture.GestureState();
      state3.setFlingVelocity(const Offset(200, 100));
      expect(state3.flingDirection, gesture.FlingDirection.right);
    });

    test('isModifierPressed 检查所有修饰键组合', () {
      final state = gesture.GestureState();
      state
        ..setModifierKey(gesture.ModifierKey.command, true)
        ..setModifierKey(gesture.ModifierKey.shift, true);

      expect(state.isModifierPressed(gesture.ModifierKey.command), isTrue);
      expect(state.isModifierPressed(gesture.ModifierKey.shift), isTrue);
      expect(state.isModifierPressed(gesture.ModifierKey.control), isFalse);
      expect(state.isModifierPressed(gesture.ModifierKey.option), isFalse);
    });
  });
}
