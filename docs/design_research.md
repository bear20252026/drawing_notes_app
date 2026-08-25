# Design System Research Report

> 基于 5 个 Penpot 设计系统文件的分析报告
> 生成日期：2026-08-25

## 1. 概览

| 设计系统 | 文件大小 | 页面数 | 适用性 |
|---------|---------|--------|--------|
| Type Scale Playground | 1.9 MB | 3 | ⭐⭐⭐ 直接借鉴字体系统 |
| Calendar Interactive UI Kit | 3 MB | 145 | ⭐⭐ 日历/导航组件参考 |
| @shadcn/ui Design System | 13.6 MB | 1158 | ⭐⭐⭐ 组件库全面参考 |
| Labyrinth UI | 63 MB | - | ⭐⭐ 完整 UI 套件 |
| Ant Design System | 59 MB | - | ⭐ 组件库参考（Ant Design 风格） |
| tailwind-kit | N/A | N/A | ❌ 无效 ZIP，跳过 |

## 2. 详细分析

### 2.1 Type Scale Playground

**结构**：3 个页面（Page 1, Root Frame, The quick brown fox jumps over the）

**可借鉴元素**：
- **字体缩放系统（Type Scale）**：基于数学比例的字体大小阶梯
  - 推荐比例：1.250（Major Third）或 1.333（Perfect Fourth）
  - 基准字号：16px
  - 建议 scale：12, 14, 16, 20, 24, 32, 40, 48 px
- **字体权重层次**：Regular (400), Medium (500), SemiBold (600), Bold (700)
- **行高比例**：标题 1.2，正文 1.5-1.6，小字 1.4

**适配建议**：
- 将 Type Scale 集成到 `lib/core/theme/text_scale_helper.dart`
- 统一全局 `TextTheme` 定义

### 2.2 Calendar Interactive UI Kit

**结构**：145 个页面，包含丰富的日历/预订 UI 组件

**关键页面**：
- Calendar UI Components / Calendar UI Dark / Calendar UI Light
- Date Component / Date Number line
- Nav Bar / Hero Section / Button / Dropdown
- Interactive Prototype Demo

**可借鉴元素**：
- **日历组件**：Date Number line（日期数字行），Month Year line
- **导航栏**：Nav Bar / Nav Links 模式
- **暗色/亮色双主题**：Calendar UI Dark/Light 适配
- **交互原型**：Interactive Component 支持

**适配建议**：
- 如果应用需要日历/时间线视图，参考 Date Component
- Nav Bar 的布局模式可参考用于 settings page
- 双主题方案可直接借鉴到 drawing_notes_app

### 2.3 @shadcn/ui Design System

**结构**：1158 个页面，7513 个文件 — 最全面的组件库

**核心组件列表**：
| 组件 | 状态 | drawing_notes_app 需要 |
|------|------|----------------------|
| Accordion | ✅ | 笔记折叠展示 |
| Alert Dialog | ✅ | 重要操作确认 |
| Avatar | ✅ | 用户头像 |
| Button (default/ghost/subtle/destructive) | ✅ | 统一按钮风格 |
| Checkbox | ✅ | 设置页选项 |
| Dialog | ✅ | 模态弹窗 |
| Dropdown Menu | ✅ | 操作菜单 |
| Input | ✅ | 表单输入 |
| Label | ✅ | 表单标签 |
| Menubar | ✅ | 编辑器菜单栏 |
| Navigation Menu | ✅ | 侧边导航 |
| Popover | ✅ | 工具提示 |
| Progress | ✅ | 导出进度条 |
| Scroll Area | ✅ | 内容滚动区 |
| Select | ✅ | 下拉选择 |
| Separator | ✅ | 分割线 |
| Slider | ✅ | 笔刷大小调节 |
| Switch | ✅ | 设置开关 |
| Tabs | ✅ | 多面板切换 |
| Textarea | ✅ | 笔记文本编辑 |
| Toggle | ✅ | 工具栏切换 |
| Tooltip | ✅ | 图标提示 |

**设计系统（Slate 色板）**：
- `#f8fafc` — Slate 50（背景）
- `#f1f5f9` — Slate 100
- `#e2e8f0` — Slate 200
- `#cbd5e1` — Slate 300
- `#94a3b8` — Slate 400
- `#64748b` — Slate 500
- `#475569` — Slate 600
- `#334155` — Slate 700
- `#1e293b` — Slate 800
- `#0f172a` — Slate 900

**暗色主题色板（从页面分析中提取）**：
- 背景：`#0f172a`（Slate 900）
- 卡片/表面：`#1e293b`（Slate 800）
- 边框：`#334155`（Slate 700）
- 主要文本：`#f8fafc`（Slate 50）
- 次要文本：`#94a3b8`（Slate 400）

**组件变体**：
- **Button**：default, ghost, subtle, destructive, outline
- **Input**：default, small, with button
- **Menu**：menubar, dropdown menu, context menu

**适配建议**：
- ⭐ **最直接参考**：shadcn 的 Slate 色板可直接用在 drawing_notes_app 的暗色主题
- Button 变体系统可直接集成到 `AppTheme`
- Dialog / AlertDialog 可替换现有的简单 AlertDialog
- Progress 组件可用于导出进度显示

### 2.4 Labyrinth UI

**文件大小**：63 MB — 完整 UI 套件

**可借鉴元素**：
- 完整组件库（具体分析受限于文件大小）
- 可能包含表单、导航、数据展示等全套组件

**适配建议**：
- 作为备用参考，当 shadcn 组件不够用时查看

### 2.5 Ant Design System

**文件大小**：59 MB — Ant Design 官方设计系统

**可借鉴元素**：
- Ant Design 风格的组件体系
- 企业级应用的布局模式
- 表格、表单、数据可视化组件

**适配建议**：
- drawing_notes_app 是个人创作工具，Ant Design 风格偏企业级，参考价值有限
- 可参考其数据展示组件（Table, List）

## 3. 适配建议总结

### 3.1 字体系统（来自 Type Scale Playground）

```dart
// lib/core/theme/app_typography.dart
class AppTypography {
  static const double baseFontSize = 16.0;
  static const double scaleRatio = 1.250; // Major Third
  
  // Type Scale
  static const double textXs = 12.0;    // caption
  static const double textSm = 14.0;    // body small
  static const double textBase = 16.0;  // body
  static const double textLg = 20.0;    // subtitle
  static const double textXl = 24.0;    // title
  static const double text2xl = 32.0;   // headline
  static const double text3xl = 40.0;   // display small
  static const double text4xl = 48.0;   // display medium
  
  // Line heights
  static const double leadingTight = 1.2;    // headings
  static const double leadingNormal = 1.5;   // body
  static const double leadingRelaxed = 1.6;  // long text
}
```

### 3.2 暗色主题色板（来自 @shadcn/ui）

```dart
// 建议更新 lib/core/theme/app_theme.dart
class AppColors {
  // Light theme (Slate)
  static const surfaceLight = Color(0xFFF8FAFC);
  static const cardLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFE2E8F0);
  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF64748B);
  
  // Dark theme (Slate)
  static const surfaceDark = Color(0xFF0F172A);
  static const cardDark = Color(0xFF1E293B);
  static const borderDark = Color(0xFF334155);
  static const textPrimaryDark = Color(0xFFF8FAFC);
  static const textSecondaryDark = Color(0xFF94A3B8);
  
  // Accent colors
  static const primary = Color(0xFF6366F1);  // Indigo 500
  static const destructive = Color(0xFFEF4444); // Red 500
  static const success = Color(0xFF22C55E);  // Green 500
  static const warning = Color(0xFFF59E0B);  // Amber 500
}
```

### 3.3 可复用组件优先级

| 优先级 | 组件 | 来源 | 用途 |
|-------|------|------|------|
| P0 | GlassSurface/Dialog | shadcn Dialog | 统一弹窗风格 |
| P0 | Button variants | shadcn Button | 统一按钮系统 |
| P1 | Slider | shadcn Slider | 笔刷大小调节 |
| P1 | Progress | shadcn Progress | 导出进度显示 |
| P1 | Switch/Toggle | shadcn Switch | 设置页开关 |
| P2 | Tabs | shadcn Tabs | 编辑器面板切换 |
| P2 | Dropdown Menu | shadcn Dropdown | 操作菜单 |
| P2 | Tooltip | shadcn Tooltip | 图标提示 |
| P3 | Calendar | Calendar UI Kit | 日历视图（如需要） |

### 3.4 不建议借鉴的部分

- **Ant Design 的企业级组件**（Table、Form Layout）— drawing_notes_app 是个人工具，不需要
- **Calendar UI Kit 的具体实现** — 风格偏预制模板，不如 shadcn 灵活
- **Labyrinth UI 的完整套件** — 太重，不如 shadcn 精简

## 4. 下一步行动

1. **立即**：更新 `AppTypography` 使用 Type Scale 比例
2. **短期**：对齐 `AppColors` 到 shadcn Slate 色板
3. **中期**：引入 shadcn 风格的 Button variants 和 Dialog 系统
4. **可选**：根据需要引入 Slider、Progress 等组件
