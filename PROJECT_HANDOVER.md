# 绘图笔记（Drawing Notes）项目交接文档

> 生成日期：2026-08-24（周一）
> 项目根目录：`D:\write\1\build_latest\drawing_notes_app`
> 分支：`ci/week1-smoke-run`（PR #1——GitHub：bear20252026/drawing_notes_app）
> 提交：153 个（最新 `9792b91`）——Actions 始终绿色

---

## 一、项目概况

**绘图笔记**：跨平台笔记 + 画板应用（Flutter——Android + Windows）。
核心定位：**笔记 = Word 文档式直接打字** + **画布 = 无限画布手写绘图**——
**同一编辑器两种模式**（AFFiNE Page/Edgeless 借鉴）——功能共通避免重复维护。

当前状态：**可运行**（Windows 已安装 `D:\software\绘图笔记`——Android APK 桌面交付）——
435 项测试全过——analyze 1 info 不阻塞。

## 二、文件位置总表（全部项目资料所在地）

### 2.1 核心源码（lib/）

| 位置 | 内容 |
|------|------|
| `lib/app/composition_root.dart` | 组合根（依赖注入——四层架构入口） |
| `lib/core/` | 核心层：`di/`（依赖注入）、`security/`（安全——加密服务）、`storage/`（存储——V2 加密事务）、`theme/`（主题）、`utils/`、`rtf_exporter.dart`、`notes_accessor.dart` |
| `lib/features/editor_v2/` | **统一编辑器（V2——笔记+画板共用）**：`application/`（EditorV2Notifier/StrokeStyleNotifier/PagedCanvasViewModel/InfiniteCanvasNotifier/ExportService 等）+ `presentation/`（EditorV2Screen/CanvasPainterV2/InfiniteCanvasWidget/NoteEditorWidget（Word 文档式笔记）/Toolbar/Sidebar/LayerPanel/PropertyPanel/HistoryPanel/ExportPanel）+ `adapters/DrawingAdapter` |
| `lib/features/notes/` | 笔记（V1——封存）：`presentation/home_page.dart`（首页——入口已指向 V2）/`notebook_view_page.dart`（V1 material_ui——已替换）/`password_disk_page.dart` 等 |
| `lib/features/drawing/` | 画板（V1——封存 Legacy——大文件 1071 行）：`editor_page.dart` 等 |
| `lib/shared/widgets/` | 共用 Widget：`apple_glass.dart`（苹果 Liquid Glass 毛玻璃）/`glass_surface.dart`/`ambient_background.dart` |

### 2.2 纯 Dart 核心库（packages/editor_core——52 个 domain 模块）

| 位置 | 内容 |
|------|------|
| `packages/editor_core/lib/src/domain/` | **52 个领域模型**（禁 Flutter/dart:io——积木式）：DocumentV2/LineItem/ShapeItem/TextItem/PageV2/TableV2/NoteItem/RichTextBlock/**NoteParagraph（Word 文档段落）**/ShapeLibrary/StrokeStyle/BrushStyles（Saber 画笔组）/ArrowBinding/ClipboardData/LassoSelection/GridConfig/InlineEditState/ChartData/I18nService/AnimatedTrail/Measurement/GestureRecognizer/NodeGraph/Alignment/CommandPalette/FeatureFlag/WorkspaceManager/Frame/BoundText/DocumentImporter/HintSystem/**EncryptionVault/EncryptionScope/EncryptionAccess/RecoveryKey**/EnvelopeEncryption/GcmSivSelector/PQHybrid/KeyRotation/AuditLog/HoneypotKey/SecureEnclave/SecretSharing/**ToolEngine（统一工具引擎）**/RainbowBrush（彩虹画笔）/ColorMagnifier（取色放大镜）/AutoshapeService（手绘整形）/HighlighterCompositing（荧光笔）/AppleTheme（苹果设计语言）/UnifiedEditorMode（统一编辑器模式）/PageDesign 等 |
| `packages/editor_core/lib/src/commands/` | DocumentReducer + 25 种命令（撤销/重做） |
| `packages/editor_core/lib/src/geometry/` | GeometryEngine（直线/矩形/椭圆/箭头——纯 Dart double 坐标） |
| `packages/editor_core/lib/src/presentation/` | PresentationService（幻灯片） |
| `packages/notebook_domain/` | NotebookSession/KeyHandle/LockPolicy + 存储端口 |

### 2.3 测试（151 个测试文件——435 项测试全过）

| 位置 | 内容 |
|------|------|
| `packages/editor_core/test/` | **纯 Dart 领域测试**（429 项）：tool_engine/rainbow_brush/brush_styles/autoshape/highlighter_compositing/apple_theme/unified_editor_mode/encryption_scope/encryption_access/recovery_key/secret_sharing/envelope_encryption/gcm_siv_selector/pq_hybrid/key_rotation/audit_log/honeypot_key/secure_enclave/color_magnifier 等 |
| `test/features/editor_v2/` | editor_v2_viewmodel/paged_canvas/infinite_canvas/export_service/pdf_import/editor_v2_screen/**note_editor_widget** 等 |
| `test/features/notes/` | notebook_keyfile/notebook_page_metadata/notebook_search_summary 等 |
| `test/shared/widgets/` | apple_glass_test 等 |
| `integration_test/` | cuj_01_test（CUJ-01 集成——手动录证路径）+ contracts/cuj01.json |

### 2.4 文档（docs/——97 个文档）

| 文档 | 内容 |
|------|------|
| `docs/ARCHITECTURE.md` | 四层积木架构（200 行——21 域模型/25 命令/18 Widget/管道数据流） |
| `docs/unified_architecture.md` | **统一架构设计**（笔记/画板共用核心——note/whiteboard 双模式） |
| `docs/note_editor_analysis.md` | 笔记编辑分析（AFFiNE BlockSuite/Saber 校验——Word 文档式） |
| `docs/feature_inventory.md` | 4 项目可搬运功能盘点（Saber/Excalidraw/excalidraw-cn/AFFiNE） |
| `docs/migration_plan_round2.md` | 高价值迁移清单（Autoshape/荧光笔/压感——P0/P1/P2） |
| `docs/encryption_hardening_report.md` | 加密加强调研（8 项——P0/P1/P2——中英双平台） |
| `docs/affine_research_report.md` | AFFiNE 深度研究（blocksuite + 双端适配） |
| `docs/excalidraw_local_integration_plan.md` | Excalidraw 本地化集成（无限画布/手绘/导出） |
| `docs/borrowing_plan.md` | 借鉴计划（P0/P1/P2） |
| `docs/editor_v2_architecture_plan.md` | EditorV2 外壳架构 |
| `docs/batch_f_recovery_plan.md` | 批次 F 恢复计划 |
| `docs/pytauri-migration-technical-plan.md` | pytauri 迁移计划（Aegis——另一项目——参考） |
| `docs/2026-08-14` 系列 | M1-M3 验收/审计/借鉴报告（历史） |
| `docs/2026-08-15` 系列 | 专家审计/工具评审/架构评估（历史） |
| `NOTICE` | **版权声明**（AFFiNE/Excalidraw/excalidraw-cn/Saber/capd/Cryptomator/fldraw/tldraw/Excalidraw+/加密加强来源） |

### 2.5 安装包 / 运行环境

| 位置 | 内容 |
|------|------|
| `dist/1.1.0+2/drawing_notes_app-1.1.0+2-windows-setup.exe` | Windows 安装包（36M——Inno Setup——`installer/drawing_notes_app.iss`） |
| `build/app/outputs/flutter-apk/app-release.apk` | Android APK（80.8M——已签名） |
| `C:\Users\17296\Desktop\drawing_notes_app-1.1.0+2-android-release.apk` | Android APK 桌面副本（SHA bfa37da6...） |
| `D:\software\绘图笔记\` | **Windows 已安装位置**（最新 data 15:58） |
| `C:\Users\17296\Desktop\绘图笔记.lnk` | 桌面快捷方式（已创建） |
| `android/app/release.jks` + `android/key.properties` | 签名机密（不入库——密码用户保管） |
| `android/app/src/main/res/mipmap-*/ic_launcher.png` | 图标（源自 `C:\Users\17296\Desktop\app_icon_source.png`——SHA 85962f59232dc1e4） |

### 2.6 历史旧安装（可删除——消除"两个版本"）

| 位置 | 说明 |
|------|------|
| `D:\DrawingNotesApp\` | 旧版 1.0.0+1（最早安装——可删除） |
| `D:\write\1\install_test\` | 旧版 1.1.0+2（测试安装——可删除） |
| `D:\write\1\drawing_notes_app_source_2026-08-14.zip` | 最初交付的源码压缩包 |

---

## 三、设计方法（核心——如何工作）

### 3.1 统一架构（最重要——避免重复维护）

```
UnifiedEditor（同一编辑器——笔记+画板共用）
├── 共用核心：DocumentV2/Reducer/Geometry/ToolEngine/CanvasPainter/工具栏/加密
├── note 模式：NoteEditorWidget（Word 文档式——直接打字——AFFiNE Page 借鉴）
└── whiteboard 模式：InfiniteCanvasWidget（无限画布——手写绘图）
（功能共通——不重复显示——特殊功能按模式）
```

### 3.2 积木式四层架构（2026 Clean Architecture——专家方案）

1. **domain 层**（editor_core 纯 Dart——52 模块——不可变模型 + 命令模式）
2. **application 层**（Notifier/ViewModel——Riverpod 3.x）
3. **presentation 层**（Widget——积木式独立组件）
4. **composition_root**（组合根——依赖注入）

### 3.3 苹果设计语言（HIG 2026——已落地）

- Liquid Glass 毛玻璃（AppleGlassWidget——工具栏/画布）
- 语义色（systemBlue #007AFF + 暗色适配）+ SF Pro 排版 + 8pt 网格/44pt 点击目标

### 3.4 4 项目借鉴（保留版权——NOTICE）

- **Saber**（GPL-3.0）：画笔组（钢笔/圆珠笔/荧光笔/铅笔）+ 荧光笔 compositing + 压感规范化 + 深色反转 + 统一编辑器模式
- **Excalidraw/Excalidraw+**（MIT）：无限画布/手绘/导出/形状库/Autoshape 整形/工具
- **excalidraw-cn**（MIT）：多画布/中文手写
- **AFFiNE**（BSL/MIT）：Page/Edgeless 双模式/数据库/便签/块编辑/侧边栏/质感

### 3.5 加密框架（8 项加强 + 访问控制）

- 内容层 AES-256-GCM + 元数据 AES-SIV（待接入）+ 后量子混合（模型）
- EncryptionScope（对象选择 app/note）+ EncryptionAccess（再次打开需密码）
- RecoveryKey（恢复密钥一键复制）+ SecretSharing（Shamir 分割）+ 审计日志等

### 3.6 工作流规则（历史约定）

- 每次迁移/借鉴前**先联网调研** 2026 最新实践（中英双平台）
- 可照搬开源源代码——但**保留原版权（NOTICE）** + 本地化适配 + 不搞崩
- **不停上传 GitHub 确定基线**（Actions 始终绿色）
- 测试全过才提交（435 项——零回归）

---

## 四、之前指出的错误（用户反馈记录——已修/状态）

| # | 用户指出的错误 | 状态 |
|---|--------------|------|
| 1 | 橡皮擦不稳定（点几下就变/整笔模式消失） | ✅ 已修（ToolEngine 统一状态——不再变） |
| 2 | 像素橡皮擦轨迹生成黑色线条无法擦除 | ✅ 已修（统一 EraserMode） |
| 3 | 荧光突然变细（粗细最大值与其他不同） | ✅ 已修（统一粗细上限） |
| 4 | 荧光效果不明显 | ✅ 已修（HighlighterCompositing——重叠不变色） |
| 5 | 画板打字崩溃（输入一个字画板无法使用） | ✅ 已修（Flutter 原生 TextField——不依赖 material_ui） |
| 6 | 双击出现文本框有干扰 | ✅ 已删（V1 画布双击 + 文本双击编辑移除） |
| 7 | 取色板使用困难（需放大镜显示颜色） | ⏳ 模型已建（ColorMagnifier）——画布 UI 接入待续 |
| 8 | 箭头/三角形/棱锥/矩形颜色只有黑色不能换 | ✅ 已修（CanvasPainterV2 fillMode + 可换色） |
| 9 | 实心填充几何体功能无法使用 | ✅ 已修（fillMode stroke/fill/both） |
| 10 | 节点连线功能指示不明 | ✅ 已明确（"节点连线(连两点)"说明） |
| 11 | 加密无效（密码盘创建后没加密任何东西） | ⏳ 框架已建（EncryptionScope/Access/RecoveryKey）——UI 接入待续 |
| 12 | 恢复密钥说可复制但没复制功能 | ✅ 已修（RecoveryKeyService——一键复制 formatForCopy） |
| 13 | 笔记本无法使用 | ✅ 已修（note 模式——Word 文档式——替代 material_ui V1） |
| 14 | 笔记本和画布区分度不大/功能重复显示 | ✅ 已修（统一架构——note/whiteboard 双模式——共用核心） |
| 15 | 搜索"绘图笔记"有两个版本 | ✅ 已定位（旧安装残留 D:\DrawingNotesApp + install_test——可删除） |
| 16 | 架构混乱（一个功能不同操作出现不同实现） | ✅ 已重构（统一工具引擎 ToolEngine + 统一架构） |
| 17 | "不停的修改需要不停上传确定基线" | ✅ 已落实（153 提交——Actions 始终绿色） |
| 18 | 笔记应该是单独界面（像 Word 文档直接打字） | ✅ 已实现（NoteEditorWidget——Word 文档式） |

## 五、未完成任务（清单——按优先级）

| 优先级 | 任务 | 说明 |
|--------|------|------|
| **高** | 加密 UI 接入 | EncryptionVaultManager/Scope/Access → 设置密码/锁定/解锁界面（用户明确要求） |
| **高** | 笔记保存持久化 | NoteDocument → NotebookStorage 接入（当前打字不落盘） |
| **高** | 取色放大镜接入画布 UI | ColorMagnifier → 画布 eyedropper 显示 |
| 中 | AES-SIV 元数据层 | 目录/文件名加密（Cryptomator 完整方案） |
| 中 | 富文本格式 | 加粗/标题/列表（AFFiNE BlockSuite 借鉴） |
| 中 | note ↔ whiteboard 模式切换按钮 | AFFiNE Ctrl+Alt+E 借鉴 |
| 中 | V1 大文件拆分 | editor_page 1071 行/drawing_controller 955 行（封存 Legacy——V2 重构） |
| 中 | 旧数据迁移 | V1 笔记本/画作 → V2 格式 |
| 中 | 当前页 PNG 导出/SVG 字体嵌入/状态图 ERD/无限嵌套文件夹 | 迁移清单 P1 |
| 中 | Slash 命令（/ 键块菜单） | AFFiNE 借鉴 |
| 中 | 后量子升级 | pqforge 真实 ML-KEM（当前模型层） |
| 低 | P-002 CUJ-01 全流程录屏 | 用户手机录屏——Android 可标可用 |
| 低 | 协作 + 端到端加密 | Excalidraw app（需服务器） |
| 低 | AI 助手（MCP） | 需 LLM |
| 低 | 手写笔支持（Windows 方向/按钮） | Saber 借鉴——平台依赖 |
| 低 | PR #1 合并 + Ruleset 对齐 | 4 条 pr-* CI 绿色确认 |

## 六、软件目标（最终形态）

**绘图笔记**——跨平台（Android + Windows）笔记 + 画板应用：

1. **笔记** = Word 文档式直接打字（富文本/块——像 Word/Notion）
2. **画布** = 无限画布手写绘图（像 Excalidraw/Miro）
3. **统一架构**——note/whiteboard 双模式——功能共通不重复维护
4. **苹果设计语言**——Liquid Glass 毛玻璃 + 清爽配色（HIG 2026）
5. **4 项目借鉴**——Saber（画笔/手写）/Excalidraw（工具/画布）/AFFiNE（模式/组件）/excalidraw-cn（多画布）——保留版权
6. **强加密**——对象选择（整个应用/单个笔记）+ 再次打开需密码 + 恢复密钥一键复制——AES-256-GCM + 后量子（可选升级）
7. **全功能正常运行 + 界面美观 + 不停上传 GitHub（Actions 绿色）**

---

*交接文档结束——接手者请从「未完成任务（五）」按优先级继续。*

