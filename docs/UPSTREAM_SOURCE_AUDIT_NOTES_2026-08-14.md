# 上游源码深度审计工作笔记

**审计日期：** 2026-08-14  
**审计对象：** Excalidraw `master` 与 Saber `main` 的公开官方 GitHub 仓库。

## 已确认入口

| 项目 | 官方仓库 | 分支与当前公开线索 | 本轮优先审计目录 | 许可证边界 |
|---|---|---|---|---|
| Excalidraw | <https://github.com/excalidraw/excalidraw> | `master`；仓库页面显示 4,073 次提交；根目录存在 `packages`、`excalidraw-app`、`firebase-project` 与 `scripts`。 | `packages/excalidraw` 的元素模型、场景、历史、绑定、选择与变换；应用层协作隔离。 | MIT；仅学习架构与交互机制，任何直接代码复用仍需逐文件保留原版权与许可。 |
| Saber | <https://github.com/saber-notes/saber> | `main`；仓库页面显示 4,213 次提交、208 个标签；根目录存在 `lib`、`test`、`packages`、`shaders`、`installers`。 | Flutter `lib` 中笔迹、页面、导入导出、存储与手势；`shaders` 的渲染性能策略。 | GPL-3.0；仅做行为、产品和架构研究，本工程独立重写且不复制或链接 GPL 源码。 |

## 初步高价值线索

Excalidraw 的顶层 `packages` 与独立应用目录表明编辑器核心与产品部署层分离；本轮将核对其元素模型、场景变更、绑定、排序索引和历史边界如何保持原子性。近期提交线索包含分数索引校验，说明对象层级和稳定排序仍是其维护重点。

Saber 的顶层同时包含 `lib`、`test`、`packages` 和 `shaders`，并在近期提交中出现“matrix approach to inverting”的着色器性能优化线索。这支持将审计重点放在手写页的 GPU 合成、阅读模式/颜色反转的渲染路径、资产缓存和跨平台输入适配，而不是从 GPL 源码中复制实现。

## 下一步审计问题

| 主题 | 需要从源码验证的问题 | 对当前 Flutter 工程的候选价值 |
|---|---|---|
| Excalidraw 关系图 | 绑定、容器、文本、箭头的关系是否使用独立可恢复结构，删除和变换如何维护逆向引用。 | 为现有绑定箭头延伸到文本容器、分组和多选奠定无悬挂关系基础。 |
| Excalidraw 事务 | 选择、拖动、缩放、复制、粘贴、层级变更如何确定一次历史边界。 | 将当前形状集合快照扩展为多选与群组的原子操作。 |
| Saber 笔迹/视口 | 笔迹渲染如何做分层、合成、裁剪、缓存、手写输入的预测与消抖。 | 提升粗笔下连续感、长文档帧率和资源内存预算。 |
| Saber 文件/导出 | 页面、PDF 背景、图片和笔迹如何持久化、恢复并在导出时保持保真。 | 强化当前多文档、PDF 批注、图片资产和 Word/PDF 导出的数据边界。 |

## References

[1]: https://github.com/excalidraw/excalidraw "Excalidraw official repository"
[2]: https://github.com/saber-notes/saber "Saber official repository"

## 已核对的源码证据：关系与变换

### Excalidraw 的关系完整性

`packages/element/src/binding.ts` 将端点更新描述为三态策略：创建绑定、明确解除绑定、保留现有绑定。它将“命中候选、绑定模式、焦点坐标”作为独立策略结果，再统一写入起点和终点。更重要的是，绑定写入同时更新箭头端的绑定字段和目标对象的反向 `boundElements` 引用；解除时也同步清理反向引用，并对同一箭头双端指向同一目标的情况进行保护。这说明专业级关系图不能只依赖单向指针，而应在模型层维护可验证的双向不变量。

Excalidraw 同时区分 `inside` 和 `orbit` 两种端点语义，并按缩放调整命中距离；在自由端拖动、同目标双端、嵌套图形、网格和角度锁定等情况下，都通过同一个策略选择器明确决定“绑定、解除还是保留”。本工程当前的归一化锚点投影与单端自由降级已解决最重要的基础关系，但尚未建立反向引用、绑定模式、端点直接编辑或复杂嵌套规则。

`updateBoundElements()` 会在目标移动、旋转或缩放后根据目标的反向引用查找受影响连接线，并避免重复更新同一元素。它还接收“本轮同时变更的元素”集合，以便在多对象事务中区分连接线应跟随重投影的情形和连接线自身也在被独立变换的情形。这是多选/分组编辑不可省略的关系更新边界。

### Excalidraw 的变换和历史原则

`resizeElements.ts` 先分派单对象与多对象路径，再在旋转、缩放或翻转后更新绑定元素；当用户直接旋转或缩放箭头本身时，端点绑定会被明确解除，避免“用户已手工调整连接线却被关系系统立即覆盖”的冲突。多选路径围绕统一包围盒计算下一尺寸、翻转轴和原始边界，在一个变换调用内应用到全部选中对象。

`history.ts` 使用增量历史而不是每次持久化整页数据。它只记录非空、可持久化的本地变更；仅当元素产生变更时才截断重做分支，避免仅取消选择等 UI 状态误清空可重做操作。撤销/重做排除协作版本号，并将历史重放作为新的同步操作发出。对于当前单机 Flutter 工程，形状集合快照仍然是正确且低风险的第一阶段；面向多选与未来协作时，应逐步演进为操作批次和元素增量。

### Saber 的笔迹绘制策略

`lib/components/canvas/_stroke.dart` 为每条笔迹懒缓存高、低质量多边形和路径。当前笔划使用高质量路径；低缩放时则每四个点采样一次，并关闭平滑与压力模拟，减少长笔记缩小时的路径成本。笔划完成后才进行完整平滑，并在模拟压力已落地时去除过密点；这一策略将“手写时低延迟”和“停笔后高保真”分离。

`lib/components/canvas/_canvas_painter.dart` 进一步将荧光笔、普通笔、激光笔、当前笔划、识别预览和选择框分层绘制。荧光笔按颜色切换合成层而不是为每条笔划创建层；铅笔仅在缩放与笔宽超过阈值时使用着色器，缩小后降级为更低成本的颜色模拟。`shouldRepaint` 对当前笔划和渐隐激光始终刷新，静态内容仅按模型/视图变化刷新。这些是可独立复现的性能原则，而非可复制的 GPL 代码。

### Saber 的文件与资产一致性

`lib/data/file_manager/file_manager.dart` 将笔记主文件、顺序编号资产和预览视为一个生命周期单元：写入先确保目录存在并更新最近访问索引；读取在临时锁定时进行有限次数重试；重命名和删除主文件时同步移动或删除其关联资产；导入归档时先识别主文档再导入顺序资产。目录监视会产生明确的写入/删除事件，最近文档列表会剔除外部删除的失效路径。

本工程已建立独立图片离线副本与文档路径，但其下一步应将“文档元数据、资产索引、缩略图、图片、PDF 页缓存”提升为同一存储事务。尤其是重命名、复制、删除、崩溃恢复和清理未引用资产必须共享可测试的不变量，才能防止此前用户指出的多文档内容错位和资源遗失。

### Saber 的导航体验策略

`interactive_canvas.dart` 在手势开始时停止残余惯性，在本手势内以 `isDrawGesture` 先行划分绘制与导航；缩放时保持手势焦点对应同一场景点，边界触达时重新校准参考焦点；平移和缩放结束后通过摩擦模型提供惯性；鼠标滚轮在无修饰键时平移、按住 Ctrl/Meta 时以指数函数缩放。该模型提供了 Windows 鼠标/触控板和 Android 双指手势可以共同遵循的交互语义。

## 新一轮候选能力排序

| 优先级 | 独立实现候选 | 上游研究依据 | 建议验收条件 |
|---:|---|---|---|
| P0 | 绑定关系反向索引与端点直接编辑 | Excalidraw 的双向绑定不变量、显式解绑和同批次关系更新。 | 每个目标的反向箭头引用可校验；拖动箭头端点可绑定、改绑或降级；删除/撤销后无悬挂 ID。 |
| P0 | 多选包围盒与原子变换 | Excalidraw 的统一包围盒、同时更新集合和变换时连接线分流规则。 | 框选、移动、缩放、锁定、删除和撤销均作为单一事务；移动目标集时箭头正确随动。 |
| P1 | 粗笔渐进细化渲染 | Saber 的当前笔划高质量、静态缩小时抽样、停笔后优化。 | 粗笔连续、无大点串感；缩放长页面无明显掉帧；笔迹形状与导出保持一致。 |
| P1 | 文档-资产事务索引与引用清理 | Saber 的主文件、资产、预览同步移动/删除和有限重试读取。 | 文档重命名/复制/删除后的图片、缩略图和 PDF 资产一一对应；异常恢复不交叉显示。 |
| P2 | 统一跨输入导航物理 | Saber 的绘制/导航裁决、焦点锁定缩放、惯性、滚轮语义。 | Android 双指、Windows 触控板和鼠标缩放/平移行为一致且可中断。 |

## References（源码定位）

[3]: https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/binding.ts "Excalidraw binding relationship implementation"
[4]: https://github.com/excalidraw/excalidraw/blob/master/packages/element/src/resizeElements.ts "Excalidraw element transform implementation"
[5]: https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/history.ts "Excalidraw history implementation"
[6]: https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_stroke.dart "Saber stroke model implementation"
[7]: https://github.com/saber-notes/saber/blob/main/lib/components/canvas/_canvas_painter.dart "Saber canvas painter implementation"
[8]: https://github.com/saber-notes/saber/blob/main/lib/data/file_manager/file_manager.dart "Saber file lifecycle implementation"
[9]: https://github.com/saber-notes/saber/blob/main/lib/components/canvas/interactive_canvas.dart "Saber interactive canvas implementation"

## 协作与同步边界补充审计

Excalidraw 的官方开发文档明确将实时协作服务与编辑器本体分离：本地协作需要单独部署 `excalidraw-room`；其自托管客户端镜像目前不直接提供分享与协作功能。这支持当前工程把单机编辑器、可恢复本地存储、将来同步提供方和实时协作会话拆成独立层，而不是把网络状态侵入笔迹与对象模型。[10]

Saber 维护的 `abstract_sync` 是一个 MIT 许可的通用文件同步框架。其公开说明将“本地文件类型、远端文件类型、包含额外路径/元数据的同步文件类型、同步接口和上传/下载队列”分为独立抽象；README 同时指出 Saber 实际同步层附加了加密和缓存。这证明专业笔记同步可先建立本地文件真相、可观测队列和远端适配边界，再独立增加加密、冲突策略和具体云端，而不让画布对象直接依赖某个 WebDAV 或厂商协议。[11]

### 新增架构判断

| 主题 | 上游证据 | 当前工程建议 |
|---|---|---|
| 实时协作 | Excalidraw 编辑器与协作房间服务分离，自托管编辑器并不自动等于自托管协作。 | 先完成本地操作批次和可重放变更日志；未来协作作为可替换会话/传输层接入。 |
| 文件同步 | Saber 的同步抽象将本地、远端、队列和实现接口解耦，真实集成可额外添加缓存/加密。 | 在现有 `DocumentRepository` 上方建立同步状态表和工作队列，保留本地 `.bak` 恢复为第一真相。 |
| 冲突治理 | 文件同步不能等同于实时对象合并。 | 首版使用每文档版本戳、内容哈希、显式冲突副本和用户可见恢复记录；不承诺隐式合并手写点列。 |

[10]: https://docs.excalidraw.com/docs/introduction/development "Excalidraw official development documentation"
[11]: https://github.com/saber-notes/abstract_sync "Saber abstract_sync official repository (MIT License)"

## 协作、同步、冲突与恢复的源码级结论

### Excalidraw：中继、持久化、加密和合并严格分层

Excalidraw 的 `excalidraw-room` 服务入口只负责 Socket 房间成员、可靠/易失广播、协作者可见性及跟随房间事件；它接收客户端已加密的载荷和 IV 并转发，不负责解密、文档对象语义或冲突合并。客户端 `Portal` 在发出场景、指针、空闲状态和视口同步消息前序列化并加密；场景同步按元素版本发送增量，并定期全量回填以收敛可能由丢包造成的偏差。[12] [13]

客户端协作控制器将实时收包、远端场景恢复、元素协调、图像文件加载、协作光标、空闲状态、视口跟随和持久化排队分开处理。接收到远端更新时会先协调元素并记录最新场景版本，随后以“不进入本地历史”的方式更新界面，防止远端变更被误记录为本地撤销操作。持久化层则将加密场景快照单独写入 Firestore 事务中：读取旧快照、客户端解密、协调、本次结果重新加密、回写；二进制文件使用独立存储与状态跟踪。[14] [15]

`reconcileElements()` 对每个对象依赖稳定 ID、版本和 `versionNonce` 做确定性取舍；正在编辑、缩放或新建的本地对象优先，其他同版本冲突使用 nonce 决定优先级，最后按分数索引重新排序。`restoreElements()` 体现更基础的恢复原则：未知/损坏元素应隔离，旧格式应迁移，绑定与容器反向关系需要修复，失效目标 ID 必须解绑，极端大线条应转为安全墓碑以避免渲染冻结。它保留空文本等“已删除墓碑”以维护协作版本完整性。[16] [17]

### Saber：文件同步适配器、队列和冲突取舍独立于编辑器

Saber 的同步抽象把队列调度、刷新互斥、传输流、重试退避与本地/远端互斥放到通用组件中。队列依据本地或远端文件身份去重；失败任务被移除后按指数退避重新加入；上传和下载路径对本地与远端 I/O 分别加锁。具体 WebDAV 适配器只负责文件身份映射、远端扫描、加密名称/内容、读取写入和时间戳取舍。[18] [19]

实际 Saber 适配器使用远端清单缓存缩短重复元数据请求，将远端零字节文件视为删除信号，优先处理预览资源，再处理主笔记。它在后台工作器中完成较重的文件名/内容加解密，并以修改时间（500ms 容忍区间）作简单的本地/远端取舍。此机制适合“单用户多设备文件同步”，但它不是逐笔划实时协作，也不保证并发编辑的语义合并；这一边界必须在产品中透明呈现。[20]

### 对当前 Flutter 工程的可执行架构规则

| 规则 | 原因 | 最小独立实现 |
|---|---|---|
| 本地文档和 `.bak` 始终是第一恢复真相。 | 网络/认证/远端服务不可用时，用户仍必须打开并继续编辑。 | 所有同步动作从不可变编码快照读取，绝不阻塞 `DrawingController` 的本地提交。 |
| 同步与实时协作采用不同协议。 | 文件时间戳取舍不能正确合并同时移动同一对象或同时编辑同一笔迹。 | 第一版仅做按文档队列的备份/同步与冲突副本；实时会话另建操作批次协议。 |
| 加密是独立的字节边界，而不是模型字段。 | 便于替换远端、保留本地检索/缩略图策略并降低密钥泄漏面。 | 在未来 `DocumentSyncAdapter` 前后调用已有 `EncryptionService`，使仓库/画布保持无网络依赖。 |
| 冲突必须可观察且可恢复。 | 静默“最新修改覆盖”会毁掉手写笔记，用户无法信任产品。 | 每个同步对象保存逻辑版本、编码哈希、最后同步时间、冲突副本 ID 和可见恢复记录。 |
| 恢复时先验证、再修复、最后显示。 | 外部文件和远端数据都不可信，且极端几何可能使渲染卡死。 | 对文档/形状/图片引用做格式、尺寸、路径和关系检查；隔离无效对象并记录诊断。 |

[12]: https://github.com/excalidraw/excalidraw-room/blob/master/src/index.ts "Excalidraw collaboration relay source"
[13]: https://github.com/excalidraw/excalidraw/blob/master/excalidraw-app/collab/Portal.tsx "Excalidraw encrypted collaboration transport source"
[14]: https://github.com/excalidraw/excalidraw/blob/master/excalidraw-app/collab/Collab.tsx "Excalidraw client collaboration controller source"
[15]: https://github.com/excalidraw/excalidraw/blob/master/excalidraw-app/data/firebase.ts "Excalidraw encrypted persistent scene source"
[16]: https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/data/reconcile.ts "Excalidraw element reconciliation source"
[17]: https://github.com/excalidraw/excalidraw/blob/master/packages/excalidraw/data/restore.ts "Excalidraw document restoration source"
[18]: https://github.com/saber-notes/abstract_sync/blob/main/lib/src/syncer_component.dart "Saber abstract sync queue source"
[19]: https://github.com/saber-notes/abstract_sync/blob/main/lib/src/abstract_sync_interface.dart "Saber abstract sync interface source"
[20]: https://github.com/saber-notes/saber/blob/main/lib/data/nextcloud/saber_syncer.dart "Saber encrypted WebDAV adapter source"
