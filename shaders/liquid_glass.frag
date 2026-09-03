// 液态玻璃边缘折射罩（L3，liquid-glass-react 配方移植）。
//
// 移植来源（MIT，tmp_design_refs/lgr）：roundedRectSDF → smoothstep 位移
// 曲线 → RGB 三通道位移分离（aberration）。平台诚实边界：Flutter 的
// BackdropFilter 拿不到自定义片元着色器（backdrop 采样无公开 API），
// 故真位移只能作用于 backdrop 模糊近似；本着色器负责配方中可前台化的
// 部分——边缘折射环 + RGB 色散分离 + 顶部镜面高光 + 微光闪烁。
// 背景模糊仍由 GlassSurface 的 BackdropFilter(blur 12) 承担。
//
// Flutter 引擎注入 FlutterFragCoord()（片元坐标，逻辑像素）。
// uniform 声明顺序与 LiquidGlassShader.bind 的 setFloat 下标一一对应。
#version 460 core
#include <flutter/runtime_effect.glsl>

// 面板尺寸（逻辑像素）。
uniform vec2 uSize;
// 圆角半径（逻辑像素，与面板 shape 一致）。
uniform float uRadius;
// 时间（秒，微光闪烁用；减弱动效时恒 0）。
uniform float uTime;
// 整体强度（0~1，默认 1）。
uniform float uIntensity;
// 高光染色（RGB，默认近白）。
uniform vec3 uTint;
// 色散分离量（像素，配方默认档 aberration 2）。
uniform float uAberration;

out vec4 fragColor;

// 圆角矩形 SDF（配方 roundedRectSDF 的像素版，中心为原点）。
float roundedBoxSDF(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// 边缘带：|sd| 越小越亮，2.5px 外衰减为 0（位移集中在边缘——配方实测）。
float bandAt(float d) {
  return 1.0 - smoothstep(0.0, 2.5, abs(d));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // 注意：rim 绘制在面板 bounds 内，frag 即面板局部坐标。
  vec2 p = frag - 0.5 * uSize;
  vec2 b = 0.5 * uSize;
  float sd = roundedBoxSDF(p, b, uRadius);

  // 有限差分法线（不用 dFdx——扩展可用性在移动 GPU 上不稳定）。
  float e = 1.0;
  vec2 grad = vec2(
    roundedBoxSDF(p + vec2(e, 0.0), b, uRadius) -
      roundedBoxSDF(p - vec2(e, 0.0), b, uRadius),
    roundedBoxSDF(p + vec2(0.0, e), b, uRadius) -
      roundedBoxSDF(p - vec2(0.0, e), b, uRadius)
  );
  vec2 n = grad / max(length(grad), 1e-4);

  // RGB 三通道分离（配方 aberration：红内收、蓝外扩，绿居中）。
  float aber = max(uAberration, 0.0);
  vec3 rim;
  rim.r = bandAt(sd - aber);
  rim.g = bandAt(sd);
  rim.b = bandAt(sd + aber);
  // 外侧略强（透镜外沿折射更明显），内侧保留一半。
  float outside = step(0.0, sd);
  rim *= mix(0.55, 1.0, outside);

  // 顶部镜面高光（法线朝上处最亮，6px 衰减）。
  float topness = clamp(-n.y, 0.0, 1.0);
  float spec = pow(max(0.0, 1.0 - abs(sd - 1.0) / 6.0), 2.0) * topness;

  // 微光闪烁（±15%，减弱动效时 uTime=0 即恒定）。
  float shimmer = 0.85 + 0.15 * sin(uTime * 0.8 + frag.x * 0.01);

  vec3 tinted = mix(vec3(1.0), uTint, 0.35);
  vec3 color = tinted * (rim * 0.9 + spec) * shimmer;
  float alpha = clamp((dot(rim, vec3(0.333)) * 0.9 + spec) * uIntensity, 0.0, 1.0);

  fragColor = vec4(color, alpha);
}
