# M9 全部文档工作台 + Apple(HIG) 设计系统 —— 验收记录

日期：2026-08-29
目标：AFFiNE「全部文档」工作台 1:1 + 全项目 Apple(HIG) 标准化
门禁：`flutter analyze` 0 / architecture 通过 / 全量回归 **1248** 全通过
提交：`56f2e43`（M9 + Apple 系统）、`7befb32`（All Docs 缓存 + 设计文档）

## 交付

### 1. All Docs 工作台（AFFiNE 1:1，作为应用新主页）
- **领域/应用层**（`features/all_docs/{domain,application}`）：
  - `all_doc.dart`：`AllDocKind{c,canvas,note,blockdoc}`、`AllDoc`、`AllDocGroup{today,thisWeek,earlier,neverUpdated}`、`AllDocSection`、`groupOf(now)`。
  - `all_doc_query.dart`：`BlockDocMeta`、`AllDocQueryResult`、`buildAllDocs({docs,notebooks,blockDocs,now,favoriteOnly})` —— 画布/笔记页/块文档三源聚合、去重、按 `updatedAt` 排序、分组、收藏过滤。
- **展示层**（`features/all_docs/presentation`）：`all_docs_page.dart`（左面板 + 工具条 + 文档/精选/标签 + 分组列表）、`all_docs_sidebar.dart`（工作区/导航/收藏/组织/标签等）、`all_doc_row.dart`（kind 图标+标题+描述+相对时间+头像+星标+⋮）、`time_ago.dart`。
- **集成（lead）**：`app_shell.dart` 第 0 个目的地换成 `AllDocsPage`；`_loadAllDocs` 聚合三源；`_openAllDoc` 按 kind 路由（canvas→编辑器 / note→NotebookViewPage / blockdoc→NoteDocModesPage）；`_newAllDoc` 新建三类文档；`app.dart` 注入共享 `NoteBlockDocStore`。
- **UX 修正**：`AllDocsPage` 用 `initState` 缓存 `loadDocs` future，避免切 tab 重载闪屏（`7befb32`）。

### 2. Apple(HIG) 设计系统
- `core/theme/app_design.dart`：重着色为苹果色板（Action Blue `#0066CC`、墨 `#1D1D1F`、米白画布 `#F5F5F7`、深画布 `#000`、`#FF3B30` 错误红、`#30D158` 绿），标题 w600+负字距，胶囊/圆角；**结构常量不变**（`app_design_test` 自洽）。
- `core/theme/apple_design.dart`：`AppleColor`/`AppleSpacing`/`AppleRadius`/`AppleType` + `ApplePrimaryButton`/`ApplePillSearchField`/`AppleSectionHeader`。
- 全库清除旧深蓝色板（`#4568A9/172033/181F2E/222B3D/F6F7FA/166C59/7C4DFF/F5A623`）。
- 落地：All Docs 全页、edgeless `#7C4DFF→#BF5AF2`；其余页面逐页打磨（M10-A/B 进行中）。

## 验收证据

- `flutter analyze`：0 问题（全仓）。
- `flutter test --concurrency=1`：**1248** 全通过（基线 1213 + AllDocs 35）。含 architecture 边界测试。

## 已知边界

- `HomeDashboardPage` 已无引用（旧首页，被 All Docs 取代）；无测试依赖，保留作为废弃代码，后续可删除。
- `AppShell._moveNote` 已移除（唯一调用方为旧首页 dashboard）。
- 页面转场用 `ZoomPageTransitionsBuilder`（vendored `material_ui` 不含 `Cupertino/FadeUpwards` 转场 builder）。
- All Docs「精选/标签」Tab 目前为视觉切换，收藏过滤需再接线（favoriteOnly）——作为后续改进项。
- Windows 真机安装/启动/导航实测通过（见 `RELEASE_MANUAL_TEST_ACCEPTANCE`）；M9 上线后首页已切换为 All Docs。
