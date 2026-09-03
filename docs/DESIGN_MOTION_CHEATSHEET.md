# 动效与材质规范速查（补充 DESIGN.md）

> DESIGN.md 管**静态**设计（色 / 字 / 间距 / 圆角）。
> 本文件管**动效与材质**（弹簧 / 时长 / 缓动 / 玻璃 / 减弱动效）——DESIGN.md 基本没覆盖这块。
> **冲突时以 DESIGN.md 为准**（它是项目宪法），本文件只做补充。

来源（2026-09-04 实际安装核对）：

| 来源 | 是什么 | 授权 | 用法 |
|---|---|---|---|
| `npx skills@latest add emilkowalski/skills` | Emil Kowalski（Vercel 设计工程负责人、Sonner 作者）的 12 个 agent skill | — | 装到 `.agents/skills/`，给 AI 读的规范 |
| `npm install liquid-glass-react` | rdev/liquid-glass-react v1.1.1，React 的 Apple 液态玻璃 | MIT | 参数配方与滤镜管线参考 |

---

## 1. 弹簧参数（Apple 出厂值）

用 **damping ratio + response** 思考，**不是 duration**。弹簧没有固定时长，稳定时间由参数自然产生。

| 交互 | damping | response | 说明 |
|---|---|---|---|
| 移动 / 重定位（如 PiP） | `1.0` | `0.4` | 临界阻尼，无回弹 —— **默认就这一档** |
| 旋转 | `0.8` | `0.4` | 仅当手势自带惯性（甩动/抛掷）才用 |
| 抽屉 / sheet | `0.8` | `0.3` | 轻微回弹 |

- 默认全用 `damping 1.0`。回弹只给**手势带惯性**的动作。菜单淡入用回弹是错的；被甩出去的卡片用回弹才对。
- Flutter 对应：`SpringDescription.withDampingRatio(ratio: ..., period: ...)`。

## 2. 可打断性（最重要的一条）

> "The thought and the gesture happen in parallel."

- 任何动画都必须能在飞行中被抓回来。**永远不要在转场期间锁输入。**
- **永远从 presentation（当前屏幕值）起动画，不能从目标值起** —— 否则打断时可见跳变。
- 手势反向时**融合速度**，不要硬切（否则出现"砖墙"）。
- 2D 位移拆成独立的 X、Y 两条弹簧，否则 X/Y 速度不同时会失步。

## 3. 手势收尾：速度交接 + 动量投影

手势结束的瞬间，动画必须以手指的**精确速度**继续，才没有接缝。

```
// 注意：不是物理课本的 v²/(2·decel)，Apple 用指数衰减
project(v, d = 0.998) = (v / 1000) * d / (1 - d)

projectedEnd = currentPosition + project(releaseVelocity)
target       = nearestSnapPoint(projectedEnd)        // 从投影点选目标
animateTo(target, { velocity: releaseVelocity })     // 再交接速度
```

- 不要从"松手位置"吸附到最近边界，要从**投影落点**吸附 —— 这才是"甩出去"的手感。
- 边界处**渐进阻尼**，不要硬停。

## 4. 时长与缓动

| 元素 | 时长 |
|---|---|
| 按钮按压反馈 | 100–160ms |
| Tooltip、小弹层 | 125–200ms |
| 下拉、选择 | 150–250ms |
| 模态、抽屉 | 200–500ms |

**UI 动画一律 < 300ms。** 180ms 的下拉比 400ms 感觉更快。

自定义曲线（内置 ease 太弱，没有" punch"）：

```
ease-out      cubic-bezier(0.23, 1, 0.32, 1)     // UI 交互默认
ease-in-out   cubic-bezier(0.77, 0, 0.175, 1)    // 屏上移动/形变
iOS 抽屉      cubic-bezier(0.32, 0.72, 0, 1)
```

**UI 动画绝不用 ease-in** —— 起始慢 = 感觉卡。

## 5. 该不该动画（先问这个，再写代码）

| 使用频率 | 决定 |
|---|---|
| 100+ 次/天（快捷键、命令面板） | **不动画，永远** |
| 数十次/天（hover、列表导航） | 删掉或大幅削减 |
| 偶尔（模态、抽屉、toast） | 标准动画 |
| 罕见 / 首次（引导、庆祝） | 可以加趣味 |

- **键盘触发的动作永不做动画** —— 一天重复几百次，动画只会让它显得慢。
- 每个动画必须回答"为什么动"：空间一致性 / 状态指示 / 解释 / 反馈 / 避免突变。只为"好看"又高频 → 不做。

## 6. 组件级铁律

| 规则 | 说明 |
|---|---|
| 按压反馈 | 所有可点元素 `scale(0.95)`，**按下即触发**（不等抬起）。本项目用 `ApplePressable` |
| 绝不从 `scale(0)` 进场 | 现实中没有东西凭空出现。用 `scale(0.95) + opacity 0` |
| Popover 必须 origin-aware | 从**触发器**缩放出来。**模态例外**，保持居中 |
| Tooltip 首次延迟、后续瞬时 | 已有 tooltip 打开时，相邻 tooltip 无延迟无动画 |
| Stagger 间隔 30–80ms | 更长的间隔让界面显得慢；stagger 期间绝不阻塞交互 |
| 只 animate transform / opacity | 动 padding/height/width 会触发 layout，掉帧 |
| 交叉淡入不理想时 | 加 `blur(2px)` 过渡遮掩（上限 20px，重模糊很贵） |
| Popover 用 transition，不用 keyframe | keyframe 打断时从零重启，transition 能平滑重定向 |
| 触屏设备 hover | 必须 gate 在 `@media (hover:hover) and (pointer:fine)` 之后，否则点击会误触发 hover |

## 7. 材质与层级（玻璃）

- 玻璃只用在**浮层**：导航条、工具条、浮动粘性条、弹出面板、菜单。
- **禁止玻璃叠玻璃** —— "Never stack a light translucent surface on another — legibility collapses."
  （这也正是 WebGL 版要用 scissor 局部 ping-pong blit 的原因：叠层采样背后是性能灾难。）
- **Materialize, don't just fade**：玻璃进出场要 **blur radius 与 scale 一起动**，让它像真实材料降临，而不是单纯淡入。
- 大表面要显得更"厚"：更强模糊 + 更深阴影。
- 滚动边缘用**渐隐遮罩**，不要 1px 硬分割线。
- 半透明表面上的文字：不用平灰，用**更高对比 + 略重字重 + 字距微增**。颜色放实心层，不放半透明前景。

**液态玻璃默认配方**（`liquid-glass-react` 实测值，可作 L3 着色器调参起点）：

| 参数 | 默认 | 按钮档 | 说明 |
|---|---|---|---|
| `displacementScale` | 25 | 64 | 边缘折射弯曲强度 |
| `blurAmount` | 12 | 0.1 | 底色模糊（**底色需 80% 不透明**） |
| `saturation` | **180** | 130 | 与 `saturate(180%)` 跨来源互证 |
| `aberrationIntensity` | 2 | 2 | 色散：三次位移分离 RGB + 一次模糊合并 |
| `elasticity` | 0.15 | 0.35 | 液态弹性 |
| `cornerRadius` | 999 | 100 | |
| `mode` | standard | | 另三种：polar / prominent / shader |

> Safari、Firefox 对位移只部分支持（位移不可见）。

## 8. 减弱动效（三个独立信号，都要响应）

| 信号 | 处理 | Flutter 侧 |
|---|---|---|
| `prefers-reduced-motion: reduce` | 用短**交叉淡入**替代位移/弹簧/视差；去掉弹性与回弹；**保留**有助于理解的透明度与颜色变化 | `MediaQuery.disableAnimationsOf(context)` |
| `prefers-reduced-transparency: reduce` | 半透明表面变实：提高底色不透明度、去掉模糊 | **无系统对应，需自建设置开关** |
| `prefers-contrast: more` | 接近实心底色 + 明确的高对比描边 | `MediaQuery.highContrastOf(context)` |

- 减弱动效 **不等于没有反馈**，是"更温和、不刺激前庭"的等价物。
- 避免：全屏移动背景、0.2Hz 附近的慢速循环晃动、明暗主题切换时亮度突变。

## 9. 与 DESIGN.md 的冲突取舍

| 冲突点 | DESIGN.md | 外部来源 | 本项目取 |
|---|---|---|---|
| 按压缩放系数 | `scale(0.95)`（:439/444/497） | Emil 主张 `0.97` | **0.95**（DESIGN.md 是宪法，0.97 属网页经验值） |
| 玻璃 | :502 禁渐变装饰、:503 禁阴影 | 液态玻璃 = 渐变高光 + 折射 | **合法**：:396-398 允许浮动粘性层用 `80% 底色 + backdrop blur`。高光只做 **1px 边缘环**，不做大面积内部渐变 |

## 10. Review 检查清单

| 问题 | 修法 |
|---|---|
| `transition: all 300ms` | 指定具体属性 |
| 从 `scale(0)` 进场 | 改 `scale(0.95) + opacity 0` |
| UI 元素用 `ease-in` | 换 `ease-out` 或自定义曲线 |
| Popover `transform-origin: center` | 改为触发器位置（模态除外） |
| 键盘动作上有动画 | 直接删掉 |
| UI 元素时长 > 300ms | 降到 150–250ms |
| 没有 media query 的 hover 动画 | 加 `(hover:hover) and (pointer:fine)` |
| 高频触发元素用 keyframe | 换 transition 以获得可打断性 |
| 进出场同速 | 出场比进场快 |
| 多个元素同时出现 | 加 stagger（30–80ms） |
| 玻璃叠玻璃 | 去掉下层玻璃 |

## 11. 术语对照（与用户沟通用）

用户说"那个弹一下的东西" → **Pop in**；"iOS 拉到底回弹" → **Rubber-banding**；
"弹窗从按钮长出来" → **Origin-aware animation**；"一个变另一个" → **Morph**；
"缩略图展开成卡片" → **Shared element transition**；"一个接一个出现" → **Stagger**；
"拖走关掉" → **Swipe to dismiss**；"按住才确认" → **Hold to confirm**。
