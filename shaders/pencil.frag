// 铅笔石墨颗粒着色器（本项目独立实现）。
//
// 将铅笔笔画渲染为“带颗粒纹理的石墨笔触”：在笔画覆盖区域内，按
// 屏幕空间的小格子产生伪随机抖动——大部分像素保留笔色，少量像素
// 被提亮/变暗，形成纸张颗粒质感。颗粒密度随笔宽动态缩放，避免
// 细笔时颗粒过大、粗笔时颗粒过密。
//
// Flutter 引擎注入 FlutterFragCoord()（片元坐标）。uniform 声明顺序
// 与 PencilShader.create 的 setFloat 下标一一对应，勿随意调整。
#version 460 core
#include <flutter/runtime_effect.glsl>

// 铅笔颜色（RGB，0~1）。
uniform vec3 uColor;
// 颗粒格边长（逻辑像素），由笔宽换算。
uniform float uGrainScale;
// 笔画整体不透明度（0~1），与普通笔画一样尊重透明度设置。
uniform float uOpacity;

out vec4 fragColor;

// 极简整数哈希：相同格子得到稳定随机值，保证颗粒纹理不闪烁。
float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 cell = floor(frag / max(uGrainScale, 1.0));
  float noise = hash2(cell);

  // 石墨感：约 12% 的格子提亮（纸面露白），其余保留笔色；
  // 亮度抖动幅度随噪声轻微变化，形成不均匀的石墨堆积。
  float brightness = 1.0 - 0.10 * noise;
  float reveal = step(0.88, noise); // 0.88 阈值，约 12% 露白
  vec3 graphite = uColor * brightness;
  vec3 paper = vec3(1.0);

  fragColor = vec4(mix(graphite, paper, reveal), uOpacity);
}
