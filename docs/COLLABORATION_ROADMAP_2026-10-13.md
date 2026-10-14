# Drawing Notes 三端协同与 Rust 后端方案（2026-10-13）

基准：桌面 `drawing_notes_app` v1.17.65+134（master `6d0eff7`，第三轮审计批次 A 已闭环、批次 B 完成两条）；
网页版 `drawing_notes_web`（v4 样式 + 像素橡皮 + .excalidraw 旁路，待发新构建）。
输入：两份专家材料 —— ①「Flutter + React + Rust，统一协同协议」路线建议；②「最值得复用的 14 个开源项目清单」。

**状态：待裁决稿。** 本文件只提方案与验收口径，不含任何已实施的架构改动。§6 是需要业主拍板的六件事；
除 §6 第 5 条外，阶段 A（§3）与审计已有 backlog 完全重叠，可以立即开工。

---

## 0. 一句话结论

采纳专家主线：**Flutter/Dart 客户端 + React/TS 网页版 + Rust(Axum+Tokio) 后端 + PostgreSQL + 对象存储 + 版本化增量协同协议**，
按 A→B→C→D 四阶段从现有 v4 格式与 WebDAV 同步逐步升级，**不推翻现有代码、不 Fork 大型笔记应用**。

但有三条前提会直接决定路线能不能落地，且都已逐条核实（不是推测）：

| # | 前提 | 核实到的事实 | 对路线的后果 |
| --- | --- | --- | --- |
| P-1 | **端到端加密与「服务端合并 CRDT」互斥** | 现同步层是 AES-GCM + PBKDF2 600k，AAD 绑 docId/manifest，`remotePath = HMAC(key, id)`；服务器只见密文 | 只能走专家**方案 B**（服务端认证/排序/中继/存储，客户端解密合并）。Y-Sweet 的明文 CRDT 合并路径不能当生产依赖，只能当参考实现 |
| P-2 | **Dart 侧没有 Yjs** | 全仓无 CRDT 依赖；`lib/core/operation/` 只有自研操作模型 | Flutter 要用 Yrs 必须经 flutter_rust_bridge（Yrs 的 C FFI）。这是全案最大不确定项：Windows/Android 原生构建、内存释放、断线合并、三端字节一致，**必须 spike 先验**（§4-Spike A） |
| P-3 | **当前托管放不住后端** | Qoder Sites 该站点 `get_backend` 返回 `status: disabled`、`capabilities: []`；网页版 `functions/handler.ts` 是 15 行 stateless HTTP echo | 阶段 B 需要一个**部署决策**（自建 VPS/Docker？谁运维？），或把目标降级为「先做我的多设备，不做多人」 |

一句提醒（专家原话的本地化）：**Rust 负责跑得省、跑得稳；协议负责数据对不对**。P0 永远是并发/断线/恢复不丢内容，
这一点我们过去三天的整改（DN-201/202/204）已经在做，方向没错。

（**2026-10-14 更新**：三条前提里 P-2 的那次「必须 spike 先验」已经做完——结论是 **GO**，
纯 `dart:ffi` 就够，`flutter_rust_bridge` 不是必需项，但中继侧换来三条硬约束，见 §12.1。
P-1 里「Y-Sweet 的明文 CRDT 合并路径不能当生产依赖」这句现在是**实测**而不是推断：服务端存储里
连笔画 JSON 都原样可读，见 §12.2。P-3 那条外部故障（Sites 上传通道）仍在，见 §13。）

---

## 1. 现在已经具备的地基（都在仓库里，file:line 可查）

| 能力 | 位置 | 状态 |
| --- | --- | --- |
| 元素级版本与随机 nonce（协同裁决的原料） | `lib/core/canvas_model/shape_item.dart:132,148,282-283,318-319`（`version`/`versionNonce`/`bumpVersion()`）；网页侧同名字段已对称读写 `drawing_notes_web/src/core/codec.ts:461-462,546-547,747-748` | ✅ 两端一致，**阶段 A 不用新造字段** |
| 可序列化操作模型 | `lib/core/operation/document_operation.dart`（`sealed DocumentOperation` + `OpStrokeAdd/Remove/Replace/LayerProp/LayerReorder/OpBatch`） | ✅ 已有，但**没有 opId / 设备序号 / 因果依赖 / 内容摘要** |
| 有界影子操作日志 | `lib/core/operation/operation_log.dart`（JSONL 双向往返逐字节保真；刻意不驱动撤销，撤销仍由命令栈权威） | 🔶 **磁盘持久化与「同步网络侧消费」是 10-10 清单明写的排队项**（`docs/EXPERT_REVIEW_REMEDIATION_PLAN_2026-10-10.md:122-123`） |
| 格式版本与迁移框架 | `document_codec.dart: latestVersion=4`；`MigrationV3ToV4`（只删非法值、绝不补默认）；「只写偏离旧推导的键」不变式 + 跨端契约夹具（两端逐字节同一份语料库） | ✅ 加可选字段的先例与门禁都已成型 |
| 条件写入与「先保两端」纪律 | `sync_service.dart`：清单 CAS（DN-104）、首次创建 `If-None-Match`（DN-202）、文档级 HEAD 探测 + `If-Match` + 412 保两端（DN-201） | ✅ 与未来服务端的排序/CAS 语义**同一条纪律**，投资不作废 |
| 离线优先 + 恢复链 | 数据根、备份/恢复三态（DN-203）、恢复前快照保留（DN-208）、恢复后同步基线隔离（DN-204） | ✅ 「模式切换前先确认」已有样板实现 |
| 性能拐点的实测证据 | 5 万笔线性剔除 13.3ms/帧（已占 60fps 预算 80%）；codec 预算限制单文档 ≤1 万笔/≤100 万点 | ✅ 用来判断「要不要为 Rust 重写绘图」——**结论：不要** |

⇒ **阶段 A 不需要新架构，只需要给已有操作模型补上「身份 + 因果 + 摘要」三样东西**，
并顺手把审计剩下的 DN-206/DN-205/DN-207 一起销账（见 §3 阶段 A 的四条）。

---

## 2. 协同协议：把专家建议落到我们的模型上

### 2.1 分层：三类数据三种策略（采纳专家表，右列是本项目的具体对象）

| 数据类型 | 同步策略 | 本项目对应 | 取舍理由 |
| --- | --- | --- | --- |
| 块文档富文本（打字笔记） | CRDT 增量（Text/Map） | `note_block_doc_store` + 新增 `OpTextIntent` | 多人同时输入/插入/删除只有 CRDT 能收敛；**唯一需要引 CRDT 的地方** |
| 自由手绘笔画 | 笔画**完成后**提交增量对象 | `OpStrokeAdd/Replace` + `StrokeBuffer` | 不必逐帧发送整条历史；本地仍按 120fps 交互，网络侧按操作语义合批 |
| 形状/图层/绑定 | 元素级补丁 + `version`/`versionNonce` + 删除墓碑 | `OpLayerProp/Reorder` | **先不上 CRDT**（专家同判）。几何/层序/绑定的并发合并用元素级 LWW + 版本号已够，且能让 v4 文件继续被旧版本打开 |
| 光标、选区、视口 | 临时 WS 消息，不落库、允许丢 | 新 ephemeral 通道 | 不参与收敛，进数据库就是负担 |
| 图片 / PDF / 像素橡皮 ink buffer | 对象存储、分块或直传 | `storage_media_store`、DAN/DNV 附件 | 大文件绝不进实时消息内存队列 |
| 裁剪 | 维持「烘焙像素覆写同文件 + `.bak`」 | 已裁决 | 加 `crop` 元数据 = 第二套真相，已明确不做 |

### 2.2 操作包络要新增的最小字段集

```
opId        全局唯一操作 id —— 现有 LocalIdGenerator 只有时间戳+序号+熵，**没有设备身份**
deviceId    装机时生成一次并持久化（跨同步必须稳定）
actorSeq    每设备单调递增 —— 与 deviceId 组成幂等键
deps        因果依赖（该 op 基于哪些元素版本）
baseRev     CAS 锚点：服务端可校验顺序，但**不需要解密内容**
digest      内容摘要（DN-206 同一条，先在同步层落地，再复用到操作层）
tombstone   删除带因果信息（现在的 `deletedIds` 只是 id 集合，协同下会「幽灵复活」）
```
幂等与 ack 语义（专家点名的两处，这里写成硬规则）：
- 服务端按 `(deviceId, actorSeq)` 去重；重放同一操作序列必须得到同一结果。
- **服务端 ack ≠ 他端已应用**。UI/恢复逻辑都按「已送达」与「已收敛」两级状态建模。

### 2.3 端到端加密的边界（需要写进隐私承诺的裁决）

1. 服务端只做四件事：身份与权限、按 `(deviceId, actorSeq)` 的整数序排序、密文存储与转发、配额/限流。
2. 合并、解密、冲突裁决、快照压缩**全在客户端**（否则服务端必须持明文，与 P-1 冲突）。
3. **工程文件仍是唯一权威格式**，操作日志是旁路：快照 + 未合并操作即可重建，日志丢失不会让文档不可打开。
4. 元数据可见面要如实记录：服务器仍能看到账号、文档标识、连接关系、操作大小与时间。
5. **真缺口**：现在的同步口令派生「一人一库」单主密钥，多人协同需要 **per-doc key + 密钥共享/轮换**，
   目前完全没有。这是阶段 C 的前置条件，不是可以后补的细节。

### 2.4 不能同时留两条写路（本方案里风险最高的一条）

WebDAV 整篇 blob 同步与 op-log 服务同时写同一篇文档 = **两个真相源**，会以我们刚修完的那类缺陷重新出现
（静默覆盖、墓碑误删、基线落后）。裁决建议：

- 一篇文档任一时刻只允许一种协同模式；
- 模式切换必须走一次显式收敛（本地状态作为快照上传 + 清空待发送队列 + 基线重锚）；
- 切换要有用户可见的确认，不能后台自动改。
  样板就是刚做完的 DN-204「恢复后基线隔离 + 方向选择」：判据从磁盘事实反推、未确认则一字节都不写。

---

## 3. 四阶段实施顺序（每阶段都可机器判定验收）

### 阶段 A：格式与协议地基 —— 与审计 backlog 完全重叠，可立即开工

| 条目 | 内容 | 与 backlog 的关系 |
| --- | --- | --- |
| A1 | `digest` 进 `SyncSnapshot`；`sameTsDiverged` 判据从「同 ts 不同 size」扩到「同 ts 同 size 但摘要不同」；旧清单缺字段一律按**不可比**处理（绝不能用 `==` 判不同，否则制造假冲突）；`_encodedCache` 编码时顺带算摘要（它本来就要编码一次算 size） | **= 任务 #18（DN-206）**，销账即交付 |
| A2 | 操作日志磁盘持久化 + 幂等重放：崩溃恢复矩阵钉在四个窗口（写 tmp / 改名 / 发送 / ack） | 10-10 清单排队项 + **批次 D** 的前半 |
| A3 | 删除墓碑带上因果与版本（`deletedIds` 从 `Set<String>` 演进为带 `deps/baseRev` 的结构，保持 JSON 向后兼容） | 新提，属本方案 |
| A4 | 写路径统一契约（懒迁移收进 `_writeFileAtomic`）+ 可注入时序屏障收敛异步错误 | **= 任务 #17/#19（DN-205/DN-207）** |

验收：① 三端（Windows / Android / 网页 TS 侧）对同一批操作重放得到**逐字节相同**的文档；
② 旧版本仍能打开新文件（可选字段 + 迁移框架）；③ `flutter analyze` 0 issues、全量 `flutter test` 绿、
跨端契约 gate（`tools/interop/check.mjs` + 桌面夹具测试）绿。
门禁影响：新增一条「协议一致性」gate（先本地脚本，形态照现有 interop/excalidraw check），CI 矩阵暂不动。

### 阶段 B：最小服务端 —— 依赖 §6 的部署决策

技术栈：Axum + Tokio + PostgreSQL + S3 兼容对象存储；**单个模块化服务**，不拆微服务、不引 Redis/NATS。
「有界内存」要写成可断言的规则，不是口号：
- 每个 WS 连接的收发缓冲有固定上限（Tokio 侧用有界队列 + 背压）；
- 房间按需加载活动状态，无人后释放；
- 慢客户端：先背压，超阈值要求重同步（不是无限排队）；
- 图片/PDF 字节不进消息队列，走对象存储直传 + 能力令牌。

首版三件事：设备令牌与鉴权、文档 op-log CRUD（`baseRev` CAS）、WS 房间（密文转发 + ack）。

验收：断网编辑 30 分钟后恢复 ⇒ 所有已持久化操作最终送达且不重复执行；
服务端重启/数据库抖动后，已确认提交可恢复、未确认操作可重试。

### 阶段 C：三端实时协同

- C1 画布：元素级 op + 版本裁决（**不引 CRDT**），先打通两台设备同一画布，每端都要能保住自己的内容（沿用 412 保两端纪律）。
- C2 文本：Yjs(Web) ↔ Yrs(Flutter via FRB)。**先跑 Spike A 再决定**；失败退路有两条，都写明：
  ① 文本也走 op-log + 服务端排序 + 客户端自研合并；② 同一段文本同一时刻单编辑者（软锁）。
- C3 光标/选区/视口 ephemeral 通道。
- C4 per-doc 密钥共享与轮换（§2.3 第 5 条的缺口）。
- C5 冲突选择 UI —— **内核清单里 P1-⑤ 早就排着**，届时一并做。

验收：专家给的「3 端同编辑同一文档 ⇒ 最终状态一致，不静默丢笔画」，用确定性并发 harness 断言（不是拿 pump 时长赌竞速）。

### 阶段 D：压测后再扩容

先测再决定：RSS / CPU / 网络流量 / 消息吞吐 / 数据库压力 → 才谈 Redis/NATS、水平分片、独立协作节点。
分档目标：3 端同编辑 → 50 人协作 → 1000 并发连接（测实际 RSS）→ 10000 长连接（跨节点验证，不预设单机能承载）。
绘图帧率与网络发送频率分离；两端继续做可视区渲染 + 空间索引 + 大文档惰性加载（空间索引 P0-3 尚未开工，与本阶段无关但要一起排期）。

---

## 4. 三个 spike：先拿证据再定案（每个 1–3 天，互不依赖，可并行）

| Spike | 要回答的问题 | 判据 | 失败时的退路 |
| --- | --- | --- | --- |
| **A：Dart ↔ Yrs 桥** | flutter_rust_bridge 把 Yrs 编进 Windows + Android，三端在同一份 `Y.Text` 上更新能否收敛到**字节一致**；原生构建、内存释放、断线合并是否可控 | 一段真实中文打字笔记，3 端并发编辑 50 次操作 ⇒ 三端文本逐字节相同且无泄漏 | C2 改走「op-log + 自研合并」或「单编辑者软锁」 |
| **B：Y-Sweet vs 自建 Axum 密文中继** | 同场景（1000 长连接 + 有界队列 + 背压）实测 RSS/延迟/恢复成本；并验证「服务器不理解内容」在 Y-Sweet 上是否根本做不到 | 两张对比表 + 一条端到端加密能否保住的结论 | 若 Y-Sweet 不能保 E2EE ⇒ 只借其 sync 语义，中继自建（当前主判断即此） |
| **C：增量协议草案双实现** | 画布元素 op 集在 TS + Dart 各实现一遍，用现有跨端契约夹具断言「同一操作序列 ⇒ 同一字节」；顺带定 v4 与 op-log 的兼容/压缩策略 | 现有 11 份夹具全部通过 + 新增「操作重放」夹具一族 | 说明 op 粒度选错，回到元素级补丁 |

三个结论写回本文件 §7，再定稿路线。**这一节的目的是避免「先宣布架构、再找证据」。**
（2026-10-14：**C、A、B 三条都已有实测结论**——C 在 §7，A、B 在 §12。B 那条判据只兑现了
一半：端到端加密的结论拿到了，两张性能对比表在自建中继有代码之前没有可测对象，那一格留着。）

---

## 5. 明确不做的事（含许可证边界，按专家清单落地）

> 下表涉及的许可与活跃度，逐条核实过程与出处见 **§8 附录**；此处只写结论。

- **不 Fork** 整体应用：AFFiNE（分目录授权，`packages/backend/server/LICENSE` 有 EE 限制）、
  AppFlowy（AGPL-3.0）、Saber（GPL-3.0）、BlockSuite（MPL 2.0）只读架构与算法思路，复制代码进产品前先过许可评估。
- **不引 AppFlowy-Cloud** 作生产协同服务器：上游已标为不再维护，新云端转向闭源。
- **不同时引三套 CRDT**（Yjs / Loro / Automerge）。只保留一套，由 Spike A/B 决定；Loro 与 Loro-Excalidraw 只作 PoC 对比参考。
- **不为用 Rust 而重写 Dart 绘图内核**（专家同判）。触发条件要具体证据：10 万笔级投诉，或产品定位转「专业绘图」。
  现有实测拐点：5 万笔线性剔除 13.3ms/帧。
- **生产不用 tldraw**（SDK 默认许可仅允许开发环境）；**不碰 BlockNote XL**（GPL-3.0/商业授权）。
- 不把工程文件降级成「CRDT 快照的导出物」；工程文件仍是权威格式。
- 不把裁剪做成元数据字段（已裁决：烘焙像素 + `.bak`，避免第二套真相）。
- 现在**不**把仓库拆成 monorepo（专家的 `apps/ services/ packages/` 目录形态作为目标形态，等阶段 B 有真实服务端代码再迁）。

最终深入研究清单收敛为五个：Excalidraw（网页编辑器与 element 几何）、Yjs/Yrs（协同内核）、Y-Sweet（同步语义参考）、
flutter_rust_bridge（桥接）、Axum/Tokio（自有后端底座）；BlockSuite 与 AFFiNE 作产品与模块边界参考。

---

## 6. 需要业主拍板的六件事（每条都给了默认建议）

| # | 决定 | 我的默认建议 | 不定会卡住什么 |
| --- | --- | --- | --- |
| 1 | 产品目标是**多人实时协同**，还是**我的多设备**优先 | 先「我的多设备」 | 阶段 B 的最小集与是否需要账号体系 |
| 2 | 确认隐私承诺走**方案 B**（服务端只见密文） | 确认（现状已是 E2E，退回不划算） | Y-Sweet 能否直接用作依赖；C2/C4 的设计边界 |
| 3 | 后端部署在哪、谁运维（Sites 托管已核实 `disabled`） | 自建 Docker/VPS，先单实例 | 整个阶段 B 能否开工 |
|   | **→ 2026-10-14 更新**：本机已核实存在一条在用运维轨道（阿里云 + pm2 + Cloudflare + R2 + WS 房间），本条已从「要不要自建」变成「复用还是另起」，三个落法与默认建议见 **§11** | | |
| 4 | 引入 op-log 后 v4 是否 bump 到 v5 | **不 bump**：可选字段 + 快照仍权威 + 迁移框架兜底 | A1/A3 的落盘格式与夹具基线 |
|   | **→ 2026-10-14 更新**：Spike C 的重放夹具证明 op-log 是文档之外的旁侧文件，重放不动 `version` 语义 ⇒ 本条按默认执行，见 **§7.3** | | |
| 5 | 是否接受 Rust 工具链进 CI（原生构建矩阵、缓存、时长） | 先把 Spike 放本地/夜间任务，阶段 C 定型后再进 CI | Spike A 的验证方式与成本 |
| 6 | 阶段 A（= DN-206/205/207 + A2/A3）现在是否开工 | **开工**，它与既有审计 backlog 完全重叠，不需新决定 | 无 —— 这一条只是走个确认 |

另外两件与本方案无关但悬着的：网页版新构建仍卡在 Sites 上传通道故障（2026-10-14 再次核实：
`get_publish_status` 报 `sites_action_unavailable`，站点元数据读取正常 ⇒ 通道故障，不是配置问题，
恢复后用同一 actionId 重放）；批次 A/B/D 这批已经收进 **v1.17.66+135** 并于 2026-10-14 推 tag、
发 Release、四件资产齐（本条悬案已结，桌面侧后续提交不再自带发版）。

---

## 7. spike 结论

- Spike A（Dart ↔ Yrs）：**2026-10-14 做完，GO，结论与三条中继约束在 §12.1**
- Spike B（Y-Sweet vs 自建密文中继）：**2026-10-14 做完，Y-Sweet 当不了密文中继，证据在 §12.2**
- **Spike C（增量协议双实现字节一致）：2026-10-14 做完，结论是「op 粒度没选错」，
  但挖出三条必须写进阶段 A 协议条款的账。** 判据里那条「新增『操作重放』夹具一族」已落地。

### 7.1 这一版拿什么当证据

| 件 | 位置 | 作用 |
|---|---|---|
| TS 侧第二实现 | `drawing_notes_web/src/core/operations.ts` | 与 Dart `document_operation.dart` 并列的 6 个 typeKey 的 apply/revert/fromJson/toJson，**不是**参考实现 |
| 规范化 + 摘要（TS） | `drawing_notes_web/tools/replay/canonical.mjs` | 规格全文写在文件头，代号 `spikec-1` |
| 规范化 + 摘要（Dart） | `test/core/operation/replay_canonical.dart` | 同一份规格的另一侧实现，两端不互相 import |
| 重放夹具 9 例 | `drawing_notes_web/tools/interop/fixtures/replay-*.json` + `replay-manifest.json` | 与 v3 契约夹具同目录，因而**自动进那条跨仓逐字节比对** |
| 跑法 | 网页 `npm run check:replay`（`--bless` 重定期望值）；桌面 `flutter test test/core/operation/replay_parity_test.dart` | 每例断言三个摘要：初始 / 正向重放 / 逆序回退 |

实测：网页侧 9 例全绿、桌面侧 43 条断言全绿（同一批文件）。突变自证：把 Dart 侧
`toStringAsFixed(6)` 改成 `(4)` ⇒ 34 条红。⇒ 摘要真的在守门，不是摆设。

**一处必须说出来的脆弱（2026-10-14 已解除）**：`drawing_notes_web` 目录当时**不是 git 仓库**
（有 `.gitignore`、无 `.git`），所以 `src/core/operations.ts` 与 `tools/replay/*.mjs` 这两件
TS 侧的实物只有本机一份，进了版本库的只有共享夹具（`test/fixtures/v3/replay-*`，与网页侧逐字节
一致）和 Dart 侧实现。规格文本在 `replay_canonical.dart` 与 `canonical.mjs` 的文件头各抄了一份，
代号 `spikec-1` 对不上就会红，但**镜像实现本身没有备份**。
⇒ 已给网页工作区建仓：`drawing_notes_web` 现为 git 仓库，首提交 `2b5bbd7`（130 个文件，
排除 `node_modules/`、`dist/`、`tmp/` 与站点描述符 `*.qoder.site`；无远端、未推送）。
镜像实现从此有历史可回溯。

为什么要中间那一层规范化：两端落盘 JSON 本来就不可能逐字节相同（Dart 把整数线宽写成
`2.0`、TS 写成 `2`；键序与可选键取舍也各有习惯）。把状态压成 `f6` 定长文本再取 SHA-256，
就把「数字怎么写」这个已知分歧从比较里剥掉，只留「数字是什么」。`-0` 坐标专门做了一例探针：
两端 `toFixed(6)` / `toStringAsFixed(6)` 给出同一个串，摘要一致 ⇒ 这条规范化站得住。

### 7.2 挖出来的三条账（都要进阶段 A 的协议条款）

1. **每个端都有两条解析腿，混用会互相掩盖。** 整份文件走宽容回读（预算裁剪、非法点丢弃、
   opacity clamp），操作体走严格解析（对应 `Stroke.fromJson`：`width=0`、`opacity=1.7`、
   遗留对象点列、末尾不足三点的点列、未知笔刷名，全都**照收**）。第一版镜像实现顺手用了
   宽容腿，`replay-strict-ops.json` 一跑就把这个分歧暴露出来——这条夹具从此钉住「操作体
   不经过预算裁剪」。含义：服务端收到的 op 体**不会**因为超预算被静默改写，预算只在落盘/解码时生效。
2. **随机身份会让重放不可复现。** `id` 或 `seed` 缺失时，两端的构造器各自随机生成
   （Dart `LocalIdGenerator.next('str')` / TS `newId`），重放摘要必然不同。⇒ 协议条款：
   **操作体必须自带 `id` 与 `seed`**，服务端与回放器都可以按「缺即拒绝」处理（`replay-manifest.json`
   的 notes 已写死这条，夹具 accordingly 全带 id/seed）。
3. **失败不是原子的，而且这个「不原子」现在两端同形。** Dart 的 `layer.reorder` 先 `removeAt(from)`
   再 `insert(to, l)`，`to` 越界时不回滚 ⇒ 文档少一层。镜像实现照搬（没有顺手改成原子的），
   `replay-errors.json` 里那条 `digestAfterError` 钉的就是抛完之后那个「少一层」的形状。
   含义：op-log 回放中途抛错**不能**继续往下回放，必须整份放弃、回退到文档权威态
   （A2 读侧那条 `baseRev` 截断正是这个用途）。
4. **顺带一条潜在分歧（本次夹具没打到，但已定位）**：`stroke.remove` 的 revert 依赖
   「按图层分组 + 组内按 `index` 升序」。同一图层里出现**重复 index** 时，还原顺序与原始顺序
   **不同**（`replay-duplicate-index.json` 实测：回退后摘要 `7e5b8c…` ≠ 初始 `a3922d…`），
   两端目前一致，是因为两侧都落到**稳定**排序（JS `Array.sort` 自 ES2019 要求稳定；Dart 对
   ≤32 条走插入排序，稳定，阈值见 `D:\flutter\bin\cache\dart-sdk\lib\internal\sort.dart:18`）。
   **条目数 >32 时 Dart 换双轴快排，不稳定 ⇒ 两端可能分叉。** 现网擦除手势按命中序记录，
   并不保证 index 严格递增，所以这不是假想问题。阶段 A 要做的收敛：记录时把同图层的条目
   按 `index` 规范化（严格递增），使 revert 不再依赖排序稳定性。本轮**没有**改记录侧。

### 7.3 判据回看

§4 那条判据是「现有 11 份夹具全部通过 + 新增『操作重放』夹具一族」。实际达成：
`check:interop` 11 例 + 预算 14 项绿，`check:replay` 9 例绿，桌面 43 条断言绿。
⇒ **失败退路（「说明 op 粒度选错，回到元素级补丁」）不启用**：元素级（stroke/layer）寻址
+ 完整笔画负载这条形状，两端可以逐字节重放同一份操作序列。v4 与 op-log 的兼容策略随之
可以定：**不必 bump v5**——op-log 是文档之外的旁侧文件，`version` 仍是文档格式的版本，
§6-④ 那条拍板因此有了默认答案（除非要改的是文档内字段本身）。

---

## 8. 附录：参考仓库地址与许可核实（2026-10-13 逐条 GitHub API 核对）

下面每条都是当场用 `gh api repos/<o>/<r>` 加读仓库根 `LICENSE*` 文件核出来的，**不是转述**：
许可取 API 的 `license.spdx_id`；API 判为 `NOASSERTION`（分目录/自定义授权）的，一律再读许可证正文首行确认；
活跃度取 `pushed_at`，是否废弃取 `archived`。

| 定位 | 仓库 | 许可（核实） | 最近推送 | 对 Drawing Notes 的用法边界 |
| --- | --- | --- | --- | --- |
| 网页版绘图编辑器（**已在用**） | https://github.com/excalidraw/excalidraw | MIT | 2026-10-12 | 我们的 `.excalidraw` 只读旁路与元素语义对齐就是它；改它不如适配它 |
| 元素冲突协调读码 | excalidraw `packages/excalidraw/data/reconcile.ts` | MIT | 同上 | 只借冲突规则的**形状**（version/versionNonce/元素级裁决）；不能改名后直接套到文件级同步（专家同判） |
| 房间 + 密文中继原型 | https://github.com/excalidraw/excalidraw-room | MIT | **2024-07-12** | 休眠约 15 个月 ⇒ 只当读码参考，不作依赖 |
| 一体化笔记架构 | https://github.com/toeverything/blocksuite | MPL-2.0 | 2026-10-05 | 只读块模型与编辑命令架构；MPL 是文件级 copyleft（改哪个文件就公开哪个文件） |
| Web 侧协同内核（阶段 C2 首选） | https://github.com/yjs/yjs | MIT（正文首行 `The MIT License`；API 判 NOASSERTION） | 2026-10-07 | 只用于**块文档富文本**；画布不上 CRDT |
| Rust 协同内核 | https://github.com/y-crdt/y-crdt | MIT（正文首行 `The MIT License`） | 2026-09-30 | 根目录就有 `yrs` / `yffi`(C FFI) / `ywasm` / `tests-ffi` / `tests-wasm` ⇒ Spike A 的原料现成 |
| 现成协同服务器 | https://github.com/jamsocket/y-sweet | MIT | **2025-12-04** | 常规路径要服务端理解明文更新 ⇒ 与 P-1 冲突：**只借 sync 语义与有界队列写法，不作生产依赖** |
| 后端框架 / 运行时 | https://github.com/tokio-rs/axum · https://github.com/tokio-rs/tokio | MIT · MIT | 2026-10-11 · 2026-10-12 | 阶段 B 底座；axum 自带 `examples/websockets` 与 `examples/testing-websockets` 可当起点 |
| Dart ↔ Rust 桥 | https://github.com/fzyzcjy/flutter_rust_bridge | MIT | 2026-10-10 | 只在 Spike A 用；不要顺手把绘图内核搬进 Rust |
| 对比候选 CRDT | https://github.com/loro-dev/loro · https://github.com/loro-dev/loro-excalidraw | MIT · MIT | 2026-10-09 · **2024-10-29（53★）** | 与 Yjs 二选一，**绝不并引**；loro-excalidraw 官方自标 PoC，只借适配思路 |
| 第二候选 CRDT | https://github.com/automerge/automerge | MIT | 2026-10-13 | 纳入 Spike B 的内存基准对比，不与 Yjs 混协议 |
| 块编辑组件（Web） | https://github.com/TypeCellOS/BlockNote | **混合**：核心 MPL-2.0；`packages/xl-*` / `@blocknote/xl-*` 为 GPL-3.0 或商业授权（照 `LICENSE.txt` 原文） | 2026-10-12 | 只用非 XL 包；用到 XL 能力就要么承担 GPL 要么买授权 |
| 产品与模块边界参考 | https://github.com/toeverything/AFFiNE | **分目录授权**（API 判 NOASSERTION）；`packages/backend/server/LICENSE` 已核实存在 | 2026-10-12 | 只读产品结构；**禁止整仓搬后端**——服务端目录另有专门限制 |
| Flutter + Rust 工程组织 | https://github.com/AppFlowy-IO/AppFlowy | AGPL-3.0 | 2026-10-08 | 我们自己要部署后端 ⇒ AGPL 的网络分发义务正中要害，**只读思路，不复制代码** |
| ~~生产协同服务器~~ | https://github.com/AppFlowy-IO/AppFlowy-Cloud | AGPL-3.0，**`archived: true`（API 已证实）** | 2026-09-11 | 专家「上游已停维护、新云端转闭源」这条在 API 上可直接证实 ⇒ 不能用 |
| 手写/分页笔记 + WebDAV 同步 | https://github.com/saber-notes/saber | GPL-3.0 | 2026-10-02 | 与我们的 WebDAV 路线最像，重点读它的同步与文件兼容处理；GPL 同样只读不搬 |
| 无限画布交互设计 | https://github.com/tldraw/tldraw | **专有（tldraw License，`LICENSE.md`）**：仅许可 Development Environment（内部开发/测试/staging，不得对终端用户或公众开放），生产需 License Key / 商业授权 | 2026-10-12 | **生产不能用**；只读选择/变换等交互设计 |

三条通用结论：

1. **许可不是标签，是义务形态**：MIT 随便用；MPL-2.0 文件级 copyleft；GPL/AGPL 会把义务扩散到整个组合作品，
   AGPL 还额外覆盖「通过网络提供服务」——本项目阶段 B 正是要自己提供网络服务，所以 AGPL 依赖按红线对待；
   tldraw 这类专有许可连生产环境都要单独买。
2. **`archived` 与 `pushed_at` 是可核事实，不必采信二手说法**：AppFlowy-Cloud 的 `archived: true`、
   excalidraw-room 与 loro-excalidraw 停在 2024 年，直接决定它们只能当读码材料。
3. **最终深入研究五个**：Excalidraw、Yjs/Yrs、Y-Sweet（仅参考）、flutter_rust_bridge、Axum/Tokio；
   BlockSuite / AFFiNE / AppFlowy / Saber 当架构与产品参考；Loro / Automerge 只在 Spike 里对比，
   **对比完只留一套内核**。

---

## 9. A2 落盘形态定形（写代码之前先钉死，避免边写边猜格式）

A2 = 操作日志磁盘持久化 + 幂等重放（任务 #22；也是 10-10 内核清单明写的排队项）。
现状：`lib/core/operation/operation_log.dart` 已有有界内存日志 + `toJsonl/fromJsonl`
逐字节往返，`drawing_controller_history.dart:15` 在命令提交点成对记录，
但**从不落盘**，也没有「这条操作属于哪篇文档的哪个版本」的坐标。
落盘形态一旦定错，会把两个已经修好的机制重新打开，所以先写清四件事：

1. **落点：数据根内的 sidecar 目录** `oplog/<docId>.jsonl`（不进 `documents/`，
   与文档文件同根不同目录）。选它而不是数据根之外，理由就是 DN-204 那条：
   备份包打包的是数据根，日志在根内 ⇒ 恢复旧库时日志**自动跟着回退**。
   若落在根外（像 `sync_state.json` 那样），就会出现「恢复出来的旧库 + 新日志」
   这种第二套真相，而那是本轮刚花两条提交堵住的那类缺陷。
   配套要求：`.old_<毫秒>` 恢复前快照与 DN-204 的隔离判据天然覆盖它，无需新代码。
2. **每行的信封字段 = `docId` + `seq` + `baseRev`，操作 payload 原样不动。**
   `seq` 每文档单调递增，`baseRev` 是该操作所基于的文档 revision（元素级已有
   `version`/`versionNonce`，文档级 revision 取现有 `updatedAt` + 摘要）。
   ⇒ **不改工程文件格式、不 bump v5**：这些键只活在日志里，旧版本读不到日志也照常打开文档。
3. **幂等与读回规则（可机器判定）**：
   - 读回时以盘上文档的 revision 为界，丢掉 `baseRev` 超前于它的尾巴
     （文档写了、日志没写 = 少几条操作；日志写了、文档没写 = 幻影操作。
     两者都不可逆，但后者会让重放造出不存在的内容 ⇒ 一律以文档为权威）；
   - 同一 `seq` 区间重放两次必须得到同一状态（重复投递、重复读取都算）；
   - 未知操作类型仍抛 `FormatException`——日志重放不容静默丢弃（现有语义保留）。
4. **四个崩溃窗口各钉一条确定性用例**（写 tmp / 改名 rename / 发送 / ack）：
   前两个是本批能落地的（用 DN-207 刚立的时序屏障手法，不靠调度碰运气）；
   后两个要等服务端协议到位，**在它们有真实实现之前不写占位断言、也不在提交里声称已覆盖**。

另外两件顺手要定的：
- **滚动与上限**：单文档日志超过 N 行或 M 字节时做一次「压缩」= 以当前文档快照为界
  截断前缀（快照即权威，截掉的是已经体现在盘上状态里的操作）。N/M 取保守值并在测试里钉住，
  避免变成又一处无界增长（内存有 `_capacity=2000` 的纪律，磁盘侧也得有一条）。
- **加密**：sidecar 走与文档同一套 DNV 信封（AAD 绑 `oplog:<docId>`），
  不给「日志是明文」留第二条降级通道——写路径的契约统一（批次 C）同样适用于新文件类型。

## 10. A2 / A3 落地进度（2026-10-14 实测；A2 那半已闭合，剩的是「有没有读者」）

### A2 操作日志落盘 —— 存储面与保存路径**两半都已闭合**（接线于 2026-10-14 落地）

`lib/core/operation/operation_log_store.dart` + `test/core/operation/operation_log_store_test.dart`
（17 条用例，CI 7/7 绿于 `a091d9b`）。§9 定的四件事逐条对上了：落点 `oplog/<docId>.jsonl`
在数据根内、信封键只活在日志行、`baseRev` 超前于盘上 revision 的尾巴在**读侧**丢弃、
两个崩溃窗口用可注入时序屏障 `writeBarrierForTest` 钉死（发送 / ack 那两条仍按 §9
的约定不写占位断言）。四条突变各自只让对应的用例变红。

**接线（本轮补齐的那半）**，三件：

1. `operation_log.dart`：日志条目带上单调 `serial`，新增 `entriesSince(serial)`。
   容量截断时**序号不清零**——水位线要能区分「同一条记录」与「同内容的新记录」，
   否则被截掉的那一段会被当成已落盘。
2. `lib/core/operation/operation_log_recorder.dart`（新，落在 `core/operation`，
   **不进 `editor_page` 库**）：按文档维护游标（`flushedSerial` / `seqBase` / `owner`），
   三条契约——①这一轮没有新操作 ⇒ **连 store 都不构造**（用例注入计数工厂，断言
   `built == 0`：没有新操作却不碰盘也要付一次解析目录 + 读盘的代价）；②水位只在写成功
   那一格前进，锁定、`append` 抛错、侧车读不懂三种情形都停在原地下一轮补齐，且
   **不把猜来的号段起点缓存下来**；③侧车任何失败都不许挡住正文保存，失败进
   `AuditLogger`，同一段停滞只报第一次（否则每 5 秒刷一条）。
3. `StorageService.saveAndLog(doc, log)` + `editor_page_persistence.dart:147` 的自动保存
   改走它。`revision` 取在 `save` **之前**（用例钉语句顺序，因为侧车记的必须是正在落盘
   那一版的号）；侧车的加密判据复用同一条 `vaultConfigured`，不另开一条通道。

**棘轮基线没动**：`editor_page` 库仍是 **7119 / 7120**。落点选在「替换一行既有语句」
而不是新增，recorder 因此放进 `core/operation`——这也顺带避免了 core 反向 import feature。

原先那两条不接的理由，现在一条解除、一条仍然成立，都写清楚：

1. ~~只剩 1 行余量~~ ⇒ 已用「净 0 行」的落法绕开，没有抬基线、没有搬代码。
2. **仍然没有读者**：中继（阶段 B）还没开工，`oplog/*.jsonl` 目前只有测试在读。
   ⇒ 代价是可控且有界的：契约①保证「没画就不碰盘」，`append` 虽是整份重写，
   上限被 `OperationLogLimits.standard`（256 条 / 64 KB）钉住，最坏情况是每 5 秒
   一次 ≤64 KB 的重写，且只在真有新操作那几轮发生。收益要等阶段 B 才兑现。

**已知边界（接线时就说清的）**：

- 只有走 `_persistArtwork` 的画布自动保存带上操作日志；其余仍调裸 `save` 的写入点
  （`lib/features/notes/**` 的笔记本集合页、`app_shell_routes.dart` 的草稿）没有
  `OperationLog` 实例可传，本轮未接。**笔记本入口照旧，没有动它。**
- 游标表 `_cursors` 按文档只增不减（进程内，`putIfAbsent` 唯一入口），关掉文档不清理。
  量级是每文档几十字节 + 一个 `_Cursor` 对象；等阶段 B 有真实的多文档数量上限再决定收不收。

门禁：`flutter analyze` 全项目 **0**（`spikes/**` 已进 `analyzer.exclude`，一次性脚本的
`print` 不该把 spike 代码诱进 `lib/`）、`flutter test` **2585 条全绿（1 skipped）**、
棘轮用例绿。突变自证 **M1–M9 九条各自只让对应那一条用例变红**（锚点与预期红项都写在
测试文件头注释里；跑批脚本是一次性工具，没进仓库）。

### A3-1 墓碑带因果 —— 已闭合（信息面），CI 待回

`SyncTombstone{id, deletedAt, baseRev}` + `SyncManifest.tombstones`，manifest.json
前后向兼容（旧清单读成「无因果」；没有删除时写出的 JSON 逐键与旧版一致，用例断言
`tombstones` 键根本不出现）。回写远端清单不再把删除历史抹平——那是乒乓的机械根因。
`deletedIds` 仍是「是否已删」的唯一裁决源，`tombstones` 只是它的富信息侧。

### A3-2 裁决与实施状态：甲已落地（`8580c25`），乙仍未做（它会移除用户内容）

判据已实现并有读者（`lib/core/sync/remote_deletes.dart`：`RemoteDeleteKind.{staleCopy, localHasEdits, unknowable}`），同步摘要里已经把三类分开报出并明确写着「本机没有删掉任何东西」——也就是**丙 的那半已经在**。甲/乙 多出来的那半（真的不再复活 / 真的删本地）仍未做。

现在能判、不能动。判据已就绪：本地那份 == 我自己的基线 ⇒ 陈旧副本，云端删除权威；
本地 != 基线 ⇒ 删除 vs 编辑，本地有独有内容。三种可执行的出口，请点名选一种：

- **甲（已实施，`8580c25`）陈旧副本不复活 + 编辑冲突保两份**：陈旧副本停止上传（不删本地，
  只在同步摘要里写明「云端已删除、本地仍是旧版」），真有改动的仍按本地保留上传。
  无销毁动作，代价是那篇文档在两端各留一份、状态长期不对称，且要在摘要里持续可见。
- **乙 删除权威 + 自动留副本**：陈旧副本按删除清掉本地文件，有改动的另存副本后清掉
  原件。语义最干净，但它是**程序主动删掉用户画布**，需要明确的同意与一次可回退窗口。
- **丙（被甲包含，不再是独立选项）**：保持今天的复活行为，仅把「远端删过、本地还在」按三类
  显示出来。最保守，乒乓继续，但删除历史与分叉形状已经可见。

**甲实施时补上的第二条判据腿（关键）**：抑制上传之后，本地基线里**不会再有这篇**
（基线沿用来自云端清单的形状），所以只靠「本地 == 我的基线」这一种证据会失效——
第二轮就退化成 `unknowable ⇒` 照常上传，变成隔一轮复活一次的振荡。现在优先级是
「先结构、后因果」：基线可用时以基线为准；基线不可得时用墓碑锚
`baseRev`（+ 新增的 `baseSize`）判定「本机这版就是被删那一版」。`updatedAt` 是
文档自己的字段、同步过之后两端拿到同一个数，所以它跨设备可比（P2 那条教训针对的
是判定时各读各的钟，不是这个）。`baseSize` 是必要的第二条腿：只比时间戳时，
「同一毫秒又存了一次、字节数恰好没变」的真编辑会被误判成陈旧而被无限期按住不上传。

**边界（甲不做的事）**：`localHasEdits` 与 `unknowable` 都**照常上传**——缺信息永远不
收紧成「不上传」，否则一篇正常文档会被无限期停止同步；抑制也**绝不**触发任何本地删除，
被按住的 id 每轮都在同步摘要里重复出现（`syncResurrectionHeld`）。

### §10 附记：第二层防御经核实**不成立**，改成堵删除路径的漏口（本批提交，hash 见 CHANGELOG 1.17.66 条目的关联提交列表）

原计划还要加一条：列表把「主文件没了但 `.bak` 还在」当成「文档存在」而不是「已删除」，
这样任何让正文消失的成因都不会再被同步推成删除墓碑。**逐条核实后否决了这个做法**——
用户主动删除后 `.bak` 会合法残留，放宽列表等于把已删内容复活：

- `note_block_doc_store_trash.dart` 的 `_removeBak` 把所有失败**静默吞掉**；且 rename
  失败的回退分支以前**根本没调** `_removeBak`；
- `storage_trash_bin.dart` 在正文已 rename 进回收站**之后**才删侧车，且那次删除
  没有 try ⇒ 抛出来就是「调用方看到删除失败、文档却已消失、种子留在原地」；
- 两族的删除入口都有 `if (!file.existsSync()) return false` ⇒ 「只剩侧车」那一格
  **删都删不掉**；
- 只有 notebook 家族（`notebook_storage_io.dart:78` 起）本来就是「正文或侧车都算存在、
  删就一起删、失败落审计」——那才是对的形状（它那句「旧备份不再参与加载」的注释是错的，
  `notebook_storage.dart:224` 确实会回退读 `.bak`，已改）。
- 另一个盲区：`storage_media_store.dart` 的托管图片回收同样只认 `.json` ⇒
  「只剩侧车」的画布其图片会被当孤儿**回收掉**（图片是真没了）——**同批已修**：
  引用面认「正文缺失而有侧车」那一篇，同时保留「正文在时上一版侧车不算引用」的
  边界（否则每次成功保存留下的上一版会让回收退化成只增不减）。两条边界各配一道
  突变自证。

⇒ 本轮把上面四个漏口堵掉（删除一定带走侧车 + 只剩侧车也删得掉 + 失败留审计
`note_block_doc.delete.bak_left` / `trash.delete.bak_left`），而不是放宽列表语义。

混合版本集群的已知降级面：尚未升级的旧客户端写清单时仍会抹掉墓碑，所以新代码将来
读 `baseRev` 时必须按「可能缺失」处理，缺失就退回今天的保守行为（A3-1 已把这条形状
钉在用例里）。

---

## 11. §6-③ 的实测答案：本机已有一条跑得通的运维轨道（2026-10-14 核实）

原 P-3 写的是「当前托管放不住后端 ⇒ 阶段 B 需要一个部署决策」。**前半句仍然成立**
（Qoder Sites 该站点 `get_backend` 依旧 `disabled`），但后半句要改写：业主已经有一条
在用的部署轨道，只是它不属于本仓库，所以此前没进过这份方案。

### 11.1 核实到的事实（逐条回查过文件与进程，不是推测）

| 项 | 事实 | 出处 |
|---|---|---|
| 项目 | 同工作区父目录下的另一个产品 `dream-gallery`（B612 画廊），与本项目无代码关系 | `D:\Workbuddy\2026-08-29-08-24-29\dream-gallery` |
| 此刻在跑 | 本机 3000 端口 `node server.js` 正在 LISTENING（PID 29184），另在 3443 挂 HTTPS 回源 | `netstat` + `Get-CimInstance Win32_Process` 实测 |
| 生产部署 | 阿里云 Ubuntu：`_setup_server.sh` 装 Node 22 → 解压到 `/opt/gallery` → **pm2** 常驻 + `pm2 startup systemd` + `ufw allow 3000` | 该目录 `_setup_server.sh` |
| 边缘与域名 | Cloudflare 边缘 `cloudbear.cloud`，Origin CA 证书做「边缘↔源站全加密回源」；CSP 里 `connect-src` 已含 `https://cloudbear.cloud` | `server.js:123-134`、`lib/config.js`、响应头实测 |
| 对象存储 | 已在用 **Cloudflare R2**（S3 兼容，`@aws-sdk/client-s3`），桶 `gallery-media`，后台增删媒体自动镜像 | `lib/r2sync.js`、`lib/config.js` 的 `CF_R2_*` |
| 数据库 | `better-sqlite3`（`gate_data.db` + WAL），**不是** PostgreSQL | `package.json`、盘上 `.db-wal` |
| 实时通道 | **已有可用的 WS 房间服务**：大厅 + 房间码、join/leave/welcome 下发既有玩家、30 s `ping` 心跳清僵尸、**空房即刻 `delete`**（正是阶段 B 要的「房间按需加载活动状态，无人后释放」） | `lib/multiplayer.js`（183 行，`ROOM_CAP=8`） |
| 鉴权 | 单个 `TOKEN`（`?token=` 或 `x-token` 头）+ 设备/入口守卫，**不是**设备令牌体系 | `server.js:106`、`lib/gate.js` |
| 进程兜底 | `uncaughtException` / `unhandledRejection` 接住不打崩服务；单请求畸形 URL 返回 400 | `server.js:21-26,37-50` |
| 运维责任人 | 该项目 SOP 的 RACI 明写：主人决策 / Kimi 改码测试部署，「全绿才能部署」是硬门禁 | `SOP-代码结构与改动部署.md` |

### 11.2 它直接解决了 §6-③ 的哪一半，没解决哪一半

**已解决**（不用再从零开始）：主机与运维习惯、pm2 常驻与开机自启、防火墙口径、
Cloudflare 边缘 + 域名 + Origin 证书、一个已在生产的 S3 兼容对象存储桶、
「Node 零依赖裸跑兜底」的部署纪律、以及一份已经跑过 3-4 人实时房间的 WS 生命周期代码。

**没解决**（阶段 B 仍要新建，且不能靠复用糊过去）：
1. **有界队列与背压**：`lib/multiplayer.js` 的 `send`/`broadcast` 是 `try { ws.send() } catch {}`
   ——满了直接丢，没有水位、没有「超阈值要求重同步」。这正是 §5 阶段 B 明文要的可断言规则，
   现成代码给不了。
2. **ack 语义**：它没有 ack 概念。而 §2.2 的硬规则是「服务端 ack ≠ 他端已应用」，
   必须按「已送达 / 已收敛」两级建模。
3. **落库**：房间状态纯内存，重启即丢。阶段 B 要的是 op-log CRUD + `baseRev` CAS。
4. **设备令牌**：现在是共享 `TOKEN`，与「谁的设备、哪篇文档、什么权限」无关。
5. **per-doc 密钥**（§2.3-5 的真缺口）：完全没有，多人协同的前置条件。
6. **PostgreSQL vs SQLite**：现成轨道只有 SQLite。单实例「我的多设备」阶段 SQLite 够用，
   但它与 §5 写的目标栈不一致——这是**一条要业主认下来的偏差**，不是实现细节。

### 11.3 三个可点名的落法（含我的默认建议）

| 方案 | 内容 | 代价 |
|---|---|---|
| **A 同机同进程扩路由**（我不建议） | 把 op-log CRUD 直接加进 `dream-gallery` 的 `lib/routes.js` | 两个产品的可用性绑死；画廊那侧的门禁/回归会拦住笔记的迭代节奏，反之亦然。改别人在跑的生产项目，属对方项目的决策 |
| **B 同主机新进程新库**（默认建议） | 阿里云那台机器上再起一个服务（pm2 第二个 app），独立端口、独立 SQLite/PG 文件、独立 Cloudflare 子域与 Origin 证书；R2 用**新桶**不复用 `gallery-media` | 需要一条新的部署 SOP；与画廊共享一台机器的故障域（可接受，两者都非关键业务） |
| **C 另起 VPS** | 全新主机、全新运维轨道 | 从零建立部署与监控，重复劳动；除非故障域不可接受，否则没有理由 |

⇒ 我的建议是 **B**，并且阶段 B 的第一版目标收窄为 §6-①默认值「我的多设备」：
设备令牌 + op-log CRUD（`baseRev` CAS）+ 单文档密文中继，`lib/multiplayer.js` 的房间生命周期
可以照形状重写（加上 11.2 的第 1、2 条），而不是直接引它的代码。

**边界（本轮没做的事）**：我没有向那台生产服务部署、修改或写入任何东西；对它只做了
本机端口探测与源码阅读。跨项目的部署属业主决策，且部署是对外动作。


---

## 12. Spike A / B 的实测结论（2026-10-14）

两条都在本机跑完、结论可一键复现。**`spikes/**` 全程 untracked**：里面有一次性夹具、
编译产物和临时密钥，不进版本库、不进 CI、不上车（已在 `analysis_options.yaml` 的
`analyzer.exclude` 里点名，避免它们的 `print` 混进 lint 计数）。

⇒ 这与 §7.1 当初是同一个形状的后果：**`run.sh` 与两条 Spike B 探针只有本机一份**，
本节记下的是数字，不是可 checkout 的证据。要不要把 spike 代码入库，得先排除
`yw.gz`（6 MB 下载缓存）、`node_modules/`、`.env_probe*`（临时密钥），并且要过
Code Guard 的目录/行数结构门禁——属结构决定，等业主点头，本轮没动。
（一次性突变跑批脚本也一并挪进来了：`spikes/mutation_proof_a2.py`，同样 untracked。）

### 12.1 Spike A（Dart ↔ Yrs 桥）——GO，但中继有三条硬约束

复现：`spikes/spike_a_yrs/run.sh`（夹具 → rust build → js build → rust merge → js merge →
dart → js mergeffi → verify，顺序是硬约束）。脚本自带突变自证：篡改 `cross.js.dump`
末字节 ⇒ `verify` 必须非 0 返回。本轮结束时再跑一次 `interop.exe verify work`：
**11 条 PASS + 2 条 AS-EXPECTED 负例**。

编译面（§4 判据里「原生构建可控」那一半）：

| 平台 | 产物 | 体积 |
|---|---|---|
| Windows | `native/target/release/spike_a_yrs.dll` | 728,064 B |
| Android arm64-v8a | `android/jniLibs/arm64-v8a/libspike_a_yrs.so` | 1,373,352 B |
| Android x86_64 | `android/jniLibs/x86_64/libspike_a_yrs.so` | 1,337,192 B |

Dart 腿是**纯 `dart:ffi`**：不引 `package:ffi`、不用 `flutter_rust_bridge`，字符串与结构体
都走 Rust 导出的 `spike_alloc/spike_dealloc`。⇒ frb 在「画布 op 的最小桥」这件事上不是必需项，
它的价值只在生成绑定与 Dart 侧类型安全，那条账要在阶段 B 真正写桥时再算。

互通面：夹具是 40 条**画布笔画**（`work/strokes.jsonl`，取值刻意带小数、`-0`、2^53 附近的
seed——Spike C 记下过数值漂移这一课），不是 §4 原文写的「中文打字笔记」。换成笔画负载是有意的
偏离：我们要合并的就是笔画，判据那句「三端逐字节相同」按真实形态验收。
Rust / yjs / dart:ffi 三侧的整份转储 **5231 B 且 SHA-256 相同**（`6fa738e16324…`）。

三条必须写进阶段 B 中继条款的结论：

1. **差量不自带基线**（两条负例钉死）：一端独立写前半、另一端发来一份按*第三方*状态向量算出的
   差量，收下之后仍是半份（`incgap.rust.dump` == `incgap.js.dump` == `half.dump`，2603 B）。
   ⇒ 中继**必须按每个接收方的状态向量现算差量**，广播一份差量给全房间会静默漏内容。
2. **update 字节跨实现不同形**：`inc.js.diff` 与 `inc.rust.diff` 同为 2883 B 但 SHA 不同
   （`a43a4128…` / `c0f90de6…`）；同一份内容 `conv.rust.update` 5647 B 对 `conv.js.update`
   5683 B。状态向量同理（各 6 B，clientID 随机 ⇒ 字节必不同）。
   ⇒ 中继**不许按 update 哈希去重**，收敛只由 CRDT 语义判定。顺带一个成本数：一条新笔画的
   差量只要 38 B（`inc.dart.diff`），全量 update 是 5734 B ⇒ 增量确实省了一个数量级。
3. **LWW 不等于删除赢**：并发「A 删 s2 / B 改 s2」双向合并**同形**（收敛没问题），
   但落点是 `s2=存在`——写入压过删除。⇒ 删除要赢只能靠 A3-1 的墓碑在 CRDT 之上裁决，
   yrs 自己不会替我们做这件事。这条与 §7.2 第 3 条（回放中途抛错必须整份放弃）是同族风险。

### 12.2 Spike B（Y-Sweet vs 自建密文中继）——Y-Sweet 当不了密文中继

探针在 `spikes/spike_b_ysweet/`，一枚含明文标记的 Y.Doc 走两条路进服务端：

| 步 | 实测 |
|---|---|
| `convert-from-update` 写文件存储 | `data_probe/probe.doc.7c1f/data.ysweet`（251 B）里标记**原样可读**，偏移 93 与 193；连键名 `strokes`/`probe`/`s2` 和 JSON 值一起明文 |
| 真实客户端经服务器写入 | `POST /doc/<id>/auth` + `Bearer server_token` ⇒ **HTTP 200**（返回 scoped client token，`authorization:"full"`）；WS 握手后已有内容同步下来（`syncedKeys:["probe","s2"]`），写入 `LIVE_PUSH_MARK_9B3E` ⇒ checkpoint（`--checkpoint-freq-seconds 1`）后同一文件涨到 320 B，标记在偏移 92 **明文可见** |
| 不存在的文档 | `POST /doc/<id>/auth` ⇒ **404**：文件存储不自动建文档，中继层发 token 之前文档必须先在盘上 |

⇒ §4 判据那句「验证『服务器不理解内容』在 Y-Sweet 上是否根本做不到」的答案是
**做不到**，不是「没做到」。机械原因不在配置：服务端要算每个 peer 的差量（12.1 第 1 条），
就必须持有**解析后的** yrs 文档，落盘即 yrs checkpoint 明文；它没有服务端侧的加密层，
只有 token 签名。§6-② 的默认选项 B（服务端只见密文）在这条路上没有回旋空间。

顺带把那条 401 结清（不是网络/代理：curl `--noproxy '*'` 与走代理响应一致）：
`--auth` 收的是**内联密钥字符串**而不是文件路径，且**服务端持 `private_key`、调用方出示
`server_token`**；用错一侧就 401，用对之后 200/404 的区分才有意义。

**裁决**：走 §4 写好的失败退路，也是当前主判断——**中继自建**（服务端只做密文转发 + 版本水位，
按 §2.3 的 E2EE 边界与 §11 那条本机运维轨道的形状来），只借 Y-Sweet 的**运维语义**（token 分层、
按 doc 路由、周期性 checkpoint），不借它的存储。

**判据没兑现的那一半要说清**：§4 要的是「两张对比表（1000 长连接的 RSS/延迟/恢复成本）」。
自建中继在本轮之前没有一行代码，没有可测对象 ⇒ 这张表**留空**，而不是填一个估出来的数。
它该在阶段 B 交付物里补上，届时 Y-Sweet 那条腿只作为「明文服务端」的下界参照。

---

## 13. 网页版发布仍卡在同一条外部通道（2026-10-15 复测）

业主指令里的「恢复后用 actionId 25b00a58-… 重放」这一条**仍未解锁**。复测到的三件事：

| 调用 | 结果 |
|---|---|
| `get_publish_status(25b00a58-3f8d-430a-8769-2d61e2a9ee18)` | `sites_action_unavailable` |
| `get_site(01a1300f-42c9-7225-b774-3df286e7c74e)` | `sites_request_failed` |
| `get_project(01a1300f-42c8-7546-86bd-381a3e76a4ea)` | `sites_request_failed`（项目级读同样取不到） |
| `get_local_context()` | 站点描述符在盘上，但被标为 `unavailableSites: sites_request_failed` |
| `list_sites()` | 返回空列表（不报错）——与上一条并读，不能当成「账号下没有站点」 |

⇒ 这不是我这一侧的动作失败：**连只读的生命周期查询都取不到**。描述符文件本身仍是有效的一份
（`drawing_notes_web/.绘图笔记 · 网页版.qoder.site`，内含 projectId / siteId / deploymentId /
releaseId / artifactSha256，是上一次成功发布留下的那一版），所以通道恢复之后可以直接拿它核对，
不需要重新 `prepare_site` 猜参数。**该文件已进 `.gitignore`，不入库。**

我没有做的事：没有新建站点、没有换 projectId、没有用新 actionId 重传一份草稿——在只读通道都
取不到状态的时候重开一次 prepare 只会造出一个无法核对的第二身份。发布属对外动作，等通道回来
再做，且按 §「Reuse an existing matching draft」的规矩先读状态再决定。

**这条 P-3 的后果没有变**：网页版的**新构建**（含 §12 两条 spike 之后的形态）目前只有本机一份；
线上仍是旧 release。阶段 B 的服务端仍需要一个部署决策（§6-③、§11），与这条通道故障无关。
