# 绑定箭头与渲染性能专题研究验收报告

**日期：** 2026-08-14  
**工程：** `drawing_notes_app`（Flutter / Windows / Android）  
**上游参考：** Excalidraw（MIT）与 Saber（GPL-3.0，仅行为和架构研究）

## 本轮交付

本轮对 Excalidraw 的绑定关系、线性元素规范化、肘形箭头路径不变量和局部场景渲染进行了深入审计，同时研究 Saber 的触控笔压力归一化、手势分流、视口分页虚拟化与资源释放策略。[1] [2] [3] [4]

实际落地的功能是 **独立绘图文档的双端绑定箭头第一版**。用户在独立画布选择箭头工具后，若从一个既有矩形、椭圆或菱形拖到另一个形状，应用会自动将起点和终点保存为“目标形状 ID + 归一化锚点”。箭头屏幕显示和 PNG 导出都从当前目标形状 bounds 投影端点，避免保存数据、实时画面与导出画面三者不一致。

| 环节 | 已实现行为 |
|---|---|
| 关系模型 | `ShapeEndpointBinding` 保存目标 ID 与 `0..1` 锚点，反序列化自动夹紧异常值 |
| 创建交互 | 独立画布的箭头拖拽创建自动识别起终点下最上层可绑定形状；任一端在空白处则保留为自由端 |
| 几何规范 | 绑定箭头统一转换为正 `width/height` 与 `flipX/flipY`，消除拖拽方向翻转问题 |
| 渲染与导出 | `DrawingController.shapeForRendering()` 在不改写模型的前提下投影端点；`CanvasPainter` 与 PNG 导出共用该路径 |
| 旧文档兼容 | 没有绑定字段的箭头维持原有自由线行为；新增字段缺失时安全回退 |
| 自动化覆盖 | 双端命中、单端自由回退、目标移动重投影、JSON 往返和锚点夹紧共 4 项回归 |

## 刻意保留的边界

本版未伪装成完整流程图系统。肘形自动路由、避障、手动中点、对象分组随动、删除目标时的关系降级、对象选择变换和协作分数层级将在统一对象变换命令完成后按依赖顺序实现。当前优先保证箭头创建、保存、重新打开、画布渲染和导出都使用同一关系数据，而不是先堆叠难以维护的视觉功能。

> Excalidraw 的实现表明，绑定、路径规范化和对象变换应由同一关系内核维护；Saber 的实现表明，书写和资料工作流必须以视口可见性和输入低延迟为前提。[1] [3]

## 质量门禁

| 检查项 | 结果 |
|---|---|
| `dart format lib test` | 完成，104 个文件均符合格式 |
| `dart analyze` | **No issues found** |
| `flutter test --coverage` | **202 项全部通过** |

## 后续优先路线

下一阶段应补齐**独立形状对象的选择、移动、缩放和一手势一历史事务**；该能力会让已保存的绑定箭头在用户真实拖动目标时自动随动。其后再实现目标删除时的自由端降级、锁定、组合与文本容器。PDF 虚拟化与图片资产回收则作为并行性能轨道，遵循 Saber 的可见资源生命周期原则。

## 参考资料

[1] [Excalidraw Binding](https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/binding.ts)  
[2] [Excalidraw Linear Element Editor](https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/linearElementEditor.ts)  
[3] [Saber Canvas Gesture Detector](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/canvas_gesture_detector.dart)  
[4] [Saber Asset Cache](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_asset_cache.dart)
