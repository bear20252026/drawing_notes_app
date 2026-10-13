# 批次 D：写路径崩溃 / 故障窗口矩阵（2026-10-14 实测）

用途：把「断电、杀软占用、磁盘满、备份位被占、并发覆盖」这类故障在**每条写腿上**
的窗口、后果、现有用例与自愈路径列成一张可勾的表。第三轮审计批次 D 要的
「崩溃恢复矩阵」就是这张表；它同时也是下一批测试的排期依据——**空行是缺口，
不是已完成**。

口径三条（都是前两批反复用过的）：
- 每格必须有 `file:line` 或明写 `未覆盖`。不写「应该有」。
- 「自愈」指**下一次正常操作会自动修正**，不是「人还能手动救」。
- 故意不钉的断言会写明理由（见 §4）。

## 1. 四条本地写腿

| # | 腿 | 写入契约 | 失败点 | 后果 | 现有用例 | 自愈 |
|---|---|---|---|---|---|---|
| L1 | 文档正常保存 `StorageService.save` → `StorageWritePipeline.writeSealedBytes`（`lib/core/storage/storage_write_pipeline.dart:282`） | tmp 写 → copy `.bak` → `replaceWithTemp` | 备份位被占 | 抛错，正式文件未动，tmp 回收 | `test/core/storage/write_fault_injection_test.dart`「备份失败 ⇒ 抛错、原字节逐字节活着、不留 .tmp」 | 下一次保存正常落地上（同文件「解除阻塞后同一 id 必须还能写进去」） |
| L1 | 同上 | 同上 | 备份位被占**连续多次** | 每次都必须回收自己的 tmp，不许累积半份内容 | 同文件「连续两次失败 + 一次成功」 | 同上 |
| L1 | 同上 | `replaceWithTemp:318` | rename 被拒 + 目标仍在 ⇒ 删除-换入回退 | 崩溃窗口落在「已删目标、未换入」之间 | 仅 `test/core/storage/storage_encryption_test.dart:225`（Windows-only，验的是**退避重试自愈**，成功分支没单独断言） | `.bak` 仍在 ⇒ 读路径回落 |
| L1 | 同上 | 同上 | rename 失败且**没有** `.bak`（首写） | 正式文件消失 | **未覆盖**（需要注入口，见 §3-B） | 无（首写失败等于这次编辑丢了） |
| L2 | 画布懒迁移 `enqueueRawRewrite` | 走同一条 L1 契约（批次 C 收口） | 密封之后、落盘之前盘上内容被改/被删 | 不复查就会反超那次改写或复活已删笔记 | `test/storage_staleness_guards_test.dart:139,154,174`（时序屏障 `rewriteBarrierForTest`） | 下轮列表时重新判定 |
| L3 | 块文档 `NoteBlockDocStore._writeFileAtomic` | tmp → rename | 备份失败 / 屏障内改写 | 明文原件字节必须原样活着 | `test/core/documents/block_doc_write_path_contract_test.dart:108,139,158,182,209` | 迁移放弃 ≠ 放弃：`:209` 反向锁「障碍移除后照常完成」 |
| L4 | 操作日志侧车 `OperationLogStore._writeAtomic`（`lib/core/operation/operation_log_store.dart:239`） | tmp → rename，**刻意没有删除-换入回退** | 改名前崩溃 / 改名后崩溃 | 上一份逐字节不变 + 无 tmp 残留 / 读回恰为新内容无半行 | `test/core/operation/operation_log_store_test.dart`「窗口 1」「窗口 2」 | 侧车可再生：少一次追加不伤文档本体 |
| L5 | 分页画布载荷 `EncryptedWriteTransaction`（`lib/infrastructure/storage/v2/encrypted_write_transaction.dart:61`） | 自己的 tmp/`.bak` 事务（**不共用 L1 契约**） | 备份失败 → `BackupFailedException`（`:27`） | 主文件保留 | `test/security/encrypted_write_transaction_test.dart:22(S-001),45(S-002),82(S-003),104(S-004)` | 下一次提交重来 |

⇒ L5 是这张表里唯一一条**另写了一套事务**的腿。批次 C 的统一契约没有覆盖它，
不是遗漏的缺陷，是还没并轨的既有实现（合并它需要在 L5 上做一轮等价性验证）。

## 2. 崩溃残留：断电留下的 `.tmp`

| 落点 | 谁会把残留读成数据 | 实测保护 | 用例 |
|---|---|---|---|
| `documents/` | 首页列表 / `load` | **两道**：列表只认 `.json` 后缀（`storage_service.dart:258`）；`load` 前 `documentPathFor` 的 id 白名单（含 `.` 直接 `ArgumentError`） | `write_fault_injection_test.dart`「残留 tmp 不算一篇文档」「拿残留文件名当 id 去 load」 |
| `oplog/` | `append` 的「读不懂现有侧车 ⇒ 放弃写入」兜底 | 侧文件名严格 `<docId>.jsonl`，残留带 `.tmp` 不参与 | `operation_log_store_test.dart`「崩溃残留：上一轮留下的 .tmp」 |
| 备份包 | zip 内容 | 打包时排除 `.tmp` | `backup_service_test.dart:60`、`backup_restore_integrity_test.dart:346` |
| 保险库密钥 | 隐私残留（内含被包装主密钥） | **唯一一条真清扫器**：`vault_key_service.dart:104 _sweepStaleTmpFiles`（每实例一次，阈值 10 分钟） | `test/core/security/vault_key_service_test.dart:412` |

`documents/`、`oplog/`、块文档目录**都没有**清扫器。

## 3. 未覆盖的窗口（下一批的排期，每格都写了它卡在哪）

- **A. tmp 写入本身抛错**（磁盘满 / 权限 / 杀软占用新建文件）：四条腿里没有任何一条
  在 tmp `writeAsBytes` 处有注入口。`S-004` 挨着但不是同一窗口——它在**封包阶段**
  因无效密钥抛错，那时 tmp 还没创建。补法要么给 L1/L3 各加一个
  `@visibleForTesting` 钩子（沿用已成立的 `rewriteBarrierForTest` /
  `writeBarrierForTest` 命名与「生产恒 null」纪律），要么写 `IOOverrides` 委托
  `File`——后者不可行：`dart:io` 的 `File` 没有可委托基类，要实现整个 API 面。
- **B. rename 真失败**（不是屏障里抛，而是 `File.rename` 自己抛）：同 A 的注入口问题；
  且 Windows 的删除-换入**成功**分支只有 Windows 能验，CI 是 Linux ⇒ 该用例会被 skip。
- **C. 写完不回读**：四条腿都不做写后校验（读回比对）。这是**代码缺口**而不是测试
  缺口——加它等于每次保存多读一遍整个文件（大画布/低内存机器上是可感知的成本）。
  取舍要业主点头。
- **D. 远端侧窗口**：`manifest.json` 已回写、本地基线未回写之间的两阶段窗口是
  **文档化的已知取舍**（`sync_service.dart:666` M3），后果全部幂等无害，本轮不改变。
- **E. 恢复换根**：`.old_<ms>` 恢复前快照（DN-208）与隔离判据（DN-204）都从
  **磁盘事实**反推（快照时间戳 vs 基线 mtime），不依赖任何写标记 ⇒ 换根中途断电
  不会留下「半恢复」的第二套真相。用例：`test/core/storage/restore_snapshot_retention_test.dart`、
  `test/features/notes/infrastructure/file_post_restore_baseline_gate_test.dart`。

## 4. 故意不钉的断言

- 「`documents/` / `oplog/` 的残留 `.tmp` 会被清扫」。现状是没有清扫器（§2），
  把它写成断言等于把将来真该写的清扫器判成回归。现有用例只主张
  **「残留不碍事」**，并在注释里点明这一点。
- 「任何写入都会回读校验」。生产里没有这件事（§3-C），测试不许假装它存在。

## 5. 这一批怎么做才算数（复现步骤）

1. `cd drawing_notes_app`
2. `NO_PROXY=127.0.0.1,localhost flutter analyze` ⇒ 必须 `No issues found`
3. `NO_PROXY=127.0.0.1,localhost flutter test test/core/storage/ test/core/operation/ test/core/documents/ test/storage_staleness_guards_test.dart` ⇒ 全绿
4. `linecheck --config linecheck.yml lib/` ⇒ 退出码 0（warn 不算失败）
5. **突变自证**：每条新断言都要能指出「把生产里哪一行改坏，它会红」。本文件 §1/§2
   的行来自 `c55dd3b` 的三道突变（备份失败不抛 ⇒ 4 红；失败不回收 tmp ⇒ 3 红；
   去掉 `.json` 过滤 ⇒ 残留那条红），已还原并复跑。
6. 全量 `flutter test` 以 CI 为准（本仓直推 master，实测 7 个编排；`ci.yml`
   是 `cancel-in-progress`，只看最新 SHA）。
