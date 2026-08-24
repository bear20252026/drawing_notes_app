// 铅笔石墨颗粒着色器（借鉴 Saber fbm noise 思路，保留原始版权声明）。
//
// Copyright (C) 2021-2026 Aditya Khanna / Saber contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// 改进：使用分形布朗运动 (fbm) 噪声替代简单哈希，产生更自然的石墨纹理。
// 5 个八度的 fbm 噪声提供丰富的频率细节，easeInOutQuad 重映射使颗粒分布
// 更均匀，Y 轴频率缩放模拟铅笔沿书写方向的纹理拉伸。
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

// ---- 分形布朗运动 (fbm) 噪声 ----
// 基于 Value Noise 的 5 八度叠加，产生自然的石墨颗粒纹理。

// 极简伪随机哈希：相同坐标得到稳定随机值。
float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 2D Value Noise：在整数网格点之间双线性插值。
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  // Hermite 平滑插值
  vec2 u = f * f * (3.0 - 2.0 * f);

  return mix(
    mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

// 分形布朗运动：5 个八度叠加，每层频率翻倍、振幅减半。
float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  float frequency = 1.0;
  for (int i = 0; i < 5; i++) {
    value += amplitude * noise(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

// easeInOutQuad：将噪声值重映射为更均匀的分布，
// 避免颗粒集中在中间灰度，使石墨质感更自然。
float easeInOutQuad(float t) {
  return t < 0.5 ? 2.0 * t * t : 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 cell = frag / max(uGrainScale, 1.0);

  // Y 轴频率缩放（0.35）模拟铅笔沿书写方向的纹理拉伸，
  // X 轴频率（0.7）保持较密的横向颗粒。
  vec2 stretchedCoord = vec2(cell.x * 0.7, cell.y * 0.35);

  // 5 八度 fbm 噪声 → easeInOutQuad 重映射
  float rawNoise = fbm(stretchedCoord);
  float noise = easeInOutQuad(rawNoise);

  // 石墨感：噪声控制亮度变化
  // 低噪声区域：颜色较深（石墨堆积）
  // 高噪声区域：颜色较浅（纸面露白）
  float brightness = mix(0.75, 1.0, noise);
  vec3 graphite = uColor * brightness;

  // 约 15% 的区域露白（模拟纸面颗粒），噪声越高越容易露白
  float reveal = smoothstep(0.82, 0.95, noise);
  vec3 paper = vec3(1.0);

  // 不透明度上限 0.7（模拟石墨半透明质感，与 Saber 一致）
  float finalOpacity = min(uOpacity, 0.7);

  fragColor = vec4(mix(graphite, paper, reveal), finalOpacity);
}
