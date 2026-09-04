import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'package:drawing_notes_app/core/theme/apple_motion.dart';

/// 液态玻璃分档（DESIGN_SYSTEM.md §5 落地分档）。
///
/// - [l1]：配方视觉（80% 底色 + blur 12 + 1px 亮边），纯 BackdropFilter；
/// - [l2]：+ 超椭圆 shape（曲率连续）；
/// - [l3]：+ [LiquidGlassRim] 着色器边缘罩（真折射近似 + 色散），带性能闸门。
enum LiquidGlassLevel { l1, l2, l3 }

/// 液态玻璃折射罩着色器加载器（L3，`shaders/liquid_glass.frag`）。
///
/// 与 [PencilShader] 同一工程范本：幂等加载、失败静默回退（调用方降级 L2，
/// 功能不受影响）。uniform 下标与 frag 声明顺序一一对应，勿随意调整。
class LiquidGlassShader {
  LiquidGlassShader._();

  static FragmentProgram? _program;
  static bool _initialized = false;

  /// 加载 `shaders/liquid_glass.frag`。幂等；失败保持回退状态。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _program = await FragmentProgram.fromAsset('shaders/liquid_glass.frag');
    } catch (_) {
      _program = null;
    }
  }

  /// 着色器是否已就绪（性能闸门第一关）。
  static bool get isReady => _program != null;

  /// 创建已绑定尺寸/圆角/时间/强度/染色/色散的片元着色器。
  ///
  /// 未就绪返回 null（调用方降级 L2）。
  static FragmentShader? bind({
    required Size size,
    required double radius,
    required double timeSeconds,
    double intensity = 1.0,
    Color tint = const Color(0xFFFFFFFF),
    double aberration = 2.0,
  }) {
    final program = _program;
    if (program == null) return null;
    final shader = program.fragmentShader();
    // uniform 声明顺序：uSize(2) → uRadius(1) → uTime(1) →
    // uIntensity(1) → uTint(3) → uAberration(1)。
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, radius)
      ..setFloat(3, timeSeconds)
      ..setFloat(4, intensity)
      ..setFloat(5, tint.r)
      ..setFloat(6, tint.g)
      ..setFloat(7, tint.b)
      ..setFloat(8, aberration);
    return shader;
  }
}

/// 液态玻璃配方常量（单一事实来源）。
///
/// 取值依据见 `docs/LIQUID_GLASS_TECHNICAL_PLAN_2026-09-05.md`：
/// - [kDefaultSigma]：CSS `blur(12px)`（σ 同量纲，无需换算）——
///   `prototype/PICKER.md:39` 实测值；Apple HIG regular 区间为 20–40px，
///   clear 区间 10–20px，本项目取 12 属 clear 偏 regular 的折中。
/// - [kDefaultSaturation]：三来源互证——Apple HIG 1.2–1.5×、
///   `liquid-glass-react` 默认 140%、`prototype/PICKER.md` 实测 1.4。
/// - [kRegularOpacity] / [kClearOpacity]：Apple HIG 两个变体的底色区间。
/// - [kDisplacement] / [kAberration]：`liquid-glass-react` 对外组件默认档
///   （`index.esm.js:281-286`），用于 G3 真折射。
abstract final class LiquidGlassRecipe {
  /// backdrop 高斯模糊标准差（默认 12）。
  static const double kDefaultSigma = 12;

  /// backdrop 饱和度倍率（默认 1.4，1.0 表示不处理）。
  static const double kDefaultSaturation = 1.4;

  /// regular 变体底色不透明度（Apple HIG 0.6–0.8 的下限，偏通透）。
  static const double kRegularOpacity = 0.62;

  /// clear 变体底色不透明度（Apple HIG 0.3–0.5）。
  static const double kClearOpacity = 0.45;

  /// 边缘位移强度（G3；`liquid-glass-react` displacementScale 默认 70）。
  static const double kDisplacement = 70;

  /// RGB 色散强度（G3；`liquid-glass-react` aberrationIntensity 默认 2）。
  static const double kAberration = 2;
}

/// Rec.709 亮度权重饱和度矩阵（`ColorFilter.matrix` 的 20 项口径）。
///
/// `k = 1` 时退化为单位矩阵；`k > 1` 提升饱和度且**保持每行系数和为 1**
/// （亮度守恒，不会整体变亮或变暗）。
///
/// 对应 CSS `backdrop-filter: blur(Npx) saturate(K%)` 中的 saturate 分量——
/// Flutter 的 BackdropFilter 没有现成 saturate API，故用 ColorFilter 矩阵实现。
List<double> liquidGlassSaturationMatrix(double k) {
  const lr = 0.213, lg = 0.715, lb = 0.072;
  final ir = 1 - lr, ig = 1 - lg, ib = 1 - lb;
  return <double>[
    lr + ir * k, lg - lg * k, lb - lb * k, 0, 0, //
    lr - lr * k, lg + ig * k, lb - lb * k, 0, 0, //
    lr - lr * k, lg - lg * k, lb + ib * k, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// L3 性能闸门（DESIGN_SYSTEM.md：低端机/集显自动降级 L2）。
///
/// 降级条件（任一命中即 L2）：
/// 1. 着色器未就绪（加载失败/不支持 Shader 编译的环境）；
/// 2. 系统减弱动效或高对比（`AppleMotion.reduceMotionOf` 口径）；
/// 3. [forceLevel] 被外部置顶（设置页低功耗开关/测试注入预留）。
class LiquidGlassGate {
  LiquidGlassGate._();

  /// 全局置顶档（null = 自动；测试与低功耗模式可强制 l1/l2）。
  static LiquidGlassLevel? forceLevel;

  /// 给定意向档，返回闸门裁决后的实际档。
  static LiquidGlassLevel resolve(BuildContext context, LiquidGlassLevel want) {
    final forced = forceLevel;
    if (forced != null) return forced;
    if (want != LiquidGlassLevel.l3) return want;
    if (!LiquidGlassShader.isReady) return LiquidGlassLevel.l2;
    if (AppleMotion.reduceMotionOf(context)) return LiquidGlassLevel.l2;
    return LiquidGlassLevel.l3;
  }
}
