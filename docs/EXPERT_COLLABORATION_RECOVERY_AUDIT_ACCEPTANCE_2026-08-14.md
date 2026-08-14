# 高级协作与防御性恢复源码审计验收报告

**日期：** 2026-08-14  
**作者：** Manus AI  
**研究对象：** Excalidraw（MIT）与 Saber（GPL-3.0）公开源码  
**本轮交付：** 协作/同步/恢复源码级审计、架构差距矩阵、独立防御性文档恢复实现与自动化验收。

## 最终结论

本轮继续深入审计 Excalidraw 与 Saber 的高级机制，但没有把“实时协作”误实现为一个没有可靠性基础的按钮。源码证据表明，成熟协作至少需要客户端加密、房间中继、持久快照、对象版本协调、二进制资源生命周期、失败反馈与断线恢复；成熟多设备同步则需要本地/远端身份映射、队列去重、I/O 互斥、重试退避、冲突策略和用户可见恢复路径。[1] [2] [3] [4]

本工程本轮选择先独立实现这些能力的安全前置条件：**防御性文档恢复**。`DocumentCodec` 现在会严格拒绝根结构或文档身份非法的数据，但对图层、笔迹、形状和图片采用逐项隔离恢复。局部对象损坏、重复 ID、非有限数值、危险几何、无效图片项或失效箭头端点绑定不会再阻断文档其余内容打开。该能力同时适用于本地 `.bak` 恢复、外部导入和未来从同步/协作通道收到的远端快照。

> **成熟协作的第一原则不是“能发送数据”，而是“收到任何不可信数据后，用户仍可安全地打开、编辑并恢复自己的内容”。**

| 验收维度 | 状态 | 验收结论 |
|---|---:|---|
| Excalidraw 协作分层研究 | 通过 | 已审计房间中继、客户端加密传输、持久场景事务、元素协调和恢复流程。 |
| Saber 同步分层研究 | 通过 | 已审计通用同步队列、指数退避、本地/远端互斥和加密 WebDAV 适配。 |
| 防御性文档恢复 | 通过 | 根结构严格校验；可选对象局部隔离；有效内容可继续打开。 |
| 几何与渲染安全 | 通过 | 画布尺寸、对象坐标、形状/图片尺寸、旋转、笔画宽度、笔压和不透明度均被验证或钳制。 |
| 绑定关系修复 | 通过 | 仅保留指向当前可绑定形状的箭头端点；失效端点安全降级为自由端。 |
| 历史兼容性 | 通过 | 恢复合法连字符文档 ID，保持已有独立形状文档文件兼容。 |
| 自动化质量门禁 | 通过 | `dart analyze` 零诊断；`flutter test --coverage` 213 项全部通过。 |

## 上游源码研究结论

### Excalidraw：协作传输不等于文档存储，更不等于对象合并

Excalidraw 的房间服务只维护 Socket 会话、房间成员、可靠/易失广播和跟随关系；客户端在发送前加密负载，服务端不解密也不理解画布对象。[1] [2] 客户端将实时消息、协作光标、图像资源状态、初始房间同步、持久快照与 UI 历史记录区分开：远端更新以非本地历史方式进入场景，避免用户撤销操作错误地撤掉他人的远端变更。[2]

其加密持久场景层与 websocket 中继独立。写入时通过事务读取、解密、协调、重新加密和更新；接收远端元素时按稳定对象 ID、版本、nonce、当前编辑状态和排序索引进行确定性协调。[3] [4] 恢复层还会迁移旧数据、修复绑定/容器关系、清理失效目标引用，并把可能导致渲染冻结的超大线性元素安全隔离。[5]

| 上游结论 | 对当前工程的独立应用 |
|---|---|
| 房间中继应只处理加密字节与会话事件。 | 未来实时服务不得直接接触 `DrawingDocument` 明文对象模型。 |
| 实时广播与持久快照应是两条链路。 | 本地 `StorageService` 和 `.bak` 保持第一恢复真相；同步/协作不阻塞绘制。 |
| 合并必须基于对象版本与明确规则。 | 在没有操作批次、版本和冲突 UI 之前，不提供伪实时协作。 |
| 恢复必须修复关系而非信任输入。 | 本轮已在文档解码阶段校验对象几何与箭头目标关系。 |

### Saber：同步应以可观测队列和适配器实现，而非侵入编辑器

Saber 的 `abstract_sync` 将队列、传输成功事件、刷新互斥、远端/本地 I/O 互斥、去重和指数退避放到通用组件；具体后端仅实现本地/远端文件映射、变更扫描与字节读写。[6] Saber 的实际 WebDAV 适配器还将加密路径、内容加解密、远端清单缓存、删除语义、预览优先级和修改时间取舍集中在后端适配层，并把较重的加解密移到工作器执行。[7]

这证明当前工程的 `DocumentRepository` 不需要、也不应直接变为网络对象。后续正确路线是在本地仓储之上添加独立的 `DocumentSyncAdapter`、同步状态记录、队列和冲突副本，而让 `DrawingController` 继续保持本地、低延迟、可离线编辑。

## 已独立实现：防御性文档恢复闭环

### 恢复规则

`DocumentCodec.decode()` 现分为严格根校验与可选对象恢复两层。根节点、`document` 对象及文档 ID 不可信时抛出 `FormatException`，拒绝创建身份未知的文档。图层、笔迹、形状和图片则逐项尝试恢复，发生错误时只隔离该对象。没有可用图层时，系统创建安全默认图层，确保编辑器依旧可以打开并继续工作。

| 对象类别 | 当前恢复行为 |
|---|---|
| 画布 | 非有限尺寸使用默认值；有效尺寸限制在 16–32,768 逻辑像素。 |
| 图层 | 去重 ID；无效图层跳过；不透明度钳制为 0–1。 |
| 笔画 | 跳过无点、不可解析、非有限坐标/笔压或异常宽度的笔画；有效笔压和不透明度钳制为 0–1。 |
| 形状 | 跳过重复 ID、无效坐标、非正或大于 8,192 的尺寸、无效旋转和异常线宽。 |
| 箭头 | 仅保留指向现存矩形、椭圆或菱形的端点绑定；无效端点解除绑定但保留箭头。 |
| 图片 | 跳过重复 ID、空文件路径、无效坐标与异常尺寸；恢复时不访问或删除磁盘文件。 |

该实现没有复制 Excalidraw 或 Saber 源码。它仅独立采用了“验证 → 局部迁移/隔离 → 修复关系 → 显示可用数据”的工程原则。[5]

### 回归覆盖与兼容性修复

新增 `test/document_codec_recovery_test.dart` 覆盖三类关键风险：根结构/文档 ID 拒绝；局部笔画、图层、形状和图片损坏后的部分恢复；全体可选对象无效时退化为默认图层。全量测试首次发现旧测试使用了连字符形式的合法文档 ID；恢复层随即调整为允许字母、数字、下划线和连字符，同时继续拒绝路径分隔符及遍历字符串。该兼容性修复已被独立形状文档测试和完整测试套件共同验证。

| 自动化用例 | 验证结果 |
|---|---|
| 根节点与不安全 ID | 正确拒绝，不构造伪文档。 |
| 有效内容与损坏对象混合 | 有效图层、笔迹、形状和图片继续恢复。 |
| 数值越界 | 尺寸、笔压和不透明度安全钳制；危险对象隔离。 |
| 箭头失效目标 | 对应端点解绑；另一端关系保持。 |
| 旧连字符文档 ID | 正确恢复，保持现有存档兼容。 |

## 可复现质量门禁

在 Flutter 3.44.9 / Dart 3.12.2 环境执行：

```bash
export PATH=/home/ubuntu/flutter/bin:$PATH
cd /home/ubuntu/drawing_notes_app
dart format lib test
dart analyze
flutter test --coverage
```

| 检查项 | 最终结果 |
|---|---|
| `dart format lib test` | 107 个文件检查，0 个文件需要修改。 |
| `dart analyze` | `No issues found!`，零诊断。 |
| `flutter test --coverage` | `+213: All tests passed!`；覆盖率原始产物更新至 `coverage/lcov.info`。 |

## 许可证边界

Excalidraw 采用 MIT 许可，研究仅提取其架构、关系完整性和交互事务的原则；任何未来逐文件复用都需保留版权声明和许可。Saber 采用 GPL-3.0，本工程没有复制、粘贴、链接或将其源文件作为运行时依赖；对 Saber 的阅读只用于产品行为、性能与系统分层的独立设计参考。[8] [9]

## 下一阶段路线

下一阶段应首先实现已在对象编辑研究中确认的**统一多选与原子变换**。该能力在单对象选择、锁定、绑定箭头投影和集合快照历史之上自然扩展，能带来远高于单个新按钮的白板/流程图生产力。随后实现箭头端点直接编辑与可重建关系索引。只有在本地操作批次、对象版本、冲突副本和加密同步队列具备后，才开始讨论真实多人会话。

| 优先级 | 后续能力 | 完成标准 |
|---:|---|---|
| P0 | 混合对象多选与组变换 | 形状/图片框选、批量移动/缩放/锁定/删除、取消与单一历史边界全部可用。 |
| P0 | 箭头端点编辑与关系索引 | 端点可改绑/解绑；关系可重建；删除、恢复和撤销无悬挂 ID。 |
| P1 | 文档变更记录与冲突副本 | 本地版本、内容哈希、最后同步记录和用户可见冲突恢复均可测试。 |
| P1 | 加密同步适配器 | 离线编辑不受阻塞；队列有重试和进度；失败不丢本地文档。 |
| P2 | 实时协作会话 | 独立服务、加密房间、操作批次协调、断线重连和多设备压力测试齐备后再交付。 |

## References

[1]: https://github.com/excalidraw/excalidraw-room/blob/master/src/index.ts "Excalidraw collaboration relay source"
[2]: https://github.com/excalidraw/excalidraw/blob/master/excalidraw-app/collab/Portal.tsx "Excalidraw encrypted collaboration transport source"
[3]: https://github.com/excalidraw/excalidraw/blob/master/excalidraw-app/data/firebase.ts "Excalidraw encrypted persistent scene transaction source"
[4]: https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/data/reconcile.ts "Excalidraw element reconciliation source"
[5]: https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/data/restore.ts "Excalidraw document restoration source"
[6]: https://github.com/saber-notes/abstract_sync/blob/main/lib/src/syncer_component.dart "Saber abstract synchronization queue source"
[7]: https://github.com/saber-notes/saber/blob/main/lib/data/nextcloud/saber_syncer.dart "Saber encrypted WebDAV adapter source"
[8]: https://github.com/excalidraw/excalidraw "Excalidraw official repository (MIT License)"
[9]: https://github.com/saber-notes/saber "Saber official repository (GPL-3.0 License)"
