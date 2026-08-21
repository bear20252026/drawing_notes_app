# 绘图笔记（drawing_notes_app）架构文档

> 2026-08-21 | 框架化 · 积木化 · 管道化 | 每个模块独立可插拔——不耦合

---

## 一、架构总览（四层积木）

```
┌─────────────────────────────────────────────────────────────┐
│                        apps 层                              │
│  lib/app/composition_root.dart（组合根——依赖注入——唯一入口） │
├─────────────────────────────────────────────────────────────┤
│                      features 层                            │
│  lib/features/editor_v2/（UI 积木——可插拔——不互相依赖）      │
│  presentation/  application/  adapters/                     │
├─────────────────────────────────────────────────────────────┤
│                      modules 层                             │
│  packages/editor_core/（纯 Dart 核心——NO UI——独立可测试）    │
│  domain/  commands/  geometry/  presentation/                │
├─────────────────────────────────────────────────────────────┤
│                       ports 层                              │
│  packages/notebook_domain/（会话/端口——纯 Dart 接口）        │
│  session/  ports/                                           │
└─────────────────────────────────────────────────────────────┘

依赖方向：presentation → application → domain/ports ← infrastructure
         features → modules（单向——modules 不依赖 features）
```

---

## 二、packages/editor_core/（modules 层——21 个积木块）

### domain/（16 个不可变模型——纯 Dart）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **DocumentV2** | document_v2.dart | 不可变文档（id/revision/layers——copyWith） |
| **LineItem** | line_item.dart | 笔画（id/points——不可变） |
| **ShapeItem** | line_item.dart | 形状（id/type/x/y/width/height） |
| **TextItem** | line_item.dart | 文本（id/content/x/y） |
| **ImageItem** | line_item.dart | 图片（id/mediaId/x/y/width/height） |
| **LayerV2** | line_item.dart | 图层（id/name/strokes/shapes/texts/images/tables/notes/visible/opacity） |
| **Point** | line_item.dart | 坐标点（x/y——不可变） |
| **PageV2** | page_v2.dart | 分页（id/index/document——多页画布） |
| **TableV2** | table_v2.dart | 数据库表格（id/headers/rows——AFFiNE 借鉴） |
| **NoteItem** | note_item.dart | 便签块（id/content/x/y/backgroundColor——AFFiNE 借鉴） |
| **RichTextBlock** | rich_text_block.dart | 富文本块（TextFormat/RichTextSpan——AFFiNE 借鉴） |
| **KanbanBoard** | kanban_board.dart | 看板视图（KanbanCard/Column/Board——AFFiNE 借鉴） |
| **ShapeLibrary** | shape_library.dart | 形状库（ShapeLibraryItem/ShapeDef——Excalidraw 借鉴） |
| **ArrowBinding** | arrow_binding.dart | 箭头绑定（EndpointBinding——Excalidraw 借鉴） |
| **StrokeStyle** | stroke_style.dart | 画笔样式（color/width/opacity/lineType） |
| **ClipboardData** | clipboard_data.dart | 剪贴板（elements/offset——Excalidraw 借鉴） |
| **LassoSelection** | lasso_selection.dart | 套索选择（rectangle/freeform——ray casting——Excalidraw 借鉴） |
| **GridConfig** | grid_config.dart | 网格吸附（GridSnap.snapToGrid/snapToElement——Excalidraw 借鉴） |
| **InlineEditState** | inline_edit_state.dart | 行内编辑状态机（idle/editing/committing/aborting——Excalidraw 借鉴） |
| **ChartData** | chart_data.dart | 图表（bar/line/pie——Excalidraw 借鉴） |
| **I18nService** | i18n_service.dart | 国际化（9 语言/RTL/参数替换——Excalidraw 借鉴） |
| **AnimatedTrail** | animated_trail.dart | 绘制动画（轨迹/插值/缓动/压力——Excalidraw 借鉴） |

### commands/（2 个文件——25 种命令）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **DocumentCommand** | document_command.dart | 命令基类（apply/inverse）+ 25 种命令 |
| **DocumentReducer** | document_reducer.dart | 状态 + 命令 → 新状态 + 逆命令（undo/redo 双栈） |

命令清单：AddStroke/RemoveStroke/CreateShape/RemoveShape/CreateText/RemoveText/InsertImage/RemoveImage/CreateTable/RemoveTable/CreateNote/RemoveNote/EraseByDistance/RestoreErased/MoveItem/UpdateDocument + ...（25 种）

### geometry/（1 个文件——5 种几何）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **GeometryEngine** | geometry_engine.dart | 几何引擎（Line/Rectangle/Ellipse/Arrow + bounds/containsPoint/distanceTo） |

### presentation/（1 个文件）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **PresentationService** | presentation_service.dart | 幻灯片模式（next/prev/goTo/play/stop——AFFiNE 借鉴） |

---

## 三、packages/notebook_domain/（ports 层——4 个积木块）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **NotebookSession** | notebook_session.dart | 状态机（uninitialized/unlocked/locked/expired——R-05 锁定阻断） |
| **KeyHandle** | key_handle.dart | scoped 密钥持有者（dispose 清零——内存安全） |
| **LockPolicy** | lock_policy.dart | 锁定策略（autoLockDuration/shortTimeout/longTimeout） |
| **RepositoryPorts** | repository_ports.dart | 端口接口（NotebookRepository/MediaRepository/KeyProvider） |

---

## 四、lib/features/editor_v2/（features 层——18 个积木块）

### application/（8 个 Notifier/ViewModel/Service）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **EditorV2Notifier** | editor_v2_viewmodel.dart | 核心 ViewModel（命令分发/undo/redo/setTool） |
| **StrokeStyleNotifier** | stroke_style_notifier.dart | 画笔样式（独立——不耦合 EditorV2） |
| **PagedCanvasNotifier** | paged_canvas_viewmodel.dart | 分页画布（addPage/deletePage/movePage） |
| **InfiniteCanvasNotifier** | infinite_canvas_notifier.dart | 无限画布（pan/zoom/reset） |
| **ViewportState** | viewport_state.dart | 视口状态（scale/offset/坐标转换/可见区域） |
| **ExportService** | export_service.dart | 导出（toJson/toSvg/toPng——Excalidraw 借鉴） |
| **PdfImportService** | pdf_import_service.dart | PDF 导入（pdfx 渲染——批次 F-4） |
| **StrokeStyle** | stroke_style.dart | 画笔样式数据（重导出自 editor_core） |

### presentation/（10 个 Widget——积木式独立）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **EditorV2Screen** | editor_v2_screen.dart | 主屏幕（Scaffold + Drawer + AppBar + Toolbar + Canvas） |
| **CanvasPainterV2** | canvas_painter.dart | 画布绘制（CustomPainter——手绘风格/深色反转/图表） |
| **InfiniteCanvasWidget** | infinite_canvas_widget.dart | 无限画布包装（GestureDetector + Transform） |
| **EditorV2Toolbar** | toolbar_widget.dart | 工具栏（8 工具图标——选中动画） |
| **EditorV2Sidebar** | sidebar_widget.dart | 侧边栏（AFFiNE 页面导航——新建/切换/删除） |
| **LayerPanel** | layer_panel.dart | 层管理面板（可见性/透明度/重排——AFFiNE 借鉴） |
| **PropertyPanel** | property_panel.dart | 属性面板（颜色/线宽/透明度/线条样式——AFFiNE 借鉴） |
| **HistoryPanel** | history_panel.dart | 历史面板（撤销/重做列表/当前位置/跳转——AFFiNE/Excalidraw 借鉴） |
| **ExportPanel** | export_panel.dart | 导出面板（PNG/SVG/JSON 选择器/预览——Excalidraw 借鉴） |
| **ZoomControls** | zoom_controls.dart | 缩放控件（滑块/百分比/缩小/放大/重置/适应窗口——Excalidraw 借鉴） |

### adapters/（1 个文件）

| 积木块 | 文件 | 功能 |
|--------|------|------|
| **DrawingAdapter** | drawing_adapter.dart | V1 → V2 桥接（迁移期——旧控制器桥接到 V2 命令模式） |

---

## 五、管道式数据流

```
用户操作（手势/键盘/工具栏）
    ↓
EditorV2Screen（presentation 层——Widget）
    ↓
EditorV2Notifier（application 层——命令分发）
    ↓
DocumentCommand（modules 层——命令模式）
    ↓
DocumentReducer（state + command → new state + inverse）
    ↓
DocumentV2（modules 层——不可变状态）
    ↓
CanvasPainterV2（presentation 层——CustomPainter 渲染）
    ↓
屏幕输出（画布/工具栏/侧边栏/面板）
```

---

## 六、积木式依赖图

```
apps/composition_root
    └── features/editor_v2/*
        ├── presentation/*（10 Widget）
        │   └── application/*（8 Notifier/Service）
        │       └── packages/editor_core/*（21 domain + 2 commands + 1 geometry）
        │           └── packages/notebook_domain/*（4 session/ports）
        └── adapters/*（1 桥接——迁移期）
```

**规则**：
- modules 不依赖 features（单向）
- features 不互相依赖（独立积木）
- 每个积木块可独立测试（NO UI — editor_core 纯 Dart）
- 新功能 = 新积木块（添加到对应层——不修改现有积木）

---

## 七、测试基线

| 包 | 测试文件 | 测试数 |
|----|---------|--------|
| editor_core | 18 个测试文件 | **137 项** |
| editor_v2 | 5 个测试文件 | **28 项** |
| notebook_domain | 1 个测试文件 | **8 项** |
| 架构边界 | 1 个测试文件 | 3 项 |
| **合计** | **25 个测试文件** | **429 项** |

---

## 八、借鉴清单（34 项——4 个项目）

| 来源 | 功能 | 数量 |
|------|------|------|
| **AFFiNE** | 数据库/幻灯片/便签/侧边栏/质感/动画/工具栏/块编辑器/Kanban/层管理/属性面板/历史面板/导出 UI | 16 |
| **Excalidraw** | 无限画布/手绘/导出/转换/形状库/箭头绑定/画笔/缩放控件/Lasso/Clipboard/Grid-Snap/WYSIWYG/Charts/i18n/Animated Trail | 17 |
| **Saber** | 深色反转 | 1 |
| **合计** | — | **34** |

---

Generated: 2026-08-21
Project: drawing_notes_app (绘图笔记)
