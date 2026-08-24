import 'dart:ui';

/// 荧光笔/马克笔纹理着色器加载器。
///
/// 产生均匀的荧光笔质感，有极轻微的墨水浓度波动。
/// 加载失败时静默回退到普通绘制。
class MarkerShader {
  MarkerShader._();

  static FragmentProgram? _program;
  static bool _initialized = false;

  /// 加载 `shaders/marker.frag`。幂等。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _program = await FragmentProgram.fromAsset('shaders/marker.frag');
    } catch (_) {
      _program = null;
    }
  }

  static bool get isReady => _program != null;

  /// 创建已绑定参数的荧光笔片元着色器。
  ///
  /// uniform 顺序：uColor(3) → uGrainScale(1) → uOpacity(1)。
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
