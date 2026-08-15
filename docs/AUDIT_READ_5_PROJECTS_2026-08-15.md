# 五项目源码再精读专家级审计意见（2026-08-15）

> 精读对象：本地 5 个优秀项目源码（`D:\write\1\research\`）——
> flutter-quill（Apache-2.0，2.9k star）、scribe_canvas（MIT）、
> iwb_canvas_engine（MIT）、Saber（GPL-3.0 仅借鉴）、excalidraw（MIT）。
> 目的：在前两轮（P0 Delta 转换层、P1 事务+缓存）落地基础上，继续挖掘
> 可模仿/照搬/适应化适配的借鉴点，输出专家级审计意见。
> 红线：每文件 ≤500 行、结构清晰、逻辑缜密；GPL 项目仅借鉴思想不引入代码。

---

## 一、本轮新发现借鉴点（按价值排序）

### 1. flutter-quill：History 合并机制（高价值，可直接照搬设计）
**源码**：`flutter-quill/lib/src/document/history.dart`
- `interval = 400ms`：400ms 内连续变更**合并为一个历史条目**（防撤销步进过碎）
- `maxStack = 100`：历史栈上限
- `userOnly` + `ChangeSource.local`：**只记录用户本地变更**；外部/同步变更走 `transform`（变换历史而非清空）——协同安全
- `handleDocChange → record/transform` 双路径

**本项目适配**：`drawing_controller_history.dart` 的 `_pushCommand` 目前每命令一条。
→ 照搬设计：新增"合并窗口"——同一 stroke 的连续增量命令（如压感采样分段）400ms 内合并为单条撤销。

### 2. iwb_canvas_engine：决策驱动输入状态机（高价值，可适应化）
**源码**：`iwb_canvas_engine/lib/src/interaction/draw_stroke_machine.dart`
- `DrawStrokeMachine` + `PointerStrokeCapture` + `StartDecision/PreviewDecision/TerminalDecision` 决策类
- 输入处理**显式状态机**：每次 pointer 事件产出"开始/预览/终止"决策，可测试、可插拔

**本项目适配**：`drawing_controller` 的笔画输入目前是隐式 if/else。
→ 借鉴状态机分层：把 `pointerDown/Move/Up → startStroke/extendStroke/endStroke` 显式化为
`_StrokeInputMachine`（decision 对象），便于单测与未来多输入源（鼠标/触控笔）。

### 3. Saber：EditorHistory 保存状态跟踪（高价值，可照搬设计）
**源码**：`saber/lib/data/editor/editor_history.dart`
- `_past/_future` 双栈 + `recordChange` + **`markLastChangeAsSaved()`** + `isCurrentStateSaved`
- 脏标记独立于历史栈：**"是否有未保存修改"可精确查询**（对标标题栏 * 提示）

**本项目适配**：`DrawingController` 目前无"未保存"状态。
→ 照搬设计：`markSaved()/isDirty` 一对方法，接 `_doAutosave` 与标题栏星标。

### 4. Saber：SBN 格式内联资源（中价值，可适应化）
**源码**：`saber/lib/data/editor/editor_core_info.dart`
- `v`（文件版本）+ `a`（inlineAssets，base64 内联图片）——单文件自包含

**本项目适配**：文档 JSON 已有多图；对齐 SBN 思路在导出（Word/PDF）时**内联图片**
保证自包含（当前 buildExportPayload 三态净化已部分覆盖，可补内联）。

### 5. excalidraw：命令注册体系（中价值，方法可照搬）
**源码**：`excalidraw/packages/excalidraw/actions/*`（46 个文件）
- 每条命令 = `register({name, trackEvent, perform, keyTest, contextItemLabel})`
- 统一声明式：快捷键/菜单/工具栏**自动汇聚**（本项目命令面板已是主菜单入口，可对齐结构）

**本项目适配**：`_registerCommands` 已存在（editor_page_commands.dart）。
→ 对齐 excalidraw 结构：命令注册携带 `keyTest + label`，命令面板自动生成（部分已实现）。

### 6. excalidraw：版本/增量广播（中价值，方法借鉴）
**源码**：`excalidraw/packages/excalidraw/data/reconcile.ts` + `encode.ts`
- `versionNonce` 快速变化指示 + StoreDelta 增量广播（本项目 `Stroke.versionNonce` 已对齐）

**本项目适配**：已落地（versionNonce）；可补"增量广播"到同步三件套（未来 WebDAV 传输层）。

### 7. scribe_canvas：PDF 导出管线（低-中价值，可照搬）
**源码**：`scribe_canvas/lib/src/widgets/scribe_canvas.dart`
- `pdfx.PdfDocument.openData` + `pw.Document`（printing 包）多页导出

**本项目适配**：已有 PDF 导出（pdf 包解析 3.12.0）；可对照多页/背景模板能力。

### 8. flutter-quill：QuillStruct 混排验证（验证性结论）
**源码**：`saber/lib/data/editor/page.dart` 引用 `QuillStruct`
- Saber 用 Quill 做页内文字——**验证本项目"flutter-quill 富文本升级"路线正确**

---

## 二、适配优先级建议

| 优先级 | 借鉴点 | 来源 | 风险 | 落地形态 |
| --- | --- | --- | --- | --- |
| P0 | 历史合并（400ms/merge） | flutter-quill | 低 | `_pushCommand` 合并窗口 |
| P0 | 保存状态跟踪（markSaved/isDirty） | Saber | 低 | `DrawingController` 增方法 |
| P1 | 输入状态机（decision 化） | iwb | 中 | `_StrokeInputMachine` |
| P1 | 命令注册结构化（keyTest+label） | excalidraw | 低-中 | `_registerCommands` 增强 |
| P2 | SBN 内联资源 / PDF 管线 / 增量广播 | Saber/scribe/excalidraw | 中 | 后续迭代 |

## 三、审慎原则（政府项目）

1. **许可红线**：Saber（GPL-3.0）仅借鉴设计思想，不引入代码；其余 MIT/Apache 可照搬
2. **不破坏基线**：每项落地独立验证（analyze + 全量测试），逐步收紧
3. **文件红线**：落地文件 ≤500 行、结构清晰、逻辑缜密
4. **可回滚**：新增能力默认关闭或旁路，验证后再切换

> 本报告为第三轮精读审计意见；P0 两项（历史合并、保存状态跟踪）价值高、风险低，
> 建议本轮立即落地，P1/P2 按迭代推进。
