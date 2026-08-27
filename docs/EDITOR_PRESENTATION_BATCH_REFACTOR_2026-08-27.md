# 编辑器展示层批量重构设计

**日期：**2026-08-27

## 目标

本轮不以“文件拆分数量”为目标，而是围绕编辑器展示层的一个连续责任链收口：**用户在工具栏发起动作 → 页面协调模式切换或对象操作 → Canvas/overlay 显示结果**。此前 `EditorToolbar`、`EditorContextBar` 和 `ToolbarUiFlags` 已经是清晰的展示契约；剩余复杂度主要集中在页面内联回调的动作装配，以及拖动时重复扫描混排对象集合的分组展开。

> 本批次将保留 `EditorPage` 作为控制器、会话和持久化通知的组合根；新协作者不持有 Widget、`BuildContext`、`DrawingController`、`EditorViewModel`、I/O 或通知回调。

## 批量改造内容

| 编号 | 协作者 | 解决的问题 | 输入输出边界 | 页面保留职责 |
|---|---|---|---|---|
| B1 | `EditorToolModeState` | 手型、框选和形状工具的互斥状态散落在左侧工具栏闭包、工具切换和输入分支中 | 只拥有 `handActive`、`marqueeActive`、`activeShape`；通过显式模式切换命令输出新的短生命周期 UI 状态 | 同步 `EditorViewModel`、`SelectionTool`、框选草稿和实际手势响应 |
| B2 | `EditorOverlayGroupResolver` | 拖动对象时，文本、图片、形状的 `groupId` 扫描和展开逻辑内嵌在页面 extension 中 | 消费三个对象集合和选中 id，返回只读扩展后的 id 集合 | 坐标变换、吸附、模型写入、通知与拖动轨迹 |
| B3 | `EditorSelectionTransformState` | 缩放和旋转滑块值与相对变换增量内联在页面闭包中 | 只拥有滑块暂态，输出缩放倍率和旋转弧度增量 | 实际对象变换、事务提交、通知和持久化 |
| B4 | 直接测试 | 目前重点覆盖状态映射，但工具模式互斥、分组解析和变换增量缺少纯测试 | 无 Widget、无真实控制器的确定性测试夹具 | 端到端编辑器回归继续由现有测试集守护 |

## 不变量

`EditorToolModeState` 只解决展示层模式互斥，不能成为 `SelectionTool`、`EditorViewModel` 或 `EditorCanvasInteractionState` 的第二个状态源。页面在单个 `_applyState` 中同时应用协作者输出与控制器/视图模型变更，保持原有重建时序。

`EditorOverlayGroupResolver` 必须保持既有语义：只有当前选择对象带有 `groupId` 时才展开；文字、图片和形状中所有同组元素均进入结果；不应修改传入集合或返回可写集合。

更大规模的 `EditorToolbarActions` 工厂化仍是后续候选，但其会同时改变大量回调组装形状。本批次优先收口已有清晰数据边界的工具模式、分组解析和变换增量，避免为追求改动量而改变稳定的展示契约。

## 验收标准

1. 左侧工具栏、上下文栏、输入路由和拖动逻辑仍使用相同的模式、分组和回调语义。
2. 新协作者均有直接单元测试，覆盖互斥模式、关闭模式复位、分组跨对象类型展开、无组回退和只读输出。
3. `EditorPage` 与 `editor_page_drag_ops.dart` 的动作装配行数明显降低，且不新增跨 feature 依赖。
4. 通过格式化、全量串行 Flutter 测试、静态分析、架构边界、差异检查和远程 14 项门禁。
