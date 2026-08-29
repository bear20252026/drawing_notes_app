# WebDAV 本地优先同步 验收记录

> 状态：✅ 已收口（commit `8f60c4d`，叠 `a2ef16a` / `ba418a7`）；端到端加密（commit `2252bfd`）；同步可观测性（commit `0c5d1ba`）
> 门禁：`flutter analyze` 0 问题 · architecture 测试全通过 · `flutter test` **1176** 全通过

## 目标

补齐最后一个 P3 生态缺口——本地优先的 WebDAV 双向同步（离线可编辑、联网可同步、删除可传播），对齐 Saber `abstract_sync` 的「本地文件真相 + 远端适配边界 + 可解释状态」分层思想，且**不污染**画布控制器与文档模型。

## 分层落地（features→shared→core 纯向内依赖）

| 层 | 文件 | 职责 |
|---|---|---|
| core/sync | `sync_planner.dart` | 纯函数计划器：`SyncSnapshot`(id/updatedAt/size) + `SyncManifest`(entries + deletedIds 墓碑, toJson/fromJson) + `SyncOperation`(upload/download/deleteRemote) + `SyncPlanner.plan(local, remote)` 确定性排序（tombstone→deleteRemote / local-only→upload / remote-only→download / both→updatedAt 较新者胜·相等忽略） |
| core/storage | `webdav_sync_client.dart` | 注入式传输：`WebDavSyncClient(baseUrl, http.Client?, username, password)`；ensureCollection MKCOL / getBytes GET 404→null / putBytes PUT / deleteRemaining DELETE / listLeafNames PROPFIND Depth:1 XML 解析 / close |
| core/sync | `sync_service.dart` | 编排器：`SyncDocMeta`(id/updatedAt/size) + 抽象 `SyncDocumentStore`(listDocuments/readDocument/writeDocument/deleteDocument) + 抽象 `SyncBaselineStore`(load/save) + `SyncResult`(uploaded/downloaded/deletedRemote/changed) + `SyncService.syncNow()`：ensureCollection→GET remote manifest→本地 manifest+墓碑→plan→执行→双写回 manifest（`manifest.json`） |
| features/notes/infrastructure | `note_block_doc_sync_store.dart` | 本地半边适配：`NoteBlockDocSyncStore` implements `SyncDocumentStore`（listDocuments 取 updatedAt.millisecondsSinceEpoch + 序列化 size；writeDocument jsonDecode→fromJson，`copyWith` 强制 `doc.id == id`） |
| features/notes/infrastructure | `file_sync_baseline_store.dart` | 基线存储：`FileSyncBaselineStore` 存 `<docs>/sync_state.json`，注入式 directoryProvider |
| features/notes/infrastructure | `webdav_config_store.dart` | 配置：`WebDavSyncConfig`(baseUrl/username/password, isConfigured, copyWith, toJson/fromJson) + `WebDavConfigStore`（SharedPreferences `webdav_sync_config`，load/save/clear） |
| features/notes/presentation | `webdav_sync_settings_page.dart` | 设置页：URL/账号/密码表单 + 立即同步（`SyncService(WebDavSyncClient + NoteBlockDocSyncStore + FileSyncBaselineStore)`）+ 保存配置；home_page AppBar 云端同步入口 |

## 测试覆盖（+86）

- `sync_planner_test.dart`：17（墓碑→deleteRemote、单侧、双侧重、updatedAt 较新者胜/相等忽略、确定性顺序）
- `webdav_sync_client_test.dart`：21（MKCOL/GET 404→null/PUT/DELETE/PROPFIND XML 解析/close，注入 http.Client 免真实网络）
- `sync_service_test.dart`：5 集成（`_MemoryServer`/`_MemoryDocStore`/`_MemoryBaseline` 全链路）
- `note_block_doc_sync_store_test.dart`：3（listDocuments 元数据、读写删回环、id 纠偏）
- `webdav_config_store_test.dart`：5（save/load 回环、默认空、损坏回退、clear、copyWith）

## 工程可测性设计

- `WebDavSyncClient` 接收可选 `http.Client` —— 全部传输测试走注入客户端，离线可测。
- `SyncService` 面向抽象 `SyncDocumentStore` / `SyncBaselineStore`；本地实现与远端实现解耦。
- 渲染/传输/存储三处均遵循「本地文件真相 + 适配边界」，画布控制器零改动。

## 已知边界 / 后续

- 跳过：端到端加密、冲突副本 UI、同步进度/重试可视化（设计参考 `DOCS_/UPSTREAM_SOURCE_AUDIT_NOTES` 与 `SABER_SPECIAL_RESEARCH_REPORT`）。当前为本地优先的确定性 manifest 计划器，无队列/退避——已在架构层预留扩展点。
- 远端覆盖策略为「updatedAt 较新者胜」的 last-write-wins，依赖本地文档 `updatedAt` 单调性。

## 端到端加密（P4-A，commit `2252bfd`）

> 边界：**本地优先、零服务器设计**。用户明确「不做服务器设计」——WebDAV 仅作为一台通用对象目录（Nextcloud/自建均可），不引入任何自定义服务端契约。加密、密钥派生、manifest 比对、文件名混淆全部在客户端完成。

### 设计
- `abstract SyncCipher`：`remotePath(docId)` / `encryptDocumentBytes` / `decryptDocumentBytes` / `sealManifestJson` / `openManifestJson`。
- `NoopSyncCipher`：恒等实现，作为默认值——**既有行为与全部测试不变**。
- `AesSyncCipher`：AES-256-GCM（`package:cryptography`），AAD 绑定 docId（文档）与 manifest 上下文（清单），`remotePath` = HMAC-SHA256(key, docId) hex（64 字符，确定性、不可逆，服务端只见不可读 blob 名）。密钥经 PBKDF2-SHA256（600k 迭代）从「同步密码 + 盐」派生（`deriveMasterKey` / `generateSalt` 顶层函数）。
- `SyncService` 注入可选 `cipher`（默认 Noop）：上传前 `encryptDocumentBytes`→PUT `remotePath(docId)`；下载 GET `remotePath`→`decryptDocumentBytes`→写文档；deleteRemote 用 `remotePath`；manifest 上下行 `seal/openManifestJson`。

### 测试（+21）
- `sync_cipher_test.dart`：18（Noop 恒等、AES 往返/随机 nonce、AAD 绑定 docId 换位失败、错误密钥失败、manifest 密封、remotePath 确定性/敏感/不可逆、deriveMasterKey 确定性/generateSalt 随机）
- `sync_service_test.dart` +3 E2E：上传只见密文 + sealed manifest 且可解密还原 / 跨设备同密钥下载解密 / Noop 明文

### 已知边界
- **口令变更 = 密钥变更**：既改密后，旧远端密文无法再用旧口令解密；需重建集合全量重传（登记为后续强化项）。
- 同步密码存储于 SharedPreferences（`webdav_sync_config`），非平台安全存储；升级到 `flutter_secure_storage` 为后续安全强化项。
- 盐一旦生成不改，保证派生 key 对既有密文稳定。

## 同步可观测性（P4-B，commit `0c5d1ba`）

> 边界：**本地优先、零服务器设计**。进度/重试/冲突均为客户端可观测性，不引入任何服务端契约。

### 设计
- `sync_progress.dart`：`SyncProgressPhase` 枚举（started/connecting/planning/uploading/downloading/deleting/writingManifest/done/failed）+ immutable `SyncProgress`（`fraction`/`description`/`copyWith` + `starting`/`phase`/`complete`/`failure` 工厂）。
- `sync_retry_policy.dart`：`SyncRetryPolicy`（`decide(SyncRetryInput)` → retry/backoff/giveUp + `delayFor` 指数退避 + `maxAttempts`）。
- `SyncService`：注入可选 `onProgress`，`syncNow` 全阶段发射进度；`SyncResult` 增 `conflictedDocIds`——比对基线检测「本地与云端都相对基线改动」的真冲突（仅可见性提示，不改变 LWW 语义，同步语义仍由 `SyncPlanner` 决定）。
- 设置页：`LinearProgressIndicator` + 状态文案；成功展示 `↑↓✕` 计数与冲突提示；失败走 `SyncRetryPolicy` 有界自动退避重试。

### 测试（+52）
- `sync_progress_test.dart` + `sync_retry_policy_test.dart`：49（fraction/description/工厂、重试决策/退避曲线/确定性）
- `sync_service_test.dart` +3：onProgress 阶段序列、双边改动报冲突、单侧改动不冲突

## 相关文档

- `docs/ADVANCED_COLLABORATION_AND_RECOVERY_ARCHITECTURE_2026-08-14.md`（设计基础）
- `docs/SABER_PARITY_TARGET_ARCHITECTURE_2026-08-14.md`（同步分级前提：本地可靠后再建云同步）
- `docs/UPSTREAM_SOURCE_AUDIT_NOTES_2026-08-14.md`（abstract_sync 分层思想）
