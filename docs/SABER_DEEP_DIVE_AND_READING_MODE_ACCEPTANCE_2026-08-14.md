# Saber 深度研究与深色阅读模式验收报告

**日期：** 2026-08-14  
**研究对象：** Saber `f534abb`（GPL-3.0）  
**当前工程：** `drawing_notes_app`（Flutter 3.44.9 / Dart 3.12.2）

## 执行摘要

本轮对 Saber 的手写、形状识别、页面渲染、PDF 资源、深色阅读、加密与 Nextcloud 同步结构进行了专项审计。Saber 是 GPL-3.0 项目，因此本项目**不复制、不改编、不移植其源码**；仅将其可观察的产品行为和高层架构原则转化为独立 Flutter 实现。

本轮实际落地了 **非破坏性深色阅读模式**。编辑器顶栏新增“深色阅读（仅显示）”开关，使用颜色变换包裹当前画布视觉层、网格、形状草稿和分页笔记的文字/图片/连接线等覆盖层。该模式不写入文档模型、不修改原始笔画或媒体资源、也不参与导出，因此关闭开关、跨设备同步或导出时都保留原始颜色。

| 验收项 | 结果 |
|---|---|
| `dart format lib test` | 100 个文件检查完成，0 个待格式化 |
| `dart analyze` | **No issues found** |
| `flutter test --coverage` | **191 项全部通过** |
| 深色阅读模式回归 | 已验证开关前后 `DrawingDocument.toJson()` 完全一致 |

## Saber 架构研究结论

### 手写与渲染

Saber 将原始点列、活动笔画、低质量/高质量轮廓、页面持久化笔画和临时激光笔迹明确分离。活动笔画及激光始终是运行时状态；完成笔画才进入页面数据。高亮笔按颜色分组离屏合成，以避免同色反复划过后不断加深。铅笔在较高质量场景下使用纹理 shader，在缩小视图时回退为低成本近似，从而平衡书写质感与滚动性能。[1] [2]

当前工程已经具有连续压感轮廓、实时稀疏采样与收笔高质量点列、非叠色高亮笔、临时高亮笔和独立激光尾迹。后续可继续增加基于缩放等级的铅笔纹理质量档位和图形识别的实时候选预览。

### 形状笔与套索

Saber 以显式形状笔触发识别，并通过去抖在书写中展示候选；收笔时才将结果转换为规则线、矩形、圆或多边形，低置信度时保留原笔画。其套索以笔画轮廓的覆盖比例筛选、以网格采样判断图片覆盖。[3] [4]

当前工程已独立实现矩形、椭圆、菱形及多采样直线的保守手绘识别，且转换支持一次撤销/重做；并为稀疏长笔画保留“边界相交也可选中”的易用性。下一步推荐新增“严格包围 / 接触即选”的选择策略，并将自动形状识别切换为显式形状笔加候选预览，减少书写误转。

### 页面、PDF 与资源生命周期

Saber 页面模型把尺寸、笔画、图片、富文本、背景图与运行时资源分离。一个 PDF 资源可由多个页面元素引用，每个元素保存页码和目标矩形；PDF 采用渐进加载和共享缓存。图像/PDF 资源可在离开视区后延迟卸载，减小长笔记的内存压力。[5] [6] [7]

当前工程的 PDF 策略是将 PDF 逐页渲染为离线 PNG 背图，创建独立 `NotebookPage` 并批注；其优势是保存结构稳定、跨端展示简单，且已有可注入 PDF 后端的自动化测试。若将来转为 PDF 原文件共享资源模式，必须先设计资源池、引用计数、可见性加载、内存上限和 Windows/Android 的 PDFium 真机压力测试。

### 深色阅读

Saber 对纸张、笔画与可反相图片采用渲染期变换，不改写内容数据。[2] [8] 本轮已将该行为原则独立落地：阅读反相只覆盖显示层。当前版本使用 Rec.709 保亮度矩阵，对彩色笔迹的层次比简单 RGB 取反更稳定。图片/PDF 的“是否反相”仍是下一阶段的元素级选项；导出必须始终使用未反相原始内容。

### 加密与同步

Saber 将云端账户认证与笔记加密密码分离，使用加密密码封装随机数据密钥与 IV；上传前处理文件内容和远端路径，按照本地/远端变更扫描、删除标记、重试和修改时间规则进行同步。[9] [10]

> 这是一项安全系统，而不是一个“同步按钮”。本项目已有本地 AES-GCM、恢复密钥、原子写入、写入队列和备份恢复；但云同步尚未实现。后续应独立制定数据密钥层级、版本化加密信封、离线操作队列、删除墓碑、冲突策略、密钥轮换与恢复测试，并在安全评审后再接入任何外部存储服务。

## 已实施的深色阅读闭环

| 环节 | 实现结果 |
|---|---|
| 入口 | 编辑器顶栏新增可见的“深色阅读（仅显示）”按钮与状态图标 |
| 主画布 | `CanvasPainter` 所在视觉层由 `ColorFiltered` 包裹；手势坐标仍由未变换布局处理 |
| 分页笔记覆盖层 | 文字、图片、连接线、拖动轨迹、对齐参考线与框选提示一起进入阅读变换 |
| 网格与图形草稿 | 同步进入阅读变换，保证纸面和实时反馈一致 |
| 数据边界 | 不调用文档 `touch()`，不改变笔画、形状、图片或文档 JSON |
| 导出边界 | PNG、PDF、SVG、JSON、RTF 等既有导出仍以原始模型/渲染路径工作 |
| 测试 | `test/reading_inversion_test.dart` 验证视觉滤镜可开关且 JSON 不变 |

## 下一阶段优先级

| 优先级 | 独立实现项目 | 完成条件 |
|---|---|---|
| P0 | 显式形状笔与实时候选预览 | 用户启用后才识别；候选实时可见；收笔转换可撤销；普通笔不误转 |
| P0 | 独立画布图片对象选择、移动、缩放、裁剪、删除与层级 | 选择、编辑、保存重开、导出、撤销重做均正确 |
| P1 | 元素级 `invertible` 标志 | 可单独决定图片/PDF 是否随阅读模式反相；保存数据与导出不变 |
| P1 | 视口驱动图片/PDF 缓存 | 资源可见时加载、不可见时按上限释放；长笔记内存基准达标 |
| P2 | 同步与端到端加密 | 密钥层级、离线队列、冲突/删除、恢复、轮换、渗透测试和真机网络测试完成 |

## 参考资料

[1] [Saber `_stroke.dart`：点列、质量缓存与轮廓](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_stroke.dart)  
[2] [Saber `_canvas_painter.dart`：渲染顺序、高亮、激光与深色显示](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_canvas_painter.dart)  
[3] [Saber `shape_pen.dart`：显式形状笔与去抖候选](https://github.com/saber-notes/saber/blob/main/lib/data/tools/shape_pen.dart)  
[4] [Saber `select.dart`：套索比例命中](https://github.com/saber-notes/saber/blob/main/lib/data/tools/select.dart)  
[5] [Saber `page.dart`：页面数据与运行时资源边界](https://github.com/saber-notes/saber/blob/main/lib/data/editor/page.dart)  
[6] [Saber `pdf_editor_image.dart`：PDF 页元素与渐进加载](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/image/pdf_editor_image.dart)  
[7] [Saber `pdf_document_cache.dart`：共享 PDF 缓存](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/image/pdf_document_cache.dart)  
[8] [Saber `invert_widget.dart`：非破坏性阅读反相](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/invert_widget.dart)  
[9] [Saber `nextcloud_client_extension.dart`：账户与数据加密密钥边界](https://github.com/saber-notes/saber/blob/main/lib/data/nextcloud/nextcloud_client_extension.dart)  
[10] [Saber `saber_syncer.dart`：本地优先加密同步工作流](https://github.com/saber-notes/saber/blob/main/lib/data/nextcloud/saber_syncer.dart)  
[11] [Saber GPL-3.0 License](https://github.com/saber-notes/saber/blob/main/LICENSE.md)
