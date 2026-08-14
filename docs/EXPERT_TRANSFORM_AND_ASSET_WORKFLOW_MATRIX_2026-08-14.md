# 专家级对象变换与资料工作流差距矩阵

**日期：** 2026-08-14  
**工程：** `drawing_notes_app`（Flutter / Windows / Android）  
**参照：** Excalidraw（MIT）与 Saber（GPL-3.0，仅行为与架构研究）

## 结论

当前工程已经具备笔画选择、图片对象编辑、绑定箭头创建、PDF 逐页批注、离线资源副本和多种书写工具。接下来最影响专业体验的缺口不是新增工具图标，而是让**独立绘图的形状对象**达到与图片同等级的编辑与历史完整性；这样用户移动节点时绑定箭头才能真正随动，关系图才有可用性。

| 优先级 | 能力 | 当前状态 | 关键不变量 | 验收标准 |
|---|---|---|---|---|
| P0 | 独立形状选择、锁定、移动、缩放、删除 | 缺失或仅创建可见 | 锁定拒绝变更；一个手势一条历史；取消回滚 | 创建后能选择编辑；重开保留；撤销/重做精确恢复 |
| P0 | 形状变换带动绑定箭头 | 绑定创建已完成，变换未接入 | 同一事务内目标和受影响箭头一致；导出与屏幕一致 | 移动/缩放节点后端点投影正确；撤销恢复两者 |
| P1 | 删除目标时箭头自由端降级 | 缺失 | 不保留悬挂 ID；删除/撤销可逆 | 删除一端后箭头仍存在；撤销恢复绑定 |
| P1 | 图片/PDF 资源可见性缓存预算 | 部分具备 | 不因不可见页维持解码位图；保存时不驱逐所需资源 | 长资料浏览无持续内存增长；关闭释放资源 |
| P2 | 多选与混合对象变换 | 分页笔记部分具备 | 所有对象以共同 bounds 变换；关系修复一次发生 | 混选拖动/缩放/撤销一致 |
| P2 | 多页导出资源预算与降级报告 | 导出已具备 | 有上限并发、超时、资源释放、可诊断错误 | 大 PDF 导出不阻塞 UI；失败页可定位 |
| P3 | 旋转形状与绑定策略 | 未实施 | 明确跟随局部锚点或解除绑定，不能静默漂移 | 旋转/撤销/导出关系可解释 |
| P4 | 协作版本、墓碑、冲突恢复 | 未实施 | 顺序、删除和绑定关系可合并 | 离线冲突演练、恢复演练全部通过 |

## 本轮实施范围

本轮将独立实现 **P0 形状对象编辑与绑定箭头随动**，范围限定为独立绘图文档。控制器将持有形状选择和手势前快照，移动/缩放时使用统一几何内核重新投影所有受影响箭头；手势结束只提交一条可逆命令，取消时回滚。锁定和删除与图片对象保持一致的用户可见反馈。

页面笔记中的混排形状暂不复用该接口，因为其目前与文字、图片、图表和页面历史采用不同存储边界。先把独立画布对象内核做对，避免为了表面一致性引入跨文档历史错误。

## 参考资料

[1] [Excalidraw Resize Elements](https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/resizeElements.ts)  
[2] [Excalidraw Selection](https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/selection.ts)  
[3] [Saber Editor Exporter](https://github.com/saber-notes/saber/blob/main/lib/data/editor/editor_exporter.dart)  
[4] [Saber Canvas Gesture Detector](https://github.com/saber-notes/saber/blob/main/lib/components/canvas/canvas_gesture_detector.dart)
