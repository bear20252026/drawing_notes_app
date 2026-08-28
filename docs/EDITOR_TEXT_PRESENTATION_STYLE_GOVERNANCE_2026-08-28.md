# 编辑器文字展示样式协作者治理

**作者：Manus AI**
**日期：2026-08-28**
**基线：`master@20d22a7`（PR #32 合并提交）**

## 目标

本专项只治理 `EditorPage` 文字 overlay 中可确定、可复用且无副作用的样式映射与布局参数计算。页面仍然拥有文字对象、控制器、选择状态、手势、编辑提交、通知、自动保存和斜杠命令；协作者不拥有任何文档状态，也不接收 `BuildContext` 或回调。

## 审计结论

`editor_page_text_overlays.dart` 同时承接文字位置转换、选择/连线/删除动画、待办交互、拖动与右下角宽度缩放，以及文字样式构造。其富文本和旧文档分支重复计算字体族、对齐方式、字号缩放、颜色、字重、字形和装饰线。这一部分可被提炼为纯展示协作者；但 `TextSpan` 构造依赖 Flutter UI 类型，仍应保留在 presentation 层，而不能下沉到 domain 或 application。

## 契约

`EditorTextPresentationStyle` 只接受原始展示输入并返回不可变 Flutter 样式值：

| 输入 | 输出 | 规则 |
|---|---|---|
| 基础字号与 view scale | `fontSize` | 继续使用 `fontSize * viewScale` |
| 字体族标识 | `fontFamily` | `serif`、`monospace`、`handwriting` 分别映射到 Flutter 字体族，其余值保持系统默认 |
| 文字颜色、待办完成态、便利贴默认色 | `color` | 保持已完成待办 0.45 透明度和默认黄色便利贴深色文字规则 |
| 粗体、斜体、下划线、删除线 | `fontWeight`、`fontStyle`、`decoration` | 保持旧文档和富文本 run 的现有映射，双装饰使用 `TextDecoration.combine` |
| 对齐标识 | `TextAlign` | `left`、`center`、`right` 一一映射 |
| 可选宽度与 view scale | `BoxConstraints`、`softWrap` | 保持有宽度时按 view scale 约束并启用换行，无宽度时不人为添加最大宽度 |

## 明确不迁移的责任

图片、文档、控制器、Widget 构建、`BuildContext`、选中/删除状态、对象拖动、文字编辑控制器、斜杠命令、宽度缩放状态、`_applyState`、`_notifyChanged`、历史快照、自动保存和任何 I/O 均不属于协作者。

## 验收不变量

改造后必须保持以下行为：旧文档无 runs 时仍按整块样式渲染；有 runs 时每个片段仍独立应用颜色、粗体、斜体、下划线和删除线；待办完成态和默认便利贴颜色保持原有视觉规则；三种对齐、字体族、字号随 view scale 缩放、可选宽度换行、文字选择与宽度手柄行为均不变。协作者必须可脱离页面单元测试，且不得引入第二状态源或跨越 presentation 边界。

## 非目标

本专项不引入富文本编辑器，不改变文档 JSON schema，不调整字体资源，不重写 `TextSpan`，不修改文字对象模型，不改变手势命中区域，也不继续机械拆分 `part` 文件。
