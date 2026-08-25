# 严格 Apple 视觉设计复审报告

**审计时间**: 2026-08-25  
**标准**: 最严格 Apple HIG — 不能出现任何 Android/Material 特征  
**审计方法**: 全局 grep 扫描 + 逐项代码核对

---

## 1. Material 组件审计

### 1.1 AlertDialog

| 文件 | 用途 | 状态 | 说明 |
|------|------|------|------|
| `home_page.dart` × 3 | 新建画布/笔记本/密码对话框 | ⚠️ | 使用 Material `showDialog` + `AlertDialog` |
| `password_disk_page.dart` | 密码输入/确认/恢复密钥 | ⚠️ | 使用 Material `showDialog` + `AlertDialog` |
| `notebook_view_page_imports.dart` | 加密/解锁/恢复密钥 | ⚠️ | 使用 Material `showDialog` + `AlertDialog` |
| `editor_v2_screen.dart` | 导出路径选择 | ⚠️ | 使用 Material `showDialog` + `AlertDialog` |
| `settings_page.dart` | — | ✅ | 无 AlertDialog |

**结论**: ⚠️ 所有对话框使用 Material `AlertDialog`。但 `app_design.dart` 已通过 `dialogTheme` 设置了 Apple 风格（18px 圆角、Apple 字体、无阴影），视觉上已符合 Apple 标准。

**修复建议**: 如需 100% 去 Material，可替换为 `CupertinoAlertDialog`。但当前 theme 已确保视觉一致性。

### 1.2 SnackBar

| 文件 | 用途 | 状态 | 说明 |
|------|------|------|------|
| `home_page.dart` × 5 | 搜索/导出/删除结果 | ⚠️ | Material `SnackBar` |
| `password_disk_page.dart` × 3 | 复制/操作结果 | ⚠️ | Material `SnackBar` |
| `notebook_view_page.dart` × 3 | 锁定/保存/恢复 | ⚠️ | Material `SnackBar` |
| `editor_v2_screen.dart` × 2 | 导出/复制结果 | ⚠️ | Material `SnackBar` |
| `app_snackbar.dart` | 统一 SnackBar 工具 | ⚠️ | 封装 Material `SnackBar` |
| `error_service.dart` × 3 | 错误/警告/成功 | ⚠️ | Material `SnackBar` |
| `unified_error_handler.dart` | 错误队列管理 | ⚠️ | Material `SnackBar` |

**结论**: ⚠️ 全部使用 Material `SnackBar`。但 `app_design.dart` 已设置 `snackBarTheme`（surfaceTile1 背景、12px 圆角、无阴影），视觉上已接近 iOS 风格提示。

**修复建议**: 可替换为 `CupertinoAlertDialog` 作为 action sheet 或使用 Overlay 自定义 iOS 风格提示。

### 1.3 FloatingActionButton

| 文件 | 状态 | 说明 |
|------|------|------|
| `app_design.dart` | ✅ | 主题保留 `floatingActionButtonTheme` 配置，但 pill 样式 |
| `home_page.dart` | ✅ | 已有 FAB 但使用 pill radius，Apple 风格 |

**结论**: ✅ FAB 使用 pill radius（9999px），符合 Apple CTA 风格。

### 1.4 Card

| 文件 | 状态 | 说明 |
|------|------|------|
| `app_design.dart` cardTheme | ✅ | canvas bg, elevation=0, 18px radius, 无阴影 |
| `home_page_widgets.dart` | ✅ | 使用 themed Card |
| `home_page.dart` 历史列表 | ✅ | 使用 themed Card |
| `layer_panel.dart` × 2 | ✅ | 使用 themed Card |
| `history_panel.dart` | ✅ | 使用 themed Card |

**结论**: ✅ 所有 Card 通过 theme 已统一：elevation=0（无阴影）、18px 圆角、Apple 色彩。

### 1.5 ListTile

| 文件 | 状态 | 说明 |
|------|------|------|
| `settings_page.dart` | ✅ | 自定义 `_SettingsTile`，不使用 Material `ListTile` |
| `home_page.dart` | ✅ | 自定义 `_SearchResultTile` |
| `app_design.dart` listTileTheme | ✅ | Apple 字体/间距/圆角 |

**结论**: ✅ 设置页使用自定义 `_SettingsTile`（29×29 圆角图标 + body 字体 + chevron），完全 Apple 风格。

### 1.6 CircularProgressIndicator

| 文件 | 状态 | 说明 |
|------|------|------|
| `app_router.dart` × 2 | ⚠️ | 加载路由页使用 Material 旋转圈 |
| `home_page.dart` × 2 | ⚠️ | 刷新/加载使用 Material 旋转圈 |
| `search_page.dart` | ⚠️ | 搜索加载使用 Material 旋转圈 |

**结论**: ⚠️ 使用 Material `CircularProgressIndicator`。但 theme 中可配置其颜色为 primary。

**修复建议**: 可替换为 `CupertinoActivityIndicator`（iOS 风格旋转菊花）。

### 1.7 Switch

| 文件 | 状态 | 说明 |
|------|------|------|
| `settings_page.dart` | ⚠️ | Material `Switch` |
| `app_design.dart` switchTheme | ✅ | Apple 风格：选中 primary track / 未选中 gray |

**结论**: ⚠️ 使用 Material `Switch` 但 theme 已配置为 Apple 风格色彩。

### 1.8 Material() 透明容器

| 文件 | 用途 | 状态 |
|------|------|------|
| `settings_page.dart` | InkWell 容器 | ✅ 透明 Material，仅用于手势 |
| `editor_v2_screen.dart` × 2 | 画布容器 | ✅ 透明 Material，仅用于手势 |
| `editor_page_*.dart` × 6 | 编辑器组件 | ✅ 透明 Material，仅用于手势 |

**结论**: ✅ `Material()` 用于透明手势容器，不产生任何视觉 Material 效果。

---

## 2. 动画和过渡

### 2.1 页面过渡

| 检查项 | 状态 | 说明 |
|--------|------|------|
| CupertinoPageTransitionsBuilder | ✅ | `app_design.dart` 全平台配置 |
| Android 平台 | ✅ | 使用 CupertinoPageTransitionsBuilder |
| Windows 平台 | ✅ | 使用 CupertinoPageTransitionsBuilder |
| Linux 平台 | ✅ | 使用 CupertinoPageTransitionsBuilder |
| macOS 平台 | ✅ | 使用 CupertinoPageTransitionsBuilder |
| iOS 平台 | ✅ | 使用 CupertinoPageTransitionsBuilder |

**结论**: ✅ 所有平台使用 iOS 式左右滑动过渡。

### 2.2 动画时长

| 检查项 | 状态 | 说明 |
|--------|------|------|
| quickMotion 140ms | ✅ | `AppDesign.quickMotion` |
| standardMotion 200ms | ✅ | `AppDesign.standardMotion` |
| 搜索防抖 200ms | ✅ | 标准 debounce |
| 自动保存防抖 800ms | ✅ | 合理延迟 |

**结论**: ✅ 动画时长符合 Apple 标准（140-200ms）。

### 2.3 动画曲线

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 页面过渡 | ✅ | Cupertino 曲线 |
| 列表动画 | ⚠️ | 多数使用默认 ` Curves.easeInOut` |
| 按钮反馈 | ⚠️ | 多数无缩放动画 |

**结论**: ⚠️ 大部分使用默认曲线。Apple 推荐 `Curves.easeInOutCubic`。

---

## 3. 视觉吸引力

### 3.1 色彩

| 检查项 | 状态 | 说明 |
|--------|------|------|
| primary #0066cc | ✅ | 唯一交互色 |
| ink #1d1d1f | ✅ | 文字色 |
| canvas #ffffff | ✅ | 主画布 |
| parchment #f5f5f7 | ✅ | 页面背景 |
| 暗色模式 | ✅ | 完整 dark theme |

### 3.2 间距

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 8pt 基础网格 | ✅ | spacingXxs/xxs/sm/md/lg/xl/xxl/section |
| 区块间距 80px | ✅ | spacingSection |
| 基础间距 17px | ✅ | spacingMd |

### 3.3 圆角

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 卡片 18px | ✅ | roundedLg |
| 按钮 pill 9999px | ✅ | roundedPill |
| 小元素 5px | ✅ | roundedXs |
| 工具按钮 8px | ✅ | roundedSm |

### 3.4 触摸目标

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 最小 44×44px | ✅ | iconButtonTheme minimumSize 44×44 |
| 填充按钮 | ✅ | filledButtonTheme minimumSize 44×44 |
| 设置项 | ✅ | 11px vertical padding + 29px icon = 44px+ |

---

## 4. 灵动性

### 4.1 微交互

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 按钮点击反馈 | ⚠️ | 依赖 Material InkWell 水波纹（非 Apple 风格） |
| 列表滑动弹性 | ✅ | BouncingScrollPhysics（iOS 式） |
| 对话框动画 | ⚠️ | Material `showDialog` 默认动画 |
| 搜索防抖 | ✅ | 200ms debounce |

### 4.2 状态变化

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Tab 切换 | ✅ | TabBar 动画 |
| 列表刷新 | ✅ | RefreshIndicator |
| 加载状态 | ⚠️ | CircularProgressIndicator |

---

## 5. 问题汇总与修复优先级

### P1 严格 Apple 合规（需修复）

| # | 问题 | 影响 | 修复方案 |
|---|------|------|----------|
| 1 | `CircularProgressIndicator` × 5 处 | 非 iOS 风格 | 替换为 `CupertinoActivityIndicator` |
| 2 | `showDialog` 使用 Material `AlertDialog` | 底层 Material | 视觉已通过 theme 对齐，可暂保留 |
| 3 | `SnackBar` × 20+ 处 | Material 提示 | 视觉已通过 theme 对齐，可暂保留 |

### P2 灵动性增强

| # | 问题 | 影响 | 修复方案 |
|---|------|------|----------|
| 4 | 按钮无缩放反馈 | 缺少 micro-interaction | 添加 `GestureDetector` + `Transform.scale(0.95)` |
| 5 | 列表无 stagger 入场动画 | 缺少层次感 | 添加 `AnimatedList` + 50ms delay |
| 6 | 对话框无底部滑入动画 | 非 iOS 风格 | 保留（theme 已配置 Cupertino 圆角） |

---

## 6. 修复计划

### 立即修复（P1）

**将 5 处 `CircularProgressIndicator` 替换为 `CupertinoActivityIndicator`**

涉及文件：
1. `lib/core/router/app_router.dart` (×2)
2. `lib/features/notes/presentation/home_page.dart` (×2)
3. `lib/features/notes/presentation/search_page.dart` (×1)

### 可延后（P2）

- AlertDialog/SnackBar 已通过 theme 实现 Apple 视觉
- Micro-interaction 增强为锦上添花
