# 会话密钥生命周期（取钥权威层）

> 定案日期：2026-11-15（框架级收口，审计 H-1/H-2/H-3/M-1~M-5 的共同根源修复）
> 状态：✅ 已实施。本文是现行规范，挂 docs/README.md 索引。

## 1. 为什么需要这一层（病根，不是补丁）

K_note 接线（PR #63）后审计发现 3 个高危 + 多个中危，摊开看**全是同一个缺失抽象的不同症状**：

| 症状 | 共同根源 |
|---|---|
| H-1 加密笔记本媒体明文回退 | 用「密钥在不在内存」代替「该不该加密」 |
| H-2 损坏槽 → 未持久化临时密钥 | 取钥瀑布把「无槽/坏槽/错密码」压成一个 null |
| H-3 懒补槽竞态 / 陈旧快照覆盖 | 生命周期操作散落、无统一编排 |
| M-3/M-4 清零竞态 / 在途复活 | 无会话世代令牌，回锁无法作废在途异步操作 |
| M-1/M-2 缓存驻留 / 逐出空白 | 密钥状态与渲染/缓存无统一归属 |

**逐个加守卫治不了本**：给 H-1 加一个 `if(nb.encrypted)`，下次新增媒体类型或改 LRU 时机，同类洞会在别处再长出来——因为「该不该加密」始终没有权威来源，每个消费点都在各自猜。

## 2. 权威层契约（三件事收归单一权威）

新增 `lib/core/security/notebook_media_keys.dart`（`NotebookMediaKeys`）：

### 2.1 加密意图与密钥可得性分离
消费方只问「给我这本的媒体密钥」（`sealMedia`/`openMedia`），由编排器依据**笔记本加密声明**（`NotebookMediaEnvelopePort.isEncryptedNotebook`，读磁盘当前信封）决定：
- 加密笔记本 → 要么返回密钥产物，要么 fail-closed 抛 `VaultFileLockException`，**永远不把「明文」这个选项交给加密笔记本**；
- 明文笔记本 → `sealMedia` 返回 null，调用方走既有 DNV/明文兼容分支。

**业务层不再出现 `hasKeyFor` 内存嗅探**（门禁 `presentation_io_seam_test` H1-② 零豁免锁死表现层不得持有加密原语 `MediaCryptoService`）。

### 2.2 会话世代令牌（`SessionEpoch`）
`SessionSecrets.clearAll()`（回锁/切后台）先 `SessionEpoch.bump()` 再逐家清零。一切**跨 await 的密钥操作**发起时捕获 `SessionEpoch.current`，完成时校验——世代已变即作废（不注入/不落盘/不用钥）。M-3/M-4 这类竞态被**构造性消除**，不靠调用方各自复查锁态。

另有 per-id **遗忘世代**（`forget` 递增）：页面 dispose/删除笔记本后，在途 ensure 完成时发现世代已变即放弃注入（防「清钥后被在途操作复活」）。

### 2.3 per-id 串行编排 + 三态契约
- 同一笔记本的 ensure 共享一条在途 Future（并发双 ensure 只生成一把 K_note，H-3）；
- 懒补槽的读-改-写经端口 `attachMediaSlot` 在存储的**独占写队列内重读最新落盘内容后只替换 encryptedPayload 字段**（`_patchEncryptedPayloadInsideExclusive`，非整本陈旧快照，H-3）；
- **三态契约（H-2）**：端口解包 K_note 时——无 media 槽 → null（编排器懒补）；密码错误/槽损坏 → 抛 `FormatException`（编排器 fail-closed，绝不把损坏槽当无槽生成临时密钥）。

## 3. 职责划界

| 组件 | 职责 | 不做 |
|---|---|---|
| `MediaCryptoService` | 加密原语：LRU 密钥映射（32）+ AES-GCM + 密钥快照（防 use-after-zero） | 不判断「该不该加密」、不触信封/文件 |
| `NotebookMediaKeys` | 取钥权威：意图判定/ensure 编排/世代校验/forget | 不持有长期密钥（驻留在原语 LRU）、不触文件 IO |
| `NotebookMediaEnvelopePort` | 信封端口契约（存储侧实现） | — |
| `NotebookStorage` | 实现端口：加密声明/会话密码/解包/补槽（独占队列内）+ CRUD | 写/读媒体不再直接消费原语，一律经编排器 |
| `SessionSecrets`/`SessionEpoch` | 回锁广播清零 + 世代翻篇 | — |

## 4. 装配（组合根唯一落点）

`app.dart`：`late final NotebookMediaKeys _mediaKeys = NotebookMediaKeys(media: _mediaCrypto, envelopes: _notebookStorage)`（late 初始化器引用实例成员，与 keyProvider 闭包同模式），注入 `NotebookStorage.mediaKeys` 与 `AppServices.mediaKeys`（同源）。

`NotebookMediaKeys.instance` 是**未装配 fail-closed 兜底**（`_UnwiredEnvelopes`：一切笔记本密钥请求抛锁异常——未知笔记本绝不按明文处理），只服务测试直构与未装配场景。

## 5. 消费方收口清单（全部经编排器）

- 写：`NotebookStorage.storeImage`/`sealMediaBytesForPath` → `_sealIfEncrypted` → `keys.sealMedia`；
- 读：`EncryptedFileImage`/`NotebookPdfExporter` → `keys.openMedia`（LRU 逐出自动重解包，M-2）；
- 解锁注入：5 处 `ensureNotebookMediaKey` 委托 `keys.ensure`；
- 清理：页面 dispose/会话锁 → `keys.forget`；删除笔记本 → `forget` + VFS `removeObject`（M-5）；回锁 → `SessionSecrets.clearAll`（清全部 + 世代翻篇）；
- 渲染缓存：`EncryptedFileImage` 缓存键含 notebookId（M-1 跨本不命中）；解锁收口 `imageCache.clear()`（跨会话明文位图不驻留）。

## 6. 回归钉（test/core/security/notebook_media_keys_test.dart）

H-1 缺钥不落明文 / H-2 损坏槽不懒补 / H-3 并发单密钥 / M-2 逐出重解包 / M-4 世代作废在途注入 / M-5 删除联动清钥——每条对应一个被结构消解的审计缺陷，防复发。

## 7. 残余边界（如实）

- 编排器不改变密码学格式（v5 信封/AAD/Argon2id 不动），不动分层骨架与 LRU 决策；
- `SessionEpoch` 是进程内令牌，不跨进程持久化（回锁即翻篇，重启自然新世代）；
- VFS 清单侧车可删绕过验签（M-7）、审计链后缀截断（M-6）属另一攻击面，不在本层范围，留后续批次。