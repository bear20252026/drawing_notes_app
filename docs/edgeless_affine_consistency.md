# Edgeless（无限画布）模式 — AFFiNE 1:1 一致性对照

> 目标：把「画记」的 Edgeless 双模式（文档页面模式 ↔ 无限画布模式）逐项对照
> AFFiNE 的 `affine:edgeless` + `affine:note` 模型，确认交互与数据语义 1:1 对齐。
> 只复刻 MIT 前端/block-suite 的**交互形式与公开数据形态**，不搬运任何后端/EE 代码。

## 1. 数据模型对照

| AFFiNE（block-suite） | 画记 | 对应源码 |
|---|---|---|
| `affine:edgeless` 页面（画布根） | `EdgelessDoc` | `lib/features/notes/domain/edgeless_doc.dart` |
| `affine:note`（可拖拽/缩放的块容器帧） | `NoteFrame`（id/x/y/w/h/zIndex/background/doc） | 同上 |
| 视口相机（平移/缩放） | `EdgelessCamera`（zoom/panX/panY + worldToScreen/screenToWorld） | 同上 |
| 线性正文 ↔ 画布帧拆分 | `noteBlockDocToFrames` / `mergeFramesToDoc` | `lib/features/notes/domain/note_block_doc_to_frames.dart` |
| 画布渲染 + 手势 | `EdgelessPage` | `lib/features/notes/presentation/edgeless_page.dart` |
| 帧精确位置/尺寸 | `NoteFrame.rect`（dart:ui Rect，逻辑 px） | `edgeless_doc.dart` |

### 1:1 语义要点
- **帧 = 块文档容器**：每个 `NoteFrame` 内含一个 `NoteBlockDoc`（block 序列）。AFFiNE 的
  `affine:note` 内部就是一个块文档（`affine:frame`/段落等），我们的帧内是 `NoteBlockDoc`，
  帧内双击进入编辑器操作的就是这份块文档。
- **x/y/w/h + zIndex**：与 AFFiNE 一致，帧用绝对布局坐标 + z 序（`bringToFront`/`sendToBack`
  重排 z，保持其余相对序）。
- **相机**：`worldToScreen(world, viewport) = (world - pan) * zoom + viewportCenter`，
  `screenToWorld` 为其严格互逆（`pan` 为「映射到视口中心的世界坐标」）；`zoomedBy(factor, focusWorld)`
  以世界坐标锚点缩放（锚点屏幕位置不变）；`fittedTo(worldRect, viewport)` 把指定世界矩形完整居中可见。
  与 AFFiNE 的 viewport 相机语义一致。

## 2. 交互对照

| 用户手势 | AFFiNE edgeless | 画记 | 实现 |
|---|---|---|---|
| 空白处单指拖动 | 平移画布 | 平移画布 | `EdgelessController.beginGesture/updateGesture` |
| 帧上单指拖动 | 移动帧 | 移动帧（`moveFrame`） | drag 命中帧 → move |
| 双指捏合 | 以焦点缩放 | 以焦点缩放（`zoomedBy(focusWorld)`） | scale 手势 |
| 单击空白 | 取消选中 | 取消选中（`select(null)`） | tap 空白 |
| 单击帧 | 选中 + 提到最上层 | 选中 + `bringToFront` | tap 帧 |
| 帧角拖拽 | 缩放帧（角手柄） | 缩放帧（选中帧四角 `_CornerHandle`，世界坐标，含左上角联动） | `_CornerHandle` / `controller.resizeFrame(topLeft,w,h)` |
| 帧背景 | note 帧背景预设 | 点击帧头取色按钮循环切换 AFFiNE 背景预设（白 + pastel） | `_kFrameBackgrounds` / `controller.setFrameBackground` |
| 双击帧 | 进入内联编辑 | 打开帧内编辑器（`NoteEditorPage`） | `_openFrameEditor` |
| 双击空白 | 聚焦空白 | 聚焦（`select(null)`） | `onDoubleTapDown` |
| 添加帧 | `affine:note` 创建 | `EdgelessDoc.addFrame` / 画布工具栏 | `addFrame` |

- **级联排布**：`addFrame` 在 `at` 为空时用 `(80+n*32, 80+n*32)` 级联偏移防重叠，对应 AFFiNE 新
  note 帧的自动错位。
- **最小尺寸**：帧缩放有 `kMinFrameWidth=120`/`kMinFrameHeight=60` 下限，与 AFFiNE 帧可缩放但
  不过小的行为对齐。四角手柄拖拽（选中态）同时支持改宽/高与联动左上角，命中缩放由
  `controller.resizeFrame(id, topLeft, w, h)` 收口。

## 3. 双模切换（page ↔ edgeless）

- AFFiNE 文档顶层在「Page mode」与「Edgeless mode」间切换，同一底层内容心智。
- 画记：`NoteDocModesPage`（`lib/features/notes/presentation/note_doc_modes_page.dart`）
  - 页面模式 → `NoteEditorPage`（线性块编辑）。
  - 无限画布模式 → `EdgelessPage`（note 帧画布）。
  - **页面→画布**：`noteBlockDocToFrames` 按顶层 heading 拆出多个 note 帧级联排布
    （无 heading 则单帧装全部块），对齐 AFFiNE server 端按 heading 自动拆分 note 的行为。
  - **画布→页面**：`mergeFramesToDoc` 按 z 升序把各帧的 `doc.body` 保序拼回一个 `NoteBlockDoc`，并 `onSave` 落盘。
  - **持久化**：`EdgelessDocStore`（`edgeless_doc_store.dart`）把画布布局
    （帧坐标/缩放/选择）独立持久化；切回画布时若存在历史布局则恢复，否则按当前正文重新拆分。
  - **退出收口**：宿主导航返回时，画布模式先合并回文档再落盘（`PopScope` `canPop:false` 接管）。

## 4. 刻意的差异化（AFFiNE 没有的部分 = 画记护城河）

- **手写/压感笔**：AFFiNE edgeless **无手写**；画记把手写作为后续 P2 增强（笔直接在块间书写）。
- **移动 + 隐私**：AFFiNE 偏协作/桌面；画记以 mobile-first + 本地优先（AES-256-GCM 媒体加密）为差异化。
- 帧内编辑器复用完整块编辑器（`NoteEditorPage` 的 `/` 菜单、撤销重做、Markdown 导入导出、内嵌块）
  —— 帧内能力与线性编辑器完全一致（AFFiNE 的 note 帧内亦然）。

## 5. 未 1:1 / 可改进（诚实清单）

- AFFiNE edgeless 支持**连接线**（note↔note 引用连线）、**群组框**、**画布内 search/命令面板**；
  画记当前未实现（后续 P3）。
- AFFiNE 的 note 帧在 web 上由 `affine:frame` 元数据承载 `prop`（标题/索引），画记直接以
  `NoteBlockDoc.title` 承载，形态简化但语义等价。
- `fittedTo` 的 padding 默认 40px，AFFiNE 的 fit 缩放策略随容器；如需逐像素一致可再调。

## 6. 参考 AFFiNE 源码分支（只读参考，不含搬运）

- block-suite `affine:edgeless`（EdgelessRootBlock + EdgelessSelection）：
  帧模型、z 序、相机、焦点缩放为对照基准。
- `affine:note` 帧的定位/缩放/拾取（hit-test 取最上层）语义已对齐；命中测试见
  `EdgelessDoc.hitTest`。
