# 块编辑器与 AFFiNE 交互一致性对照

> M5 收口交付 — 对照 AFFiNE (MIT) 的块式编辑交互，逐项核对当前实现状态。

## 对照范围

基于 M0-M4 已交付的块模型（NoteBlock / NoteBlockEditor / NoteBlockDoc）与 `note_editor_page.dart` 展示层。

## 交互对照表

| 交互 | AFFiNE 行为 | 当前实现 | 状态 |
| --- | --- | --- | --- |
| **Enter 分块** | 在当前块光标处拆分，生成同类型新块 | `splitAtCursor` + onKeyEnter | ✅ 已实现 |
| **Backspace 合并** | 空块按 Backspace 合并到前一块 | `mergeWithPrev` + onKeyBackspace | ✅ 已实现 |
| **块聚焦高亮** | 点击块显示聚焦背景色 | 聚焦块 primaryContainer 浅色背景 | ✅ 已实现 |
| **标题层级** | h1-h6 六级字级 | 1-6 级（28/24/20/18/16/14px） | ✅ 已实现 |
| **Todo 勾选** | 点击复选框切换完成状态 | Checkbox + toggleTodo | ✅ 已实现 |
| **代码块等宽** | monospace 字体 + 浅色背景 | monospace + surfaceContainerHighest | ✅ 已实现 |
| **空文档提示** | 显示占位引导文字 | "键入 / 添加块" + 图标 | ✅ 已实现 |
| **未保存提示** | 标题栏显示未保存状态 | AppBar "未保存" 标签 | ✅ 已实现 |
| **退出提醒** | 未保存时退出弹窗确认 | PopScope + AlertDialog | ✅ 已实现 |
| **保存成功提示** | 轻量 toast/snackbar | SnackBar "文档已保存" | ✅ 已实现 |
| **类型切换** | 工具栏即时切换块类型 | 工具栏按钮 + changeType | ✅ 已实现 |
| **深色模式** | 自动适配系统主题 | Theme.of(context) 全链路 | ✅ 已实现 |
| **无障碍** | 语义标签 + 朗读 | Semantics label | ✅ 已实现 |
| **块手柄拖拽** | 左侧拖拽手柄排序 | 未实现 | ⏳ 后续 |
| **/ 菜单** | 键入 / 弹出类型选择面板 | 未实现 | ⏳ 后续 |
| **键盘导航** | 上下箭头在块间移动焦点 | 未实现 | ⏳ 后续 |
| **块间拖放** | 拖拽块到任意位置 | 未实现 | ⏳ 后续 |
| **富文本** | 块内粗体/斜体/链接 | 未实现（M1.5） | ⏳ 后续 |
| **图片预览** | 点击图片放大预览 | 未实现（M2） | ⏳ 后续 |
| **表格编辑** | 表格增删行列 | 未实现（M2） | ⏳ 后续 |

## 核心交互一致性结论

### 已对齐（M5 范围内）
- **Enter/Backspace 行为**：与 AFFiNE 一致 — Enter 继承类型拆分，Backspace 空块合并到前块。
- **块聚焦反馈**：聚焦块有浅色背景高亮，AFFiNE 使用类似的 subtle highlight。
- **标题层级**：h1-h6 六级字号递减，与 AFFiNE 的 heading 级别一致。
- **Todo 交互**：复选框 + 删除线 + 灰色文字，与 AFFiNE 一致。
- **代码块**：等宽字体 + 浅色背景，AFFiNE 风格。
- **空文档引导**：AFFiNE 显示 "Click to edit" 或类似提示，当前实现 "键入 / 添加块"。
- **未保存状态**：AFFiNE 在标题旁显示 dirty indicator，当前实现 "未保存" 标签。
- **退出确认**：AFFiNE 未保存退出时弹窗确认，当前实现 PopScope + AlertDialog。
- **主题适配**：AFFiNE 支持深色模式，当前实现全链路 Theme.of(context)。
- **无障碍**：AFFiNE 有语义标签，当前实现 Semantics label。

### 待后续里程碑
- **块手柄拖拽**：需要 M5+ 或 M6 实现（依赖手势识别）。
- **/ 菜单**：需要浮层 UI + 搜索过滤，建议 M6。
- **键盘导航**：需要 FocusNode 管理 + 箭头键监听，建议 M5+。
- **富文本**：M1.5 规划。
- **内嵌块渲染**：M2 负责。

## 实现细节说明

### 主题适配
所有颜色均通过 `Theme.of(context).colorScheme` 获取，自动适配 light/dark 模式：
- `primaryContainer`（聚焦背景）
- `onSurface`（文本颜色）
- `surfaceContainerHighest`（代码块背景）

### 无障碍
每个块行包裹 `Semantics` 标签，格式为 `"{类型}: {内容}"`，如 `"标题2: 我的标题"`、`"待办事项: 买菜"`。

### 退出保护
使用 `PopScope` 拦截返回手势，未保存时弹出确认对话框，用户可选择"取消"或"放弃"。

---
*文档由 Claude 团队生成 | Drawing Notes App | M5 收口*
