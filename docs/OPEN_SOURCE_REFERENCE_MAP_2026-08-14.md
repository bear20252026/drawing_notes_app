# 开源参考项目：能力与迁移边界

本文件记录用户提供的参考方向在本 Flutter 绘图笔记应用中的**合法借鉴方式**。原则是学习交互范式、信息架构和独立实现思路；不复制项目源码、资源、商标、专有设计资产或受许可证约束的实现细节。

| 参考项目 | 已核实的成熟能力 | 对本项目的可迁移方向 | 本轮不应直接复制的内容 |
| --- | --- | --- | --- |
| Krita | 多类笔刷、图层、辅助工具、稳定器、资源包、模板和插件生态 | 笔刷预设应有明确用途；稳定器、笔压、图层与模板以可验证闭环逐项实现 | GPL 源码、笔刷资源包、商标与具体 UI 资产 |
| Inkscape | SVG 为核心的矢量图形、形状、路径、文本、变换、分组、图层和多格式导出 | 形状/文字/连接线应统一为对象层；未来以独立实现的 SVG 导出与对象分组为重点 | GPL 源码、GTK 界面、图标和具体路径编辑实现 |
| Joplin | 多媒体笔记、附件、搜索、同步、加密、插件和跨平台数据访问 | PDF/音频等附件进入可搜索、可保存、可导出的统一资料模型；同步先明确后端与冲突策略 | Joplin 源码、品牌与其服务实现 |
| TriliumNext | 深层级笔记树、克隆、版本、快速导航、搜索、属性、加密、画布和关系图 | 当前收藏/最近/版本历史继续扩展为可靠知识组织；克隆和页面关系保持真实数据语义 | AGPL 源码、前端组件、Excalidraw 集成代码和服务端实现 |
| Photopea | 面向专业编辑任务的多格式导入/导出体验 | 只学习非破坏性工作流、清晰的格式提示和失败反馈 | Photopea 并非完全开源，不纳入代码借鉴或复制范围 |

## 从参考中提炼的产品原则

Krita 的价值不在于一次添加数百个笔刷，而在于每个笔刷、稳定器和图层工具都有清晰的创作目标。[1] Inkscape 证明了对象、层和变换应建立在一致的数据模型上，而不是按页面功能零散堆叠。[2] Joplin 与 TriliumNext 则强调：笔记价值来自长期可查找、可组织、可恢复与可保护，而不是单次编辑器体验。[3] [4]

因此，本应用后续实现的优先级是：先完善已有对象的选择、层级、保存与恢复；再扩展输入和附件；最后才考虑协作、同步、插件或真正无限画布。所有玻璃视觉改造必须服务于这些内容层，而不能遮挡画布或降低文本对比。

## References

[1] [Krita: Features and licensing](https://krita.org/en/)  
[2] [Inkscape source repository and README](https://gitlab.com/inkscape/inkscape)  
[3] [Joplin official site](https://joplinapp.org/)  
[4] [TriliumNext repository and feature overview](https://github.com/TriliumNext/Trilium)  
[5] [Photopea repository notice](https://github.com/photopea/photopea)
