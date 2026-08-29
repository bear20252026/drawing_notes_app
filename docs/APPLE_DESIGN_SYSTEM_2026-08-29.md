# Apple (HIG) 设计系统 —— 标准化实施记录

日期：2026-08-29
里程碑：M9 All Docs 工作台 + Apple (HIG) 设计系统（commit `56f2e43`）
门禁：`flutter analyze` 0 / architecture 通过 / 全量回归 **1248** 全通过

## 目标

用户 directive：「使用苹果的设计语言对这个项目进行完成标准化的UI设计，完全1:1设计，完全照搬苹果」。本项目采用 Apple (HIG) 设计语言对全应用进行标准化：单一强调色、低噪声表面层级、胶囊按钮与圆角卡片、SF 风格排版（标题 w600 + 负字距）。

## Token 来源

`npx --yes getdesign@latest add apple` 生成的 `DESIGN.md` 按 Apple HIG 抽取，落地为 Flutter 可用的 token 模块：

- **`lib/core/theme/app_design.dart`** — 全局主题（`lightTheme()` / `darkTheme()`），已被 `themeProvider`（`core/di/providers.dart`）与 `app.dart` 的 `darkTheme` 采用，**所有页面自动跟随**。颜色为苹果色板；结构常量（`pagePadding`/`cardRadius`/`controlRadius`/`quickMotion`/`standardMotion`）保持不变以兼容既有测试。
- **`lib/core/theme/apple_design.dart`** — Apple token（`AppleColor` / `AppleSpacing` / `AppleRadius` / `AppleType`）+ 可复用部件（`ApplePrimaryButton` / `ApplePillSearchField` / `AppleSectionHeader`），供各页面统一采用。

## Token 速查

| 语义 | 亮色 | 暗色 | token |
|---|---|---|---|
| 主强调 Action Blue | `#0066CC` | `#2997FF` | `AppleColor.actionBlue` / colorScheme.primary |
| 主墨色 | `#1D1D1F` | `#F5F5F7` | `AppleColor.ink` |
| 次要墨 | `#6E6E73` | `#98989F` | `AppleColor.inkMuted` |
| 淡墨（辅助） | `#98989F` | `#98989F` | `AppleColor.inkSubtle` |
| 画布 | `#F5F5F7` | `#000000` | `AppleColor.parchment` / canvansDark |
| 表面 | `#FFFFFF` | `#1D1D1F` | `AppleColor.surfaceWhite` / surfaceDark |
| 芯片底 | `#EBEBED` | `#2C2C2E` | `AppleColor.subtleSurface` |
| 细描边 | `#E0E0E0` | `#3A3A3C` | `AppleColor.hairline` |
| 系统绿（笔记） | `#30D158` | 同 | `AppleColor.noteGreen` |
| 系统紫（块文档） | `#BF5AF2` | 同 | `AppleColor.blockPurple` |
| 星标/收藏 | `#FF9F0A` | 同 | `AppleColor.favourite` |
| 错误 | `#FF3B30` | `#FF453A` | `AppleColor.errorRed` |

- **间距刻度**（base=8）：`AppleSpacing.xxs4 / xs8 / sm12 / md16 / lg24 / xl32 / xxl48`
- **圆角**：`AppleRadius.xs6 / sm10 / md12 / lg18 / full9999`
- **排版**（SF 风格）：标题 = w600 + 负字距；正文 17px；控制 13px；标注 11.5px + 0.2 字距。`AppleType.headlineStyle/titleStyle/bodyStyle/controlStyle/captionStyle(color)`。
- **复用部件**：`ApplePrimaryButton`（胶囊强调按钮）、`ApplePillSearchField`（胶囊搜索框）、`AppleSectionHeader`（分组标题灰字+字距）。

## 落地范围

1. **全局主题**：`app_design.dart` 重着色 + `apple_design.dart` 建 token/部件（commit `56f2e43`）。
2. **All Docs 主页（AFFiNE 1:1）**：`features/all_docs/presentation/` 全部改用苹果 token（主区白表面、侧栏米白/暗画布、新建文档=`ApplePrimaryButton`、搜索=`ApplePillSearchField`、kind 图标 = canvas 蓝 / note 绿 / blockdoc 紫）。
3. **其它页面**（home / schedule / notes_writing / webdav_sync_settings / note_editor / note_doc_modes / edgeless / note_frame_preview）：逐页按 token 打磨（进行中，M10-A / M10-B）。

## 约定

- 主强调只用一个 Action Blue，克制使用；次级控件用灰阶（`onSurfaceVariant` / `inkMuted`）。
- 表面层级低噪声：米白画布 + 白色表面 + hairline 细描边，去硬阴影。
- **禁止**再写旧深蓝色板：`#4568A9 / #172033 / #181F2E / #222B3D / #F6F7FA / #7C4DFF / #F5A623`；一律用 `Theme.of(context).colorScheme` 或 `AppleColor`。
- 深色模式：以系统（亮/暗）为准，暗色用暗画布 `#000` + 暗表面 `#1D1D1F`。

## 技术注意

- `material_ui` 是 vendored 1:1 Material 库：**`CupertinoPageTransitionsBuilder` / `FadeUpwardsPageTransitionsBuilder` 不在其导出中**，页面转场统一用 `ZoomPageTransitionsBuilder`（`app_design.dart` 已如此）。
- `apple_design.dart` **只** import `package:material_ui/material_ui.dart`；勿同时 import `package:flutter/material.dart`（会与 material_ui 重定义类型冲突）。
- `NoteBlockDocStore.newId()` / `NotebookStorage.newId('notebook')` 是**静态**方法，非实例方法。
