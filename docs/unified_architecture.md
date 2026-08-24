# 统一架构设计（笔记端 + 画板端共用核心——2026-08-22）

> 用户批评：架构混乱——笔记端和画板端重复维护。
> 目标：笔记端和画板端尽可能共用同样的功能——避免重复维护——
> 只有一部分功能更特殊（模式化——特殊功能按模式启用）。

## 一、核心思想（借鉴 Saber + Excalidraw + AFFiNE）

**同一编辑器内核——两种模式**（像 Saber 的 Editor 同时是笔记+画布）：

```
┌─────────────────────────────────────────────────┐
│  UnifiedEditor（共用编辑器——笔记/画板都用）      │
│  ├── 共用核心（editor_core——已建 43+ 模块）      │
│  │   ├── DocumentV2（不可变文档）                │
│  │   ├── DocumentReducer（命令 + 撤销/重做）      │
│  │   ├── GeometryEngine（几何）                  │
│  │   ├── ToolEngine（统一工具状态——橡皮擦/荧光/   │
│  │   │          彩虹/填充/取色）                 │
│  │   └── ViewportState（视图）                   │
│  ├── 共用 UI（editor_v2——已建 18+ 组件）         │
│  │   ├── EditorV2Screen（画布 + 工具栏 + 侧边栏）│
│  │   ├── CanvasPainterV2（渲染——共用）           │
│  │   ├── EditorV2Toolbar（工具栏——共用）         │
│  │   ├── LayerPanel/PropertyPanel/HistoryPanel   │
│  │   └── AppleGlassWidget（毛玻璃——苹果设计语言）│
│  └── 模式切换（UnifiedEditorMode——特殊功能）     │
│      ├── note 模式（笔记端）                     │
│      │   ├── 分页（PageV2——多页文本）           │
│      │   └── 笔记列表（Saber HomePage 借鉴）     │
│      └── whiteboard 模式（画板端）               │
│          ├── 无限画布（InfiniteCanvas——缩放平移）│
│          └── 快速白板（Saber whiteboardSubpage） │
└─────────────────────────────────────────────────┘
```

## 二、避免重复维护（用户核心要求）

| 功能 | 旧架构（重复） | 统一架构（共用） |
|------|--------------|----------------|
| 文档模型 | notes/ + drawing/ 各一套 | ✅ DocumentV2（共用） |
| 命令/撤销 | notes/ + drawing/ 各一套 | ✅ DocumentReducer（共用） |
| 渲染 | notes/ + drawing/ 各一套 | ✅ CanvasPainterV2（共用） |
| 工具 | notes/ + drawing/ 各一套 | ✅ ToolEngine（共用） |
| 工具栏 | notes/ + drawing/ 各一套 | ✅ EditorV2Toolbar（共用） |
| 加密 | notes/ 有——drawing/ 无 | ✅ EncryptionScope/Access（共用） |

**特殊功能（只按模式启用——不重复）**：
- note 模式：分页（PageV2）+ 笔记列表（Saber HomePage 借鉴）
- whiteboard 模式：无限画布（InfiniteCanvas——ViewportState 缩放平移）

## 三、借鉴 Saber（搬运笔记功能——保留版权 GPL-3.0）

| Saber 模块 | 搬运（本地化到统一架构） | 版权 |
|-----------|------------------------|------|
| **HomePage**（首页——recent/browse/whiteboard/settings 4 子页） | 首页模式（最近/浏览/白板/设置——统一导航） | ✅ GPL-3.0 版权记录 |
| **Editor**（编辑器——笔记+画布） | UnifiedEditor（模式化——共用） | ✅ |
| **EditorCoreInfo**（文档模型 SBN） | DocumentV2（已建——不可变） | ✅ 概念借鉴 |
| **FileManager**（文件树——无限嵌套文件夹） | NotesRepository/WorkspaceManager（已建） | ✅ |
| **ResponsiveNavbar**（大屏侧边栏/小屏底部导航） | EditorV2Sidebar（已建）+ 响应式 | ✅ |
| **CanvasGestureDetector/InnerCanvas** | InfiniteCanvasWidget/CanvasPainterV2（已建） | ✅ |

## 四、实施步骤（框架级——积木式）

1. **UnifiedEditorMode**（枚举 note/whiteboard——模式切换——特殊功能启用）
2. **UnifiedEditorScreen**（共用编辑器——按模式显示特殊功能——笔记端/画板端一个入口）
3. **Saber 首页模式**（最近/浏览/白板/设置——统一导航——笔记列表）
4. **接入**（笔记端 + 画板端共用 EditorV2——特殊功能（分页/无限画布）按模式）
5. **验证 + 交付**（全量测试 + git + 双平台）

## 五、参考

- Saber（GPL-3.0——saber-notes/saber——DeepWiki 架构）
- Excalidraw（MIT——无限画布/工具）
- AFFiNE（BSL/MIT——侧边栏/数据库）
- excalidraw-cn（MIT——多画布）
- 苹果设计语言（HIG 2026——Liquid Glass——已落地）

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)
