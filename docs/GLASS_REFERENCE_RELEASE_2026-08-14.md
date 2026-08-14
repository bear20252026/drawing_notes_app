# 开源参考与 Apple 风格玻璃工作区：实现发布说明

**版本：2026-08-14 Glass Workspace Build**  
**范围：绘图笔记应用的导航层、资料库、筛选工具和编辑器上下文工具条。**

本轮以用户提供的 Krita、Inkscape、Joplin、TriliumNext 和 Photopea 方向为研究基线，重点迁移可独立实现的产品模式，而不是复制任何项目源码或视觉资源。Krita 促使我们将笔刷、图层与稳定器视为有明确创作目标的对象；Inkscape 强化对象、图层、变换和导出的一致模型；Joplin 与 TriliumNext 则强化附件、组织、加密、检索与版本的长期可用性。[1] [2] [3] [4]

| 参考方向 | 本轮落地 | 用户可直接感知的结果 |
| --- | --- | --- |
| Apple 材质层级 | 新增 `GlassSurface`，在首页分段导航、笔记本筛选和编辑器工具条使用受裁剪的局部模糊 | 控制层呈现透明玻璃深度，画布、纸张、列表正文仍保持稳定阅读对比 |
| Apple 动效与可访问性 | 玻璃组件在平台请求简化动效时退化为半透明实色；既有卡片继续尊重 `disableAnimations` | 体验不会依赖动态效果来理解状态，敏感用户或低负载场景仍可用 |
| Flutter 渲染约束 | 每个模糊层以 `ClipRRect` 裁剪，仅用于少数静态工具面；不对网格每张卡片和绘图过程使用 BackdropFilter | 避免把玻璃感变成滚动卡顿或书写延迟 |
| Apple 内容分层 | 新增 `AmbientBackground`，只为首页与笔记库提供低对比背景参照；画布/纸张不使用装饰背景 | 玻璃导航层可辨识，但注意力仍聚焦在笔记和画作内容上 |
| Krita / Inkscape | 继续保留以对象、图层、笔压、模板、形状、连接线和版本为中心的实现策略 | 高级绘图能力不会退化为无功能的菜单符号 |
| Joplin / TriliumNext | 已有页面收藏、最近访问、版本、克隆、加密和搜索流程保持回归验证 | 笔记不只“能写”，还能够组织、追踪、恢复与保护 |

## 关键实现文件

| 文件 | 职责 |
| --- | --- |
| `lib/ui/widgets/glass_surface.dart` | 裁剪区域内的 BackdropFilter、半透明表面、边框和阴影，以及简化动效时的可读降级 |
| `lib/ui/widgets/ambient_background.dart` | 仅用于内容库的低对比环境背景，避免将玻璃效果扩散进画布内容层 |
| `lib/ui/pages/home_page.dart` | 首页玻璃分段导航与环境背景 |
| `lib/ui/pages/notebook_view_page.dart` | 笔记本筛选玻璃控制层与环境背景 |
| `lib/ui/widgets/editor_context_bar.dart` | 编辑器上下文工具条玻璃层，同时保持透明 Material 以支持工具交互反馈 |
| `test/glass_surface_test.dart` | 玻璃默认模糊、关闭模糊降级和环境背景的回归测试 |

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 静态分析 | `dart analyze` 通过，零问题 |
| 自动化测试 | `flutter test` 通过，**130** 项全部成功 |
| 行覆盖率 | **85.1%（1376/1616）** |
| 玻璃组件测试 | 已验证默认局部模糊、`enabled: false` 可读降级、环境背景内容承载 |
| 真机性能验证 | 仍需在 Windows/Android 设备上使用 Flutter Profile/DevTools 观察绘图、缩放和滚动帧时间；不得用 Debug 模式结果代替体验结论 |

## 重要边界

Apple 的 Liquid Glass 是平台材质系统；本应用采用的是 Flutter 中可控、跨平台的**局部模糊与半透明层级**，并不声称复刻 Apple 的专有实现。Flutter 官方文档说明 BackdropFilter 是较昂贵的非局部操作，因此本版本刻意限制其区域和数量。[5] 同时，Photopea 并不是完全开源项目，本项目仅研究其任务流与格式提示模式，不纳入代码或资产复用范围。[6]

下一轮建议从参考项目中选择**一个完整闭环**而非堆叠菜单：例如以 Inkscape 思路实现对象分组与独立 SVG 导出，或以 Joplin 思路实现 PDF 附件导入、批注、搜索和导出。两者都需要数据模型、失败处理、测试与真机验证齐全后再推进。

## References

[1] [Krita](https://krita.org/en/)  
[2] [Inkscape](https://gitlab.com/inkscape/inkscape)  
[3] [Joplin](https://joplinapp.org/)  
[4] [TriliumNext](https://github.com/TriliumNext/Trilium)  
[5] [Flutter: BackdropFilter](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)  
[6] [Photopea repository notice](https://github.com/photopea/photopea)  
[7] [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)  
[8] [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
