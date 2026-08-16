# editor_core——纯 Dart 编辑器核心（专家目标架构 V2 引导——2026-08-16）

## 约束（非协商——R-02/R-03）

- **禁止 import**：Flutter、dart:io、file_selector、path_provider、shared_preferences
- 纯 Dart 领域包——可独立单测（无平台依赖）

## 职责（逐步接管）

- `domain/`：Document、Page、Layer、Stroke、Text、Shape（**不可变数据模型**——copyWith/版本化 DTO/合法性验证）
- `commands/`：AddStroke、CreateShape、CreateText、MoveItem、Undo/Redo
- `geometry/`：唯一 GeometryEngine（直线/箭头/矩形/椭圆——端点/包围盒/旋转/命中/预览/导出 primitives）
- `history/`：immutable state + inverse command（撤销/重做）
- `serialization/`：DocumentV2 DTO

## 当前阶段（批次 A 引导）

空包引导——仅建立包结构与依赖约束；后续按批次 B（GeometryEngine）→ C（命令历史）→
E（Editor V2 主路径）接管。
