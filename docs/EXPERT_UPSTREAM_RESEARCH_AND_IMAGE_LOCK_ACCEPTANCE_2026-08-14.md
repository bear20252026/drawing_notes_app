# 专家级上游研究与图片锁定能力验收报告

**日期：** 2026-08-14  
**工程：** `drawing_notes_app`（Flutter，Windows / Android）  
**研究对象：** Excalidraw（MIT）与 Saber（GPL-3.0）

## 本轮结论

本轮研究从“功能清单比对”深入到 **关系图、稳定层级、并发协调、笔迹质量分档、资料资产生命周期和 PDF 原生资源释放**。Excalidraw 的启示是：流程图和无限白板的可靠性由对象关系不变量决定；Saber 的启示是：手写与资料体验的流畅性取决于活动状态和完成状态使用不同预算、资源缓存遵循可见消费者生命周期。[1] [2] [3] [4]

在完全遵守许可证边界的前提下，本轮没有复制 Saber GPLv3 源码，所有应用代码均为独立实现。实际落地了一项高频的对象安全能力：**独立绘图文档图片的持久化锁定**。

| 能力 | 行为闭环 | 自动化证据 |
|---|---|---|
| 图片锁定 | 在选中图片的上下文工具栏点击锁定；图片仍可选中以解锁，但不能被拖动、缩放或删除 | `document_image_editing_test.dart` |
| 持久化 | `locked` 随图片几何、资源路径、层级进入 DocumentCodec 的实际磁盘存储 | `document_image_persistence_test.dart` |
| 历史 | 锁定/解锁为独立图片状态命令，支持撤销与重做 | `document_image_editing_test.dart` |
| 编辑保护 | 控制器而非 UI 单独负责拒绝锁定对象的移动、缩放与删除 | `document_image_editing_test.dart` |
| 既有闭环保持 | 导入资源副本、重开恢复、内容边界、PNG 导出、图片选择和编辑维持有效 | 图片持久化与对象编辑回归 |

## 新增研究成果

| 主题 | 可独立采用的工程原则 | 本工程下一步 |
|---|---|---|
| 分数层级 | 数组顺序可作为缓存；持久层级键应允许中间插入与确定性排序 | 在统一对象协议中预留 `orderKey`，暂不扰动单机 `zOrder` |
| 关系图 | 连接线端点保存对象 ID 与局部锚点；变换/删除在同一事务维护关系 | 实施最小双端绑定箭头，再增加肘形路由与文本标签 |
| 协作协调 | 本地编辑优先、版本/nonce 决胜、删除与层级不变量可验证 | 先完成本地对象 version/墓碑，再讨论生产同步 |
| 笔迹性能 | 活动笔画低质量预览，完成后高质量轮廓；缓存失效有明确边界 | 为现有双质量缓存补充性能基准与最小区域重建 |
| 资源生命周期 | 缓存应由可见消费者引用，而非文件存在性决定；保存期避免驱逐 | 抽取 `DocumentAssetCache`，优先处理 PDF 邻页加载与句柄释放 |

## 质量门禁

发布前完整检查已执行：

| 检查项 | 结果 |
|---|---|
| `dart format lib test` | 完成，101 个文件均符合格式 |
| `dart analyze` | **No issues found** |
| `flutter test --coverage` | **198 项全部通过** |

## 后续优先顺序

下一项应是独立绘图的 **双端绑定箭头最小内核**，而不是先添加复杂肘形路线或云同步。它可在已存在的形状、稳定 ID、命令栈和选择体系上验证对象关系是否能在移动、缩放、删除、撤销、保存和重开时保持正确。只有该内核稳定后，分组、文本容器、frame、对齐分布和未来多端协调才不会建立在不可靠的坐标复制之上。

## 参考资料

[1] [Excalidraw Fractional Index](https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/fractionalIndex.ts)  
[2] [Excalidraw Binding](https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/binding.ts)  
[3] [Excalidraw Reconciliation](https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/data/reconcile.ts)  
[4] [Saber Stroke](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_stroke.dart)  
[5] [Saber Asset Cache](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_asset_cache.dart)
