# WebDAV 本地优先同步 验收记录

> 状态：✅ 已收口（commit `8f60c4d`，叠 `a2ef16a` / `ba418a7`）
> 门禁：`flutter analyze` 0 问题 · architecture 测试全通过 · `flutter test` **1094** 全通过

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

## 相关文档

- `docs/ADVANCED_COLLABORATION_AND_RECOVERY_ARCHITECTURE_2026-08-14.md`（设计基础）
- `docs/SABER_PARITY_TARGET_ARCHITECTURE_2026-08-14.md`（同步分级前提：本地可靠后再建云同步）
- `docs/UPSTREAM_SOURCE_AUDIT_NOTES_2026-08-14.md`（abstract_sync 分层思想）
