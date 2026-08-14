# Saber 源码研读笔记：手写引擎与文档内核

**审阅基线：** Saber `f534abb3a29ad9fa15d7bb83a5b69593477cda6c`（main，2026-08-14 读取）。

## 许可证结论

Saber 主仓库为 **GNU GPL v3**，而非 MIT/Apache 类宽松许可证。其 GPLv3 文本要求：对受覆盖程序的修改版本进行传播时，整体作品需以 GPLv3 发布并提供相应源代码；因此，现有 `drawing_notes_app` 若保持闭源或采用非 GPL 发行策略，**不得复制、粘贴或链接 Saber 的 GPL 代码**。可以合法学习其公开的功能设计、数据模型理念和算法思路，并在不复制表达性代码的前提下独立实现；任何实际源码复用都必须先决定将整体项目转为 GPLv3，并完成版权、许可证、修改声明与相应源代码义务。[1]

## 已确认的手写与画布架构

| Saber 源码位置 | 机制 | 对产品体验的价值 | 建议迁移方式 |
| --- | --- | --- | --- |
| `lib/components/canvas/_stroke.dart` | 笔画保留采样点、压力、工具类型、画笔参数和页面上下文；低/高质量多边形与路径按需缓存 | 书写中降低计算量，收笔后高质量稳定显示 | 独立重写 `StrokeGeometryCache`；现有项目可保留其压力输入模块 |
| `_stroke.dart` | 实时 `low` 每 4 点采样、平滑/流线关闭；完成后 `high` 全点重建，随后压缩近点 | 兼顾低延迟、平滑外观、文件体积和重绘性能 | 优先实现为现有 `StrokeRenderer` 的双质量渲染策略 |
| `_stroke.dart` | 真压感到来时自动停止模拟压感；无真压感时仅按工具策略模拟 | 不把鼠标速度效果伪装为硬件压感 | 与现有 `StylusInputProcessor` 合并为明确的输入来源状态 |
| `canvas_gesture_detector.dart` | 仅对 stylus/invertedStylus 使用 `pressureMin/pressureMax` 归一化；处理悬停、侧键、倒置笔和触控笔出现后关闭手指书写 | 处理真实 Windows/Android 触控笔的主要误触与设备差异 | 独立重写“输入仲裁器”，并作为下一轮真机压感优化 P1 |
| `interactive_canvas.dart` | 基于 Flutter `InteractiveViewer` 的改造版，显式区分画笔手势和移动/缩放手势，支持双指缩放、惯性、边界与滚轮缩放 | 画画不会误触平移；桌面触控板/鼠标与触控输入具有一致行为 | 从现有 Viewport 组件独立提炼 API；不要复制 GPL 代码 |
| `_canvas_painter.dart` | 先按颜色分层绘制高亮笔：`saveLayer` + `BlendMode.darken/lighten`，再绘制普通笔画 | 同色高亮反复划过不变深；普通笔画位于高亮笔之上，文本更清晰 | 以 Flutter `Canvas.saveLayer` 独立实现；这是高价值 P1 功能 |
| `editor_history.dart` | 有界过去/未来栈（100 项）、保存点指针、重做延迟清除、误触笔画可撤回 | 自动保存不会与撤销状态混乱，缩放手势误判可无痕取消 | 扩展现有历史模型为“操作命令 + 保存点”，不要复制数据结构代码 |
| `editor_core_info.dart` | 版本化 BSON 文档、分离图片资产、SBA ZIP 归档、旧格式迁移、超过 2MB 时转 isolate 解析 | 大笔记加载不阻塞 UI，长期格式兼容可控，图片不污染主文档 | 仅在现有 JSON 模型稳定后引入独立的版本头、资源清单和后台解码策略 |

## 可验证的优先功能

1. **分层高亮笔**：不依赖服务器和新文件格式，用户可以立即验证“不叠色、普通内容保持清晰”。
2. **触控笔输入仲裁**：压力归一化、手指书写自动策略、悬停反馈、侧键状态，需要 Android/Windows 真机验收。
3. **双质量笔画渲染**：开始书写使用低成本路径，收笔后后台升级并压缩笔画点。
4. **文档格式演进**：版本号、迁移器、异步大文件载入和独立资源清单，属于可靠性基础工程。

## References

[1] [Saber LICENSE.md — GNU GPL v3](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/LICENSE.md)  
[2] [Saber Stroke model](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/components/canvas/_stroke.dart)  
[3] [Saber Canvas painter](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/components/canvas/_canvas_painter.dart)  
[4] [Saber canvas gesture detector](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/components/canvas/canvas_gesture_detector.dart)  
[5] [Saber editor history](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/data/editor/editor_history.dart)  
[6] [Saber document core](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/data/editor/editor_core_info.dart)

## 跨平台输入、资料工作流、同步与导出

| Saber 源码位置 | 机制 | 对产品体验的价值 | 建议迁移方式 |
| --- | --- | --- | --- |
| `pages/editor/editor.dart` | 绘制前基于指针数量、当前工具、触控笔类型、压力与“是否允许手指书写”进行仲裁；从单指写字切换双指缩放时移除意外笔画 | 避免双指缩放留下误笔画；手指、笔、橡皮、选择和激光笔状态可解释 | 独立设计 `InputArbiter`，和现有手型/框选/触控笔模块协同，不复制代码 |
| `data/file_manager/file_manager.dart` | 跨平台虚拟文件根目录、文件系统监听、路径合法性校验、原子工作流、最近访问记录和文件变更广播 | 文件夹层级、外部改动、同步和主页刷新不各自维护状态 | 将现有 NotebookStorage 收敛为“文件存储网关 + 变更流” |
| `pages/home/browse.dart` | 由目录变更流驱动笔记库刷新；响应式网格、路径面包屑、多选后的重命名/移动/删除/导出命令条 | 创建、寻找、整理和导出的工作流闭环，而非单纯列表展示 | 继续增强现有首页；优先增加文件夹级管理与批量操作的真实持久化 |
| `components/home/new_note_button.dart` | 新建、导入自有格式和导入 PDF 共用一个明确入口；PDF 先检查平台栅格化能力 | 用户知道每种新建/导入行为的边界，不会点击无结果的图标 | 把现有模板、PDF 导入和白板入口收敛成“新建”工作流并增加能力预检 |
| `data/file_manager/file_manager.dart` | 移动端图片保存到相册、其他文件走系统分享；桌面使用另存为对话框；随 Android API 级别请求对应权限 | 导出不是“生成文件”即结束，而是按平台完成交付动作 | 当前导出功能补齐平台交付层与权限失败提示 |
| `data/editor/editor_exporter.dart` | PDF 使用“高亮笔/铅笔光栅底图 + 其他笔画矢量前景”的混合导出；导出前预载图像并用稳定浅色主题截屏；CPU 并行数限为 1–4 | 兼顾视觉真实度、PDF 放大清晰度、设备资源和深浅色主题一致性 | 作为导出子系统 P1：先建立导出快照与资源预载，再做混合输出 |
| `data/nextcloud/saber_syncer.dart` | 对文件内容与远端路径加密；本地/远端基于修改时间比较；删除标记、防重复删除、预览优先；加解密转到 worker isolate | 服务器不可读，网络慢时不阻塞编辑，笔记库预览及时更新 | 仅在先完成可靠本地存储、冲突策略和密钥生命周期设计后建设；不能把“加密同步”当作单个 UI 开关 |

## Saber 的工作流级成熟点

Saber 的优势不只来自笔刷。编辑器将输入仲裁、当前工具、历史项、延迟自动保存、缩略图、PDF/图片导入和多格式导出串成一个可追踪的状态机。主页则以本地文件系统作为可观察的数据源，并让新建、导入、整理和同步都落到相同的文件变更流中。其 PDF 导出策略也体现出产品级取舍：对于透明高亮和着色铅笔，不错误地声称可纯矢量导出，而是使用一致主题的光栅底图，再将普通笔画保持为矢量。

## References（补充）

[7] [Saber editor input and tool state machine](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/pages/editor/editor.dart)  
[8] [Saber file manager](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/data/file_manager/file_manager.dart)  
[9] [Saber Browse page](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/pages/home/browse.dart)  
[10] [Saber new note and import workflow](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/components/home/new_note_button.dart)  
[11] [Saber editor exporter](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/data/editor/editor_exporter.dart)  
[12] [Saber Nextcloud syncer](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/lib/data/nextcloud/saber_syncer.dart)

## 官方路线图补充：全量能力范围

Saber 的官方 README 将其定位为跨平台手写笔记应用，并明确说明：笔记深色反转、图片/PDF 随主题反转、双密码保护、无重叠变深且不遮挡文字的高亮笔、无限嵌套文件夹和主页最近笔记。[13] 官方功能进度讨论还列出了其已完成或长期范围：动态主题/深色模式、画布书写、撤销重做、缩放、擦除、颜色、离线保存、笔记重命名、真实主页/文件树/画布预览、多页、手指与触控笔区分、工具切换、编辑器快捷键、高亮笔、Nextcloud 登录与同步、擦除也可撤销、双密码、PDF 导出、多语言、纸张背景、图片、笔刷大小和颜色、笔刷类型及平滑、文本笔记、选择移动、形状、文件夹内移动、PDF 背景导入、Android 本地文件夹同步、部分笔画擦除、页面重排/复制/删除和 PNG 导出。[14]

这份路线图不应被解读为“所有项目永远都会完成”的产品承诺；它是本项目建立功能等效矩阵时的范围来源。针对每一项能力，我们会区分：现有应用已经真实实现、需要独立重写、需依赖 Android/Windows 原生能力、以及需要服务端/密钥/隐私设计才能开放的项目。

[13] [Saber README](https://github.com/saber-notes/saber/blob/f534abb3a29ad9fa15d7bb83a5b69593477cda6c/README.md)  
[14] [Saber official roadmap](https://github.com/saber-notes/saber/discussions/1)
