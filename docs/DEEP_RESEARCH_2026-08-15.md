# 开源标杆全量深度研究报告（2026-08-15）

> 研究对象：saber-notes/saber（Flutter 手写笔记，4213 提交 / 2273 文件 / 266MB）
> 与 excalidraw/excalidraw（React 白板，4073 提交 / 1269 文件 / 146MB）**全量代码**。
> 方法：逐模块精读 + 交叉对比 + 专家级审阅，提炼可落地到「绘图笔记」项目的优秀经验。
> 原则：只借鉴设计思想，**独立实现**，不复制任何 GPL 代码（saber 为 GPLv3，仅学习）。

---

## 一、Saber 全量研究

### 1.1 数据模型与文件格式（SBN）

**核心：`EditorCoreInfo`（556 行）+ `EditorPage` + `Stroke` + sealed `EditorImage`**

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **SBN 版本化** | `sbnVersion = 19`；`fromJson` 检测 `fileVersion > sbnVersion` 时置 `readOnlyReason = versionTooNew`，防止新格式被旧版本破坏性改写 | ✅ 前向兼容的"只读降级"策略，比直接拒绝打开更友好 |
| **点编码压缩** | `PointExtensions.toBsonBinary`：坐标点序列化为 BSON binary（v13 起），兼容旧 JSON 路径；`fromJson` 标记 deprecated 仅向后兼容 | ✅ 文件体积优化 + 迁移通道并存 |
| **图片资源** | 内联 assets（base64）在 v19 起**弃用**，改为 `AssetCache` 按需加载文件路径；`EditorImage` 为 sealed 类：PNG/PDF/SVG 三个实现 | ✅ sealed 类强制穷举，PDF 图片支持矢量页渲染 |
| **画笔属性** | `StrokeOptionsExtension.setDefaults()` 集中设定 perfect_freehand 默认值（thinning 0.5 / streamline 0.5 / cap） | ✅ 全局默认集中管理 |
| **图片最小尺寸** | `dstRect` setter 强制 `minImageSize` 下限，防止图片缩成 0 尺寸 | ✅ 防御性边界 |

**可借鉴**：① 格式版本"只读降级"；② BSON 二进制点压缩；③ sealed 图片类族（本项目图片可拆 PNG/PDF/SVG 三态）。

### 1.2 绘图引擎

**核心：`Stroke`（双质量缓存）+ `CanvasPainter`（分层合成）+ `InnerCanvas`（Quill 混排）**

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **双质量几何** | `lowQualityPolygon/highQualityPolygon` 惰性缓存 + `markPolygonNeedsUpdating()` 失效；低质量用于绘制中，高质量收笔后生成 | ✅ 本项目已落地同款缓存（Expando + geometryRevision） |
| **点优化** | `optimisePoints`：间距 < `size×0.1` 的冗余点删除，幂等；`skipPoints(N)` 每 N 点采样 | ✅ 高频采样压缩 |
| **高亮分层** | `_drawHighlighterStrokes`：每颜色 `saveLayer + BlendMode.darken`，同色共享一层防叠脏 | ✅ 本项目已落地 |
| **铅笔 Shader** | `FragmentShader`（pencil.frag）颗粒纹理；缩小时降级为颜色混合快速模拟 | ✅ 本项目已落地自写 Shader |
| **Quill 混排** | `InnerCanvas` 内嵌 `QuillEditor`（CustomPaint + Quill 叠加），文字与手写同页编辑；`SaberQuillStyles` 按主题/行高定制 | ✅ 本项目 notebook 文字块可参考其 Quill 内嵌方式 |
| **背景图案** | `CanvasBackgroundPainter` 按 `CanvasBackgroundPattern`（line/grid/dot 等）生成 `PatternElement` 集合 | ✅ 本项目已有 paperType，可扩展更多图案 |

**可借鉴**：① `InnerCanvas` 的 Quill 内嵌混排（本项目文字块目前独立，可升级为页内富文本）；② 铅笔 Shader 缩放降级策略。

### 1.3 工具系统

**核心：`Tool` 抽象（22 行）+ 具体工具（pen/pencil/highlighter/eraser/select/shape_pen/laser_pointer）**

| 工具 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **Select** | `SelectResult{pageIndex, strokes, images, path}` 统一承载多对象选择；`getDominantStrokeColor` 按笔画长度加权取主色 | ✅ 主色提取算法（权重=长度）值得借鉴 |
| **ShapePen** | 继承 Pen + one_dollar_unistroke_recognizer：笔画实时识别 line/rect/circle/polygon，绘制中虚线预览 | ✅ 本项目已有 shape_recognizer，可对照其 one-dollar 集成 |
| **Eraser** | `_strokeHitsCircle`：线段到圆心距离 + 半径/线宽阈值判定；`sqrDistance` 优化避免 sqrt | ✅ 性能细节：平方距离比较 |
| **激光笔** | `LaserStroke` 尾迹：`firstVisiblePointAt` 按时间推进首点索引，实现从起笔端逐段消退；`opacityAt` 分段 ease-out | ✅ 时间轴驱动的尾迹动画（本项目已落地同款） |

**可借鉴**：① Select 主色加权提取；② one-dollar 手势识别集成模式。

### 1.4 同步（Nextcloud WebDAV）

**核心：`SaberSyncInterface`（605 行）+ abstract_sync 框架**

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **抽象同步层** | `findLocalChanges`/`findRemoteChanges`/`getBestFile` 通用三件套，底层 WebDAV 可替换 | ✅ 存储层抽象，本项目云同步可借鉴其接口划分 |
| **文件相等判定** | `areRemoteFilesEqual` 仅按 path 比较（本地改动优先） | ✅ 简单可靠 |
| **路径加密** | `encryptPath/decryptPath` + `.sbe` 扩展：文件名混淆加密 | ✅ 隐私保护细节 |
| **缓存优先** | `getBestFile(preferCache)` 两级缓存策略 | ✅ 减少网络往返 |

**可借鉴**：① 同步三件套接口抽象；② 文件名加密。

### 1.5 文件管理

**核心：`FileManager`（969 行，全静态 API）**

- `readFile(filePath, retries: 3)`：读失败自动重试 ✅
- `broadcastFileWrite`：文件写事件广播，UI 实时刷新 ✅
- `watchRootDirectory`：目录监听（跨进程变更检测）✅
- `removeUnusedAssets`：引用计数清理孤儿资源 ✅
- `validateFilename`：文件名合法性校验 ✅

### 1.6 UI 与主题

- **自适应主题**：`saber_theme.dart` 的 `createTheme/createThemeFromSeed` + `_adjustColorScheme`（Material 3 + 平台微调）✅
- **自适应组件族**：`adaptive_*.dart` 系列（对话框/进度/图标/开关/输入框按平台切换）✅
- **工具栏**：`Toolbar`（583 行）全部回调注入（setTool/setColor/undo/redo/export...），Widget 与逻辑解耦 ✅
- **设置体系**：`prefs.dart` 全 `ValueNotifier` 驱动，设置即状态 ✅

---

## 二、Excalidraw 全量研究

### 2.1 元素系统（packages/element，53 文件）

**核心：`ExcalidrawGenericElement` 基类 + 工厂 + 不可变变更**

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **元素基类** | `seed/version/versionNonce/groupIds/boundElements/fractionalIndex/updated`；`version` 每次变更 +1，`versionNonce` 供协作/内存去重 | ✅ 本项目已落地 seed/version/versionNonce |
| **变更范式** | `mutateElement`（同引变更 + bumpVersion）+ `newElementWith`（新引用替换）；`bumpVersion` 独立函数统一版本管理 | ✅ "可变内部 + 版本外显"平衡了性能与可追踪 |
| **渲染** | `renderElement`（715 行）+ `elementWithCanvasCache` WeakMap 缓存 Canvas2D 指令；`getFreedrawOutlineAsSegments` 自由画笔轮廓段化 | ✅ 渲染指令缓存思路可借鉴到 Flutter（本项目用 Path 缓存） |
| **箭头绑定** | `binding.ts`（2100 行）：`bindOrUnbindBindingElement`/`updateBoundElements`/`getBindingGap`/`maxBindingDistance_simple`，焦点点/吸附/弯折箭头完整 | ✅ 本项目的 ShapeEndpointBinding 可对照补全弯折箭头（elbow） |
| **碰撞/命中** | `collision.ts`：`hitElementItself`（自由画笔逐段）/`hitElementBoundingBox`/`getAllHoveredElementAtPoint`/`intersectElementWithLineSegment` | ✅ 分精度命中测试分层清晰 |
| **缩放** | `resizeElements.ts`：`transformElements`/`resizeSingleElement`（722 行）/`resizeMultipleElements`，含 text 字号按宽度重测 | ✅ 文字元素缩放自动重排版 |
| **吸附** | `snapping.ts`（1300 行）：`SnapCache` + `getVisibleGaps`/`getReferenceSnapPoints`/`snapDraggedElements`/`snapResizingElements`/`snapNewElement` | ✅ 参考点/参考线体系完整，本项目吸附可升级 |
| **Store** | `Store`（快照）+ `CaptureUpdateAction`（immediately/preserveRedoState）+ `StoreDelta`（逆操作）+ `StoreSnapshot` | ✅ 差量历史模型，本项目已落地 EraseStrokesCommand 同类思想 |

**可借鉴**：① 元素渲染指令缓存（WeakMap）；② 弯折箭头绑定；③ 参考点吸附体系；④ 文字缩放重排版。

### 2.2 命令体系（actions，46 文件）

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **Action 契约** | 每个 action：`name/contextItemLabel/keyPriority/perform/elementsToBeReplacedAfterUndo`；统一注册进 ActionManager | ✅ 本项目 CommandRegistry 已对齐 |
| **键盘分发** | `handleKeyDownEvent` 集中分派 + `shortcut.ts` 的 `getShortcutKey`（平台中立修饰键） | ✅ |
| **action 覆盖** | 对齐/分布/翻转/编组/剪贴板/导出/删除/锁定/复制/重复/框架/裁剪/元素链接/库 46 项 | ✅ 功能完备度标杆 |
| **导出** | `actionExport.tsx`：JSON/PNG/SVG/剪贴板，`cleanAppStateForExport` 剥离非必要状态 | ✅ 导出净化状态值得借鉴 |

### 2.3 协作（Portal.tsx + collab）

**核心：基于版本号的增量广播**

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **增量广播** | `broadcastScene`：只发送 `version > broadcastedElementVersions.get(id)` 的元素（按版本差量），`broadcastedElementVersions` Map 记录已广播版本 | ✅ 版本驱动的最小同步，比全量广播高效 |
| **文件同步** | `_broadcastSocketData`：先 `fileManager.saveFiles` 上传资源，再广播元素（图片 URL 替换） | ✅ 资源与元素分离传输 |
| **远程光标** | `clients.ts`：`getClientColor`（按客户端稳定色）+ `renderRemoteCursors` | ✅ 协作光标渲染 |

**可借鉴**：① 版本号差量广播（本项目已有 version，协作可直接启用）；② 资源/元素分离传输。

### 2.4 持久化

| 模块 | 设计要点 | 专家评价 |
| --- | --- | --- |
| **序列化** | `serializeAsJSON/saveAsJSON/loadFromJSON` + `isValidExcalidrawData` 校验 | ✅ |
| **恢复** | `restoreElement/restoreElements`（501-1050 行）：防御性恢复 + `bumpElementVersions` 冲突修复 | ✅ 与本项目 document_codec 防御性恢复同思路 |
| **文件存取** | `fileOpen/fileSave`（浏览器 File System Access API 包装） | ✅ 平台抽象 |
| **加密** | `encryption.ts`：场景加密（用于加密房间） | ✅ |
| **库** | `library.ts`：元素库（可复用组件集合）持久化 | ✅ 本项目 shape_library 可扩展 |

### 2.5 AppState

`getDefaultAppState`（~270 行）：视图/工具/样式/UI 状态集中；`clearAppStateForLocalStorage/cleanAppStateForExport/clearAppStateForDatabase` 三态净化 —— 不同出口剥离不同状态，避免污染 ✅

---

## 三、交叉对比与专家级审阅

### 3.1 架构总览对比

| 维度 | Saber（Flutter） | Excalidraw（React/TS） | 本项目（Flutter） |
| --- | --- | --- | --- |
| 状态模型 | ChangeNotifier + 类型化历史条目 | Store 快照 + StoreDelta 差量 | DocCommand 命令栈（已差量化） |
| 数据格式 | SBN v19（BSON 压缩） | JSON（.excalidraw）+ 版本化 | JSON 工程文件（v2） |
| 渲染 | CustomPaint + 分层合成 + Shader | Canvas2D + 指令缓存 + rough.js | CustomPaint + 图层位图缓存 |
| 命令体系 | 类型化 EditorHistoryItem | ActionManager（46 actions） | CommandRegistry（已对齐） |
| 协作 | Nextcloud WebDAV 双向同步 | WebSocket 版本增量广播 | 未实现（有 version 基础） |
| 同步细节 | 路径加密 .sbe | 资源/元素分离传输 | — |

### 3.2 专家审阅：三大最值得借鉴的架构决策

1. **Excalidraw 的"版本号驱动一切"**：`version/versionNonce` 贯穿元素变更、协作增量、冲突修复——本项目已落地元素模型，**下一步协作功能可直接启用**，无需改数据层。
2. **Saber 的"混合媒体页面"**：手写 + Quill 富文本 + 图片 + PDF 背景在同一画布无缝混排——本项目 notebook 文字块目前独立，升级为页内 Quill 混排是最大体验提升点。
3. **Excalidraw 的"渲染指令缓存"**（WeakMap 缓存 Canvas2D 指令）+ Saber 的"双质量 Path 缓存"：本项目已落地后者，前者思路可优化图片/形状重绘。

### 3.3 审阅发现的可落地清单（按优先级）

| 优先级 | 实践 | 来源 | 本项目落地建议 |
| --- | --- | --- | --- |
| P0 | 弯折箭头（elbow）绑定 | Excalidraw binding.ts | 扩展 ShapeEndpointBinding 支持 elbow 端点 |
| P0 | 参考点吸附体系 | Excalidraw snapping.ts | 网格吸附升级为对象参考线吸附 |
| P1 | 格式版本只读降级 | Saber SBN | document_codec 检测高版本时置只读 |
| P1 | Select 主色加权提取 | Saber select.dart | 选区取色按笔画长度加权 |
| P1 | 文字缩放重排版 | Excalidraw resizeElements | 文字块缩放时按字号重测宽度 |
| P2 | 文件名路径加密 | Saber .sbe | 云同步场景启用 |
| P2 | 渲染指令缓存 | Excalidraw WeakMap | 图片/形状重绘优化 |
| P2 | 三态 AppState 净化 | Excalidraw | 导出/存储/本地分离状态 |

---

## 四、结论

两个项目是互补的标杆：**Saber 在手写体验与跨平台工程化上领先**（BSON 压缩、双质量缓存、Quill 混排、WebDAV 同步），**Excalidraw 在可扩展状态与协作架构上领先**（版本驱动、差量历史、46 命令体系、参考点吸附）。本项目已吸收两者大量设计（命令体系、fractionalIndex、差量历史、双质量缓存、压感正规化、高亮分层、PDF 混合导出），剩余可落地项按上表优先级推进，其中**弯折箭头、参考点吸附、版本只读降级**三项收益最直接。
