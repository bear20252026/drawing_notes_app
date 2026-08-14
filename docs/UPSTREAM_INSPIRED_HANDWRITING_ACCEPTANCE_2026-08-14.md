# 上游参考驱动的手写与笔记体验增强验收记录

**验收日期：** 2026-08-14  
**工程：** `drawing_notes_app`（Flutter 3.44.9 / Dart 3.12.2）  
**上游研究版本：** Excalidraw `abeeaeb`；Saber `f534abb`

## 结论

本轮完成了对 Excalidraw 与 Saber 的源码结构、官方功能范围和许可证的针对性研究，并将高价值、可合规独立重写的行为落地到当前 Flutter 工程。重点不是复制界面图标，而是把**临时激光尾迹、手绘形状识别和真实页面浏览预览**接入输入、渲染、保存边界与自动化测试。

| 本轮能力 | 用户可见结果 | 数据与撤销语义 | 自动化证据 |
|---|---|---|---|
| 独立激光指示器 | 左侧工具栏新增“激光指示器（临时尾迹）”；书写时为彩色外辉光加亮色内芯；释放后先短暂停留，再从起笔端逐段退场 | 从不写入图层、工程文件、导出或撤销栈 | `test/laser_pointer_tool_test.dart` |
| 手绘规则形状扩展 | 支持保守识别矩形、椭圆、菱形；高直线度且具有足够连续采样的笔画识别为线条，方向保持 | 转换为可编辑形状；一次撤销恢复原笔画，重做再次转形状 | `test/shape_recognizer_test.dart` |
| 防误识别边界 | 普通快速两点书写不会被转为直线；低置信度涂鸦与高亮笔保持原样 | 不改变普通书写语义 | `test/shape_recognizer_test.dart` |
| 页面真实缩略图 | 笔记本页面卡片按真实坐标显示手写/高亮、文字框、图片位置比例和形状，而不是随机位置占位条 | 缩略图无需解码原始大图片，避免列表滚动 I/O；编辑内容仍来自页面本体 | 静态分析与全量回归覆盖集 |

## 上游行为如何转化为独立实现

Excalidraw 的自由绘制架构强调原始点列、压力数据、平滑中心线和最终轮廓的分离，其仓库明确列出无限画布、手绘样式、图像、形状库、PNG/SVG/JSON 导出、箭头绑定、撤销重做及视口导航等功能。[1] 当前工程已经采用 MIT 许可的 `perfect_freehand`，并保留了实时稀疏采样和收笔后高质量点列的双质量几何缓存；本轮在这一基础上新增了恒宽激光尾迹的独立路径。

Saber 的公开产品强调触控笔书写、同色不叠加且位于文字下方的高亮笔、嵌套文件夹、最近文档、深色阅读和加密同步。[2] [3] 它的 GPL-3.0 源码不被复制或移植。本项目仅参考其可观察到的产品行为，独立实现了临时激光工具的“停留—起笔端逐段消退—末端柔和淡出”状态机。当前高亮笔原有的局部合成也继续保持不叠色行为。

> 许可证边界：Excalidraw 为 MIT；如将来直接引入其可分离代码，必须保留版权与许可证。Saber 为 GPL-3.0；当前工程仅研究其行为和架构目标，所有实现均独立编写，未复制、改编或合并 Saber 源码。[4] [5]

## 质量门禁

本轮已在工程目录执行：

```bash
export PATH=/home/ubuntu/flutter/bin:$PATH
cd /home/ubuntu/drawing_notes_app
dart format lib test
dart analyze
flutter test --coverage
```

| 检查项 | 结果 |
|---|---|
| 统一格式化 | 99 个文件已检查，0 个待修改 |
| 静态分析 | **No issues found** |
| 覆盖率测试 | **190 项全部通过** |

## 后续路线

本轮并不声称已经“全部复制”两个成熟产品。Excalidraw 与 Saber 的完整能力还包括大规模对象场景、绑定箭头、通用对象多选/组合/锁定、SVG 保真导出、层级文档树、页面操作、同步冲突处理、协作及端到端密钥生命周期。已将这些能力以“已闭环 / 部分具备 / 待实施”的状态写入对标矩阵，并按先手写、再统一对象编辑器、再笔记工作流、最后同步安全的顺序推进。任何后续功能仍需满足创建、编辑、保存、关闭重开、撤销或明确例外、自动化测试和必要真机验收的闭环标准。

## 参考资料

[1] [Excalidraw 官方仓库与功能清单](https://github.com/excalidraw/excalidraw)  
[2] [Saber 官方仓库与功能说明](https://github.com/saber-notes/saber)  
[3] [Saber 官方站点：高亮笔、组织、同步与深色模式](https://saber.adil.hanney.org/)  
[4] [Excalidraw MIT License](https://github.com/excalidraw/excalidraw/blob/master/LICENSE)  
[5] [Saber GPL-3.0 License](https://github.com/saber-notes/saber/blob/main/LICENSE.md)
