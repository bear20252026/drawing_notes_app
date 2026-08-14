# 玻璃化界面：性能与可访问性实施约束

“玻璃感”在本项目中只用于导航、工具与短暂检查器等**功能层**；画布、笔记正文、长列表和高密度编辑内容仍使用稳定的不透明或半透明表面。这与 Apple 对材质层级的建议一致：玻璃材质应帮助区分控制层与内容层，而不是覆盖内容层。[1]

| 规则 | 实现约束 | 原因 |
| --- | --- | --- |
| 局部模糊 | 每个玻璃组件必须以 `ClipRRect` 或 `ClipRect` 限定 BackdropFilter 区域 | Flutter 的 BackdropFilter 若没有裁剪可能作用于整个父区域，模糊属于昂贵的非局部渲染操作。[2] |
| 少量玻璃层 | 首页顶栏分段导航、编辑器工具条、浮动检查器可使用；卡片网格不逐项模糊 | 避免滚动列表产生大量重叠 BackdropFilter；Flutter 建议共享 BackdropKey 或减少模糊范围以降低开销。[2] |
| 高可读性 | 浅色使用偏白 72–86% 表面，深色使用偏蓝黑 62–78% 表面；所有正文保持主题语义文字色 | 模糊和透明不能替代文字对比；无障碍要求不只依赖颜色传达状态。 |
| 降级模式 | `MediaQuery.disableAnimationsOf` 为真时关闭位移/缩放；通过平台可访问性特征关闭实时模糊并使用半透明实色 | 平台可能要求禁用或简化动画；动效不能是理解信息的唯一方式。[3] |
| 性能预算 | 仅在静态导航/工具表面启用模糊；书写、拖拽、缩放期间不在画布上叠加新的 Filter | Flutter 性能文档要求控制 build 成本、谨慎使用 saveLayer/透明与裁剪，并以帧预算衡量流畅度。[4] |
| 交互反馈 | 玻璃不通过大幅浮动表达状态；使用 120–200ms 的颜色、边界和轻微透明变化 | Apple 的动效规范强调短促、精确、有目的，频繁交互应避免额外等待。[5] |

## 可迁移的开源模式

Krita、Inkscape、Joplin 和 TriliumNext 的共性不是视觉风格，而是把复杂能力放入清晰的对象模型、层级结构和渐进菜单中。当前应用采用相同原则：笔刷和对象设置归入上下文工具条；页面组织归入笔记本库；导入、保护与批量操作归入更多菜单；版本、收藏和最近访问保存在模型层。[6] [7] [8] [9]

## References

[1] [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)  
[2] [Flutter: BackdropFilter](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)  
[3] [Flutter: `disableAnimations`](https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures/disableAnimations.html)  
[4] [Flutter: Performance best practices](https://docs.flutter.dev/perf/best-practices)  
[5] [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)  
[6] [Krita](https://krita.org/en/)  
[7] [Inkscape](https://gitlab.com/inkscape/inkscape)  
[8] [Joplin](https://joplinapp.org/)  
[9] [TriliumNext](https://github.com/TriliumNext/Trilium)
