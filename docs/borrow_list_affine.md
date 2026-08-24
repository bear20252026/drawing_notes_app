# AFFiNE 高价值借鉴选定清单（2026-08-22——基于审计报告）

> 审计报告：docs/affine_audit_report.md（15 项界面/UI/功能审计）
> 选定：P0 三项（低风险高价值——照搬本地化——不崩溃——保留版权）

## 一、选定清单（P0——本轮照搬）

| # | 借鉴功能 | AFFiNE 来源 | 照搬方式（本地化） | 价值 |
|---|---------|-----------|------------------|------|
| 1 | **Slash 命令**（/ 键——块菜单） | BlockSuite Slash Commands | SlashCommandService（/ 键解析——段落/标题/列表/引用/代码命令——CommandPalette 已有——补文档插入命令）——editor_core 纯 Dart | ★★★★ |
| 2 | **Markdown 快捷**（输入 # 标题/- 列表/[] todo） | BlockSuite Markdown 支持 | MarkdownShortcutService（输入行解析——# → 标题/- → 列表/[] → todo——Word 式打字增强）——editor_core 纯 Dart | ★★★★ |
| 3 | **工具栏底部统一**（note/whiteboard 一致） | AFFiNE UI（Paper/Edgeless 工具栏一致） | 工具栏位置统一（底部——两种模式一致——不重复显示）——UI 层 | ★★★ |

## 二、照搬原则（本地化——不崩溃）

1. **积木式**（每个借鉴 = 独立组件——纯 Dart 可测——不搞崩）
2. **本地化适配**（照搬概念/模型——本地化到我们的架构——Flutter 原生）
3. **保留版权**（NOTICE 更新——AFFiNE BSL 1.1/MIT 版权声明保留）
4. **测试后合入**（全量测试零回归——Actions 绿色）

## 三、后续（P1/P2——审计报告）

- P1：Block Hub 拖放面板 / 便签块 edgeless / 页面树 / Workspace 卡片 / 演示 UI
- P2：协作 CRDT / AI 助手 / 智能连接器

## 四、版权声明（保留）

- AFFiNE：BSL 1.1（BlockSuite 组件 MIT）——https://github.com/toeverything/AFFiNE
- 借鉴概念/模型——本地化实现——NOTICE 已记录版权归属

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)
