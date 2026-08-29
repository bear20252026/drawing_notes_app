# Apple (HIG) 设计系统 —— 标准化实施记录

日期：2026-08-29
里程碑：M9 All Docs 工作台 + Apple (HIG) 设计系统（commit `56f2e43`）
门禁：`flutter analyze` 0 / architecture 通过 / 全量回归 **1248** 全通过

## 设计策略（用户@要求保留深蓝色系）

> 「深蓝系是那个黑暗模式，前的设计还是要保留…苹果这是这种明亮模式下的苹果啊」
> 「之前的深蓝的色系也要保留，但设计风格要统一成跟苹果一样」

最终策略为**双模式、单风格**：

| 模式 | 颜色 | 来源 |
|------|------|------|
| **明亮模式** | Action Blue `#0066CC` / 米白底 `#F5F5F7` / 墨色 `#1D1D1F` | Apple (HIG) |
| **黑暗模式** | `#172033` / `#4568A9` / 画布 `#101521` / 表面 `#181F2E` / 芯片 `#222B3D` | 既有深蓝（保留） |
| **结构风格**（圆角/间距/字重/动效/胶囊/过渡） | 两种模式一致，统一为 Apple | Apple (HIG) |

即：**颜色随模式切换（亮=苹果、暗=深蓝），结构风格全模式统一 Apple。**

## 实现位置

- `lib/core/theme/app_design.dart` — 全局主题承载：
  - `_theme(Brightness)` 选择 `_appleLightScheme()`（明亮）或 `_navyScheme()`（黑暗）。
  - `_navyScheme()`：primary `#B5CCFF` / onPrimary `#102244` / primaryContainer `#294579` /
    surface `#181F2E` / onSurface `#E2E8F4` / inversePrimary `#4568A9`；scaffold 背景 `#101521`。
  - `_appleLightScheme()`：primary `#0066CC` / onSurface `#1D1D1F` / surface 白 /
    scaffold 背景 `#F5F5F7`。
  - 结构：圆角 18/12、间距 20/12、字重 w600+负字距、ZoomPageTransitionsBuilder、胶囊/圆角卡片、pill/snackbar/dialog。
  - 常量：`ink` `#1D1D1F`、`accent` `#0066CC`（明亮）；`navyInk` `#172033`、`navyAccent` `#4568A9`、
    `darkCanvas` `#101521`、`darkSurface` `#181F2E`、`darkSubtleSurface` `#222B3D`（深蓝）。
- `lib/core/theme/apple_design.dart` — Apple token + 可复用部件：
  - 浅色 token：`actionBlue` `#0066CC` / `ink` `#1D1D1F` / `inkMuted` `#6E6E73` /
    `parchment` `#F5F5F7` / `surfaceWhite` `#FFFFFF` / `subtleSurface` `#EBEBED` /
    `hairline` `#E0E0E0` / `noteGreen` `#30D158` / `blockPurple` `#BF5AF2` /
    `favourite` `#FF9F0A` / `errorRed` `#FF3B30`。
  - 深色 token（改为深蓝）：`canvansDark` `#101521` / `surfaceDark` `#181F2E` / `subtleSurfaceDark` `#222B3D`。
  - `AppleSpacing` / `AppleRadius` / `AppleType`；`ApplePrimaryButton` / `ApplePillSearchField` / `AppleSectionHeader`。

## 实施要点（对页面/部件）

1. **自适应颜色优先 `Theme.of(context).colorScheme`**——背景/表面/文本/强调随模式自动切换
   （深色自动落到深蓝、浅色自动落到苹果）。这是「双模式单风格」的最稳实现。
2. 固定的强调/品牌色（块类型色、选中描边、拖动线、收藏星标）用 Apple 浅色 token 或 `colorScheme.primary`。
3. 深色表面/背景用 `AppleColor.canvansDark/surfaceDark/subtleSurfaceDark`（现=深蓝）或
   `AppDesign.darkCanvas/darkSurface/darkSubtleSurface`；**不要**写死成 Apple 黑/灰。
4. 结构风格全模式 Apple：`AppleRadius.lg(18)` 卡片、`AppleRadius.full(9999)` 胶囊、`AppleType` 字重、`AppleSpacing`。
5. 旧强调色映射：`#4568A9→#0066CC` / `#7C4DFF→#BF5AF2` / `#166C59→#30D158` / `#F5A623→#FF9F0A`（浅色+深色通用）。

## 页面落地状态

- M9 All Docs（lead 已交付）：left sidebar + 工具条 + tab + 分组列表；深色背景走 `AppleColor.canvansDark/surfaceDark`（=深蓝）。
- M10-A/B（进行中）：块编辑器/双模/Edgeless 页与主页/日程/笔记写作/同步设置页 Apple 化收口。

## 相关文档

- `docs/M9_ALL_DOCS_ACCEPTANCE_2026-08-29.md` — All Docs 工作台验收记录。
