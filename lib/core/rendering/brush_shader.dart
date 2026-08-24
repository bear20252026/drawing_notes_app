import 'dart:ui';

/// 毛笔/画笔纹理着色器加载器。
///
/// 用条纹噪声模拟毛笔刷毛痕迹，中心墨色浓、边缘变淡。
/// 加载失败时静默回退到普通绘制。
class BrushShader {
  BrushShader._();

  static FragmentProgram? _program;
  static bool _initialized = false;

  /// 加载 `shaders/brush.frag`。幂等。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _program = await FragmentProgram.fromAsset('shaders/brush.frag');
    } catch (_) {
      _program = null;
    }
  }

  static bool get isReady => _program != null;

  /// 创建已绑定参数的毛笔片元着色器。
  ///
  /// uniform 顺序：uColor(3) → uGrainScale(1) → uOpacity(1) → uWidth(1)。
  static FragmentShader? create({
    required Color color,
    required double grainScale,
    required double opacity,
    required double width,
  }) {
    final program = _program;
    if (program == null) return null;
    final shader = program.fragmentShader();
    shader
      ..setFloat(0, color.r)
      ..setFloat(1, color.g)
      ..setFloat(2, color.b)
      ..setFloat(3, grainScale)
      ..setFloat(4, opacity)
      ..setFloat(5, width);
    return shader;
  }
}
