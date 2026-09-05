// 液态玻璃 G3 backdrop 滤镜：真折射位移 + RGB 色散（liquid-glass-react 配方移植）。
//
// 与 liquid_glass.frag（前景边缘罩）互补：本文件是 **backdrop 滤镜**——经
// `ImageFilter.shader` 绑定为 BackdropFilter 的 filter，引擎自动把背景纹理
// 绑到 uInput（sampler2D），纹理尺寸填到 uniform 0（vec2）。
// 依据 docs/LIQUID_GLASS_TECHNICAL_PLAN_2026-09-05.md §5；uniform 下标与
// LiquidGlassShader.bindBackdrop 的 setFloat 一一对应，勿随意调整。
//
// 管线位置：backdrop → 本滤镜（位移+色散）→ blur → saturate（见
// glass_surface.dart G3 分支）。
//
// 平台约束（技术方案 §4）：
// - 仅 Impeller 生效（`ImageFilter.isShaderFilterSupported` 兜底，调用方回落 G1）；
// - GLES 后端 backdrop 纹理 y 轴翻转需反 y——Impeller 各后端方向以真机
//   目视为准：若边缘折射上下反相，把下方 uv 的 y 一行反相修正即可。
//
// Flutter 引擎注入 FlutterFragCoord()（片元坐标，逻辑像素）。
#version 460 core
#include <flutter/runtime_effect.glsl>

// 滤镜应用层尺寸（逻辑像素；引擎填 bound texture 尺寸）。
uniform vec2 uSize;
// filter input（背景纹理；引擎填）。
uniform sampler2D uInput;
// 边缘位移强度（px，liquid-glass-react displacementScale 默认 70）。
uniform float uDisplacement;
// RGB 色散强度（liquid-glass-react aberrationIntensity 默认 2）。
uniform float uAberration;
// 玻璃圆角半径（px，与面板 shape 一致）。
uniform float uRadius;
// 位移作用带宽（px，边缘带厚度——位移集中在边缘，中心为零）。
uniform float uBandWidth;

out vec4 fragColor;

// 圆角矩形 SDF（像素空间，中心为原点；负 = 内部）。
float roundedBoxSDF(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  // 中心化像素坐标与径向单位向量（位移方向：沿径向向外采样）。
  vec2 c = uv - 0.5;
  vec2 dir = normalize(c + vec2(1e-5, 1e-5));

  // 圆角矩形 SDF；边缘带内位移 0→1 渐入（sd ∈ [-band, 0]）。
  float sd = roundedBoxSDF(c * uSize, 0.5 * uSize, uRadius);
  float edge = smoothstep(-uBandWidth, 0.0, sd);

  // 径向位移（uv 空间）：px / 尺寸。
  vec2 offset = dir * edge * uDisplacement / uSize;

  // RGB 三通道递减位移（feDisplacementMap 三次 scale 语义；
  // aberration=2 → 红全量、绿 90%、蓝 80%）。
  float r = texture(uInput, uv + offset).r;
  float g = texture(uInput, uv + offset * (1.0 - uAberration * 0.05)).g;
  float b = texture(uInput, uv + offset * (1.0 - uAberration * 0.10)).b;

  fragColor = vec4(r, g, b, 1.0);
}
