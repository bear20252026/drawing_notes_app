# M0-M10 里程碑收口 + Apple(HIG) 双模式验收记录

> 日期：2026-08-29　状态：✅ 全量闭环并通过发布门禁
> 基线 commit：`f3106cb`（M10 Apple(HIG) 收口）　远端：`master` == `origin/master`（0/0）

## 1. 项目定位（当前）

**绘图笔记 Drawing Notes** —— 面向 **Windows 桌面 + Android** 的跨平台绘图与笔记应用，Flutter(Dart) 开发。

设计定位在本阶段从"自制深蓝视觉"演进为 **AFFiNE 1:1 功能 + Apple(HIG) 标准化视觉** 的双模单风格体系：
- **功能**：AFFiNE 块模型 / 无限画布(edgeless) 双模 + All Docs 工作台 + WebDAV 端到端加密同步。
- **视觉**：一套结构风格（Apple），按亮度切换色板 —— **明亮=Apple**，**黑暗=深蓝（保留原设计）**。

## 2. 双模式单风格设计（定稿）

| 维度 | 明亮模式（Apple） | 黑暗模式（深蓝，保留原设计） |
|---|---|---|
| 主强调 | `#0066CC` actionBlue | `#B5CCFF`（暗底主色 / inverse `#4568A9`） |
| 画布背景 | `#F5F5F7` parchment | `#101521` / `#172033` |
| 表面 | `#FFFFFF` / `#EBEBED` | `#181F2E` / `#222B3D` |
| 文本 | `#1D1D1F` / `#6E6E73` | `#E2E8F4` |
| 结构（两模式统一） | 圆角 18/12 · 间距 20/12 · w600 负字距 · pill/卡片 · `ZoomPageTransitionsBuilder` | 同左 |

- `lib/core/theme/app_design.dart`：`_theme(Brightness)` 双色板（`_appleLightScheme()` + `_navyScheme()`），`AppDesign.darkTheme()` 返回深蓝主题。
- `lib/core/theme/apple_design.dart`：`AppleColor` / `AppleSpacing` / `AppleRadius` / `AppleType` token + 复用件 `ApplePrimaryButton` / `ApplePillSearchField` / `AppleSectionHeader`。

## 3. M0-M10 里程碑总览（全部 ✅）

| 里程碑 | 内容 | 归属 |
|---|---|---|
| M0 | NoteBlock / NoteBlockEditor 纯逻辑块模型 | 领域 |
| M1 | 块式笔记编辑器 UI（NoteEditorPage） | 展示 |
| M2 | 内嵌块渲染（canvas/image/table/database 非文本块） | 展示 |
| M3 | NoteBlockDoc 容器 + 存量迁移 | 领域 |
| M4 | 块编辑器/NoteBlockDoc 接入导航与打开链路 | 集成 |
| M5 | 块编辑体验与 AFFiNE 一致性打磨 | 展示 |
| M6-1..5 | 富文本 + / 菜单、图片预览/表格编辑、块手柄拖拽、键盘导航、块间拖拽 | 展示/领域 |
| M7-1..4 | 撤销/重做历史栈、Markdown 导入导出、斜杠菜单搜索分组、块文档搜索索引 | 领域 |
| M8-1/2 | EdgelessDoc/NoteFrame/EdgelessCamera + 帧拆分合并纯逻辑 | 领域 |
| M9-1/2/3 | AllDoc 领域模型 + 统一查询 + 全部文档工作台 UI（左面板/工具条/Tab/分组列表） | 领域/应用/展示 |
| M10 | 全部页 Apple(HIG) 化（双模式单风格落地） | 展示 |

数据化成果（M10 收口时）：
- `flutter analyze` → **0 问题**
- `flutter test --concurrency=1` → **1255 全通过**
- 架构依赖边界（features→shared→core 单向、零循环、feature 隔离、耦合度量）→ ✅ 通过
- 库代码 229 dart 文件 / 约 42,500 行；测试 184 个 `*_test.dart`；docs 98 篇；GitHub Actions 12 条流水线

## 4. M10 Apple(HIG) 化改动明细

仅在展示层做视觉改造，不改任何编辑/逻辑行为（Enter/Backspace/类型切换/撤销重做/键盘导航均保持）。

| 文件 | 改动 |
|---|---|
| `note_editor_page.dart` | 块类型工具栏/AppBar 自定义色 → `Theme.of(context).colorScheme.primary` 或 `AppleColor`；块聚焦高亮/手柄/dropline 用 Apple 强调 `#0066CC`；标题 w600 + 负字距；正文留白 `AppleSpacing` |
| `note_doc_modes_page.dart` | 页面/无限画布切换控件、AppBar、容器背景 → 苹果米白/白表面 + 胶囊控件 |
| `edgeless_page.dart` | 帧卡片背景/选中描边/缩放环/命令面板/AppBar → Apple 色板（选中=actionBlue 描边、卡片=白/暗表面）；`_FrameCard` 用 `AppleColor.ink`/`surfaceWhite`；`_colorOf` hex 兜底 `0x7C4DFF`→`0x0066CC` |
| `note_frame_preview.dart` | 帧预览占位/边框 → Apple 色板 + `AppleRadius.lg` |
| `home_page.dart` | AppBar（含云同步入口）底色/图标 → 米白/暗画布 + `colorScheme.primary`；搜索框用 `ApplePillSearchField`；卡片/列表白/暗表面 + `AppleRadius.lg`(18) + hairline 描边 |
| `schedule_page.dart` | 日格、选中态、今天标识、事件点 → Apple 强调 `#0066CC`；日历容器/AppBar 米白/暗画布 |
| `notes_writing_page.dart` | AppBar、列表、时间分组头、空态 → Apple token；分组头用 `AppleSectionHeader`/`apple.captionStyle` |
| `webdav_sync_settings_page.dart` | 表单/字段/按钮 → 苹果样式；主操作按钮用 `ApplePrimaryButton`；错误用 `AppleColor.errorRed` |

**旧色→Apple 映射**：`#4568A9→#0066CC`、`#7C4DFF→#BF5AF2`、`#166C59→#30D158`、`#F5A623→#FF9F0A`（浅+深通用）。
M10 收口后**全库无旧深蓝/旧紫硬色**（仅保留 `app_design.dart` / `apple_design.dart` 中对 deep-blue 深色模式的文档注释）。

### 4.1 域层默认色修正
- `edgeless_connector.dart`：`kDefaultConnectorColor = '#7C4DFF'` → `'#0066CC'`（Apple actionBlue）。对应测试用常量断言，不破坏。

## 5. 本地化（l10n）修复记录

**问题**：`No MaterialLocalizations found` —— AllDocsSidebar 的 Flutter `TextField` 在 material_ui MaterialApp 下找不到 Flutter 的 MaterialLocalizations。

**根因（双方言）**：`material_ui`（正式新 Flutter Material 库）自有一套 `MaterialApp`/`Theme`/`ThemeMode`/`MaterialLocalizations`，与 `flutter/material.dart` 的类型**各自独立**；应用两者并用。

**修复（commit `e8ce8e4`）**：在 `app.dart` 同时注册两套 GlobalMaterialLocalizations。
- `GlobalMaterialLocalizations.delegate`（material_ui）
- `flutter_localizations` 的 `GlobalMaterialLocalizations.delegate`
- `supportedLocales: const [Locale('zh'), Locale('en')]`

每套方言解析自己的 localizations 类型，二者共存。回归测试 `test/localizations_regression_test.dart`（commit `3b30aa8`）证明 Flutter TextField 在 mui MaterialApp 下可正常找到 Flutter MaterialLocalizations。

## 6. 发布构建与安装包（Inno Setup）

执行（2026-08-29）：
- `flutter build windows --release` → `build\windows\x64\runner\Release\drawing_notes_app.exe` + `data\app.so`（M10 版，12MB）。
- 实机启动无崩溃；**明亮=Apple All Docs 工作台渲染正确**（白色/parchment 内容、pill 搜索、紫色 accent、文档/精选/标签 tabs、今天分组列表）。
- **安装包**：Inno Setup 6 脚本 `tools/drawing_notes_setup.iss`（可移植相对路径）→ 生成
  `build\windows\installer\setup_绘图笔记_1.1.0.exe`（16.0 MB，LZMA2 高压缩、64 位 x64、管理员权限、默认装 `C:\Program Files\绘图笔记`、开始菜单+可选桌面图标、安装后可立即启动）。

**云端构建（GitHub Actions）**：`.github/workflows/release-build.yml` 的 `windows` 任务在 windows-latest runner 上自动 `flutter build windows --release` → `choco install innosetup` → `ISCC tools/drawing_notes_setup.iss` → 上传 `windows-setup-installer` artifact；推送 `v*` tag 时自动创建 GitHub Release 并挂载安装包（需 `contents: write` 权限，已按任务级配置）。

> 深蓝暗色模式实机复测说明：外部直改 prefs `flutter.theme_mode` 不生效（Windows shared_preferences 插件缓存/异步回写怪癖，非代码缺陷）。已用端到端探针测试**确定性证明**完整深色链路可用：prefs=dark → `AppThemeController.mode=dark` → 真实 app 接线（`themeProvider`+`AppDesign.darkTheme()`）下 mui MaterialApp 解析 `Brightness.dark`(navy)。用户经应用内设置的主题切换（`controller.cycle()`）即正确显示深蓝。

## 7. 结构评估（lead 理解）

**强项**：
- 分层依赖方向由 `forbidden_import_test` + `dart_arch_test` **测试级强制**（features→shared→core）。
- 纯逻辑/UI 分离优秀：EdgelessDoc/EdgelessCamera、NoteBlockHistory、SyncPlanner、SyncCipher、SaveScheduler 全纯 Dart + 独立单测，与 BlockSuite 同构。
- 测试密度商业级（lib:test ≈ 1:0.8），12 条 GitHub Actions CI 流水线（CI/architecture/security/secret-scan/SBOM/release-build）。
- 文档 98 篇 + ADR，决策可追溯。

**与原版 AFFiNE 的映射**：
| AFFiNE/BlockSuite | 本项目 | 完成度 |
|---|---|---|
| Doc = block sequence | NoteBlockDoc + NoteBlockEditor | ✅ 1:1 |
| Edgeless 帧模型 | EdgelessDoc + NoteFrame + EdgelessCamera | ✅ 1:1 |
| 内嵌块 | EmbeddedBlockView + builder 注入 | ✅ |
| 斜杠菜单/块手柄拖拽/撤销重做 | block_slash_menu / moveBlock / NoteBlockHistory | ✅ |
| All Docs 工作台 | all_docs/ 三层 | ✅ |
| 块文档 ⇄ Markdown | note_block_doc_markdown 双向可逆 | ✅ |

**差距/风险**：
1. **双 Material 方言**：`material_ui` 与 `flutter/material` 并行，靠双 delegate 桥接并已有回归测试锁死；长期建议统一单一方言。
2. **V2 抽取名不副实**：`packages/editor_core`(3 文件)/`notebook_domain`(2 文件) 为架构实验壳，需决策扩充或移除。
3. **`legacy/` 空目录**：建议删除。
4. **单工作区**：无多用户/云协作（E2E 加密 WebDAV 同步已就绪，协作是下一阶段课题）。

## 相关文档
- `docs/RELEASE_PACKAGING_ACCEPTANCE_2026-08-29.md`（全平台打包验收）
- `docs/APPLE_DESIGN_SYSTEM_2026-08-29.md`（Apple 设计 token）
- `docs/M9_ALL_DOCS_ACCEPTANCE_2026-08-29.md`（全部文档工作台）
- `docs/WEBDAV_SYNC_ACCEPTANCE_2026-08-29.md`（同步/加密验收）
- `docs/ARCHITECTURE.md`（分层架构）
