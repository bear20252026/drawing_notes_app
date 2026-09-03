# AGENTS.md — 画板笔记（drawing_notes_app）代码协作约定

> 本文件给 AI 编码助手与人类协作者阅读。
> **动任何 UI（含动效）之前，先读 [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md)——那是整合后的唯一总纲，含全部冲突裁决表。** 本文件是它的执行摘要。

## 1. 设计规范的唯一来源

规范按**域**分权，不是按文件排等级（`DESIGN.md` 管静态视觉，Emil 体系管动效，两者几乎不重叠）：

| 文件 | 角色 | 是否可改 |
|---|---|---|
| **`docs/DESIGN_SYSTEM.md`** | **总纲**：四个来源的分域规则 + 10 处冲突裁决 + 玻璃配方 + Review 清单 | 可增补，改动须说明理由 |
| `DESIGN.md`（根目录，已入库） | **静态视觉宪法**：色板 / 排版 / 间距 / 圆角 / 组件 / Do's & Don'ts（562 行，由 `npx getdesign@latest add apple` 生成） | **不可改**（重新生成会覆盖） |
| `lib/core/theme/apple_design.dart` | 静态视觉令牌层：`AppleColor` / `AppleSpacing` / `AppleRadius` / `AppleType` + 部件 | 可增，改值须回查 DESIGN.md |
| `lib/core/theme/apple_motion.dart` | **动效令牌层**：`AppleMotion` 曲线 / 时长 / 弹簧 / 阈值 | 可增，改值须回查裁决表 |
| `lib/core/theme/app_design.dart` | `ThemeData` 组装层（light/dark 两套 ColorScheme + 组件主题） | 可改 |

**规则**：静态视觉一律以 DESIGN.md 为准；**动效一律以 `AppleMotion` 令牌为准**（其数值出自 Emil 体系 `STANDARDS.md`，DESIGN.md 在动效域无表决权）。禁止在页面里自创数值。

## 2. 写 UI 时的硬性约束

### 颜色
- 主强调色只用 **Action Blue `#0066CC`**（深模式 `#2997FF`），全 App 唯一。
- 键盘焦点环用 **Focus Blue `#0071E3`**，`2px` 实线描边（DESIGN.md:300、440）。
- **禁止**在页面里写 `Color(0xFF...)` 字面量——一律走 `AppleColor` 或 `Theme.of(context).colorScheme`。
- 危险操作用 `AppleColor.errorRed`；其余一律灰阶。

### 排版（DESIGN.md:346、493、506）
- 正文 **17px / 400 / 行高 1.47 / 字距 -0.374px**。**行高不得低于 1.47**（原文："the editorial leading is part of the brand"）。
- 层级：标题 17(w600) · 控制文本 13 · 说明文字 11.5。
- 走 `AppleType.bodyStyle/titleStyle/controlStyle/captionStyle`，不要手写 `TextStyle(fontSize: ...)`。

### 圆角（DESIGN.md:127-135）
合法档位**只有**：`none 0` / `xs 5` / `sm 8` / `md 11` / `lg 18` / `pill 9999` / `full 9999`。
**禁止中间值**（如 6、10、12、14）。一律走 `AppleRadius.*`。

### 间距
`AppleSpacing.*`（base=8：4/8/12/16/24/32/48）。

### 微交互（DESIGN.md:439、444、497）
- 所有可点控件按压态 = **`transform: scale(0.95)`**（触屏主用，取力度更强一档；Emil 体系标准值 0.97，两者同属其合法 subtle 区间 0.95–0.98）。
- 用 `lib/shared/widgets/apple_pressable.dart` 的 `ApplePressable` 包裹；它同时响应鼠标、触屏、键盘三种输入的按下。
- 键盘焦点必须可见：`2px` Focus Blue 描边。

### 动效（域权威 = Emil 体系，DESIGN.md 不参与）
- 曲线**只用** `AppleMotion.easeOut / easeInOut / easeSheet / linear`。
  ⚠️ **禁止**用内置 `Curves.easeOutCubic`——其控制点 `(0.215,0.61,0.355,1)` 与规范曲线 `(0.23,1,0.32,1)` 不是同一条。
- 时长**只用** `AppleMotion.press / tooltip / dropdown / modal / sheet / toastIn / toastOut`。
- **硬规则**：UI 动画 < 300ms；**绝不用 `ease-in`**；**禁止 `scale(0)` 入场**（用 `0.96` + `opacity 0`）；只动 `transform/opacity`（手风琴与 tab pill 豁免）。
- **频率闸门**：>100 次/天或键盘触发的动作**永不动画**。
- 减弱动效三信号（motion / transparency / contrast）→ `AppleMotion.reduceMotionOf(context)`。
- 完整规则与 Review 清单见 `docs/DESIGN_SYSTEM.md`。

## 3. 三输入兼容（用户硬性要求）

用户主用**触屏笔记本**：任何交互必须**同时**支持鼠标、触屏、键盘。
- 只响应 `onSecondaryTap`/`MouseRegion`/`onPointerHover` 的入口，必须补长按或 `⋮` 按钮等价入口。
- 只响应 `onLongPress`/`onPanUpdate` 的入口，必须补鼠标拖拽或按钮等价入口。
- 核心操作（新建 / 删除 / 重命名 / 收藏 / 导出 / 撤销重做 / 对话框确认取消）必须有键盘可达路径。
- 触控目标 ≥ **44×44**；自定义 `InkWell`/`GestureDetector` 纯图标交互需显式 `Semantics(label: ..., button: true)`。

## 4. 液态玻璃（Liquid Glass）使用边界

DESIGN.md:502-503 禁止**装饰性**渐变与阴影；但 :396-398、:434、:476 明确允许**浮动粘性层**用 `背景 80% + backdrop-filter blur`。

**结论（分层规则）**：
- ✅ 可用玻璃：**浮层**——导航条、工具条、浮动粘性条、弹出面板、对话框、菜单。
- ❌ 禁用玻璃：**内容层**——画布、长列表、每张内容卡片。内容区保持扁平。
- 材质配方必须含 **80% 底色 + backdrop blur**；高光只做 **1px 边缘环**，不做大面积内部渐变。

现有 `lib/shared/widgets/glass_surface.dart` 的注释已写明此规则，升级液态玻璃时沿用同一条边界。

## 5. 响应式

断点 **900dp**（`maxWidth >= 900` = 桌面双栏，否则移动单栏）。
外层 `app_shell`（侧栏 / 底部导航）与内层页面**各自**判断——只做一层会漏。
窄屏判定另有一档 **600dp**（画板顶栏低频开关收进主菜单，见 `editor_page_appbar.dart`）。

## 6. 门禁（提交前必须全绿）

```bash
cd /c/Users/17296/WorkBuddy/2026-08-29-23-43-00/drawing_notes_app
flutter analyze          # 必须 No issues found
flutter test             # 必须全绿
```

> ⚠️ **shell 工作目录铁律**：本工作区外层是 `2026-08-29-23-43-00`，项目在子目录 `drawing_notes_app`。
> 每条命令**必须**以 `cd /c/Users/17296/WorkBuddy/2026-08-29-23-43-00/drawing_notes_app &&` 开头，
> 否则 `flutter` 报 "No pubspec.yaml file found"、`git` 作用错仓库、`flutter analyze` 会静默分析外层
> 目录并误报 "No issues found"（最危险）。同一命令失败 ≥3 次立即改用子代理接管。

提交后 push，并确认 CI 五个工作流（CI / 软件质量工程门禁 / Code Guard / SBOM / Secret Scan）全绿。

## 7. 其他铁律

- **任何删改（删功能 / 删入口 / 删代码 / 重构）必须先征求用户同意**，不得自行判断删除。增量新增不受限。
- **笔记本（画布页集合）入口必须保留**；打字笔记（块文档）为主推；两者并存。
- 引用第三方代码（AFFiNE/BlockSuite 等）须保留版权声明，见 `THIRD_PARTY_NOTICES.md`。
- 改 UI 后若涉及改密/加密路径，注意 `test/` 里真 KDF 用例需 `@Timeout(Duration(minutes: 3))`。
- 发版 bump 三处同步：`pubspec.yaml` + `tools/drawing_notes_setup.iss`（`MyAppVersion`）+ `CHANGELOG.md`。
- `docs/audit_*.html` 审计报告按约定保持 **untracked**，不入库。
