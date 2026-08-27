# EditorPage 形状缩放几何协作者治理说明

**日期：2026-08-27**
**适用分支：`refactor/editor-shape-resize-geometry`**

## 审计结论

`EditorPage` 的对象叠层通过 private `part` extension 构建形状展示。`ResizeHandles` 已经将八向手柄的 Widget、命中和屏幕增量换算回调从页面移出，但每次拖拽后如何修改 `PageShapeItem` 的 `x`、`y`、`width`、`height`，仍以 50 余行条件分支直接驻留在 `_EditorPageOverlays` 中。

该段逻辑是一个稳定的**纯几何叶子职责**：输入为当前边界、手柄位置、是否角手柄和已经换算为画布坐标的增量；输出为受尺寸上限约束的新边界。它不需要 `BuildContext`、`DrawingController`、`Widget`、存储、命令栈、通知或可变文档状态。因此适合成为 presentation 内的无状态协作者，而不是再创建另一个 `part` extension 或下沉到应用层。

## 协作者契约

`EditorShapeResizeGeometry` 对外只暴露不可变的 `EditorShapeBounds` 与 `resize(...)`：

| 输入 | 含义 |
|---|---|
| 当前 `EditorShapeBounds` | `x`、`y`、`width`、`height` 的画布坐标快照 |
| `handlePosition` | `ResizeHandles` 已定义的局部手柄位置 |
| `isCorner` | 区分角手柄同时调整宽高与边手柄单轴调整 |
| `canvasDelta` | 宿主已通过 `screenDeltaToCanvas` 处理旋转和缩放后的画布增量 |

| 输出 | 保证 |
|---|---|
| 新 `EditorShapeBounds` | 保持现有左/上/右/下手柄锚点语义与 `20..1000` 宽高钳制 |
| 无副作用 | 不写入 `PageShapeItem`，不通知，不保存，不触发历史事务 |

`EditorPage` 仍是状态拥有者：它在既有 `_applyState` 周期中把输出赋回形状，并保持 `ResizeHandles.onChanged` 的通知/自动保存时序。协作者不能持有形状实例，不能自行调用页面回调。

| 手柄 | 影响轴 | 锚点语义 |
|---|---|---|
| 左上、右上、左下、右下 | 宽度和高度 | 左/上边被拖动时同步移动 `x/y`；右/下边被拖动时保持原点 |
| 左边、右边 | 宽度 | 左边同步移动 `x`；右边保持 `x` |
| 上边、下边 | 高度 | 上边同步移动 `y`；下边保持 `y` |

## 行为不变量

1. 八个手柄位置、屏幕到画布的转换、选中边框和 Widget 结构保持不变。
2. 左/上拖拽继续同步移动 `x/y`，右/下拖拽继续保持原点；角手柄继续双轴调整，边手柄继续单轴调整。
3. 宽度和高度继续钳制为 `20..1000`，且在钳制时保持当前页面已有的增量/原点语义。
4. 不改变形状旋转、拖动、删除、选择、工具模式、命令历史、保存或渲染。
5. 协作者为 pure Dart 对象，可在不构建 Widget、控制器或页面状态的测试中验证。

## 验收标准

1. overlay extension 不再含形状缩放的条件分支，只负责传递明确输入和写回明确输出。
2. 单元测试覆盖左右上下四边、四角、最小/最大钳制和输入不可变性。
3. 现有形状编辑、几何、撤销/重做、编辑器展示和全量回归保持通过。
4. 新协作者不导入 Flutter widget、控制器、存储、I/O 或 `BuildContext`。
