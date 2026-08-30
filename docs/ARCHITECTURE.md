# 架构说明（ARCHITECTURE.md）

> 面向本仓库贡献者的模块地图与依赖规则。修改结构前请先读此文件。
> 参照项目：AFFiNE / BlockSuite（MIT，© toeverything）——版权声明见 `THIRD_PARTY_NOTICES.md`。

## 1. 技术栈与总体形态

- Flutter（Dart），单仓库单应用：`drawing_notes_app`
- 目录：`lib/core`（跨模块基础设施）+ `lib/features/*`（业务模块）+ `lib/l10n` + `lib/app`（组合根）
- 测试：`test/`，与 lib 结构镜像（约 1300 项，全绿基线）

## 2. 功能模块地图

| 模块 | 职责 | 关键入口 |
|---|---|---|
| `features/doc` | **笔记**（AFFiNE Page 式打字文档）：块编辑核心、块 UI、页面壳 | `doc_page.dart`、`doc_editor.dart`、`presentation/block_*` |
| `features/notes` | 画板·笔记本宿主：无限画布（Edgeless）、笔记本（画布页集合）、搜索、快捷键盘会话 | `presentation/edgeless_page.dart`、`home_page.dart` |
| `features/drawing` | 绘图引擎：DrawingDocument、图层位图、笔刷/形状/选区/对象编辑 | `application/drawing_controller.dart`、`presentation/editor_page*.dart` |
| `features/all_docs` | 全部文档工作台：列表/搜索/收藏/排序/文档树 | `presentation/all_docs_page.dart` |
| `features/schedule` | 日历·待办：月历 + 24 小时时间轴事件 | `presentation/schedule_page.dart` |
| `features/home` | （已废弃，待删除确认） | — |

## 3. 依赖规则（允许的方向）

```
app（组合根，唯一知道所有实现的地方）
 └→ features/* 页面
      └→ 本模块 application/domain/infrastructure
           └→ 本模块 domain（纯 Dart）+ core/*
```

硬性约定：

1. **组合根唯一装配**：`app/app_shell.dart` 负责创建 store、注入依赖、路由。
   页面不得自行 import 其它 feature 的 infrastructure。
2. **页面级跳转允许 notes → doc**（如画板帧文字跳转笔记页）；**禁止 doc → notes/presentation**
   （块编辑 UI 全部位于 `features/doc/presentation/`）。
3. **共享域**：`notes/domain` 与 `drawing/domain` 目前共享 page_* 模型
   （历史设计：笔记本页=画布文档）。收敛工作见下方"已知债务"。
4. **core**：只放真正跨模块的基础设施（存储、安全、主题、l10n 渡口）。

## 4. 已整改（2026-08-30 第一批）

- ✅ 死模块 features/home 已删除
- ✅ 块编辑 UI 迁入 `features/doc/presentation/`（notes↔doc 表示层循环消除）
- ✅ 共享页面对象模型抽至 `core/canvas_model/`
- ✅ 渲染器移至 `features/drawing/rendering/`
- ✅ 保存机制统一：DocPage 复用 `core/saving/SaveScheduler`
- ✅ DocEditor 拆分（focus/richtext/outline/blocks 四个 part）
- ✅ all_docs_page / edgeless_page 拆分 widgets part
- ✅ NoteEditorPage → DocEditor 更名

## 4b. 剩余债务

| 债务 | 位置 | 说明 |
|---|---|---|
| notes/domain 仍依赖 drawing/domain 的 DrawingDocument | notebook_page*.dart、page_version.dart 等 | 笔记本页=画布文档的历史设计；彻底解耦需抽象页面内容接口（专项） |
| UI 方言双体系 | flutter/material 直引 vs material_ui | 页面壳统一用一方；`apple_design.dart` 禁止再定义与 Flutter 重名的类 |

## 5. 代码规范要点（踩坑沉淀）

1. **UI 方言**：`apple_design.dart` 自定义了 `Scaffold` 等与 Flutter 重名的类。
   同文件混用两种方言时，flutter 类型必须加前缀（`import '...material.dart' as fm show Scaffold, Checkbox;`）。
2. **part/extension**：超过 ~500 行的页面用 part 文件拆分（参照 editor_page_*.dart）；
   extension 上的新增方法必须写在 extension 块内（文件尾会落到类外）。
3. **FakeAsync 测试**：testWidgets 内不得 await 真实文件 IO——注入内存版 store
   （参照 `test/app_shell_smoke_test.dart` 的 `_MemBlockDocStore`）。
4. **BlendMode 语义**：橡皮擦（clear）必须画在 saveLayer 隔离层内，
   直接画主画布会清穿纸面（回归测试：`test/features/drawing/eraser_render_test.dart`）。
5. **保存**：文档编辑 → `_commitHistory()`（历史+脏标记）→ 宿主 `onDirty` →
   防抖自动保存 / 手动 💾。状态显示"未保存 / 保存中… / 已保存 HH:mm"。
6. **删除纪律**：任何删改先征求产品负责人同意（铁律）。

## 6. 发布流水线

`bump pubspec + setup.iss + CHANGELOG` → commit → tag `vX.Y.Z+N` → push →
GitHub Actions `release-build.yml`（Windows 安装包 + Android APK 自动挂 Release）→
`gh release download` 到本机 Downloads。
