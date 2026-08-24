// 渲染引擎单元测试——Shader 效果加载器（MarkerShader / BrushShader）。
//
// 验证 GPU 着色器加载器契约：
// - 未初始化时 create() 安全返回 null（不崩溃、优雅降级）
// - init() 加载 shaders/*.frag 成功（flutter test 会打包 assets）
// - isReady 状态一致性
// - create() 绑定 uniform 参数并返回可用 FragmentShader
// - 重复 init 幂等
//
// uniform 绑定顺序契约（源码核对）：
//   MarkerShader: uColor(3) → uGrainScale(1) → uOpacity(1)   → 索引 0..4
//   BrushShader:  uColor(3) → uGrainScale(1) → uOpacity(1) → uWidth(1) → 索引 0..5
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/rendering/brush_shader.dart';
import 'package:drawing_notes_app/core/rendering/marker_shader.dart';

void main() {
  group('MarkerShader（荧光笔着色器）', () {
    test('未初始化时 create 返回 null 而非抛异常', () {
      // 本文件隔离 isolate 中首个用例：_program 尚为 null
      final shader = MarkerShader.create(
        color: const Color(0xFFFFFF00),
        grainScale: 8,
        opacity: 0.5,
      );
      expect(shader, isNull);
    });

    test('init() 加载成功且 isReady 为 true', () async {
      await MarkerShader.init();
      expect(MarkerShader.isReady, isTrue,
          reason: 'shaders/marker.frag 在 pubspec assets 中注册，应能加载');
    });

    test('init 后 create 返回已绑定 uniform 的 FragmentShader', () async {
      await MarkerShader.init();
      final shader = MarkerShader.create(
        color: const Color(0x80FFEB3B),
        grainScale: 6,
        opacity: 0.45,
      );
      expect(shader, isNotNull);
    });

    test('create 多次调用参数不同均成功（uniform 重绑定）', () async {
      await MarkerShader.init();
      for (final grain in [2.0, 6.0, 12.0]) {
        final shader = MarkerShader.create(
          color: const Color(0xFF00FF00),
          grainScale: grain,
          opacity: 0.3,
        );
        expect(shader, isNotNull, reason: 'grainScale=$grain 应创建成功');
      }
    });

    test('重复调用 init 是幂等的', () async {
      await MarkerShader.init();
      expect(MarkerShader.isReady, isTrue);
      await MarkerShader.init(); // _initialized=true 直接返回
      expect(MarkerShader.isReady, isTrue);
    });
  });

  group('BrushShader（毛笔/画笔纹理着色器）', () {
    test('未初始化时 create 返回 null 而非抛异常', () {
      // 注意：MarkerShader 组的 init 不影响 BrushShader 的独立状态
      final shader = BrushShader.create(
        color: const Color(0xFF000000),
        grainScale: 10,
        opacity: 1.0,
        width: 12,
      );
      // 若同 isolate 中 BrushShader 已被前序用例初始化则非 null；
      // 本组是首次触碰 BrushShader，应为 null。
      expect(shader, isNull);
    });

    test('init() 加载成功且 isReady 为 true', () async {
      await BrushShader.init();
      expect(BrushShader.isReady, isTrue,
          reason: 'shaders/brush.frag 在 pubspec assets 中注册，应能加载');
    });

    test('init 后 create 返回已绑定 uniform 的 FragmentShader', () async {
      await BrushShader.init();
      final shader = BrushShader.create(
        color: const Color(0xFF212121),
        grainScale: 12,
        opacity: 0.9,
        width: 16,
      );
      expect(shader, isNotNull);
    });

    test('create 多次调用含 width 维度的参数变化均成功', () async {
      await BrushShader.init();
      for (final w in [4.0, 12.0, 24.0]) {
        final shader = BrushShader.create(
          color: const Color(0xFF212121),
          grainScale: 10,
          opacity: 0.85,
          width: w,
        );
        expect(shader, isNotNull, reason: 'width=$w 应创建成功');
      }
    });

    test('重复调用 init 是幂等的', () async {
      await BrushShader.init();
      expect(BrushShader.isReady, isTrue);
      await BrushShader.init();
      expect(BrushShader.isReady, isTrue);
    });
  });
}
