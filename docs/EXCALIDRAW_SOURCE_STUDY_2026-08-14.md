# Excalidraw 源码深度研读：合规复用与 Flutter 适配

**审阅基线：** Excalidraw GitHub 仓库当前浅克隆提交 `abeeaeba217ab3b5193b78c8d8d63c373b518ced`。  
**许可证：** 根目录 `LICENSE` 为 MIT License，版权声明为 `Copyright (c) 2020 Excalidraw`。MIT 允许复制、修改、合并、发布、分发、再许可和销售，但在软件副本或实质性部分中必须保留版权与许可声明。[1]

> **本项目策略：** Flutter 与 TypeScript/React 的运行时和架构不同，因此默认采用“逻辑学习 + Flutter 原生重写”。只有确有必要移植的小型、独立的 MIT 代码片段才会保留原始版权和 MIT 许可文本，并在源文件和第三方声明中标注来源；不复制 Excalidraw 的品牌、图标、字体、视觉资产或大段 UI。

## 1. Excalidraw 的核心分层

| 层级 | Excalidraw 模块 | 作用 | Flutter 适配结论 |
| --- | --- | --- | --- |
| 场景内核 | `packages/element/src/Scene.ts` | 维护有序元素数组、包含删除项的 ID 映射、非删除元素映射、帧缓存、选区缓存和场景失效 nonce | 当前项目应在 `DrawingController` 之外建立轻量对象场景索引；对象读取避免重复线性扫描 |
| 元素动作 | `packages/excalidraw/actions/*` 与 `actions/manager.tsx` | 将工具栏、菜单、快捷键、上下文菜单、API 和命令面板统一进入 `Action.perform()` | Flutter 应建立统一 `EditorCommand` 注册表，禁止每个入口各自写状态变更 |
| 快捷键 | `actions/manager.tsx`、`actions/shortcuts.ts` | 按优先级匹配；多命令冲突时取消执行；处理前置条件、只读与视图模式 | Flutter 快捷键应先匹配唯一命令，再由 `isAvailable` 判断；文本输入时不截获字符快捷键 |
| 命令面板 | `components/CommandPalette/CommandPalette.tsx` | 命令分类、关键词检索、模糊匹配、最近使用、可用性过滤、键盘上下导航和快捷键提示 | Flutter 应从统一命令注册表生成命令面板；仅展示当前状态可执行命令，保留最近执行命令 |
| 对齐动作 | `actions/actionAlign.tsx` | 选区必须有多个可对齐对象；计算后单次提交；UI 可见性、快捷键和动作谓词共用条件 | 当前对齐入口应明确禁用原因；对齐算法与按钮/菜单/快捷键入口共享同一命令 |
| UI 模式 | `Action` 的 `predicate`、`viewMode`、`navigation` 字段 | 同一个命令声明可用条件、只读支持和导航能力，而非散落在各视图 | Flutter 命令应显式包含 `availability`、`requiresEditable` 与 `recordHistory` |

## 2. 已读取源码中的关键实现细节

### `ActionManager`：一个动作，多种入口

`ActionManager` 将 Action 注册到名称映射；键盘处理会按 `keyPriority` 排序、收集命中项，并在**命中数不为一**时拒绝执行以避免快捷键歧义。它还在执行前检查编辑器交互能力、视图模式和视口过渡锁。键盘、UI、API 与命令面板最终都调用同一 `perform(elements, appState, value, app)`，再统一交由 updater 提交结果。[2]

Flutter 对应实现应把以下字段作为命令数据，而不是写进单个 `onPressed`：标识、名称、关键词、快捷键、可用性谓词、执行器、历史策略和来源。这样可保证未来工具栏、更多菜单、浮动面板和快捷键不会产生行为差异。

### `Scene`：有序数组加 ID 映射，而非单一列表

`Scene` 同时维护完整有序元素、完整 `id → element` 映射、非删除元素及映射、帧集合和选区缓存。`replaceAllElements` 是唯一的全量替换路径，负责同步索引并触发更新；`mapElements` 只有在实际元素引用变化时才替换数组，避免无变化重绘；`getSelectedElements` 将同一选区与选项组合缓存起来。[3]

Flutter 对应改造可先实现独立 `EditorObjectIndex`：保留对象原有顺序，维护 ID 映射，并由文档变更版本号使缓存失效。它不应改变现有笔画数据的保存兼容性；应先支持形状、图片、文字、图表与连接线等现有对象。

### `CommandPalette`：命令不是菜单的副本

Excalidraw 命令面板会从 Action 自动构建命令项，并加入工具、导出、搜索、库等附加命令。每个命令包含分类、关键词、快捷键、可用谓词和执行器；打开后用模糊匹配在命令名称和关键词中搜索，保留最近使用项，并支持方向键、回车和 Esc。执行时先关闭面板并暂时禁用动画，再触发命令，避免转场与画布动作同时出现。[4]

Flutter 对应命令面板应控制在高频的现有操作范围：撤销/重做、复制/粘贴、删除、选择、图层顺序、对齐、导出、插入文本/形状、全屏、显示/隐藏面板和缩放。未实现的图标或命令不得加入。

## 3. 立即可适配的优先级

| 优先级 | Flutter 原生化改造 | 来自 Excalidraw 的学习点 | 验收标准 |
| --- | --- | --- | --- |
| P0 | 统一 `EditorCommand` 注册表与快捷键调度 | Action + ActionManager | 每个高频命令的工具栏、菜单、快捷键行为一致；冲突不误执行 |
| P0 | 当前状态可用性谓词 | Action `predicate`、`viewMode` | 无选区时禁用对齐/删除对象；只读时禁用编辑命令 |
| P1 | 可搜索命令面板与最近命令 | CommandPalette | Ctrl/Cmd+Shift+P 或 Ctrl/Cmd+/ 打开；键盘可完成搜索、选择、执行与关闭 |
| P1 | 对象索引与选区缓存 | Scene | 读取对象不再反复扫描；变更后映射和缓存正确失效 |
| P1 | 对齐和层级动作原子化 | actionAlign / actionZindex | 一次操作只产生一个撤销记录，不影响未选对象 |
| P2 | 复杂绑定、帧、多人协作 | element binding / frame / collab | 需重构数据模型与存储后再评估；不在本轮伪实现 |

## References

[1] [Excalidraw LICENSE at reviewed commit](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/LICENSE)  
[2] [Excalidraw ActionManager](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/excalidraw/actions/manager.tsx)  
[3] [Excalidraw Scene](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/element/src/Scene.ts)  
[4] [Excalidraw Command Palette](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/excalidraw/components/CommandPalette/CommandPalette.tsx)  
[5] [Excalidraw alignment actions](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/excalidraw/actions/actionAlign.tsx)
