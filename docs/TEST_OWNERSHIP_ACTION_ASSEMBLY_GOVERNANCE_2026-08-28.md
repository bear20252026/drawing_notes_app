# 测试所有权与编辑器动作装配治理

**作者：Manus AI**
**日期：2026-08-28**
**基线：`master@d263c75`（PR #35 合并提交）**

## 目标

本专项将与 `drawing` presentation 直接对应的测试从 `test/` 根目录渐进归属到 `test/features/drawing/presentation/`，使测试位置表达生产代码所有权，降低编辑器展示改造时的定位成本。迁移只改变路径，不改变测试名称、断言、夹具、执行顺序或 Flutter 的递归发现行为。

同时审计 `EditorToolbarActionFactory` 的动作装配。现有工厂已是无状态的窄契约：四组命名动作对象作为输入，输出既有 `EditorToolbarActions`，只透传回调引用，不读取页面、控制器或 `BuildContext`，也不执行动作。因此本轮不重复拆分工厂，不引入第二动作接口，而是在页面组合根增加 `_mutateSelectedText` 与 `_mutateSelectedShape` 两个窄执行契约，将选中解析、`setState` 和 `_notifyChanged` 的时序集中管理。

## 迁移范围

前批迁移直接属于编辑器 presentation 的测试：编辑器默认构建、画布交互、输入仲裁、overlay 计划/分组、选区变换、工具模式、形状缩放、图片裁剪、文字展示样式、缩放手柄和工具栏动作工厂测试。本批补齐绘图阅读展示及 notes 页面编辑会话测试，分别归属 `drawing/presentation` 和 `notes/application`。必须保持 notes 领域模型测试、存储/安全测试、`phase1` 至 `phase7` 综合回归、drawing/notes 跨域测试和历史兼容测试在根目录。这样可以推进所有权，而不是只为路径整洁进行无收益的大搬家。

## 不变量

Flutter 测试运行器继续递归发现 `test/**/*.dart`；所有测试的 URI、测试名称和断言保持不变。动作工厂的每一项回调必须按照既有字段映射传递一次，不得提前执行、包装为延迟副作用、改变参数类型或修改动作对象 API。文字与形状共享执行契约只接受领域对象字段变更闭包；无选中对象时必须无副作用，有选中对象时必须保持一次状态写回和一次变更通知。页面仍拥有回调真正触发时的状态写回、通知、偏好保存和持久化时序。

| 边界 | 允许 | 禁止 |
|---|---|---|
| 测试目录 | 按生产 feature/layer 迁移当前直接归属测试 | 只为减少根目录文件数而迁移跨域测试 |
| 动作工厂/页面执行契约 | 增加映射完整性回归；用窄闭包统一文字/形状字段变更和通知时序 | 修改回调时序、增加控制器依赖、创建第二动作模型或下沉 Widget 生命周期 |
| CI 发现 | 依赖 Flutter 对 `test/` 的递归发现 | 修改 CI 过滤器、隐藏旧路径或复制测试文件 |
| 生产代码 | 保持现有 `EditorToolbarActionFactory` 实现 | 为测试迁移而改写业务动作和页面状态 |

## 验收标准

迁移后 `find test/features/drawing/presentation -name '*.dart'` 能完整列出编辑器测试；notes presentation 的后续迁移也应使用 `test/features/notes/presentation/`，根目录不保留重复所有权入口。`flutter test --concurrency=1` 仍完整执行全部测试。动作工厂测试应覆盖四组输入对象中所有 `EditorToolbarActions` 输出字段，并通过计数回调验证工厂只保存引用、不提前调用任何回调。
