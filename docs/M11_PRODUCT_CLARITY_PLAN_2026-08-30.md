# M11 产品清晰化方案（Product Clarity Plan）

> 日期：2026-08-30
> 背景：M0-M10 交付后产品仍呈"半成品"状态——功能入口重叠、部分入口为空壳、IA 不清晰。本方案对照 **AFFiNE（重点）**、Excalidraw、Saber 三款参考产品，给出收敛路线并实施第一阶段。
> 基线：master（HANDOVER_REPORT_2026-08-29 之后）。

---

## 1. 问题诊断（审计结论）

### 1.1 入口重叠（"有重叠的"）
| 重叠项 | 证据 | 判断 |
|---|---|---|
| HomePage「时间线」Tab ≈ AllDocsPage 分组列表 | home_page_tabs.dart / all_doc.dart `groupOf` | 几乎等价；且 HomePage 不列块文档 |
| SchedulePage「日程」 | 无自有存储，由 updatedAt 派生（schedule_entry.dart / schedule_page.dart） | 伪日程，与 All Docs「今天/本周/更早」分组语义重复 |
| NotesWritingPage「纯笔记」 | 自述占位骨架（notes_writing_page.dart:5-8），无数据无路由 | 与块编辑器完全冗余 |
| home_dashboard_page.dart | 零引用孤页 | 死代码 |

### 1.2 空壳入口（"没有的"）
- AllDocsPage 侧栏：Journals/提醒/Intelligence/回收站/导入/邀请成员/模板 全部无实现（纯装饰复制）。
- AllDocsPage 搜索框：空回调（all_docs_page.dart:62-64）。
- 收藏夹 Tab：`onToggleFavorite: () {}`（:462），恒空。
- 工具条：视图切换/显示按钮均为空 `onPressed: () {}`。

### 1.3 与三款参考产品的定位
| 参考 | 借鉴点 | 不抄的 |
|---|---|---|
| **AFFiNE（重点）** | 单一文档工作台（All Docs）+ Page/Edgeless 双模文档 + 收藏/标签组织 + 块编辑器 | 云协作/邀请成员/AI（本项目纯本地） |
| Excalidraw | 无限画布工具面板（画笔/形状/便签） | 纯白板定位 |
| Saber | 手写笔记体验 | PDF 标注（已有 PDF 导出即可） |

**产品一句话**：一款本地优先的「文档工作台」——每个文档要么是 Page（块编辑页），要么是 Edgeless（无限画布），全部文档一个入口，收藏/文件夹做组织。

---

## 2. 目标 IA（收敛后）

```
AppShell
├── 全部文档（唯一列表入口，AFFiNE All Docs 模式）
│     ├── 快速搜索（实时过滤标题/描述）
│     ├── Tab：文档 / 收藏夹 / 标签
│     └── 行操作：打开 / 收藏星标
└── 画板·笔记本（绘画库：文件夹组织 + WebDAV 同步/密码盘/搜索设置入口）
        （设置类功能集中于此页 AppBar，后续可上收为全局设置页）
编辑器层：EditorPage（画布）/ NoteDocModesPage（Page↔Edgeless 双模）
```

砍掉的导航目的地：**日程**（数据派生 + 与时间分组重叠）、**纯笔记**（占位冗余）。

---

## 3. 分阶段落地路线

### P1（本轮已实施）——IA 收敛 + All Docs 真实化
- [x] 导航 4 → 3：移除纯笔记占位页；**日历保留**（用户决策 2026-08-30），HomePage「最近」时间线 Tab 删除，其"按时间看文档"能力并入日历看板
- [x] 日历真实化：新增 ScheduleEvent 待办/日程（domain + infrastructure JSON 原子写）——新增/勾选完成/删除，月历活动点含事件；日历从"修改日期派生视图"升级为"真日程本"
- [x] HomePage 收敛为两 Tab：无限画布 / 笔记本（FAB 相应简化）
- [x] All Docs 侧栏精简为真实可达项：全部文档 / 收藏夹 / 标签（与 Tab 一一对应）
- [x] 快速搜索接线：`filterSections` 纯函数（application/all_doc_search.dart）+ UI 实时过滤
- [x] 收藏接线：`FavoriteStore`（infrastructure/favorite_store.dart，原子写 JSON）+ 乐观 UI + `_loadAllDocs` 回填收藏态
- [x] 删除零引用孤页 home_dashboard_page.dart
- [x] 工具条移除无实现的空按钮（视图切换/显示）
- 测试：all_doc_search_test / favorite_store_test / schedule_event_store_test / schedule_page_events_test / all_docs_page_test（搜索过滤、星标乐观更新、Tab 切换）+ 存量全量回归

### P2（下一步）——块编辑器/Edgeless 与 AFFiNE 一致性打磨
1. 选中块浮动工具条（当前为固定工具栏，AFFiNE 为选中浮出）
2. 嵌套子块拖拽（当前仅顶层块可拖）
3. Edgeless 工具面板：画笔/便签/形状（对照 Excalidraw）
4. All Docs 排序与"最近打开"置顶

### P3（收尾）——清档
1. 删除 legacy：schedule/、notes_writing_page、孤立测试更新
2. 设置入口上收为独立设置页（同步/密码盘/主题）
3. 标签维度落地（blockdoc 元数据 + folder 归一）

---

## 4. 风险与护栏
- **依赖边界**（features→shared→core）为最高护栏：FavoriteStore 按 NoteBlockDocStore 同模式放 infrastructure，不越界。
- **material_ui 方言**：测试中 flutter/material 与 mui 的同名类（TextField/Material）需显式别名——本轮测试已踩过并按既有模式处理。
- **双 GlobalMaterialLocalizations 委托**：任何新 pumpWidget 测试都必须双注册（回归测试 3b30aa8 锁定）。
- **AppShell 常驻环境背景动画**：测试禁用 pumpAndSettle。
