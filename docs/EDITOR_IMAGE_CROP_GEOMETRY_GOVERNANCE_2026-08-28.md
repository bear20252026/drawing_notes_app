# EditorPage 图片裁剪几何协作者治理说明

**日期：2026-08-28**
**适用分支：`refactor/editor-image-crop-geometry`**

## 审计结论

图片裁剪分为两类职责。`EditorCanvasInteractionState` 拥有短生命周期的裁剪目标和裁剪矩形；`EditorPage._confirmCrop` 读取文件、解码/重编码图片像素、写回文件、更新图片对象并通知上层保存。这两类职责均不应下沉。

但 `editor_page_drag_ops.dart` 中四角手柄如何根据拖拽增量更新裁剪矩形，以及 `_confirmCrop` 如何将画布裁剪矩形映射到原始图片像素矩形，均为确定性的纯几何规则。当前规则直接混在手势和 I/O 代码中，难以在不构造页面、图片文件或 `ui.Image` 的情况下单独验证。

## 协作者契约

`EditorImageCropGeometry` 只依赖 `dart:ui` 的 `Rect`、`Offset` 和 `Size`，且暴露以下无副作用操作：

| 操作 | 输入 | 输出 | 非职责 |
|---|---|---|---|
| `resizeCropRect` | 当前画布裁剪矩形、图片画布边界、命名四角手柄、已换算的画布增量 | 受图片范围和最小 10px 尺寸约束的新裁剪矩形 | 不修改交互状态、图片对象或 Widget |
| `sourceRectForCrop` | 图片画布边界、裁剪矩形、原图像素尺寸 | 现有 `+1` 比例换算与钳制规则对应的像素矩形 | 不读取文件、解码、绘制或写入字节 |

`EditorPage` 继续负责屏幕到画布的增量换算、在 `_applyState` 中写入 `_cropRect`、以及手势期间原有的重建时序。`_confirmCrop` 继续拥有文件存在性校验、图像解码/绘制/编码、对象尺寸写回、交互状态清理、用户提示和 `_notifyChanged`。

## 四角语义与不变量

| 手柄 | 可移动边 | 锚点 |
|---|---|---|
| 左上 | `left`、`top` | `right`、`bottom` 保持 |
| 右上 | `right`、`top` | `left`、`bottom` 保持 |
| 左下 | `left`、`bottom` | `right`、`top` 保持 |
| 右下 | `right`、`bottom` | `left`、`top` 保持 |

1. 裁剪边界继续限制在图片 `x/y/width/height` 范围内，宽高继续至少为 10 画布单位。
2. 像素映射继续使用现有 `sourceSize / (imageExtent + 1)` 比例，防止本次重构造成单像素的图像裁剪偏移。
3. 进入裁剪、确认裁剪、失败提示、文件写入、对象更新、交互清理、历史事务和通知时序保持不变。
4. 协作者不导入 `BuildContext`、Widget、控制器、存储、`dart:io`、`ui.Image` 或领域图片对象，不形成第二状态源。

## 验收标准

1. 拖拽 extension 不再含按角判断和边界钳制的几何分支，只传入明确手柄与画布增量。
2. 像素映射不再驻留 I/O 编排方法中，并由纯单元测试锁定。
3. 测试覆盖四角更新、边界钳制、最小尺寸、像素映射和输入不可变性。
4. 既有画布交互、图片资产、笔记保存、撤销/重做、编辑器展示及全量回归全部通过。
