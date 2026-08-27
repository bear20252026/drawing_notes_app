# 编辑器工具栏动作装配重构

**作者：Manus AI**  
**日期：2026-08-27**  
**目标分支：`refactor/editor-toolbar-action-assembly`**

## 1. 改造背景

`EditorContextBar` 通过 `EditorToolbarActions` 接收 40 个用户操作回调。此前，`_buildContextBar` 的 `ListenableBuilder` 在构造 Widget 的同时内联装配所有闭包；该段代码还包含选择对象空值处理、状态写入、文档通知、偏好存储、工具互斥和缩放导航的业务时序。页面状态、控件结构和动作装配因此混在同一渲染闭包中，难以独立审阅，也无法在不创建 Widget 的前提下验证动作字段是否正确透传。

> 本批次将“把命名页面委托映射为既有 `EditorToolbarActions`”定义为无状态展示层装配职责。工厂不拥有状态、不调用回调、不读取控制器；页面仍保留业务闭包、状态周期、控制器同步、通知和 I/O。

| 当前问题 | 根因 | 改造方式 |
|---|---|---|
| 上下文栏构建器同时含 40 个动作闭包 | 展示结构与动作装配未分层 | `_buildContextBar` 仅消费 `_buildToolbarActions()` |
| 动作组合没有显式语义分组 | 单一巨型构造器掩盖工具域边界 | 以笔刷、对象、形状、视口四组命名委托装配 |
| 不能独立测试字段映射 | 映射逻辑嵌入 `State` 和 Widget builder | 新增纯 Dart 工厂直接测试 |
| 迁移易误接同签名回调 | 大量 `VoidCallback`/`ValueChanged` 并列 | 工厂的具名分组构造器提供编译期字段约束 |

## 2. 目标边界

| 类型 | 责任 | 禁止持有或执行 |
|---|---|---|
| `EditorToolbarBrushActions` | 选择笔刷/橡皮、橡皮设置、临时标记、笔刷尺寸和预设 | 控制器、Widget、状态、持久化 |
| `EditorToolbarObjectActions` | 取色、选择、文字、图片、纸张、链接、文字样式与删除命令 | 控制器、Widget、状态、通知 |
| `EditorToolbarShapeActions` | 形状、填充、对齐/分布、描边、透明度、重排和框选命令 | 控制器、Widget、状态、通知 |
| `EditorToolbarViewportActions` | 网格、吸附、适应画布与缩放命令 | 控制器、Widget、状态、通知 |
| `EditorToolbarActionFactory` | 把四组委托无副作用地映射为既有 `EditorToolbarActions` | 执行任何动作或保存业务状态 |
| `_EditorPageToolbarActions` | 以原有顺序/时序创建真实页面委托 | 改变 `EditorToolbarActions` UI 契约 |
| `_buildContextBar` | 监听控制器、映射显示状态、构建 `EditorContextBar` | 内联业务回调实现 |

## 3. 行为不变量

本批次保持 `EditorToolbarActions` 的公开字段、控件消费点和启用条件不变。各页面闭包的操作顺序保持不变，包括：形状或文字变化必须在同一 `_applyState` 周期中写入并通知；橡皮模式写入后仍异步保存偏好；工具选择继续经既有 `_select*` 方法完成互斥；纸张循环仍执行 `tickFrame` 再通知；缩放、适应画布、图片插入、文字编辑、删除和导航仍直接调用原页面方法。

工厂只做引用透传，不包装或延迟回调，也不捕获 `BuildContext`、`DrawingController`、`EditorViewModel` 或会话对象，因此不会引入第二状态源、额外刷新、额外持久化或生命周期风险。

## 4. 验收标准

| 标准 | 验证方式 |
|---|---|
| 四组动作字段逐一映射到原 `EditorToolbarActions` | 工厂直接测试，以可识别回调验证引用与参数透传 |
| 调用工厂本身不执行任何动作 | 直接测试中的调用计数保持零 |
| 工厂输出的动作调用仅触发对应委托一次 | 直接测试覆盖无参数、布尔、数值、字符串、枚举和整数回调 |
| 上下文栏的状态映射与控件构建不变化 | 现有 Widget/回归测试与全量测试 |
| 没有新增领域、应用或 I/O 依赖 | 静态分析、架构边界和源码审阅 |
| 单一文件与目录预算保持合规 | 行数守卫与远程门禁 |

## 5. 非目标

本批次不修改工具栏控件布局、按钮文案、快捷键、`EditorToolbarState`、动作业务实现或存储格式。不会将页面回调进一步下沉到 domain/application，也不会合并不同操作的通知时序。未来若要将可重复的对象编辑命令收口为应用层服务，应在独立 PR 中先设计事务、撤销与通知契约。
