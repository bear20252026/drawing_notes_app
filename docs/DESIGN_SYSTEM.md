# 设计规范总纲（统一版）

> 本项目的**唯一设计宪法**。任何 UI 改动以本文件为准；本文件自身有矛盾时，按第 2 节的优先级裁决并回来修订本文件。
>
> 整合自四个来源，共 3577 行原始规范。本文件不是新增一套规范，而是把已有规范**去重、对齐、裁决冲突**后落到可执行的一页。

---

## 1. 四个来源与分工

| 来源 | 体量 | 管什么 | 不碰什么 | 授权 |
|---|---|---|---|---|
| **`DESIGN.md`**（根目录，`npx getdesign@latest add apple` 生成） | 562 行 | **颜色 / 字号 / 间距 / 圆角 / 组件调性** | —— | 已入库 |
| **Emil Kowalski 12 skills** | 2563 行 + 1014 行 companion | **动效**：曲线、时长、弹簧、手势、可中断性、减弱动效 | 颜色 | 研究目录，不入库 |
| **`liquid-glass-react`** | MIT，v1.1.1 | **材质**：液态玻璃的参数配方与滤镜管线 | —— | 仅抄参数 |
| **`shadcn/ui`** | MIT | **信息层级的做法**（选项怎么分层、说明放哪、列表行怎么排） | **颜色**（不引入，避免第二套设计源） | 仅抄做法 |

**四者不冲突，因为边界是 DESIGN.md 自己划的**：它第 396–398 行本就允许「浮动的粘性条」用 `80% 底色 + backdrop blur`（毛玻璃），液态玻璃只是毛玻璃的升级版，位置完全合法。

---

## 2. 权限划分：按**域**分权，不按文件排序

> ⚠️ **重要修正（2026-09-04）**：初版把四个来源排成「1→4 优先链」，那是**错误的表述**。
> 它暗示 `DESIGN.md` 在动效上也能压过 Emil 体系——但事实是：
> **`DESIGN.md` 几乎没有动效内容，Emil 体系完全没有颜色内容。**
> 两者管辖范围基本不重叠，所谓"优先级"只在极窄的重叠带上才真正生效。
> 正确模型是按**域**分权，不是按文件排等级：

| 域 | 唯一权威 | 其它来源的表决权 |
|---|---|---|
| **颜色 / 字号 / 间距 / 圆角** | `DESIGN.md` | Emil 体系：**零**（3577 行里没有一条颜色规则，覆盖不了） |
| **动效**（曲线 / 时长 / 弹簧 / 手势 / 可中断性） | `review-animations/STANDARDS.md` | **`DESIGN.md`：零**——它不具备该领域知识，不应参与表决 |
| **材质**（液态玻璃配方） | `liquid-glass-react` | `DESIGN.md`：只有**否决权**（禁装饰性渐变、要求 80% 底色），不给具体数值 |
| **信息层级做法** | `shadcn/ui` + Emil | `DESIGN.md`：不参与 |

**分域之后，真正的重叠只剩一处**（按压缩放系数，见裁决 #1）。此前列出的多处"冲突"经复核，大部分是我把不同域的内容误判成了同一域的打架。

### 权威链（**仅在同一域内**生效）

1. **`STANDARDS.md`** —— 动效数值的权威源；SKILL.md 与 RECIPES.md 的散值与之冲突时以它为准。
2. **`RECIPES.md`**（Web / Expo 两份）—— 配方参数；两份打架时取**更严格**的那组（守住 300ms 上限）。
3. **理念层**（`apple-design` / `animation-vocabulary` / `emil-design-eng`）—— 无数值可查时的判断依据。

**数值铁律**：所有曲线、时长、弹簧配置必须来自上表，**禁止凭空发明**，也禁止"看起来差不多"的近似。

---

## 3. 冲突裁决表（共 10 处，已全部裁决）

| # | 冲突 | 甲说 | 乙说 | **裁决** | 依据 |
|---|---|---|---|---|---|
| 1 | 按压缩放 | `DESIGN.md:439` 明文 **0.95** | Emil 全体系 **0.97**（subtle 区间 0.95–0.98） | **0.95** | **唯一真正跨域的一处**。按第 2 节分域，动效域应归 Emil（即 0.97）；但 0.95 落在 Emil 的 subtle 区间内，同样合法。取 0.95 靠的是**独立理由**：本项目触屏主用，按压力度更强才易被手指感知——**不是靠"宪法"压人**。若将来改用鼠标为主，应改回 0.97 |
| 2 | 弹簧参数化 | `animation-vocabulary`：**damping + response**（1.0/0.4、0.8/0.4、0.8/0.3） | `animate-expo`：**duration + dampingRatio**（300/0.8、300/1） | **统一用 dampingRatio** | Flutter 的 `SpringDescription.withDampingRatio` 以 ratio 为参数，而 ratio 与 animation-vocabulary 的 damping 同义（1.0=临界阻尼，0.8=轻微回弹），两参数化在此合流 |
| 3 | Toast 时长 | Web `RECIPES`：**400ms + `ease`** | Expo `RECIPES`：**300ms 入 / 250ms 出**，明写"300ms cap holds here too" | **300 / 250** | 300ms 是总纲硬规则；Web 版 400ms 是 Sonner 组件的自觉例外（原文：toast 是"elegant"，按组件性格调），本项目不继承该性格 |
| 4 | 入场起始缩放 | `STANDARDS` **0.9–0.97**；`find-animation` 入场 **0.95–0.97**、按压 **0.95–0.98** | —— | **0.96** | 取交集内偏中值；**硬底线是禁止 scale(0)** |
| 5 | 按压时长 | Web **160ms** | Expo **120ms** | **120ms** | 均落在 100–160ms 权威区间内；本项目为触屏主用设备，偏快更跟手 |
| 6 | 玻璃饱和度 | `liquid-glass-react` **saturate 180** + `apple-design` **saturate(180%)** | `prototype/PICKER.md` **saturate(1.4)** | **180** | 两独立来源互证；`blur 12` 三处也完全一致（PICKER 的 1.4 是那个特定深色 picker 的取值） |
| 7 | 液态玻璃 vs DESIGN.md 禁装饰性渐变 | `:502-503` 禁止装饰性渐变背景 | `:396-398` 允许浮层 `80% 底色 + backdrop blur` | **做，但只做浮层** | 禁令针对**背景**，不针对浮层边缘描边。高光只做 1px 边缘环，不做大面积内部渐变 |
| 8 | 禁动 width/height 的例外 | `STANDARDS:112` 只动 transform/opacity | `RECIPES` 手风琴动 height、tab pill 动 width | **两处豁免** | ① 手风琴无 transform 等价；② 绝对定位且无子元素的 pill，`scaleX` 会把圆角拉成椭圆。其余一律不豁免 |
| 9 | 超 300ms 的既有配方 | 滚动揭示 600ms、WAAPI 1000ms、长按确认 2s | 总纲 <300ms | **按性质区分** | 前两者是营销/解释性场景（总纲允许更长）；长按确认 2s 是用户**主动决策**阶段（非对称时序：决策慢、响应快），三者都不是"UI 反馈类动画"，不违反 |
| 10 | 减弱动效的信号数 | Web 版：reduced-motion + hover 门控 | `apple-design`：**三个独立信号**（motion / transparency / contrast） | **三信号** | 更严格。Flutter 侧：`disableAnimations` 与 `highContrast` 有系统对应，`reduced-transparency` 无，需自建开关 |

**裁决后仍悬空（待实测）**：第 6 条的 saturation 180 在 Windows 集显上的实际开销未验证；L3 着色器方案必须带性能闸门，低端机自动降级 L2。

---

## 4. 动效令牌（已落地到 `lib/core/theme/apple_motion.dart`）

### 曲线

| 令牌 | 数值 | 用途 |
|---|---|---|
| `AppleMotion.easeOut` | `Cubic(0.23, 1, 0.32, 1)` | 进出场、默认 |
| `AppleMotion.easeInOut` | `Cubic(0.77, 0, 0.175, 1)` | 屏幕上移动/形变 |
| `AppleMotion.easeSheet` | `Cubic(0.32, 0.72, 0, 1)` | 抽屉/底部面板 |
| `AppleMotion.linear` | `Curves.linear` | 进度、跑马灯、长按进度推进 |

> **陷阱**：Flutter 内置 `Curves.easeOutCubic` 的控制点是 `(0.215, 0.61, 0.355, 1)`，与规范要的 `(0.23, 1, 0.32, 1)` **不是同一条曲线**。原文评价内置曲线"too weak"，必须显式构造 `Cubic`。

### 时长

| 令牌 | 值 | 权威区间 |
|---|---|---|
| `press` | **120ms** | 100–160ms |
| `tooltip` | **125ms** | 125–200ms |
| `dropdown` | **200ms** | 150–250ms |
| `modal` | **250ms** | 200–500ms |
| `sheet` | **300ms** | 200–500ms |
| `toastIn` / `toastOut` | **300 / 250ms** | 见裁决 #3 |
| `staggerItem` / `staggerStep` | **300 / 40ms** | 步长区间 30–80ms |

**硬规则：UI 动画一律 < 300ms。绝不用 `ease-in`**（它起步慢，拖延的正是用户在盯着看的那一瞬间）。

### 弹簧

```dart
AppleMotion.settled   // ratio 1.0，临界阻尼无过冲 —— 普通 UI 过渡
AppleMotion.gesture   // ratio 0.8，轻微回弹 —— 拖拽归位/吸附/抽屉/滑动撤销
AppleMotion.playful   // ratio 0.7 —— 仅罕见时刻（onboarding、成功庆祝）
```

**只用手势驱动的场景才用弹簧**（弹簧能传递速度、可中断；定时动画会重启）。bounce 保持 0.1–0.3，大多数 UI 不用回弹。

### 其它硬数值

| 项 | 值 | 出处 |
|---|---|---|
| 入场起始缩放 | `0.96`（**禁 scale(0)**） | STANDARDS:53 |
| 入场起始位移 | `8px` | RECIPES stagger |
| 按压缩放 | `0.95` | DESIGN.md:439 |
| 甩除速度阈值 | `|位移|/耗时(ms) > 0.11` | STANDARDS:139 |
| 交叉淡入遮掩模糊 | `2px`（上限 20px） | STANDARDS:147 |
| 触控目标 | 桌面 ≥44×44、Android ≥48dp | 三输入一致性要求 |

### 频率闸门（写代码前先过这一关）

| 使用频率 | 决定 |
|---|---|
| >100 次/天（快捷键、命令面板开关） | **永不动画** |
| 数十次/天（hover、列表导航） | 几乎不可感知，或干脆不做 |
| 偶发（模态、抽屉、提示条） | 标准动画 |
| 罕见/首次（引导、成功、庆祝） | 愉悦感预算放在这里 |

**键盘触发的动作是「一票否决」，不是酌情**。（Raycast 的开关没有动画——那才是每天开几百次的东西该有的样子。）

再说一遍目的六选一，说不出就别做：**反馈 / 空间一致性 / 状态指示 / 避免突变 / 解释 / 愉悦（仅罕见档）**。

---

## 5. 液态玻璃：分层规则与配方

### 分层（这是硬边界）

| 层 | 元素 | 材质 |
|---|---|---|
| **浮层**（可用玻璃） | 顶部工具条、主菜单、弹窗、底部标签栏、滑块、分段控件、悬浮按钮 | 液态玻璃 |
| **内容层**（**一个像素都不加**） | 画布、文档列表、每张内容卡片、笔记正文 | 保持扁平 |

> 这条规矩项目里早就写好了——`glass_surface.dart:5-9` 原文：「面向导航与工具层的局部玻璃表面……画布、长列表和每张内容卡片不应无差别使用该组件」。我们要做的不是改规矩，是把它升级成液态玻璃版。

### 配方

```
底色       80–82%（DESIGN.md:396-398 要求 80%；prototype/PICKER.md 实测 82%）
模糊       blur 12        ← liquid-glass-react 与 PICKER.md 两处一致
饱和度     saturate(180%) ← liquid-glass-react 与 apple-design 两处互证
高光       仅 1px 边缘环，不做大面积内部渐变（否则踩「禁装饰性渐变」红线）
```

`liquid-glass-react` 默认档：`displacementScale 25 / blur 12 / saturation 180 / aberration 2 / elasticity 0.15`；按钮档 `64 / 0.1 / 130 / 2 / 0.35`。

色散实现思路（供 L3 着色器参考）：三次位移分离 RGB + 一次模糊合并。

**红线**：**禁止玻璃叠玻璃**（原文"legibility collapses"）。这也是那个 WebGL 移植版要用 scissor ping-pong 优化的原因——叠两层时每层都要采样背后，性能塌方。

### 落地分档

| 档 | 内容 | 状态 |
|---|---|---|
| **L1** | 升级 `GlassSurface`：内高光 + 1px 亮边 + saturation 180 | 待做 |
| **L2** | 加 `RoundedSuperellipseBorder`（Apple 超椭圆圆角，曲率连续）+ 弹簧动效 | 待做 |
| **L3** | 自定义 `FragmentProgram` 做真折射 + 色散 | 待做，**必须带性能闸门**，低端机/集显自动降级 L2 |

项目已在用 `FragmentProgram`（`pencil_shader.dart`），Flutter 3.47.0，L3 的技术路径是通的。

---

## 6. Flutter 映射速查

| 规范写法 | Flutter 对应 |
|---|---|
| `cubic-bezier(a,b,c,d)` | `Cubic(a, b, c, d)` |
| `{duration, dampingRatio}` | `SpringDescription.withDampingRatio(mass:1, stiffness:150–180, ratio:)` |
| 传递手势速度 | `SpringSimulation(spring, start, end, velocity)` |
| `translateY(100%)` | `SlideTransition` + `Offset(0, 1)`（相对自身尺寸） |
| `transform-origin` | `Transform.scale(origin:)` / `Transform.translate` |
| `clip-path: inset()` | `ClipRect` + `Align`，或自定义 `CustomClipper<Rect>` |
| `prefers-reduced-motion` | `MediaQuery.disableAnimationsOf` |
| `prefers-contrast` | `MediaQuery.highContrastOf` |
| `prefers-reduced-transparency` | **无系统对应**，需自建开关 |
| Haptics 三档 | `HapticFeedback.selectionClick` / `lightImpact` / `mediumImpact` |
| `overshootClamping` | 无直接对应，用 `ratio >= 1.0` 代替 |
| `hitSlop` | 无同名字段，用透明 padding 或 `HitTestBehavior.opaque` |

**两条 Flutter 特有纪律**（来自 `write-swift` 的工程律，与 Flutter 同理）：
- **UI 事件回调内同步启动动画**，不要 `await` 之后再启动——手势/滚动触发的动画必须落在事件同帧。
- 用**枚举建模互斥状态**，不要堆 `isLoading / isError` 布尔组；`dispose()` 不做副作用。

---

## 7. Review 清单（提交前自检）

**自动拦截项**（出现任一条即打回）：

- [ ] `scale(0)` 入场 → 改 `scale(0.96)` + `opacity 0`
- [ ] UI 元素用了 `ease-in` → 改 `AppleMotion.easeOut`
- [ ] 用了内置 `Curves.easeOutCubic` 冒充规范曲线 → 改 `AppleMotion.easeOut`
- [ ] 动画超过 300ms 且无理由 → 压到 150–250ms
- [ ] 动 `width/height/top/left/margin/padding` → 改 `transform/opacity`（手风琴与 tab pill 除外）
- [ ] 键盘触发或 >100 次/天的动作带动画 → 删掉
- [ ] 缺 `prefers-reduced-motion` 分支 → 补（更少更轻，**不是零**）
- [ ] hover 动效未用指针类型门控 → 触屏会误触发
- [ ] 一群元素同时入场无错位 → 加 30–80ms stagger
- [ ] 玻璃叠玻璃 → 拆掉一层
- [ ] 内容层（画布/卡片/正文）加了玻璃材质 → 撤掉

**必答三问**：这个动画的**目的**是什么（六选一）？**频率**在哪一档？**中断**后从哪继续（弹簧还是过渡）？

---

## 8. 已知未决

| 项 | 状态 |
|---|---|
| saturation 180 在 Windows 集显上的开销 | 未实测，L3 需带性能闸门 |
| `prefers-reduced-transparency` | Flutter 无系统对应，需自建开关 |
| 硬编码圆角 79 处 / 硬编码色值 153 处 | 待分批收编进 `apple_design.dart` |
| DESIGN.md 其余未兑现条款 | 见 `AGENTS.md` 的缺口清单 |
