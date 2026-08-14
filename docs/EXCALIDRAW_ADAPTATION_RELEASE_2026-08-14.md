# Excalidraw 深度学习与 Flutter 原生化适配发布说明

**版本：2026-08-14 Excalidraw Adaptation Build**  
**源码审阅基线：** Excalidraw commit `abeeaeba217ab3b5193b78c8d8d63c373b518ced`。  
**重点：** 学习并原生化实现 Excalidraw 的动作、快捷键、命令面板与可用性管理模式，同时保留本应用既有的 Apple 风格局部玻璃控制层。

## 合规处理

Excalidraw 根目录许可证为 MIT，允许复制、修改和再分发，但要求在副本或实质性部分保留版权与许可证文本。[1] 本次实现没有复制 TypeScript/React 源码、Excalidraw 图标、字体、品牌或视觉资产；而是根据其公开的 Action、ActionManager、Scene 与 CommandPalette 架构，使用 Dart/Flutter 独立重写了命令层。因而本轮无须在 Flutter 运行时代码中嵌入 Excalidraw 源码片段；参考与决策记录保存在 `EXCALIDRAW_SOURCE_STUDY_2026-08-14.md`。

| Excalidraw 源码机制 | 本项目原生化实现 | 用户获得的实际体验 |
| --- | --- | --- |
| `Action`：动作声明包含名称、关键词、快捷键、谓词和执行器 | `EditorCommand` 现在包含分类、关键词、快捷键、`isAvailable` 和 `run` | 同一功能不再由多个界面入口各自写逻辑；状态变化后动作可用性一致 |
| `ActionManager`：统一键盘、UI、API 与命令面板执行路径 | `CommandRegistry` 执行并返回是否真正处理；顶栏、快捷键和命令面板以命令 ID 为核心 | 不可用操作不会误消费按键或假装执行；撤销/重做状态保持一致 |
| Action `predicate`：按选区、视图模式等上下文筛选 | 复制、复制副本、删除、文本格式和对齐均声明实时 `isAvailable` | 无选中对象时，命令面板不会展示删除/复制；未选中文本时不会展示文本格式命令 |
| `CommandPalette`：按分类、关键词、可用性和最近使用组织 | 命令面板直接消费注册表，按编辑/格式/视图/导出分组，支持中文/英文关键词、回车执行和最近命令 | 用户能快速完成真实存在的操作，而不是面对含无效入口的长菜单 |
| 快捷键冲突保护 | 重写快捷键分发为 `CommandRegistry.run()`，并修复原有 Ctrl/Cmd+V 的重复分支 | Ctrl/Cmd+V 统一走系统剪贴板粘贴；Ctrl/Cmd+Shift+V 只在有选区时粘贴样式 |
| 多快捷键入口 | Ctrl/Cmd+K 和 Ctrl/Cmd+Shift+P 均打开命令面板 | 对齐主流创作软件和 Excalidraw 的键盘优先效率 |

## 本轮新增与修复的真实功能

| 功能 | 入口 | 可用性与结果 |
| --- | --- | --- |
| 命令面板搜索 | Ctrl/Cmd+K；Ctrl/Cmd+Shift+P | 搜索名称、分类和关键词；回车执行第一条可用命令；Esc 关闭系统对话框 |
| 最近命令 | 命令面板空查询时 | 最近一次成功执行的命令显示在顶部；不可用时自动隐藏 |
| 选择性编辑 | Ctrl/Cmd+C、Ctrl/Cmd+D、Delete | 仅在存在单选或多选对象时处理，否则按键不被错误拦截 |
| 文本格式 | Ctrl/Cmd+B、I、U、E；Ctrl/Cmd+Shift+X | 仅在选中文本项时执行；无文本选区时不会产生无意义状态变化 |
| 样式复制 | Ctrl/Cmd+Shift+C / V | 仅在对象选中时处理，避免空状态错误 |
| 视图与导出 | 命令面板 | 网格、网格吸附、适应画布以及 PNG/PDF/SVG 导出均只有真实执行器才会出现 |

## 验证结果

| 检查项目 | 结果 |
| --- | --- |
| 静态分析 | `dart analyze` 通过，零问题 |
| 自动化测试 | `flutter test` 通过，**133** 项全部成功 |
| 行覆盖率 | **85.4%（1404/1644）** |
| 新增测试 | `command_registry_test.dart` 验证可用性过滤、关键词搜索、执行结果和稳定覆盖注册 |
| 既有绘图/笔记/玻璃工作区回归 | 已包含在全量测试中，无回归 |

## 后续适配路线

下一阶段优先考虑 Excalidraw `Scene` 的**有序对象数组 + ID 索引 + 可失效选择缓存**。这必须先为当前的文字、图片、形状、图表和连接线建立统一对象适配层，且要保持已有 JSON 保存的后向兼容。完成后再考虑对象对齐、分布、群组和层级命令的一次性历史记录；不应在索引和历史模型未建立前添加外观相似但无法恢复的“高级对象编辑”按钮。

## References

[1] [Excalidraw MIT License](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/LICENSE)  
[2] [Excalidraw ActionManager](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/excalidraw/actions/manager.tsx)  
[3] [Excalidraw Action type](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/excalidraw/actions/types.ts)  
[4] [Excalidraw Command Palette](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/excalidraw/components/CommandPalette/CommandPalette.tsx)  
[5] [Excalidraw Scene](https://github.com/excalidraw/excalidraw/blob/abeeaeba217ab3b5193b78c8d8d63c373b518ced/packages/element/src/Scene.ts)
