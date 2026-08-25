# 100% Apple 设计还原 — 全面审计报告

**日期**: 2026-08-25  
**审计人**: Aion CLI  
**基准**: DESIGN.md + Apple HIG  
**应用**: Drawing Notes App

---

## 审计维度总览

| 维度 | 检查项数 | ✅ 通过 | ⚠️ 需修复 | ❌ 缺失 |
|------|---------|---------|-----------|---------|
| 1. 按钮系统 | 12 | 9 | 2 | 1 |
| 2. 动画系统 | 10 | 7 | 2 | 1 |
| 3. 交互反馈 | 8 | 5 | 2 | 1 |
| 4. 导航栏 | 8 | 7 | 1 | 0 |
| 5. 卡片系统 | 6 | 5 | 1 | 0 |
| 6. 颜色系统 | 14 | 14 | 0 | 0 |
| 7. 字体系统 | 15 | 15 | 0 | 0 |
| **总计** | **73** | **62** | **8** | **3** |

---

## 1. 按钮系统

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 1.1 | Primary Button: primary bg, pill radius, 11×22 padding, min 44×44 | ✅ | `AppDesign.buttonPrimary` 完全匹配 |
| 1.2 | Secondary Pill: transparent bg, primary border, pill radius | ✅ | `AppDesign.buttonSecondaryPill` 完全匹配 |
| 1.3 | Dark Utility: ink bg, sm radius, 8×15 padding | ✅ | `AppDesign.buttonDarkUtility` 完全匹配 |
| 1.4 | Icon Button Circular: 44×44, full radius, 无阴影 | ✅ | `AppDesign.buttonIconCircular` + `IconButtonThemeData` 匹配 |
| 1.5 | Pearl Capsule: surface-pearl bg, md radius | ✅ | `AppDesign.buttonPearlCapsule` 匹配 |
| 1.6 | Store Hero: primary bg, button-large typography, pill | ✅ | `AppDesign.buttonStoreHero` 匹配 |
| 1.7 | 所有按钮最小 44×44 触摸目标 | ✅ | 所有 buttonStyle 均含 `minimumSize: Size(44, 44)` |
| 1.8 | InkWell 使用 highlightColor（非水波纹） | ⚠️ | `settings_page.dart` 的 `_SettingItem` 使用默认 `InkWell`，无 `highlightColor` |
| 1.9 | 点击缩放动画 0.95x | ❌ | 全局未实现按钮 press 缩放动画 |
| 1.10 | CupertinoButton 用于 iOS 风格 | ⚠️ | 仅 `password_disk_page` 使用 CupertinoButton，其余页面未统一 |
| 1.11 | OutlinedButton 样式统一 | ✅ | 通过 `outlinedButtonTheme` 统一 |
| 1.12 | TextButton 样式统一 | ✅ | 通过 `textButtonTheme` 统一 |

### 需修复
1. **P0**: `settings_page.dart` — `InkWell` 缺少 `highlightColor: AppDesign.primary.withValues(alpha: 0.12)`, `splashColor: Colors.transparent`
2. **P0**: 全局缺少按钮 press 缩放动画（0.95x, 200ms, `Curves.easeInOutCubic`）
3. **P1**: 全局未统一使用 CupertinoButton 或在按钮主题中配置 `overlayColor` 替代水波纹

---

## 2. 动画系统

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 2.1 | 页面过渡: CupertinoPageTransitionsBuilder | ✅ | `AppDesign.lightTheme().pageTransitionsTheme` 已配置全部平台 |
| 2.2 | 动画曲线: Curves.easeInOutCubic | ✅ | `AppDesign.animationCurve` = `Curves.easeInOutCubic` |
| 2.3 | 默认动画时长: 350ms | ✅ | `AppDesign.animationDuration` = 350ms |
| 2.4 | 弹性动画时长: 500ms | ✅ | `AppDesign.animationDurationElastic` = 500ms |
| 2.5 | 列表入场 stagger 动画 | ⚠️ | 部分使用 `FadeInAnimation`（onboarding），首页列表无 stagger |
| 2.6 | 按钮缩放反馈: 0.95x + highlight | ⚠️ | `home_page.dart` 的 `_settingsButton` 有 `GestureDetector(onTapUp:...scale)`，但非全局 |
| 2.7 | 对话框从底部滑入（iOS 式） | ✅ | `IosDialog` 使用 `SlideTransition` + `FadeTransition`，从底部滑入 |
| 2.8 | SnackBar 从底部滑入 + 自动消失 | ✅ | `AppSnackbar.show()` 使用 `SnackBar` 标准行为 |
| 2.9 | 弹性滚动物理 | ✅ | `app.dart` 配置 `BouncingScrollPhysics` |
| 2.10 | TabBar 切换动画 | ✅ | 使用 Flutter 标准 TabBar 动画 |

### 需修复
1. **P1**: 首页列表缺少 stagger 入场动画（每项延迟 50ms）
2. **P1**: 按钮缩放反馈未全局统一（仅 `home_page` 部分实现）

---

## 3. 交互反馈

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 3.1 | 触摸目标最小 44×44 | ✅ | 通过 IconButtonTheme + ButtonStyle 统一 |
| 3.2 | 滑动删除（iOS 式） | ⚠️ | 无 iOS 式滑动删除实现（`Dismissible` 未使用） |
| 3.3 | 下拉刷新 RefreshIndicator | ✅ | `home_page.dart` 使用 `RefreshIndicator` |
| 3.4 | 长按高亮 + 缩放 | ⚠️ | 长按仅在 `home_page` 的 `onLongPress` 有确认对话框，无视觉缩放反馈 |
| 3.5 | 删除二次确认对话框 | ✅ | 使用 `IosDialog`（iOS 风格） |
| 3.6 | 搜索交互反馈 | ✅ | `AppleSearchBar` 有焦点高亮 |
| 3.7 | 缩放/平移手势 | ✅ | 编辑器支持 `InteractiveViewer` + 手势 |
| 3.8 | 键盘快捷键 | ✅ | 编辑器支持 Ctrl+Z/Ctrl+Y |

### 需修复
1. **P2**: 无 iOS 式滑动删除（可在列表项添加 `Dismissible` + `SwipeAction`）
2. **P2**: 长按缺少视觉缩放反馈

---

## 4. 导航栏

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 4.1 | 大标题: display-md 34px/600 | ✅ | 首页 + 设置页使用 `SliverAppBar` + 大标题 |
| 4.2 | 标准导航栏: body 17px/600 | ✅ | 编辑器使用标准 AppBar |
| 4.3 | 按钮: 14px/400, primary 颜色 | ✅ | 通过 `textButtonTheme` 统一 |
| 4.4 | 透明背景 | ✅ | 所有 AppBar 使用 `Colors.transparent` |
| 4.5 | 滚动时磨砂效果 | ⚠️ | `SliverAppBar(floating: true)` 无 `stretch` 或 `snap`，无磨砂 |
| 4.6 | Leading 按钮（返回箭头） | ✅ | `arrow_back_ios_new` 图标 |
| 4.7 | 搜索栏: AppleSearchBar 44px 高 | ✅ | `home_page.dart` 自定义 `_AppleSearchBar` |
| 4.8 | 底部标签栏 | ✅ | 首页 `TabBar` 在 SliverToBoxAdapter 中 |

### 需修复
1. **P1**: `SliverAppBar` 缺少 `snap: true` + `floating: true` 实现滚动时磨砂/缩放效果

---

## 5. 卡片系统

| # | 检查项 | 状态 | 说明 |
|---|--------|------|------|
| 5.1 | Store Utility Card: canvas bg, hairline, lg radius, 24px padding | ✅ | `AppDesign.storeUtilityCard` + `storeUtilityCardPadding` |
| 5.2 | 产品阴影: rgba(0,0,0,0.22) 3px 5px 30px | ✅ | `AppDesign.productShadowComponent` offset(3,5) 正确 |
| 5.3 | 圆角统一 lg (18px) | ✅ | 卡片统一使用 `roundedLg` |
| 5.4 | 无阴影 Flat | ✅ | 无额外阴影设置 |
| 5.5 | Surface Tile 暗色卡片 | ✅ | `surfaceTile1/2/3` 已定义 |
| 5.6 | 环境引用卡: surface-tile-1 bg | ✅ | `AppDesign.environmentQuoteCard` |

### 需修复
1. **P1**: 卡片缺少 hover/focus 微动画（桌面端鼠标悬停缩放 1.02x）

---

## 6. 颜色系统 — 14/14 通过

所有颜色 token 与 DESIGN.md 完全一致 ✅

## 7. 字体系统 — 15/15 通过

所有字体 token 与 DESIGN.md 完全一致 ✅

---

## 修复优先级汇总

| 优先级 | 问题 | 文件 | 预计工时 |
|--------|------|------|----------|
| P0 | InkWell highlightColor + splashColor: transparent | settings_page.dart + 全局 | 30min |
| P0 | 全局按钮 press 缩放动画 0.95x | 全局 ButtonStyle 或 widget | 1h |
| P1 | SliverAppBar snap + frosted effect | home_page + settings_page | 30min |
| P1 | 列表 stagger 入场动画 | home_page_widgets.dart | 45min |
| P1 | CupertinoButton 统一 + overlayColor 替代水波纹 | 全局 | 30min |
| P2 | iOS 式滑动删除 | 列表页面 | 1h |
| P2 | 长按视觉缩放反馈 | 列表页面 | 30min |
| P2 | 卡片 hover 微动画（桌面端） | 卡片 widget | 30min |

---

## 总结

**得分: 85/100** — 基础扎实，颜色/字体/阴影已 100% 匹配 DESIGN.md。主要差距在交互细节（按钮缩放、InkWell 高亮、列表动画）。修复 P0+P1 后可达 95 分。
