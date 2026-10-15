# 批次 D：写路径崩溃 / 故障窗口矩阵（2026-10-14 实测）

用途：把「断电、杀软占用、磁盘满、备份位被占、并发覆盖」这类故障在**每条写腿上**
的窗口、后果、现有用例与自愈路径列成一张可勾的表。第三轮审计批次 D 要的
「崩溃恢复矩阵」就是这张表；它同时也是下一批测试的排期依据——**空行是缺口，
不是已完成**。

口径三条（都是前两批反复用过的）：
- 每格必须有 `file:line` 或明写 `未覆盖`。不写「应该有」。
- 「自愈」指**下一次正常操作会自动修正**，不是「人还能手动救」。
- 故意不钉的断言会写明理由（见 §4）。

## 0. 本批实测发现的一条数据丢失链（写这张矩阵的直接收获）

**发现方式**：给 L1 补 (b)「改名失败」用例时，断言 `正式文件应等于上一版` 直接抛
`PathNotFoundException` —— 文件根本不在盘上了。不是测试写错，是生产真的会这样。

链条（Windows 为主，Linux 上 rename 直接覆盖成功所以走不到）：

1. `replaceWithTemp`（`storage_write_pipeline.dart:318`）的兜底是「rename 被拒 ⇒
   **删掉正式文件** ⇒ 再 rename」。第二次 rename 仍可能失败：句柄删除挂起期返回
   ACCESS_DENIED(5)，代码把它当瞬态退避重试，5 次用尽后 rethrow。
2. 此刻正式 `.json` 已没了，只剩刚写好的 `.bak`。
3. 读路径能从 `.bak` 回退（`storage_service.dart:193`、`note_block_doc_store.dart`
   的 `loadDocument`），所以**打开它还是好的**——正因如此这条链一直没被发现。
4. 但 `listDocuments` / `listDocHeaders` **只认 `.json`**（`storage_service.dart:258`、
   `note_block_doc_store.dart:315`）⇒ 这篇笔记从首页与搜索里消失。
5. 首页消失还不是最坏的：同步侧 `listDocuments()` 的清单里没有它，而基线里有
   ⇒ 走 `sync_service.dart:385` 的墓碑推导 ⇒ `deleteRemote` ⇒ **云端副本被真删**。
   `note_block_doc_sync_store.dart` 里 DN-107 的注释写的正是这条推导——DN-107 修的是
   「存在但解不开」，这次是同一个形状的**另一种成因**。

⇒ 结论：**一次失败的保存，可以让一篇笔记从本地列表和云端一起消失**。

**本批的处置**（两条腿同一出口，纯新增，只在 catch 分支跑，成功路径零额外 IO）：
失败出口先把 `.bak` **复制**回正式文件（`_restoreFromBackup`，
`storage_write_pipeline.dart` / `note_block_doc_store.dart` 各一份，同一形状），
再清 tmp，再原样上抛；并在审计链留下 `*.write_rolled_back_from_backup`。
用 `copy` 而不是 `rename`：`.bak` 是读路径的兜底依赖，回滚不该把另一份唯一副本吃掉
（这一条由突变验证：改成 `rename` 后「`.bak` 仍在」的断言立刻红）。

**曾经列出的第二层，逐条核实后被否决**（不是没做完，是方向错了，任务 #23）：原设想让列表把
「只有 `.bak`」这种情况当成「存在但读不出来」（DN-107 的口径）而不是「已删除」，用来防
**其它**让正式文件消失的成因（杀软隔离、手动改文件、恢复换根中途断电）。它依赖的前提是
「用户主动删除后侧车一定不残留」——实测**不成立**：两族删除入口都在主文件缺失时早退
（等于「删不掉」）、块文档 rename 回退分支不清侧车、`_removeBak` 静默吞失败、画布族侧车删除
会把整次删除抛断。放宽列表等于**复活用户真删的笔记**，比它要防的问题更糟 ⇒ 改成把删除
本身的这些漏口堵掉（§5）。
**推论**：想给「读得到但列不出」加纵深防御之前，先证明它依赖的前提成立；证明不了就修源头。

## 1. 五条本地写腿

| # | 腿 | 写入契约 | 失败点 | 后果 | 现有用例 | 自愈 |
|---|---|---|---|---|---|---|
| L1 | 文档正常保存 `StorageService.save` → `StorageWritePipeline.writeSealedBytes`（`lib/core/storage/storage_write_pipeline.dart:320`） | tmp 写 → copy `.bak` → `replaceWithTemp` | 备份位被占 | 抛错，正式文件未动，tmp 回收 | `test/core/storage/write_fault_injection_test.dart`「备份失败 ⇒ 抛错、原字节逐字节活着、不留 .tmp」 | 下一次保存正常落地上（同文件「解除阻塞后同一 id 必须还能写进去」） |
| L1 | 同上 | 同上 | 备份位被占**连续多次** | 每次都必须回收自己的 tmp，不许累积半份内容 | 同文件「连续两次失败 + 一次成功」 | 同上 |
| L1 | 同上 | `replaceWithTemp:392` | rename 被拒 + 目标仍在 ⇒ 删除-换入回退 | 崩溃窗口落在「已删目标、未换入」之间 | 成功分支：`write_fault_injection_test.dart`「(f)」+ `block_doc_write_rollback_test.dart`「兜底腿的成功分支」（注入点见 §3-F）；退避重试自愈那一格仍只有 `storage_encryption_test.dart:225`（Windows-only） | `.bak` 仍在 ⇒ 读路径回落 |
| L1 | 同上 | 同上 | rename 失败且**没有** `.bak`（首写） | 这次编辑确实丢失，但盘上不留半份文件骗过下一次读 | `write_fault_injection_test.dart`「(b2) 首写就撞上改名失败」 | 无（如实记录：首写失败就是丢内容） |
| L2 | 画布懒迁移 `enqueueRawRewrite` | 走同一条 L1 契约（批次 C 收口） | 密封之后、落盘之前盘上内容被改/被删 | 不复查就会反超那次改写或复活已删笔记 | `test/storage_staleness_guards_test.dart:139,154,174`（时序屏障 `rewriteBarrierForTest`） | 下轮列表时重新判定 |
| L3 | 块文档 `NoteBlockDocStore._writeFileAtomic` | tmp → rename | 备份失败 / 屏障内改写 | 明文原件字节必须原样活着 | `test/core/documents/block_doc_write_path_contract_test.dart:108,139,158,182,209` | 迁移放弃 ≠ 放弃：`:209` 反向锁「障碍移除后照常完成」 |
| L4 | 操作日志侧车 `OperationLogStore._writeAtomic`（`lib/core/operation/operation_log_store.dart:258`） | tmp → **回读校验** → rename，**刻意没有删除-换入回退** | 改名前崩溃 / 改名后崩溃 | 上一份逐字节不变 + 无 tmp 残留 / 读回恰为新内容无半行 | `test/core/operation/operation_log_store_test.dart`「窗口 1」「窗口 2」 | 侧车可再生：少一次追加不伤文档本体 |
| L5 | 分页画布载荷 `EncryptedWriteTransaction`（`lib/infrastructure/storage/v2/encrypted_write_transaction.dart:61`） | 自己的 tmp/`.bak` 事务（**不共用 L1 契约**） | 备份失败 → `BackupFailedException`（`:27`） | 主文件保留 | `test/security/encrypted_write_transaction_test.dart:22(S-001),45(S-002),82(S-003),104(S-004)` | 下一次提交重来 |

**补上 (a)/(b) 之后新增的行**（钩子见 §3-A/B/F；(a)(b) 是 10-14 同日，标 (f) 的两行是
10-15 补的兜底换入成功分支）：

| # | 窗口 | 注入方式 | 用例 | 主张 |
|---|---|---|---|---|
| L1 | tmp 第一笔字节就失败 | `tmpPathObserverForTest` 把 tmp 路径占成目录 | `write_fault_injection_test.dart`「(a) …」 | 抛错；正式文件一字节没动；**此时不该有 `.bak`**（备份排在 tmp 之后）；不留 tmp |
| L1 | 改名这一步失败（已有上一版） | `renameBarrierForTest` 移走 tmp | 同文件「(b) …」 | 上一版逐字节活着 + `.bak` 正是被保住的 v2 + **回滚把正式文件放回** + 审计留痕 |
| L1 | 改名失败且是首写 | 同上 | 同文件「(b2) …」 | 没有半份文件、没有 `.bak`、没有 tmp（这次编辑确实丢了，如实记录） |
| L1 | 改名被拒**之后**兜底换入成功（(f)，10-15 补） | `renameFaultForTest` 只拒第一次，第二次走真系统调用 | 同文件「(f) 改名被拒之后那条兜底换入」 | 新内容仍落地 + `.bak` 仍是上一版 + 不留 tmp + **回滚审计一条都不许出现**（回滚只属于失败出口；成功路径跑进它=这次写被误判成失败，新内容没被盖回去只是靠 `existsSync` 那道守卫） |
| L3 | 改名失败（块文档，喂同步的那条腿） | `NoteBlockDocStore.renameBarrierForTest` | `test/core/documents/block_doc_write_rollback_test.dart`（3 条） | 回滚 + 列表**仍看得见这篇**（列表可见性就是这条链的终点）；反向锁：成功写入绝不触发回滚 |
| L3 | 改名被拒**之后**兜底换入成功（(f)，10-15 补） | `NoteBlockDocStore.renameFaultForTest` | 同文件「兜底腿的成功分支」 | 同 L1 那条，另加两条终点断言：`loadDocument` 读回第三版、`listDocHeaders` 仍列出这篇 |
| L4 | 改名失败（操作日志侧车） | 已有的 `writeBarrierForTest` 里移走 tmp | `operation_log_store_test.dart`「改名这一步真失败」 | 上一份侧车逐字节不变、不留 tmp、队列没被毒住（摘掉屏障后还能追加） |
| L4 | 写完回读不是所写（**§3-C，2026-10-14 补**） | 同一个屏障里改写 tmp —— 校验就排在这个屏障之后，不需要新钩子 | `operation_log_store_test.dart`「不变量④」两条 | 抛 `OperationLogIntegrityException`；旧侧车逐字节活着、不留 tmp、摘掉注入后照常能写；**加密腿比密文**：tmp 上出现明文同样判失败 |

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

- **A. tmp 写入本身抛错**（磁盘满 / 权限 / 杀软抢占新建文件）：**已闭合**。注入口用
  `@visibleForTesting tmpPathObserverForTest`（`storage_write_pipeline.dart:70`，同处另有
  `renameBarrierForTest:77` 与 `renameFaultForTest:86`；块文档腿的同名钩子在
  `note_block_doc_store.dart:103` 与 `:112`）——
  它在 tmp 路径算出来之后、写第一笔字节之前同步回调，测试据此把该路径占成目录，
  于是 `writeAsBytes` 确定失败。选它而不是 `IOOverrides`：`dart:io` 的 `File` 没有
  可委托基类，委托等于重写整个 API 面。用例：
  `test/core/storage/write_fault_injection_test.dart`「(a) tmp 写第一笔字节就失败」，
  并断言此时**不该有 `.bak`**（备份排在 tmp 之后）。
- **B. 改名这一步真失败**：**已闭合**（`renameBarrierForTest`，画布腿与块文档腿各一份，
  侧车腿复用已有的 `writeBarrierForTest`）。注入的是**等价类**而不是真实共享冲突：
  屏障里把 tmp 移走 ⇒ rename 抛错，Linux 与 Windows 同判，所以 CI 上也真跑。
  真实句柄冲突那一格仍由 `storage_encryption_test.dart:225` 覆盖（Windows-only，
  Linux 上 skip），两条不互相顶替。用例见 (b)/(b2) 与
  `test/core/documents/block_doc_write_rollback_test.dart`、
  `operation_log_store_test.dart`「改名这一步真失败」。
- **C. 写完不回读**：**L4 已闭合（2026-10-14，业主批准只做这一条腿）**。`_writeAtomic`
  在改名**之前**回读临时文件，与 `sealed`（密文，不是明文）逐字节比对，不一致就抛
  `OperationLogIntegrityException` 并回收 tmp（`operation_log_store.dart:269`）。选「改名前验」
  而不是「改名后验」只有一个理由：验不过时正式侧车还没被换掉，失败出口的形状与
  「改名真失败」那一格**完全相同**（上一份逐字节活着、盘上没有半份日志）。比的是密文，
  所以既不多一次解密，又顺带把「tmp 上出现明文」判成失败——不变量③的第二条降级通道
  一并堵在这里（用例：`operation_log_store_test.dart`「加密腿比的是密文」）。
  **代价实测**（本机一次性基准：flush 写 + 同名文件回读，不含加密与改名，n=200）：

  | 体积 | 不回读 median | 回读 median | 回读 p95 |
  |---|---|---|---|
  | 4 KB | 1.35 ms | 3.51 ms | 5.28 ms |
  | 64 KB（侧车 `maxBytes` 上限） | 1.58 ms | 11.12 ms | 19.35 ms |
  | 512 KB | 2.68 ms | 13.13 ms | 19.04 ms |
  | 2 MB | 3.26 ms | 18.14 ms | **75.02 ms** |

  ⇒ 多出的是一次「开文件 + 读」的固定开销（约 +9 ms），落在 5 秒一次的自动保存节奏上
  不构成可感知延迟，所以侧车这一档值得加。**L1/L3 不要照抄这张结论**：大画布可达 MB 级，
  p95 已到 75 ms，且真实写腿还要多付一次解密与一次整份读。要给 L1/L3 加，得先拿
  「加密 + 改名 + 回读」的全链路实测说话——那一格仍按业主决策处理，本轮不擅自铺开。
  另外 L2（画布懒迁移）复用 L1 契约，L5（分页画布事务）仍是独立一套（§1 末注）。
- **D. 远端侧窗口**：`manifest.json` 已回写、本地基线未回写之间的两阶段窗口是
  **文档化的已知取舍**（`sync_service.dart:666` M3），后果全部幂等无害，本轮不改变。
- **E. 恢复换根**：`.old_<ms>` 恢复前快照（DN-208）与隔离判据（DN-204）都从
  **磁盘事实**反推（快照时间戳 vs 基线 mtime），不依赖任何写标记 ⇒ 换根中途断电
  不会留下「半恢复」的第二套真相。用例：`test/core/storage/restore_snapshot_retention_test.dart`、
  `test/features/notes/infrastructure/file_post_restore_baseline_gate_test.dart`。

- **F. 兜底换入的成功分支**（B 留下的那半格）：**已闭合（2026-10-15，`9aa44d7`）**。
  B 注的是「改名失败」这个**等价类**（把 tmp 移走 ⇒ 第二次 rename 也必然失败），所以
  「被拒之后先删目标再换入」这条兜底腿从来没能**成功**跑通一次。原排期写的是「只有
  Windows 本机可以验」——动手前先量了它的前提，**前提是假的**：
  ① 目标已存在时 Windows 的 `File.rename` **直接成功**（带 replace 语义），代码注释里
  「若 Windows 拒绝覆盖已有文件」描述的是一条不发生的事，这条兜底并不是 Windows 的常规路径；
  ② 真正会拒的是别人持有目标句柄：实测 rename 报 `code 5 拒绝访问`，而同一个句柄让紧随的
  `delete` 报 `code 32 另一个程序正在使用此文件`；
  ③ ⇒ 这条腿只在「持句柄者刚好在两次调用之间放手」的窗口里才走得通。用 sleep 去赌那个窗口，
  赌赢的测试同样是假的；Linux CI 更是永远到不了。
  处置：`@visibleForTesting renameFaultForTest`（两条写腿各一个，生产恒 null），返回 true 表示
  这一次改名**不执行**、tmp 与目标都原地不动——复刻真实拒绝留下的盘上形状，第二次换入仍走
  真系统调用。「拒绝」这个动作的定义收在 `lib/core/storage/rename_injection.dart` 一处：
  两条腿各自决定要不要拒，但异常形状若在两处各写一遍，注入验的就不再是同一条腿。
  三条突变自证：①注入点永不拒绝 ⇒ 恰好只有这两条新用例红（证明它们真的依赖钩子被调到）；
  ②画布腿摘掉兜底 ⇒ (f) + (b) 红（(b) 红是因为兜底没删目标，回滚审计自然没有）；
  ③块文档腿摘掉兜底 ⇒ 新用例 + 「换入失败放回上一版」红。
  **仍然**只有 Windows 有语义的是 `storage_encryption_test.dart:225` 那条**退避重试自愈**
  （靠 40ms 后关句柄去赌窗口），与 (f) 不是同一条主张，两条不互相顶替。

## 4. 故意不钉的断言

- 「`documents/` / `oplog/` 的残留 `.tmp` 会被清扫」。现状是没有清扫器（§2），
  把它写成断言等于把将来真该写的清扫器判成回归。现有用例只主张
  **「残留不碍事」**，并在注释里点明这一点。
- 「所有写腿都会回读校验」。只有 L4 有（§3-C，业主批准的范围就到这条腿）；L1/L2/L3/L5
  都没有，测试不许把这一条推广到其余四条腿。

## 5. 删除路径的侧车（本批逐条核实的结果，任务 #23）

矩阵本来只覆盖写，但 §3 那条「只剩 `.bak`」把删除也拖进来了：想让列表把侧车当存在，
前提是**用户主动删除后侧车一定不残留**。逐条核实后这个前提**不成立**，所以放宽列表
语义的做法被否决，改成把删除本身的四个漏口堵掉。

| 位置 | 以前的行为 | 后果 | 现在 |
|---|---|---|---|
| `storage_trash_bin.dart` 入口 | `if (!file.existsSync()) return false` | 只剩侧车 ⇒ **删不掉**，种子原地留着 | 侧车也算源：搬进回收站并清干净（用例：`trash_delete_bak_test.dart`） |
| `storage_trash_bin.dart` 侧车删除 | 正文已 rename **之后**裸 `await backup.delete()` | 抛出 ⇒ 调用方看到「删除失败」，文档却已消失 | 收进 try + 审计 `trash.delete.bak_left` |
| `note_block_doc_store_trash.dart` 入口 | 同上早退 | 同上（这一族还喂同步，形状是「基线有、清单无」⇒ 云端 `DELETE`） | 同上（用例：`block_doc_delete_bak_test.dart`） |
| `note_block_doc_store_trash.dart` rename 失败的回退分支 | 直接 `return true`，**没调** `_removeBak` | 用户删进回收站了，盘上还留一份 `.bak` | 回退分支也清侧车 |
| `_removeBak` | `catch (_) { // 忽略 }` | 静默失败 = 没人知道这里着过火 | 落审计 `note_block_doc.delete.bak_left` |
| notebook 家族 | 本来就是「正文或侧车都算存在、删就一起删、失败落审计」 | — | 只改了一句**错注释**（原文写「旧备份不再参与加载」，而 `notebook_storage.dart:224` 确实会回退读 `.bak`） |

**托管图片回收（同批已修）**：`storage_media_store.dart` 的引用扫描同样只认
`.json` ⇒ 处于「只剩侧车」形态的画布，其图片会被当无引用孤儿**回收掉**，而正文还能
从侧车读回来（图片真没了、画布还在）。现在引用面把「正文缺失且有侧车」的那一篇也算
进去，两条边界各有用例与突变自证：

- 侧车那篇与别的文档**交叉引用**同一张图 ⇒ 图保留（`continue` 掉第二趟就红）；
- 正文还在时上一版侧车的引用**不算数** ⇒ 图照常回收（把它也算进来就红）——
  每一次成功保存都会留一份上一版，若连它一起算，「回收」就退化成只增不减。

制造这种形态的主要成因（失败的写、删不掉的残留）本批也已堵住；这一条是**老数据根里
可能已经躺着残留**的止损，不是重复防护。

## 6. 这一批怎么做才算数（复现步骤）

1. `cd drawing_notes_app`
2. `NO_PROXY=127.0.0.1,localhost flutter analyze` ⇒ 必须 `No issues found`
3. `NO_PROXY=127.0.0.1,localhost flutter test test/core/storage/ test/core/operation/ test/core/documents/ test/storage_staleness_guards_test.dart` ⇒ 全绿
4. `linecheck --config linecheck.yml lib/` ⇒ 退出码 0（warn 不算失败）
5. **突变自证**：每条新断言都要能指出「把生产里哪一行改坏，它会红」。本文件 §1/§2
   的行来自 `c55dd3b` 的三道突变（备份失败不抛 ⇒ 4 红；失败不回收 tmp ⇒ 3 红；
   去掉 `.json` 过滤 ⇒ 残留那条红），已还原并复跑。
6. 全量 `flutter test` 以 CI 为准（本仓直推 master，实测 7 个编排；`ci.yml`
   是 `cancel-in-progress`，只看最新 SHA）。
