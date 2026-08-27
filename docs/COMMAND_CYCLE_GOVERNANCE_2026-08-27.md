# 命令恢复契约与零循环门禁治理说明

**日期：2026-08-27**  
**适用分支：`refactor/command-cycle-governance`**

## 背景

此前架构测试的“零循环依赖”规则使用 `freeze('zero_cycles', ...)` 包装，并在注释中将 `document_commands ↔ drawing_controller` 记录为历史双向协作。当前主干审计显示，该描述已经过期：`document_commands.dart` 只依赖 `DocCommandContext`，而 `doc_command_context.dart` 只依赖绘图领域类型；`DrawingController` 实现该窄接口并在控制器侧依赖命令类型。命令层不再导入控制器，因此没有实际静态导入环。

| 组件 | 允许依赖 | 不允许依赖 | 当前角色 |
|---|---|---|---|
| `document_commands.dart` | 绘图领域类型、`DocCommandContext` | `DrawingController`、Widget、存储、渲染缓存 | 定义可逆命令和独立快照值 |
| `doc_command_context.dart` | 绘图领域类型 | `DrawingController`、命令实现、UI、基础设施 | 定义命令执行时所需的最小恢复宿主契约 |
| `drawing_controller.dart` | 命令、上下文、会话、缓存协调器 | 不适用 | 实现恢复、副作用、缓存失效和通知协调 |
| `DocumentEditHistory` | `DocCommand` | 控制器、UI、存储 | 持有命令栈并调度 `undo` / `redo` |

## 本批目标

本批不重写命令行为。目标是把已经事实成立的“命令依赖窄上下文而非控制器”提升为**严格且持续执行的架构门禁**：移除过期的零循环冻结包装，使任何未来 `lib/` 导入环都会直接导致 CI 失败。

同时，更新架构说明和上一轮结构评估报告，避免将已消除的依赖环继续误列为现存 P0 风险。报告中的后续治理重心相应调整为仍被冻结的 feature 横向依赖与 onion 方向基线。

## 必须保持的不变量

1. `DocCommand` 的 `undo`、`redo` 方法签名及各命令的快照、引用和恢复行为不变。
2. `DrawingController` 仍是 `DocCommandContext` 的实现者，继续拥有文档脏标记、缓存刷新、选择修正和 UI 通知时序。
3. `DocumentEditHistory` 仍只调度命令，不获得控制器、Widget 或存储依赖。
4. 严格零循环检查覆盖 `features/`、`core/` 和 `shared/`，不因本批再使用 `freeze` 放宽。
5. 本批不修改用户可见撤销/重做行为、历史格式、文档 JSON 或持久化流程。

## 验收标准

| 验收项 | 预期 |
|---|---|
| 命令—控制器依赖 | `document_commands.dart` 与 `doc_command_context.dart` 不导入 `drawing_controller.dart` |
| 循环架构测试 | 不使用 `freeze('zero_cycles', ...)`，且 `shouldBeFreeOfCycles` 直接通过 |
| 回归 | 命令上下文、编辑历史、控制器撤销重做和对象编辑测试通过 |
| 全量门禁 | 串行 Flutter 全量测试、分析、边界检查、差异检查和远程 14 项检查通过 |
