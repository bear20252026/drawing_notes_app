# Feature 隔离与 Onion 方向门禁治理说明

**日期：2026-08-27**  
**适用分支：`refactor/strict-dependency-boundaries`**

## 审计结论

当前 `test/architecture_test.dart` 中尚有两处 `freeze`：`feature_isolation` 与 `onion_direction`。它们记录的是早期架构状态，而非当前源代码的实时结论。

本轮对 `lib/features/drawing/` 和 `lib/features/notes/` 执行完整导入检索：未发现 drawing 直接导入 notes 的 `infrastructure` 或 `presentation`，也未发现 notes 直接导入 drawing 的 `infrastructure` 或 `presentation`。`tools/check_boundaries.sh` 的白名单说明仍保留过去的迁移背景，但当前执行结果已是“drawing 无 notes 横向依赖”。

对 `features/*/application` 的导入审计也未发现应用层直接导入 feature 内 `infrastructure` 的路径。原有 onion 冻结说明所列的渲染、识别和导出协作已移动到 `core/rendering` 或由现有协作者契约隔离；它们不再属于该测试所定义的 feature 分层违规。

| 规则 | 旧状态 | 当前审计结论 | 本批治理 |
|---|---|---|---|
| feature 隔离 | `freeze('feature_isolation', ...)` | 不存在 feature 间非 domain 直接导入 | 恢复严格 `shouldNotDependOn` 断言 |
| onion 方向 | `freeze('onion_direction', ...)` | 不存在 application → feature infrastructure 直接导入 | 恢复严格 `enforceOnionRules` 断言 |
| 零循环 | 已在 PR #28 移除冻结 | 严格检查已通过 | 不在本批重复改动 |

## 设计边界

本批只升级**已符合的依赖方向**为严格自动化门禁，并清除过期测试注释与迁移背景；不重写控制器、导出器、渲染器、导航、存储或业务功能。架构测试继续允许 feature 间共享最内层 domain 实体，但严格禁止跨 feature 的 `application`、`infrastructure` 与 `presentation` 直接导入。

## 不变量

1. 不修改绘图、笔记本、导出、演示、搜索、存储或导航的用户可见行为。
2. 不改变 `core/notes_accessor.dart` 的既有跨 feature 只读契约；该契约仍是允许业务集成的组合边界。
3. `core/` 与 `shared/` 对 feature 非 domain 层的禁止规则保持不变。
4. 除本批解除的 `feature_isolation` 与 `onion_direction` 外，不扩大或删除任何其他冻结基线。
5. 严格断言必须通过 architecture 测试、全量 Flutter 测试、分析、边界脚本和远程门禁。

## 验收标准

| 验收项 | 预期结果 |
|---|---|
| feature 隔离 | 不使用 `freeze('feature_isolation', ...)`，四个 `shouldNotDependOn` 直接通过 |
| onion 方向 | 不使用 `freeze('onion_direction', ...)`，`enforceOnionRules` 直接通过 |
| 行为回归 | 现有导出、导航、存储、编辑器和架构测试通过 |
| 质量门禁 | 全量串行 Flutter 测试、分析、边界检查、差异检查和远程 14 项检查通过 |
