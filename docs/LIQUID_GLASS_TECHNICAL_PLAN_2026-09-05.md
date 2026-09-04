# 液态玻璃技术方案（2026-09-05）

目标：把「苹果那种透明玻璃」从「有组件、没观感」变成「方案正确 + 参数正确 + 真的渲染出来」。

---

## 1. 三个权威来源的真实参数

| 来源 | 文件 | 关键参数 |
|---|---|---|
| Apple HIG（官方规范） | `tmp_design_refs/agent/skills/apple-design/references/hig/liquid-glass.md` | 模糊 20–40px（regular）/ 10–20px（clear）；底色不透明度 **0.6–0.8（regular）/ 0.3–0.5（clear）**；饱和度 **1.2–1.5×**；按背景亮度自适应着色 |
| liquid-glass-react（可运行复刻，MIT） | `tmp_design_refs/lgr/node_modules/liquid-glass-react/dist/index.esm.js` | 见下方 §2，**重点不是模糊而是边缘折射** |
| PICKER.md（实测深色 pill） | `tmp_design_refs/agent/skills/prototype/PICKER.md:38-44` | `rgba(10,10,10,0.82)` + `backdrop-filter: blur(12px) saturate(1.4)` + `inset 0 0 0 1px rgba(255,255,255,0.08)` |

**CSS `blur(Npx)` 的 N 就是高斯标准差 σ**，与 Flutter `ImageFilter.blur(sigmaX:)` 同量纲，直接等值换算（不要除以 2）。

---

## 2. 参考实现的真正机制（这是最容易被误解的地方）

`liquid-glass-react` **不是**「整块毛玻璃」。它的 SVG 滤镜管线（`index.esm.js:140-190`）最终合成是：

```
最终 = EDGE_ABERRATION  over  CENTER_CLEAN
        ↑ 边缘：位移+色散           ↑ 中心：原图，完全不动
```

- `EDGE_MASK` 是径向渐变遮罩（`index.esm.js:135-139`）：中心 0、边缘 1
- `EDGE_ABERRATION` = 位移+色散后的图 ∩ 边缘遮罩 → **只有边缘一圈被折弯**
- `CENTER_CLEAN` = 原图 ∩ 反遮罩 → **中心保持原始背景，不加任何色板**

**结论：苹果玻璃的观感来自「边缘把背后内容折弯并分离出红蓝色边」，中心是通透的。**
项目当前「80% 不透明底色铺满整块」的做法，等于把中心那块最关键的通透感盖掉了。

### 色散怎么来的（`index.esm.js:153-173`）

RGB 三通道用**递减的位移量**分别取样，再 `feBlend mode="screen"` 合并：

```
红通道 scale = S
绿通道 scale = S × (1 − aberration × 0.05)
蓝通道 scale = S × (1 − aberration × 0.10)
```

### 默认参数（对外组件 `LiquidGlass`，`index.esm.js:281-286`）

| 参数 | 值 |
|---|---|
| displacementScale | **70** |
| blurAmount | **0.0625**（系数，非像素） |
| saturation | **140**（%） |
| aberrationIntensity | **2** |
| elasticity | 0.15 |
| cornerRadius | 999（pill） |

真实模糊量在 `index.esm.js:224`：

```js
backdropFilter: `blur(${(overLight ? 12 : 4) + blurAmount * 32}px) saturate(${saturation}%)`
```

代入默认：`4 + 0.0625 × 32 = 6px` → **σ = 6**，饱和 **1.4×**。

---

## 3. 项目既有文档的两处错误（必须纠正）

### 错误一：参数表引用了错误的组件

`docs/DESIGN_SYSTEM.md:214` 写的是
`liquid-glass-react 默认档：displacementScale 25 / blur 12 / saturation 180 / aberration 2 / elasticity 0.15`

这组数字来自**内部组件 `GlassContainer` 的默认值**（`index.esm.js:197-211`），而开发者真正用的是对外导出的 `LiquidGlass`（`index.esm.js:281-286`），两者默认档不同（70 / 0.0625 / 140）。

### 错误二：`blur 12` 被当成像素值

`blurAmount = 12` 是**系数**，真实模糊 = `4 + 12 × 32 = 388px`。把它当 σ=12 用属于巧合正确（恰好等于 PICKER.md 实测的 `blur(12px)`），但**出处标错了**。

> 结论：项目当前 `sigma = 12` 数值上站得住（PICKER.md 实测值），**真正缺的不是模糊量，是 saturate 和折射**。

---

## 4. 关键更正：Flutter 3.47 其实做得了 backdrop 自定义采样

`docs/DESIGN_SYSTEM.md:224` 与 `glass_surface.dart:20-22` 都断言「BackdropFilter 不支持自定义片元采样，真位移不可做」。

**这个结论已经过时。** Flutter 3.47.0（本项目所用版本）的 `dart:ui` 提供：

| API | 位置 | 能力 |
|---|---|---|
| `ImageFilter.shader(FragmentShader)` | `painting.dart:4460` | **用自定义片元着色器当滤镜**，引擎自动绑定 `sampler2D`（filter input）+ `vec2`（纹理尺寸） |
| `ImageFilter.compose(outer:, inner:)` | `painting.dart:4406` | 合成两个滤镜，`result = outer(inner(source))` |
| `ImageFilter.isShaderFilterSupported` | `painting.dart:4488` | 运行时能力检测（= Impeller 是否启用） |

约束：
1. 仅 **Impeller** 生效，否则抛 `UnsupportedError` → 必须 `isShaderFilterSupported` 兜底
2. 第一个 uniform 必须是 `vec2`（引擎填 bound texture 尺寸）
3. 至少一个 `sampler2D` uniform（引擎填 filter input）
4. GLES 后端 y 轴翻转，需反 y

**含义**：把 `liquid-glass-react` 的位移管线移植成 GLSL，作为 `BackdropFilter` 的 filter，就能做到**真折射 + 真色散 + 真 saturate**，不再需要「边缘罩近似」。

---

## 5. 落地分档（重定义）

| 档 | 内容 | 依赖 | 现状 |
|---|---|---|---|
| **G0 兜底** | 80% 实色板，无模糊无饱和 | —— | 现有行为（减弱动效/非 Impeller） |
| **G1 毛玻璃 + 饱和** | `compose(outer: blur(σ), inner: ColorFilter.matrix(saturate))` | 无 | **本轮新增** |
| **G2 超椭圆** | + `RoundedSuperellipseBorder` | 无 | 已有 |
| **G3 真折射** | + `ImageFilter.shader` 位移色散罩 | Impeller | **本轮新增** |

### G1 的饱和度矩阵（Rec.709 亮度权重）

```
k = 饱和度倍率（1.4）
R' = (0.213 + 0.787k)R + (0.715 − 0.715k)G + (0.072 − 0.072k)B
G' = (0.213 − 0.213k)R + (0.715 + 0.285k)G + (0.072 − 0.072k)B
B' = (0.213 − 0.213k)R + (0.715 − 0.715k)G + (0.072 + 0.928k)B
```

### G3 的折射着色器（`shaders/liquid_glass_backdrop.frag`）

与现有 `liquid_glass.frag`（前景边缘罩）不同，这个是**滤镜**：

```glsl
uniform vec2 uSize;      // 引擎填：bound texture 尺寸
uniform sampler2D uInput;// 引擎填：filter input（背景）
uniform float uDisplacement;   // 70
uniform float uAberration;     // 2
out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 c = uv - 0.5;
  float sd = roundedBoxSDF(c * uSize, 0.5 * uSize, uRadius);
  // 位移强度：只在边缘带内非零（对应参考实现的 EDGE_MASK）
  float edge = smoothstep(-uBandWidth, 0.0, sd);
  vec2 offset = normalize(c + 1e-5) * edge * uDisplacement / uSize;
  // RGB 三通道递减位移（对应 feDisplacementMap 的三次 scale）
  float r = texture(uInput, uv + offset).r;
  float g = texture(uInput, uv + offset * (1.0 - uAberration * 0.05)).g;
  float b = texture(uInput, uv + offset * (1.0 - uAberration * 0.10)).b;
  fragColor = vec4(r, g, b, 1.0);
}
```

---

## 6. 覆盖面：该用玻璃的位置（`DESIGN_SYSTEM.md:200` 清单）

| 位置 | 当前 | 目标 |
|---|---|---|
| 顶部 AppBar（9 个页面） | 原生 Material `AppBar` | 玻璃 |
| 弹窗 | `AppleDialog` | 玻璃 |
| 底部/侧边导航 | 原生构件 | 玻璃 |
| 滑块、分段控件、悬浮按钮 | 原生 | 玻璃 |
| 画布、列表、卡片、正文 | 扁平 | **保持扁平（红线）** |

---

## 7. 红线（不可违反）

1. **禁止玻璃叠玻璃**（`DESIGN_SYSTEM.md:218`）
2. **内容层一个像素都不加玻璃**
3. 每个 BackdropFilter 必须 shape 一致的双裁剪，避免全屏模糊
4. 可读性兜底：玻璃上的文字加 `textShadow`（参考实现用 `0 2px 12px rgba(0,0,0,0.4)`）
5. 减弱动效 / 非 Impeller 一律回落 G0/G1
