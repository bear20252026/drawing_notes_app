# 分层开发框架（AI 多人协作契约）

> 版本：draft（2026-08-28）
> 适用：本仓库后续 AI 协作开发，所有功能/修复均在此框架内落地。
> 原则：**先搭框架与契约 → 队友按契约实现小部件 → lead 组装填充与收口**。绝不改为"多处并行东写一块西改一块"的无序现场。

本文与 `docs/ARCHITECTURE.md` 配合：`ARCHITECTURE.md` 描述既有结构，本文定义"如何在此结构上安全地并行开发"。

---

## 1. 三方分工（不可互换）

| 角色 | 负责 | 产出 | 禁止 |
|---|---|---|---|
| **lead（组合架构师）** | 定义框架、稳定契约、组合根装配、页面 `_applyState`、通知/持久化/历史时序、跨层接线 | 可运行、可验收的整体 | 无；需把"框架"先于"实现"交付 |
| **队友（部件实现者）** | 在框架划定的目录内写叶子实现：纯计算协作者、领域模型、存储适配、Presentation 小组件、动作/几何/命中/快照服务 | 无副作用、有单测、可独立验证的模块 | 触碰组合根、页面私有状态、跨层接线、I/O 时无需归口的直达 |
| **集成（仅 lead）** | 消费队友产出的契约/回调，写入页面状态与组合根 | 完整功能 | 不复制队友模块、不绕过其契约 |

规则：任何功能开发，必须先由 lead 确定"契约 + 目录位置 + 集成点"（本文第 3、4 节），再由队友实现小部件，最后 lead 集成。

---

## 2. 分层骨架（代码落位）

```
lib/
├── main.dart / app.dart            # 启动 + 根组合根                       【lead】
├── app/
│   ├── composition_root.dart       # V2 纯 Dart 能力组合根                【lead】
│   └── default_editor_page_builder.dart  # 唯一 UI 组合点                【lead】
├── core/                           # 跨功能中立契约                        【lead定契约/队友实现】
│   ├── navigation/editor_page_builder.dart   EditorPageBuilder 契约
│   ├── navigation/editor_page_session.dart   EditorPageSession 契约
│   ├── notes_accessor.dart                   INotebookAccessor
│   └── di/ rendering/ security/ storage/ theme/ utils/
├── features/
│   ├── drawing/
│   │   ├── domain/            # 纯模型（文档/图层/笔触/对象）              【队友】
│   │   ├── application/       # 控制器/会话/命令/服务（逻辑）             【队友写+lead收口】
│   │   ├── infrastructure/    # 编解码/几何/缓存/平台适配                 【队友】
│   │   └── presentation/      # EditorPage 组件与小组件                  【队友写部件+lead集成】
│   └── notes/
│       ├── domain/ application/ infrastructure/ presentation/
├── shared/widgets/             # 不依赖 feature 的公共组件                 【队友】
└── l10n/
packages/
├── editor_core/                # 纯 Dart 几何与 V2 文档试点               【队友】
└── notebook_domain/            # 仓储、媒体、密钥 ports                    【队友】
```

---

## 3. 依赖约束（门禁强制）

| 区域 | 可依赖 | 不可依赖 |
|---|---|---|
| `app/` | 任意 feature、core、shared | 业务规则、存储细节 |
| `features/*/presentation` | 自身 application/domain、core、shared、中立契约 | 另一 feature 的 presentation/infrastructure |
| `features/*/application` | 自身 domain、core、抽象 ports | Widget、另一 feature UI |
| `features/*/infrastructure` | 自身 domain、core、平台/文件适配 | presentation（反向依赖走 port） |
| `features/*/domain` | 同领域 + 中立纯 Dart 模型 | `dart:io`、Widget、平台 plugin |
| `core/` | Flutter SDK、三方库、feature domain 实体 | feature application/infrastructure/presentation |
| `shared/` | Flutter SDK、core、三方库 | 任意 feature |

**硬校验**：`bash tools/check_boundaries.sh`（core/shared 违规返回非零）、`flutter test test/architecture_test.dart`（层方向/零循环/Feature 隔离/onion 方向）。架构测试必须 `Collector.buildGraph('.')`，不得改回 `../`。

---

## 4. 稳定契约（队友实现的依据）

队友实现的每个模块，都必须通过下列某一种契约交给页面/组合根，绝不直接操作页面私有状态或创建第二状态源。

- **跨 feature 中立契约**：`EditorPageBuilder`、`EditorPageSession`、`INotebookAccessor`。
- **主机窄契约（Host）**（协作者通过它取"最小协作能力"，不反向引用控制器）：
  - `DocumentObjectEditingHost` → 当前图层、笔画选区、可逆命令、缓存失效、通知
  - `LayerEditingHost` → 当前图层索引、图层快照命令、缓存注册/释放、局部/全量刷新、通知
  - `StrokeInputHost` → 当前工具配置、临时墨迹接收、持久笔画/识别形状提交、帧级重绘
  - `StrokeSelectionInteractionHost` → 帧级重绘与状态级通知区分
- `DocCommand` + `DocumentEditHistory`：命令/历史不依赖 `DrawingController`，经 `DocCommandContext` 请求图层恢复/脏标记/缓存刷新/形状恢复。
- **Presentation 只读计划与动作工厂**：`EditorOverlayItemPlan`（只读展示计划）、`EditorToolbarActionFactory`（纯动作映射）、`EditorTextPresentationStyle`（样式纯映射）。

**硬性要求**：
1. 纯计算/无副作用：不可变输入、确定性输出，不持有控制器/命令栈/缓存/UI/回调。
2. 不产生第二状态源：任何变更必须交由页面统一执行 `setState`/`onChanged`/历史提交。
3. 几何/命中/裁剪/缩放等计算不得 import `dart:io`、`ui.Image`、Widget、控制器、领域实例、存储。
4. 新增文件前核算目录预算（`drawing/application` 等受每目录文件上限约束；接近上限先合并同域或清死代码，不机械拆文件）。

---

## 5. 第一波（P0）框架契约与模块划分

> 评估报告识别的 P0 三项。每项 = lead 先定契约 → 队友写部件 → lead 集成。

### P0-1 异步过期保护（导入/资源加载）
- **lead 定的契约**：`ImportRequestToken`（generation/取消契约 + `mounted`/页面存活检查），统一收口连续导入、页面退出、导入中撤销/删除。
- **队友写**：`ImportGuard` 纯逻辑（token 递增、过期判断、取消登记）；`ImportLifecycleState` 纯状态（pending/active/cancelled/stale）。
- **lead 集成**：把 guard 接进页面导入时序、`onChanged`、自动保存与通知调度。

### P0-2 文字编辑会话显式状态机
- **lead 定的契约**：`TextEditSessionPhase`（idle → editing → committing/canceling → settled）+ 每阶段允许的输入/副作用表。
- **队友写**：`TextEditSessionStateMachine` 纯转移逻辑（提交/取消/失焦/重复提交判定）。
- **lead 集成**：接入页面文字编辑、焦点节点、overlay 生命周期与历史快照提交。

### P0-3 保存/自动保存/通知调度统一
- **lead 定的契约**：`SaveScheduler`（防抖 + 退出兜底 + 失败重试 + 串行化）。
- **队友写**：`SaveScheduleDecision` 纯调度判定（是否应保存/何种方式/是否合并）；`SaveFailurePolicy` 纯失败策略。
- **lead 集成**：接页面保存、通知、生命周期；写保存序列/失败重试/页面销毁测试。

---

## 6. 验收与流程

1. 每个"小部件"必须带单测（纯输入→断言输出），测试归属 `test/features/<feature>/<layer>/`。
2. 每项开发走 `feature branch → PR → 远程门禁（analyze/测试/架构/边界/行数/秘密/双端构建）`，不直接推 master。
3. 只允许 lead 收口（把部件写入页面/组合根）并对该 PR 负责 review。
4. 合并前必须跑：`dart analyze`、`flutter test --concurrency=1`、`bash tools/check_boundaries.sh`、行数门禁。
