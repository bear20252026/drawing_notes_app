# AFFiNE 审计评估报告（研发评估——2026-08-22）

> 用户要求：继续借鉴 AFFiNE（toeverything/AFFiNE）——照搬代码越多功能越好——
> 本地化适配——不崩溃——保留原版权声明——先给出审计意见。

## 一、AFFiNE 概览（审计对象）

- **仓库**：https://github.com/toeverything/AFFiNE（71.7k 星——Blocksuite 驱动）
- **定位**：Notion + Miro 替代品——docs + whiteboards + databases + AI——local-first
- **技术**：BlockSuite（块编辑器框架——CRDT 协作——Yjs）+ Flutter/React
- **版权**：BSL 1.1（源码可用——修改需授权）+ MIT 组件

## 二、优秀界面设计（审计——可借鉴——照搬风险评估）

| # | 界面/UI | 价值 | 照搬风险评估 | 本地化建议 |
|---|---------|------|-------------|-----------|
| 1 | **Page vs Edgeless 模式**（右上角切换 Ctrl+Alt+E——文档/画布双模式） | ★★★★★ | 低（概念——架构已有） | ✅ 已部分落地（note/whiteboard 模式——补切换按钮） |
| 2 | **块编辑器**（BlockSuite——/ 键加块——段落/标题/列表/引用/代码/LaTeX/Table） | ★★★★★ | 中（需块渲染） | ✅ 已落地基础（NoteEditorWidget——补 / 键菜单） |
| 3 | **侧边栏**（页面树——Workspace 卡片——文件系统抽象） | ★★★★ | 低（概念） | ✅ 已落地（EditorV2Sidebar——补页面树） |
| 4 | **数据库表格**（TableV2——多视图——Filter/Collections） | ★★★★ | 中（数据模型） | ✅ 已落地（TableV2——补视图切换） |
| 5 | **Block Hub**（右下角——拖放插入块） | ★★★★ | 低（UI 组件） | ⏳ 可搬（拖放块面板） |
| 6 | **Slash 命令**（/ 键——双栏菜单——左分类右功能） | ★★★★ | 中（命令系统） | ⏳ 可搬（CommandPalette 已有——补双栏） |
| 7 | **工具栏底部**（Paper/Edgeless 一致——界面统一） | ★★★ | 低（布局） | ⏳ 可搬（工具栏统一） |
| 8 | **便签块**（Note Block——嵌套文档容器——edgeless 便签） | ★★★★ | 低（模型已有） | ✅ 已落地（NoteItem——补 edgeless 便签） |
| 9 | **智能连接器**（直线/曲线/正交/箭头——自动吸附形状/绕障碍/路径标签） | ★★★★ | 高（几何复杂） | ⏳ 部分（ArrowBinding 已有——补正交/绕障碍） |
| 10 | **多用户协作**（CRDT——实时协作——端到端加密） | ★★★ | 高（需服务器） | ⏳ 后续（架构层） |
| 11 | **AI 助手**（AI 写作/布局——MCP——自定义 Token） | ★★★ | 高（需 LLM） | ⏳ 后续（可选——本地模型） |
| 12 | **演示模式**（edgeless 幻灯片——PresentationService） | ★★★★ | 中（渲染） | ✅ 已落地（PresentationService——补演示 UI） |
| 13 | **Workspace 卡片**（本地/云同步状态——信息密度） | ★★★ | 低（UI 卡片） | ⏳ 可搬（状态卡片） |
| 14 | **暗色模式**（不暗化 UI 也暗化内容） | ★★★★ | 低（渲染） | ✅ 已落地（isInverted——补全局暗色） |
| 15 | **Markdown 快捷**（# 标题/- 列表/[] todo/> 引用/``` 代码/$$ LaTeX/[[反向链接]]） | ★★★★ | 低（输入解析） | ⏳ 可搬（输入快捷转换——高价值） |

## 三、研发评估结论（照搬优先级）

**P0（本轮——低风险高价值——照搬本地化）**：
1. **Slash 命令**（/ 键——块菜单——CommandPalette 已有——补文档插入）
2. **Markdown 快捷**（输入 # 标题/- 列表/[] todo——Word 式打字增强）
3. **工具栏底部统一**（note/whiteboard 一致）

**P1（后续）**：Block Hub 拖放面板 / 便签块 edgeless / 页面树 / Workspace 卡片 / 演示 UI
**P2（架构）**：协作 CRDT / AI 助手 / 智能连接器

## 四、照搬原则（本地化——不崩溃）

1. **积木式**（每个借鉴 = 独立组件——纯 Dart 可测——不搞崩）
2. **本地化适配**（照搬概念/模型——本地化到我们的架构——Flutter 原生）
3. **保留版权**（NOTICE 更新——AFFiNE BSL 1.1/MIT 版权声明保留）
4. **测试后合入**（全量测试零回归——Actions 绿色）

## 五、版权声明（保留）

- AFFiNE：BSL 1.1（BlockSuite 组件 MIT）——https://github.com/toeverything/AFFiNE
- 借鉴概念/模型——本地化实现——NOTICE 已记录版权归属

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)
