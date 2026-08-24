import 'dart:ui';

/// 铅笔颗粒着色器加载器（借鉴 Saber fbm noise 思路，保留原始版权声明）。
///
/// Copyright (C) 2021-2026 Aditya Khanna / Saber contributors
/// SPDX-License-Identifier: GPL-3.0-or-later
///
/// 铅笔笔触在 [StrokeRenderer] 中默认以低透明度石墨色模拟；启用着色器后
/// 改为"fbm 噪声颗粒纹理"渲染，让铅笔看起来有纸张石墨质感。加载失败（例如
/// 运行在不支持 Shader 编译的环境）时静默回退到低透明度模拟，不影响功能。
///
/// 小尺寸降级策略（借鉴 Saber）：当笔宽 × 缩放比例 < 3 时，着色器纹理
/// 在屏幕上过于密集反而产生摩尔纹，此时回退到普通半透明绘制。
class PencilShader {
  PencilShader._();

  static FragmentProgram? _program;
  static bool _initialized = false;

  /// 加载 `shaders/pencil.frag`。幂等；失败时保持回退状态。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _program = await FragmentProgram.fromAsset('shaders/pencil.frag');
    } catch (_) {
      // 编译/资源不可用时回退到普通铅笔绘制，不抛错打断渲染。
      _program = null;
    }
  }

  /// 着色器是否已就绪（可用于铅笔渲染）。
  static bool get isReady => _program != null;

  /// 判断当前笔宽和缩放比例下是否应使用着色器。
  ///
  /// 当笔宽在屏幕上的投影像素 < [minScreenPixels] 时，fbm 噪声纹理
  /// 会在屏幕上过于密集，产生摩尔纹或纯色效果，此时应回退到普通绘制。
  static bool shouldUse(double strokeWidth, double currentScale,
      {double minScreenPixels = 3.0}) {
    return strokeWidth * currentScale >= minScreenPixels;
  }

  /// 创建已绑定画笔颜色、颗粒密度与不透明度的片元着色器。
  ///
  /// uniform 顺序：uColor(3) → uGrainScale(1) → uOpacity(1)。
  /// 未就绪时返回 null，调用方应回退到普通绘制。
  static FragmentShader? create({
    required Color color,
    required double grainScale,
    required double opacity,
  }) {
    final program = _program;
    if (program == null) return null;
    final shader = program.fragmentShader();
    shader
      ..setFloat(0, color.r)
      ..setFloat(1, color.g)
      ..setFloat(2, color.b)
      ..setFloat(3, grainScale)
      ..setFloat(4, opacity);
    return shader;
  }
}
