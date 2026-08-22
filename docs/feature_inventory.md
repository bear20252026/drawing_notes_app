# 4 项目可搬运功能盘点（2026-08-22）

> 用户要求：按 Saber/Excalidraw/excalidraw-cn/AFFiNE 的源代码与 UI 设计修改——
> 小组件功能/画笔笔画功能都可以搬——保留版权说明。

## 一、Saber（GPL-3.0——重点：画笔笔画组——待搬运）

| 功能 | 说明 | 状态 |
|------|------|------|
| **钢笔（Pen）** | 压力感应笔画——粗细随压力变化（手写感） | ⏳ **待搬运** |
| **圆珠笔（Ballpoint）** | 均匀笔画——无压力变化（清晰书写） | ⏳ **待搬运** |
| **荧光笔（Highlighter）** | 半透明宽笔画——强调/高亮（暗光护眼） | ⏳ **待搬运**（当前荧光粗细已修） |
| **铅笔（Pencil）** | 纹理笔画——粗糙感（手绘铅笔效果） | ⏳ **待搬运** |
| **形状笔（Shape Pen）** | 手绘形状自动整形（直线/矩形/圆形） | ⏳ 待搬（GeometryEngine 已建——整形可接入） |
| **橡皮擦** | 整笔/像素（已搬——ToolEngine 统一） | ✅ 已搬 |
| **选择工具** | 选择/移动/缩放（已搬） | ✅ 已搬 |
| **深色反转** | 白墨黑底（已搬） | ✅ 已搬 |
| **首页模式** | recent/browse/whiteboard/settings（概念已搬——完整首页后续） | ⏳ 部分 |

## 二、Excalidraw（MIT——已搬 22 项——补强）

| 功能 | 说明 | 状态 |
|------|------|------|
| 无限画布/手绘/导出/形状库/箭头绑定/Lasso/Clipboard/Grid/WYSIWYG/Charts/i18n/AnimatedTrail/Measurement/Gesture/CommandPalette/Frames/BoundText/Hints | 全部已搬（editor_core 纯 Dart——积木式） | ✅ 已搬 |
| **补强**：元素编辑（双击编辑——用户删了——不做）；图库/组件库（Excalidraw Library——已搬 ShapeLibrary） | — | ✅ |

## 三、AFFiNE（BSL/MIT——已搬 21 项）

| 功能 | 说明 | 状态 |
|------|------|------|
| 数据库/幻灯片/便签/块编辑/Kanban/层管理/属性面板/历史面板/导出 UI/FeatureFlag/Workspace/DocumentImport/页面设计 | 全部已搬（editor_core + editor_v2） | ✅ 已搬 |
| **补强**：块编辑器（RichTextBlock——已搬）；布局（侧边栏/工具栏——已搬）；Liquid Glass 质感（苹果设计语言——已搬） | — | ✅ |

## 四、excalidraw-cn（MIT——已搬 2 项）

| 功能 | 说明 | 状态 |
|------|------|------|
| 多画布（PageV2——已搬） | 分页管理（侧边栏——已搬） | ✅ 已搬 |
| 中文手写风格 | 中文手写字体适配（后续） | ⏳ 可选 |

## 五、优先搬运（本轮——Saber 画笔笔画组）

**用户强调"什么画笔的笔画功能都可以搬"**——优先搬运 Saber 画笔组：
1. **钢笔（Pen）**——压力感应（pressure → 粗细变化——AnimatedTrail 已有 pressure——接入）
2. **圆珠笔（Ballpoint）**——均匀（基础笔画）
3. **荧光笔（Highlighter）**——半透明宽笔画（高亮）
4. **铅笔（Pencil）**——纹理笔画（粗糙感）

**实施**（本地化——editor_core 纯 Dart——保留版权——NOTICE 更新）。

## 版权说明

- Saber：GPL-3.0（Adil Hanney）——仅借鉴笔画风格参数（非代码复制）——NOTICE 已记录
- Excalidraw：MIT——已记录
- AFFiNE：BSL 1.1/MIT——已记录
- excalidraw-cn：MIT——已记录

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)
