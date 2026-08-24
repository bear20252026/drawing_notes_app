// 荧光笔/马克笔纹理着色器。
//
// 产生均匀的荧光笔质感：中心区域颜色均匀，边缘略微变淡，
// 整体半透明（模拟荧光笔墨水渗入纸张的效果）。
// 比纯 srcOver 半透明更自然——有轻微的边缘柔化和墨水浓度变化。
//
// uniform 顺序：uColor(3) → uGrainScale(1) → uOpacity(1)。
// 与 MarkerShader.create 的 setFloat 下标一一对应。
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec3 uColor;
uniform float uGrainScale;
uniform float uOpacity;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 cell = frag / max(uGrainScale, 1.0);

  // 极轻微的噪声变化（5% 以内），模拟荧光笔墨水浓度微小不均
  float noise = hash(cell) * 0.05;

  // 荧光笔颜色均匀，仅有极轻微的浓度波动
  vec3 ink = uColor * (0.97 + noise);

  fragColor = vec4(ink, uOpacity);
}
