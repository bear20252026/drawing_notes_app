# 项目交接报告（Handover Report）

> **项目**：绘图笔记 App（Drawing Notes）
> **交接日期**：2026-08-29
> **交接人**：项目 Lead（Aion CLI）
> **接收方**：后续维护/接手开发团队
> **交接基线**：`master` = `origin/master` = `691aa36`（0 待同步），tag `v1.1.0+2` → `691aa36`
> **仓库**：https://github.com/bear20252026/drawing_notes_app

---

## 0. 文档目的

本报告对项目的**全部工作内容、关键技术决策、对项目的理解**做一次正式、完整、可自检的移交说明，使接手者无需重新考古即可：
1. 快速建立对产品、架构、代码的全局认知；
2. 复现构建/测试/发布流程；
3. 明确已闭环与待办；
4. 理解若干"看似异常、实则有意为之"的设计取舍。

配套资料全部归档在 `docs/`（98 篇）并在下文中给出索引指引。

---

## 1. 项目概况

**绘图笔记 Drawing Notes** 是一套面向 **Windows 桌面 + Android** 的跨平台绘图与笔记应用，使用 **Flutter (Dart)** 开发。项目依据《绘图笔记App-完整方案汇编》实施，**全部为本地离线功能**，不涉及云账号、AI、网络请求（WebDAV 同步除外）。

### 1.1 安全定位（政府级）
- **加密笔记**：K_note，每笔记独立密钥；
- **策略引擎**：默认拒绝（deny-by-default）；
- **会话守卫**：自动锁定；
- **VFS 加密对象仓库**：版本化、原子提交；
- **不可篡改审计**：SHA-256 哈希链；
- **导入隔离**：SVG/PDF 预检。

### 1.2 产品演进三阶段
| 阶段 | 内容 |
|---|---|
| A. 画布/笔记基础（Phase 1-7） | 最小画布→绘图工具→图层→选区变换→笔记→文件持久化→体验打磨 |
| B. AFFiNE 1:1 复刻（M0-M9） | 块模型编辑器 + Edgeless 无限画布双模 + All Docs 工作台 |
| C. WebDAV 加密同步 + Apple(HIG) 标准化（P0-P4 / M10） | 端到端加密同步 + 双模式单风格落地 |

**本阶段设计定位从"自制深蓝视觉"演进为「AFFiNE 1:1 功能 + Apple(HIG) 标准化视觉」的双模单风格体系。**

---

## 2. 技术栈与架构

### 2.1 技术栈
- **Flutter 3.47.0 / Dart 3.12.2**（或更高稳定版）
- **Windows**：Visual Studio 2022+（含"使用 C++ 的桌面开发"组件）
- **Android**：compileSdk 36 + JDK 17 及以上（Gradle 8.x / AGP 8.x）
- **打包**：fastforge（Windows）+ Inno Setup 6（安装包）+ Android（APK/AAB）
- **同步**：WebDAV（本地优先，端到端加密）
- 项目目录名为中文（`画板`），已在 `android/gradle.properties` 设 `android.overridePathCheck=true` 放行。

### 2.2 分层架构（核心约束）
采用 **features → shared → core** 单向依赖分层，由自动化守护强制：
- **core**：主题（`core/theme/`）、领域基础设施、加密、VFS、审计；
- **shared**：跨 feature 复用的组件/工具，**禁止反向依赖 feature**；
- **features**：业务页面与功能模块（notes / all_docs / webdav / home / schedule / 等）。

**守护手段**（均为 CI 门禁，通过才允许合并）：
- `test/forbidden_import_test.dart` —— 禁止跨层逆向引入（feature→core 越界等）；
- `test/architecture_test.dart` —— 层方向 / 零循环 / feature 隔离 / 耦合度量；
- `tools/check_boundaries.sh` —— 依赖边界检查；
- `tools/code_guard.py --dir lib` —— 行数门禁 / 边界静态查。

> 这条边界是**全项目最高优先级的护栏**，任何重构都不得破坏它。已有专门的 `docs/DEPENDENCY_BOUNDARY_GOVERNANCE_*.md` 记录每次边界决策。

---

## 3. 里程碑完成情况（全部 ✅ 闭环）

### 3.1 AFFiNE 块模型与编辑器（M0-M7）
| 里程碑 | 内容 |
|---|---|
| M0 | `NoteBlock` / `NoteBlockEditor` 纯逻辑块模型 |
| M1 | 块式笔记编辑器 UI（`NoteEditorPage`） |
| M2 | 内嵌块渲染（canvas/image/table/database 非文本块） |
| M3 | `NoteBlockDoc` 容器 + 存量迁移 |
| M4 | 块编辑器/NoteBlockDoc 接入导航与打开链路 |
| M5 | 块编辑体验与 AFFiNE 一致性打磨 |
| M6 | 富文本 + / 菜单、图片预览/表格编辑、块手柄拖拽、键盘导航、块间拖拽 |
| M7 | 撤销/重做历史栈、Markdown 导入导出、斜杠菜单搜索分组、块文档搜索索引 |

核心能力：Enter 分块 / Backspace 合并 / 类型切换 / 斜杠菜单 / 块手柄拖拽 / 撤销重做 / Markdown 双向。

### 3.2 Edgeless 无限画布双模（M8）
- `EdgelessDoc` + `NoteFrame` + `EdgelessCamera`
- note 帧在无限画布上**拖拽、缩放、pan-zoom**
- **页 / 画布**双模式切换
- 帧拆分/合并纯逻辑

### 3.3 All Docs 工作台（M9）
- `all_docs/` 三层：**领域模型 + 统一查询 + UI**
- 画布 / 笔记 / 块文档统一列表
- 分组：今天 / 本周 / 更早 / 从未更新
- 工作区侧栏 + 新建 + 搜索
- 关键优化：**缓存 `loadDocs` Future 避免切 tab 闪屏**（commit `7befb32`）

### 3.4 Apple(HIG) 标准化（M10）
详见 §4。

### 3.5 WebDAV 端到端加密同步（P0-P4）
详见 §5。

---

## 4. 双模式单风格设计系统（M10 定稿）

**设计哲学**：一套结构风格走天下（Apple），按**亮度**切换**色板**。这是"明亮=Apple、黑暗=深蓝"的折中——既拥抱 Apple 的现代简洁，又保留原有深蓝品牌识别。

### 4.1 色板（token）
| 维度 | 明亮模式（Apple） | 黑暗模式（深蓝，保留原设计） |
|---|---|---|
| 主强调 | `#0066CC` actionBlue | `#B5CCFF`（暗底主色 / inverse `#4568A9`） |
| 画布背景 | `#F5F5F7` parchment | `#101521` / `#172033` |
| 表面 | `#FFFFFF` / `#EBEBED` | `#181F2E` / `#222B3D` |
| 文本 | `#1D1D1F` / `#6E6E73` | `#E2E8F4` |
| 结构（两模式统一） | 圆角 18/12 · 间距 20/12 · w600 负字距 · pill/卡片 · `ZoomPageTransitionsBuilder` | 同左 |

### 4.2 Token 文件与复用件
- `lib/core/theme/app_design.dart`：`_theme(Brightness)` 双色板（`_appleLightScheme()` + `_navyScheme()`），`AppDesign.darkTheme()` 返回深蓝主题。
- `lib/core/theme/apple_design.dart`：`AppleColor` / `AppleSpacing` / `AppleRadius` / `AppleType` token + 复用件 `ApplePrimaryButton` / `ApplePillSearchField` / `AppleSectionHeader`。

### 4.3 M10 改动范围（仅展示层，不改编辑/逻辑行为）
| 文件 | 改动 |
|---|---|
| `note_editor_page.dart` | 块类型工具栏/AppBar 用 `colorScheme.primary` / `AppleColor`；块聚焦高亮/手柄/dropline 用 `#0066CC`；标题 w600 + 负字距 |
| `note_doc_modes_page.dart` | 页/画布切换控件、AppBar、容器背景 → 米白/白表面 + 胶囊控件 |
| `edgeless_page.dart` | 帧卡片/选中描边/缩放环/命令面板/AppBar → Apple 色板 |
| `note_frame_preview.dart` | 帧预览占位/边框 → Apple 色板 + `AppleRadius.lg` |
| `home_page.dart` | AppBar/搜索框（`ApplePillSearchField`）/卡片列表 → Apple token |
| `schedule_page.dart` | 日格/选中态/今天标识/事件点 → `#0066CC` |
| `notes_writing_page.dart` | AppBar/列表/分组头/空态 → Apple token |
| `webdav_sync_settings_page.dart` | 表单/按钮（`ApplePrimaryButton`）/错误（`AppleColor.errorRed`） |

**旧色→Apple 映射**：`#4568A9→#0066CC`、`#7C4DFF→#BF5AF2`、`#166C59→#30D158`、`#F5A623→#FF9F0A`。
M10 收口后**全库无旧深蓝/旧紫硬色**。

### 4.4 域层默认色修正
- `edgeless_connector.dart`：`kDefaultConnectorColor = '#7C4DFF'` → `'#0066CC'`（Apple actionBlue），对应测试断言同步，不破坏。

---

## 5. WebDAV 端到端加密同步体系

### 5.1 设计理念：本地优先（local-first）
同步引擎采用 **planner + transport + orchestrator** 三层，保证可测性与可观测性。

### 5.2 关键模块
- **SyncCipher（端到端加密）**：AES-256-GCM + AAD + HMAC 文件名 + PBKDF2，密钥从 OS 凭据库读取（`SyncSecretStore` 纯容器 + 注入式实现），避免明文入库。
- **SyncPlanner**：规划同步操作（增量/差分）。
- **SyncRetryPolicy**：失败有界重试（纯逻辑）。
- **SyncProgress**：同步进度模型（纯逻辑），驱动 UI 进度。
- **冲突可见性**：版本冲突暴露给用户，`interactive conflict resolution UI`（keep local / remote / both）。
- **可观测性**：进度回调 + 冲突可见 + 失败有界重试（commit `0c5d1ba`）。
- **配置存储**：URL/账号/立即同步/保存，机密移入 OS 凭据库（`73b4354`）。

### 5.3 相关验收文档
`docs/WEBDAV_SYNC_ACCEPTANCE_2026-08-29.md`、`docs/RELEASE_PACKAGING_ACCEPTANCE_2026-08-29.md`（含端到端加密/可观测/机密安全/冲突解析各段）。

---

## 6. 工程化与质量门禁

### 6.1 当前数据化成果（M10 收口）
- `flutter analyze` → **0 问题**（用 `dart analyze`；flutter analyze 的 LSP 通道与中文路径有兼容问题，故用 dart analyze）
- `flutter test --concurrency=1` → **1255 全通过**（覆盖 Phase 1-7 + 安全审计回归 + M0-M10 AFFiNE 块模型/edgeless/All Docs/WebDAV 同步）
- 架构依赖边界（features→shared→core 单向、零循环、feature 隔离、耦合度量）→ ✅ 通过
- 库代码 229 个 dart 文件 / 约 42,500 行；测试 184 个 `*_test.dart`；docs 98 篇；GitHub Actions 12 条流水线

### 6.2 常用命令
```bash
flutter pub get
dart analyze            # 静态检查（用 dart analyze 而非 flutter analyze）
flutter test            # 全量单元/组件测试
flutter test test/architecture_test.dart   # 架构守护
bash tools/check_boundaries.sh             # 边界检查
python tools/code_guard.py --dir lib --force-native --json   # 行数门禁
```

### 6.3 测试约定
- **MUI 方言探针**：项目同时用了 `material_ui`（自带 MaterialApp/Theme/ThemeMode）与 `flutter/material`。探针 App 的 MaterialApp 时**必须只用 `material_ui` 的 `Theme.of`**（仅 import `package:material_ui`），混用 Flutter 的 `Theme.of` 会产生误报。
- **l10n 修复**：`material_ui` 定义了自己的 GlobalMaterialLocalizations，与 Flutter SDK 的冲突导致 `No MaterialLocalizations found`。修复为**同时注册双方 GlobalMaterialLocalizations 委托**（commit `e8ce8e4`），并有回归测试 `3b30aa8` 锁定（`test(l10n): add regression for Flutter TextField under material_ui MaterialApp`）。

---

## 7. 构建与发布

### 7.1 本地构建
- **Windows**：`flutter build windows --release` → `build\windows\x64\runner\Release\drawing_notes_app.exe`
- **Android**：`flutter build apk --release`（88,419,490 B）+ `flutter build appbundle --release`（76,644,004 B）
- **Windows 安装包**：fastforge `package windows exe` + Inno Setup 6 → `setup_drawing_notes_1.1.0.exe`（16 MB）

### 7.2 云端 CI 构建（本阶段新增，已验证）
`.github/workflows/release-build.yml`（windows job）实现 **tag 自动触发**全流程：
```
push tag v* → 构建 Windows release → choco 装 Inno Setup 6
→ 编译 tools/drawing_notes_setup.iss → 上传 windows-setup-installer artifact
→ softprops/action-gh-release 自动创建/更新 GitHub Release 挂载 .exe
```
- Android job 走同一 workflow（`inputs.build_windows` 或 tag 触发）。
- **已实测**：tag `v1.1.0+2` 指向 `691aa36` 触发，运行 `33258837602` 全绿；GitHub Release `v1.1.0+2` 挂载 `setup_drawing_notes_1.1.0.exe`（16 MB）。

### 7.3 **关键坑：中文文件名在 Release 上被剥离**
- 现象：Inno `OutputBaseFilename` 用中文 `setup_绘图笔记_<版本>.exe` 时，GitHub Release 上传会把非 ASCII 折叠成 `setup_._1.1.0.exe`。
- 修复：改为 **ASCII** `setup_drawing_notes_<版本>.exe`（commit `691aa36`）。本地与云端统一干净命名；**安装在开始菜单/应用标题里的中文名「绘图笔记」不受影响**。
- 教训：**所有进入 GitHub Release/artifact 的文件名必须 ASCII**，避免命名被剥离。

---

## 8. 团队协作与流程

本项目采用 **Lead（协调者）+ Teammate B / Teammate A** 三人协作模式。
- **Lead**：负责总体架构、任务拆分、验收把关、文档同步、构建发布、问题收敛；
- **Teammate B**（`01a047e4-cb39-71f3-be70-80e8341bc6b1`）：M10-B（home/schedule/notes_writing/webdav_sync_settings 页 Apple 化）、M9-3（All Docs 工作台 UI）、P4-C1（SyncSecretStore）等；
- **Teammate A**（`01a047de-da06-7382-9893-9335c83ae961`）：M10-A（块编辑器/双模/Edgeless 页 Apple 化）、M9-1/2（AllDoc 领域模型 + 统一查询）、P4-B1（SyncRetryPolicy）、P4-B3（同步可观测性收口）等。

**协作机制要点**：
- 任务通过 **任务看板** 分配（owner + blocked_by），完成即置 completed；
- Teammate 产出由 Lead **独立复验**（analyze/test/架构测试）后方可合并；
- 关键文档由 Lead 统一同步进 `docs/` 并推送到 GitHub（开源仓库同步，sync 0/0）。

---

## 9. 遇到的关键问题与解决（经验沉淀）

| 问题 | 根因 | 解决 |
|---|---|---|
| `material_ui` 方言冲突（MaterialLocalizations） | `material_ui` 定义独立 MaterialApp/GlobalMaterialLocalizations，与 Flutter SDK 冲突 | 同时注册双方 GlobalMaterialLocalizations 委托 + 回归测试锁定 |
| `material_ui` 主题探针误报 | 混用 Flutter 与 mui 的 `Theme.of` | 探针只 import `package:material_ui` 的 `Theme.of` |
| Windows shared_preferences 外部改主题不可靠 | 插件缓存/异步写 | 用 App 内设置切换 or 测试中 mock prefs；已用 E2E probe 测试证明代码路径正确 |
| 中文路径导致 flutter analyze LSP 通道兼容问题 | flutter analyze 与中文目录兼容性 | 改用 `dart analyze` |
| GitHub Release 中文文件名被剥离 | 上传流程折叠非 ASCII | `OutputBaseFilename` ASCII 化（见 §7.3） |
| Inno Setup 无中文本地化文件 | Inno 6 缺 `ChineseSimplified.isl` | 改用英文语言脚本 |
| PyYAML 把 workflow 的 `on` 当布尔 | YAML 1.1 与 GitHub YAML 1.2 差异 | 通过 `d['jobs']` 访问验证，不动 workflow |
| 多行提交信息在 cmd 被 `()` 破坏 | cmd 解析括号 | 用 PowerShell `Set-Content` + `git commit -F`（或写文件再 `-F`） |

---

## 10. 尚未完成 / 后续跟进项

### 10.1 待办（低优先级，均不影响当前交付）
1. **app_shell 最左导航栏亮色下仍为深蓝底**：若要"明亮=全 Apple"，需将其改为米白/浅色。当前为观察项，用户未要求修改。
2. **Android APK 打包**：可用 `release-build.yml` 的 android job（同一 workflow）打包，本次未请求。

### 10.2 需要注意的既有约定（非 bug）
- **深蓝深色模式**是刻意保留，不是遗漏（见 §4 双模式单风格定稿）。
- **`dart analyze` 是标准静态检查**，不要因为 README 写 `flutter analyze` 而误用。
- **git tag 版本号含 `+`（`v1.1.0+2`）** 与 pubspec 的 build number 一致；推 tag 会自动触发云端 Release Build。

---

## 11. 参考资料索引

### 11.1 必读（按顺序）
| 文档 | 说明 |
|---|---|
| `docs/PROJECT_MASTER_PLAN.md` | 项目总计划 |
| `docs/ARCHITECTURE.md` | 架构总览 |
| `docs/DEPENDENCY_BOUNDARY_GOVERNANCE_*.md` | 依赖边界治理（最强护栏） |
| `docs/M10_APPLE_HIG_ACCEPTANCE_2026-08-29.md` | M10 Apple(HIG) 收口 + 双模式单风格验收 |
| `docs/M9_ALL_DOCS_ACCEPTANCE_2026-08-29.md` | All Docs 工作台验收 |
| `docs/WEBDAV_SYNC_ACCEPTANCE_2026-08-29.md` | WebDAV 加密同步验收 |
| `docs/RELEASE_PACKAGING_ACCEPTANCE_2026-08-29.md` | 发布打包验收（本地） |
| `docs/RELEASE_MANUAL_TEST_ACCEPTANCE_2026-08-29.md` | 电脑端真机实测验收 |

### 11.2 按主题
- **架构/边界**：`docs/ARCHITECTURE_ANALYSIS_2026-08-15.md`、`ARCHITECTURE_ASSESSMENT_2026-08-15.md`、`CODE_STRUCTURE_ASSESSMENT_2026-08-27.md`、`LAYERED_DEV_FRAMEWORK.md`、`MASTER_ARCHITECTURE_BLUEPRINT_2026-08-14.md`
- **AFFiNE/Excalidraw 复刻**：`EXCALIDRAW_*`、`OPEN_SOURCE_REFERENCE_MAP_2026-08-14.md`、`block_editor_affine_consistency.md`、`edgeless_affine_consistency.md`
- **设计系统**：`APPLE_DESIGN_SYSTEM_2026-08-29.md`、`EXPERIENCE_DESIGN_SYSTEM_2026-08-14.md`
- **安全**：`SECURITY_AUDIT.md`、`supply_chain_evidence.md`、`encrypted_asset_vault_design.md`、`PASSWORD_DISK_DESIGN.md`
- **打包**：`RELEASE_PACKAGING_GUIDE_2026-08-14.md`、`RELEASE_PACKAGING_ACCEPTANCE_2026-08-29.md`
- **编辑器交互**：`EDITOR_*`（interaction/presentation/resize/crop 等 governance 系列）
- **计划/经验**：`PROJECT_EXPERIENCE.md`、`LEARNED.md`、`PHASES.md`、`DEV_QUALITY_GUIDE*`、`COMMAND_CYCLE_GOVERNANCE_2026-08-27.md`

---

## 12. 对项目的整体理解与判断

1. **这是一个"功能-视觉-工程"三线并重的项目**。功能上向 AFFiNE 1:1 看齐（块模型 + edgeless + All Docs），视觉上向 Apple HIG 靠拢（双模式单风格），工程上以架构边界 + 自动化测试 + CI 门禁作为质量底座。三者相互约束，任何单点改动都需同时评估对另外两条线的影响。

2. **最强护栏是依赖边界**（features→shared→core）。它决定了所有 feature 能否独立演化、能否安全重构。任何"看起来方便但破坏边界"的改动都应被拒绝。

3. **"双模式单风格"是当前最重要的视觉决策**。它既不是纯 Apple 也不是纯深蓝，而是"结构 Apple、颜色随亮度"。理解这一点是看懂所有页面配色的钥匙——**深色下的深蓝不是没改，是刻意保留**。

4. **`material_ui` 与 Flutter 的方言共存是本项目最隐蔽的坑**。凡是涉及 MaterialApp / Theme / MaterialLocalizations / 主题探针的改动，都必须用 mui 方言处理，否则会踩到"看似正常实则误报/报错"的坑。回归测试已把 l10n 问题锁死，但主题探针仍要小心。

5. **可测性设计是同步/编辑器体系能安全演进的前提**。大量纯逻辑（SyncCipher/SyncPlanner/SyncRetryPolicy/SyncProgress/块模型/EdgelessCamera）被刻意抽成"领域"层，正是为了能在不启动 UI 的情况下被测试锁定。接手后应**延续这一分层习惯**，不要把纯逻辑写进展示层。

6. **交付链路已打通到"云端一键出安装包"**。本地 + CI 双通道构建、ASCII 命名规范、tag 触发 Release 都已验证。后续版本发布只需：`bump pubspec 版本 → 打新 tag → 推 tag`，即可在云端自动出 Windows 安装包与 GitHub Release。

7. **这是一个"可交付、可审计、可演化"的中型 Flutter 应用**，当前状态健康（analyze 0、测试 1255 全绿、架构边界通过、本地+云端发布链路闭环）。后续若继续深化，重点方向是：① app_shell 左栏亮色化；② Android APK 云端打包；③ 进一步打磨块编辑与 AFFiNE 的一致性；④ 持续维护架构边界与测试。

---

*本报告由项目 Lead（Aion CLI）编写，审计自实际 git 历史、构建日志与验收文档。所有结论均可通过 `git` 历史与 `docs/` 复核。*
