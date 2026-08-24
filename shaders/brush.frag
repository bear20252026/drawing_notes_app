// 毛笔/画笔纹理着色器。
//
// 产生柔软的毛笔质感：沿笔触方向的条纹噪声模拟刷毛痕迹，
// 中心区域墨色较浓，边缘逐渐变淡，模拟毛笔的墨水扩散效果。
//
// uniform 顺序：uColor(3) → uGrainScale(1) → uOpacity(1) → uWidth(1)。
// 与 BrushShader.create 的 setFloat 下标一一对应。
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec3 uColor;
uniform float uGrainScale;
uniform float uOpacity;
// 笔触宽度（逻辑像素），用于边缘衰减计算。
uniform float uWidth;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 1D Value Noise：沿单一轴向的噪声，用于产生毛笔条纹。
float noise1d(float p) {
  float i = floor(p);
  float f = fract(p);
  float u = f * f * (3.0 - 2.0 * f);
  return mix(hash(vec2(i, 0.0)), hash(vec2(i + 1.0, 0.0)), u);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 cell = frag / max(uGrainScale, 1.0);

  // 沿 X 轴的条纹噪声（模拟刷毛方向）
  float stripe = noise1d(cell.x * 3.0);

  // 径向衰减：距笔触中心越远越淡（模拟毛笔边缘散开）
  // 使用 cell.y 的小数部分作为相对位置
  float centerY = 0.5;
  float dist = abs(cell.y - centerY) * 2.0; // 0~1 范围
  float edgeFade = 1.0 - smoothstep(0.4, 1.0, dist);

  // 墨色变化：条纹 + 径向衰减
  float inkDensity = mix(0.6, 1.0, stripe) * edgeFade;
  vec3 ink = uColor * inkDensity;

  fragColor = vec4(ink, uOpacity * edgeFade);
}
