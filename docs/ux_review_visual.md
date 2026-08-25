# UX 复查报告 — 视觉一致性 + 交互反馈 + 暗色模式

> 基于源码级审计的用户体验全面复查
> 生成日期：2026-08-25

---

## 1. 页面加载和首屏体验

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 首页白屏/闪烁 | ✅ 已修复 | `AuthGuard.initialize()` 已改为后台异步，路由立即创建（commit b1358ec） |
| 编辑器打开文档 | ✅ 正常 | `EditorV2Screen.initState` → `createDocument()` → `loadNoteDocument()` 流程清晰 |
| 设置页加载 | ✅ 正常 | 无异步阻塞 |
| Onboarding 弹窗 | ✅ 正常 | 首次启动后延迟 1s 弹出，不阻塞首屏 |

---

## 2. 交互反馈

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 按钮水波纹/高略 | ✅ 正常 | 使用 Material InkWell/Semantics 组件，自带水波纹 |
| 列表滑动流畅 | ✅ 正常 | `ListView.builder` + `ScrollPhysics.alwaysScrollable` |
| 对话框动画 | ✅ 正常 | 使用 `showDialog` + `AlertDialog`，Material 默认动画 |
| SnackBar 提示 | ⚠️ 不一致 | 存在 **3 套 SnackBar 系统**（见下文） |

### ⚠️ SnackBar 系统不一致（P1）

当前存在 3 套独立的 SnackBar 实现：

| 系统 | 文件 | 用途 |
|------|------|------|
| `AppSnackBar` | `app_snackbar.dart` | 统一工具类（error/success/warning/info + 图标） |
| `ErrorSnackBarService` | `unified_error_handler.dart` | 统一错误 SnackBar（队列管理 + 最大 3 个） |
| `ScaffoldMessenger.showSnackBar` | 各页面直接调用 | 底层 SnackBar API |

**问题**：
- `password_disk_page.dart` 直接使用 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))`
- `home_page.dart` 也直接使用底层 API
- `notebook_view_page.dart` 混合使用两种

**建议**：统一使用 `AppSnackBar` 封装类，所有 SnackBar 调用经过同一个入口。

---

## 3. 错误处理

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 文件不存在 | ✅ 友好提示 | `_refresh()` 捕获异常 → `_error.value = '读取列表失败：$type'` |
| 存储失败 | ✅ 有提示 | `_saveNow()` → SnackBar 提示 |
| 密码错误 | ✅ 有提示 | `_unlock()` → `_snack('未找到有效的密码盘')` |
| PIN 错误 | ✅ 有提示 | `_snack('PIN 至少 6 位')` |
| 恢复密钥错误 | ✅ 有提示 | `_snack('恢复密钥错误')` |
| 错误分类系统 | ✅ 完善 | `UnifiedErrorHandler` + `ErrorCode` 枚举 + 9 大分类 |
| 降级策略 | ✅ 有 | `AppFallbackService` + 降级标志持久化 |

---

## 4. 边界情况

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 空画板列表 | ✅ 有引导 | "还没有无限画布，点击右下角按钮新建一个吧" |
| 空笔记本列表 | ✅ 有引导 | "还没有笔记本，点击右下角按钮新建一个吧" |
| 空最近列表 | ✅ 有引导 | "还没有任何内容，先新建画作或笔记本吧" |
| 回收站为空 | ✅ 有提示 | "回收站为空" |
| 搜索无结果 | ✅ 有提示 | "未找到匹配内容" |
| 空笔记本页 | ✅ 有引导 | "这个笔记本还没有页面，点击右上角新建" |
| 列表性能 | ⚠️ 基本正常 | `_buildDrawingsTab` 使用 `SingleChildScrollView` + `ResponsiveGrid`（非 builder），中等列表无问题 |
| 超长文本 | ⚠️ 未验证 | 编辑器文本块未限制最大长度（无限输入 OK，但极长时性能待测） |
| 特殊字符 | ✅ 安全 | XML 导出已做 `XmlEscape()`；文件名通过 `trim()` + `isEmpty` 校验 |

### ⚠️ 空列表引导文案引用了旧 FAB 位置（P1）

```
'还没有无限画布，点击右下角按钮新建一个吧'
'还没有笔记本，点击右下角按钮新建一个吧'
```

FAB 已移除（Apple 设计打磨），文案中"右下角按钮"已过时。应改为"点击导航栏 + 按钮新建"。

---

## 5. 暗色模式

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 主题切换系统 | ✅ 完善 | `themeModeProvider` + 三态切换（系统/浅色/深色）+ SharedPreferences 持久化 |
| AppDesign 暗色色板 | ✅ 有定义 | `surfaceTile1/2/3`、`bodyOnDark`、`bodyMuted`、`primaryOnDark` |
| 暗色主题对象 | ✅ 有 | `AppDesign.darkTheme()` |
| 密码盘指纹图标 | ✅ 正常 | `Icon(Icons.fingerprint, color: Colors.white)` 在 gradient 上 |
| 搜索栏暗色 | ✅ 有适配 | `_AppleSearchBar`: `#F2F2F7`(light) / `#2C2C2E`(dark) |
| 设置页硬编码颜色 | ⚠️ 问题 | `settings_page.dart:299`: `color: Colors.white` 在 Switch thumb — 暗色模式可能不可见 |
| 演示页硬编码颜色 | ⚠️ 问题 | `presentation_page.dart`: 多处 `Colors.white/white54/white38/white70` — 暗色模式正常（背景是黑色） |

### ⚠️ 设置页 Switch thumb 硬编码白色（P2）

`settings_page.dart:299` — `color: Colors.white` 在 Switch thumb 上。浅色模式下 OK（thumb 在激活态本身是白色），但非激活态的灰色 thumb 上如果也有白色叠加则对比度不足。

---

## 6. 响应式布局

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 编辑器响应式 | ✅ 有 | `ResponsiveValue<UnifiedEditorLayout>` 根据 `width >= 1200` 切换布局 |
| 搜索页响应式 | ✅ 有 | `ResponsiveValue<double>` 自适应 padding/字体 |
| 首页响应式 | ✅ 有 | `ResponsiveGrid(mobileColumns: 2, tabletColumns: 3, desktopColumns: 4)` |
| 响应式缩放系统 | ✅ 完善 | `context.responsiveScale()` + `context.responsiveFont()` + 5 级断点 |
| 编辑器 Toolbar 响应式 | ✅ 有 | `UnifiedEditorResponsiveHelper.toolbarHeight()` |
| 窗口缩放自适应 | ✅ 正常 | Flutter 流式布局天然支持 |

---

## 7. 统一设计系统

| 检查项 | 状态 | 说明 |
|--------|------|------|
| AmbientBackground | ✅ 统一 | 所有页面使用 `AmbientBackground` 包裹（commit 26fcc4c） |
| GlassSurface | ✅ 统一 | 内容区域使用 `GlassSurface` |
| Apple 大标题 | ✅ 新增 | 首页使用 `SliverAppBar(floating)` + `FlexibleSpaceBar`（commit 0cc85d6） |
| 编辑器标题 | ✅ 已优化 | 显示文档标题而非原始 ID（commit b1fb4a2） |
| controlRadius | ✅ 统一 | 8.0 常量 |
| 字体系统 | ✅ 统一 | `AppTypography` + `responsiveFont()` |
| 颜色系统 | ✅ 完善 | `AppDesign` 单一蓝色 #0066CC + 完整色板 |

---

## 8. 问题汇总

### ❌ P0 问题（0 个）
无

### ⚠️ P1 问题（2 个）

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 1 | SnackBar 系统不一致（3 套独立实现） | `app_snackbar.dart` / `unified_error_handler.dart` / 各页面直接调用 | 体验不统一，维护困难 |
| 2 | 空列表引导文案引用已移除的 FAB | `home_page.dart:882,941` | 用户困惑 |

### ⚠️ P2 问题（1 个）

| # | 问题 | 位置 | 影响 |
|---|------|------|------|
| 3 | 设置页 Switch thumb 硬编码白色 | `settings_page.dart:299` | 暗色模式对比度不足 |

---

## 9. 改进建议

### P1-1：统一 SnackBar 系统
```dart
// 所有页面统一使用 AppSnackBar：
AppSnackBar.error(context, '错误信息');
AppSnackBar.success(context, '操作成功');
AppSnackBar.warning(context, '请注意');
AppSnackBar.info(context, '提示信息');
```

### P1-2：更新空列表引导文案
```dart
// 更新为：
'还没有无限画布，点击导航栏 + 按钮新建一个吧'
'还没有笔记本，点击导航栏 + 按钮新建一个吧'
'还没有任何内容，点击导航栏 + 按钮新建吧'
```

### P2-3：Switch thumb 颜色适配
```dart
// 使用 Theme 颜色而非硬编码：
Switch(
  thumbColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) return Colors.white;
    return Theme.of(context).colorScheme.outline;
  }),
)
```

---

## 10. 总结

| 维度 | 评分 | 说明 |
|------|------|------|
| 页面加载 | 9/10 | 首屏流畅，无白屏 |
| 交互反馈 | 7/10 | SnackBar 系统不一致拉分 |
| 错误处理 | 9/10 | 完善的错误分类 + 降级策略 |
| 边界情况 | 8/10 | 空列表引导存在但文案过时 |
| 暗色模式 | 8/10 | 基本完整，个别硬编码颜色 |
| 响应式布局 | 9/10 | 5 级断点 + 自适应组件 |
| 设计系统 | 9/10 | Apple HIG 大标题 + 统一色板 |

**综合评分：8.4/10**

核心功能和设计系统已达到较高水平。主要改进空间在 SnackBar 统一和空列表文案更新。
