# 外部专家审计整改清单（分类整理版）

> 来源：2026-10-10 外部四轮深度审计（安全/同步/架构 → 绘图引擎/文档模型/存储 →
> 控制器/Stroke/编解码 → Storage/History/RenderCache/Sync）及其附带的
> 《v1.0 专家级整改方案》《文件级改造清单》。
>
> **本文件不是外部意见的原文转抄**——每一条都对照本仓实际代码重新核实过状态，
> 并校正了外部意见中与本仓事实不符的断言（见 §三）。用途：作为下一代内核升级
> （v2 Kernel Upgrade）的长期 backlog，防止意见散失、防止照过期前提施工。
>
> 与既有台账的关系：`docs/audit_2026-10-05.md`（untracked）记录的是**当前产品线**
> 的审计闭环（P1/P2 已清、P3 已清、发版项已结）；本文件记录的是**下一代架构
> 投资**，不在当前发版节奏内执行，动工前按 AGENTS.md 铁律逐项征求授权。

## 状态图例

- ✅ 已解决：外部审计提出时本仓已实现（附证据）
- 🔶 部分成立：问题真实存在但已有实质缓解
- ✗ 不成立：外部意见与本仓事实不符（见 §三校正表）
- 📌 成立待做：确认成立、列入 backlog（附建议优先级）

---

## 一、安全域

| 编号 | 外部意见 | 核实状态 | 证据 / 说明 | 处置 |
|---|---|---|---|---|
| S-001 | KEK/DEK/session key 驻留 Dart heap，`fillRange(0)` 无法保证 GC 快照/VM 拷贝清除；建议 native 隔离（DPAPI/CNG、Android Keystore） | 🔶 部分成立 | 生态限制属实。现有缓解：锁定路径逐字节擦除（VaultKeyService.lock / SessionSecrets.clearAll / KEK SessionCache hidden 即清）；快速解锁已走 DPAPI/Keystore 绑定（QuickUnlockService）。但主密钥/媒体 DEK 确实常驻 Dart 内存（设计取舍：本地优先、解锁态可用） | 📌 P2 长期：native 密钥隔离属架构级投资，收益集中在「设备被攻破后内存取证」场景；记档待产品定位升级（企业/高机密）再动。短期不作为 |
| S-002 | 4 位 PIN 空间 10⁴，离线拿到 pin_hash+salt 可暴力；建议默认 ≥6 位或 PIN+生物识别 | 📌 成立待做 | `AppLockService.minPinLength = 4`（app_lock_service.dart:72）；Argon2id + 指数冷却只提高在线成本，离线熵由 PIN 长度决定。**低成本高收益** | 📌 P1 产品口径：新设 PIN 默认引导 ≥6 位（设置页文案 + 默认档），是否强制升至 6 需产品拍板（影响既有 4 位用户口径）；生物识别已有（快速解锁），文档可补「建议搭配」 |
| SEC-DOC-001 | 明文工程文件无格式签名，任意 JSON 都会被尝试解析；建议文件头 `DNOTE + version + checksum` | 📌 成立待做（低） | 加密文件已有 DNV 魔数+版本头（VaultFileCodec）；明文 JSON 确无签名。注意：加签名=改格式，需与迁移框架（DOC-001）同批做，单独做会制造第三种格式 | 📌 P2，并入 DOC-001/Binary Format 批次，不单独做 |
| — | 防爆破/LockoutGuard/恒定时间比较 | ✅ 已解决 | 外部审计自己确认「方向正确」 | 无 |

## 二、绘图内核域

| 编号 | 外部意见 | 核实状态 | 证据 / 说明 | 处置 |
|---|---|---|---|---|
| DRAW-001 / DRAW-005 | 磁盘虽已扁平数组，**运行时仍是 `List<StrokePoint>` 对象**；百万点级 GC 压力/内存/序列化开销大 | 📌 成立待做 | `stroke.dart:89 final List<StrokePoint> points`。属真实瓶颈，但**当前用户规模（手写笔记）距百万点尚远** | 📌 P0（内核升级批首个任务）。方案采纳外部建议：`StrokeBuffer(Float32List)` + 兼容 getter + 双轨迁移；动工前先立性能基线测试（外部 TASK-001 建议，采纳） |
| DRAW-002 | Undo 若是文档快照会爆内存，应改命令模式 | ✅ 已解决 | **已是命令模式**：`document_commands.dart` 有 AddStroke/EraseStrokes/TransformStrokes/LayerVisibility/LayerOpacity/LayerReorder/ReplaceStrokeWithShape/DocumentImageState 等命令 + SnapshotCommand 仅用于大操作兜底；`DocumentEditHistory` 管游标/分支裁剪 | 无（外部第三轮自己也确认了） |
| HISTORY-001 | Command 长期运行无界增长 | ✅ 已解决 | `DocumentEditHistory({required this.maxEntries})`：超限丢弃最早、游标居中先裁剪重做分支（document_edit_history.dart:8-42） | 无。Level2/3 压缩历史（外部建议）属锦上添花，记 P2 观察项：若真机出现长会话内存压力再做 |
| DRAW-003 | 无限画布缺空间索引（R-tree），遍历全部对象渲染会崩 | 🔶 部分成立 | 现状=图层级显隐/离屏缓存 + 逐层遍历；**未发现对象级空间索引**（u2_canvas_perf_test 守性能基线）。手写规模（千笔级）现状够用 | 📌 P0（与 RENDER-001 同批）。先写 10 万笔基准确认实际拐点，再决定 R-tree 范围——避免为不存在的规模提前施工 |
| RENDER-001 | 图层缓存粒度粗，缺 512² Tile 系统 | 📌 成立待做 | 现状 `LayerRenderCacheCoordinator`（图层级离屏缓存 + 增量脏矩形），无对象级瓦片 | 📌 P0（内核升级批）。Tile 系统是大改，须与 DRAW-003 空间索引同设计（瓦片失效依赖空间查询）；有 4K 画布/10 倍缩放的性能投诉再提前 |
| RENDER-002 | 缩放分级缓存（MipMap）缺失 | 📌 成立待做（低） | 同上，依赖 Tile 系统 | 📌 并入 RENDER-001 批次尾部 |
| DRAW-004 | DrawingController 仍承担过多职责（输入/状态/历史/缓存/事务） | 🔶 部分成立 | 已拆 StrokeInputSession/SelectionSession/LayerEditingSession/History/命令等（外部第三轮确认）；controller 主文件+15 part 靠行数棘轮看住（本仓 2026-10-10 已立库级 7120 棘轮） | 📌 长期方向记档（Kernel/Adapter 分层）。「继续拆」不设排期——以棘轮+DCM 门禁看住腐化，等真实扩展需求（AI/协作）出现时顺势拆 |
| PERF-001 | stroke 简化/平滑/缩略图应下 isolate | 🔶 部分成立 | JSON/加密/ZIP/PDF 已在 isolate（README 宣称项落地）；绘制热路径已 frameTick 驱动 | 📌 P1：动工前先 profile 定位（避免搬移反噬——小数据 isolate 往返更慢）；有实测卡顿点再做 |

## 三、外部意见校正表（⚠️ 防止照错误前提施工）

| 外部断言 | 本仓事实 | 证据 |
|---|---|---|
| 「Undo 可能是文档快照，需改命令模式」（DRAW-002 前提） | **早已是命令模式**，快照仅大操作兜底 | document_commands.dart 全套命令类 |
| 「缺少保存队列优先级/合并，连画 4 笔会存 4 次」（STORAGE-003） | **SaveScheduler 已实现 coalesce + 快照稳定收敛**（防抖 5s、`_coalescedSave`、直到快照稳定才收敛） | save_scheduler.dart:178-251 |
| 「tmp 文件断电残留无处理」（STORAGE-001 部分） | 已有**孤儿 tmp 清扫**（VaultKeyService._sweepStaleTmpFiles + A4 写失败清理 tmp）+ `.bak` 崩溃恢复 + `readWithRetry` + Windows errno 32/5 退避 | vault_key_service.dart / storage_write_pipeline.dart |
| 「无冲突处理」（SYNC-001 前提） | **冲突可见**：sync_conflict 有冲突计划整合，README 宣称「冲突可见性」；但确实非 CRDT/operation 级（见 SYNC 项） | sync_conflict.dart:210-241 |
| 「点列 JSON 对象开销大」（DRAW-001 前提） | **磁盘侧早已扁平数组**（外部第三轮自己也确认）；仅运行时未二进制化 | stroke.dart toJson |
| 「文档无版本概念」 | 有 `latestVersion=2` + 高版本拒绝打开 + 旧版本向后兼容解码；缺的只是**形式化迁移管线** | document_codec.dart:34 |

## 四、文档与存储域

| 编号 | 外部意见 | 核实状态 | 证据 / 说明 | 处置 |
|---|---|---|---|---|
| DOC-001 / DOC-003 | 缺形式化 Migration 框架（v1→v2→…管线、MigrationRunner） | 🔶 部分成立 | 有版本门+防御解码+向后兼容缺键兜底；无正式管线。**当前仅 2 个版本，真实迁移需求=0**；但块文档已有 v4→v5 密码信封等历史包袱，证明版本演化会持续发生 | 📌 P1：**下一个破坏性格式变更出现时**顺势立 `core/documents/migration/`（Runner+注册表+逐级迁移），不为存在而存在；SEC-DOC-001 签名同批 |
| STORAGE-001/004 | 缺 Write-Ahead Journal（断电极端态：旧文件+tmp+bak 三态不明） | 🔶 部分成立 | tmp+rename 原子 + bak + 恢复读 + 孤儿清扫已覆盖绝大多数断电窗口；journal 是锦上添花的极端加固 | 📌 P2：真机出现「三态不明」实际案例或入政府验收清单再动 |
| STORAGE-002/005 | 万级小文件 NTFS 退化；JSON 大工程打开慢，建议 manifest+binary 分层 | 📌 成立待做（远期） | 现状单文件/文档 + 统一数据根；万级文档为远期规模 | 📌 P2：与 Binary Format（DNOTE 容器）同属「格式代际升级」，绑定版本 3 一起规划 |
| — | DocumentCodec 防御（大小/数量/坐标上限、高版本拒绝） | ✅ 已解决 | 外部第三轮确认「比很多个人软件成熟」 | 无 |

## 五、同步域

| 编号 | 外部意见 | 核实状态 | 证据 / 说明 | 处置 |
|---|---|---|---|---|
| SYNC-001 / SYNC-002 / HISTORY-002 | 快照级同步会互相覆盖；应统一 Operation Log（Undo/Sync/协作共用） | 🔶 部分成立 | 现状=文件级快照+冲突可见+加密；Operation Log 是真实方向，但**是三代架构**（依赖 Operation Engine 与内核解耦先行），当前单用户双设备场景实际风险可控（冲突可见不静默覆盖） | 📌 P2（内核升级后的大版本）。前置：Operation Engine 落地；产品前提：多设备高频同编成为真实场景 |
| SYNC-003 | 冲突解决需用户可见的「冲突中心」（保留A/B/合并） | 🔶 部分成立 | 冲突可见已有（设置页同步流程内）；「合并」确实没有 | 📌 P1 小项：冲突**选择 UI**（保留云端/保留本地）可低成本补；「合并」依赖 Operation Log，不承诺 |
| — | 同步结构（cipher/conflict/planner/progress/retry/service） | ✅ 已解决 | 外部确认「比一般 WebDAV 好」 | 无 |

## 六、架构与扩展域

| 编号 | 外部意见 | 核实状态 | 证据 / 说明 | 处置 |
|---|---|---|---|---|
| ARCH-001 | core 正在变胖，未来会成「万能垃圾桶」，建议 kernel/services/platform 三分 | 🔶 部分成立 | core 现有八域各有边界；已有三重看门：dart_arch_test 9 规则（层方向/循环/feature 隔离/洋葱/耦合度量基线）+ sloc-guard 结构门（目录文件数上限）+ 架构边界棘轮。**三分是大迁徙**，无真实扩展需求时纯属搬家风险 | 📌 方向记档不排期。触发条件：AI/协作/插件市场任一真实立项时，按该域独立成 `services/<x>` 顺势走，不做一次性大拆 |
| PLUG（外部建议） | 不要直接开放 Dart 插件，走 Manifest+权限+IPC | ✅ 与现状一致 | 当前插件系统**无生产装配点、无第三方加载**（能力接口仅 log，§七已挂起待产品愿景）——外部担心的「执行第三方 Dart」攻击面目前不存在 | 📌 已有挂账口径；PluginContext 设计重启时把 Manifest/权限模型作为前置需求吸收 |
| AI（外部建议） | AI 不得直改 Document，须走 Operation | ✅ 与现状一致 | 本仓**无 AI 功能**（README 硬性约束「无 AI」）；NOVA 接口（core/plugins/nova_ai_plugin.dart）设计即「返回 proposal、不改文档」 | 📌 记档：若产品解除「无 AI」约束，按该原则设计 |

## 七、执行队列（核定后顺序）

> 原则：**性能与格式投资全部后置于真实规模信号**；动工前先立基线（外部 TASK-001
> 采纳：`test/performance/` 大笔迹/长会话/大文档三基线）；双轨迁移、每步可回滚、
> 每任务独立提交（外部整改方案的原则与本仓 AGENTS.md 铁律一致，照单执行）。

| 批次 | 内容 | 触发条件 / 前置 |
|---|---|---|
| **内核 P0** | ① 性能基线测试（先做，量化拐点）→ ② StrokeBuffer(Float32List) 双轨迁移 → ③ 空间索引 + Tile 渲染（同设计，含 MipMap） | 有 10 万笔级性能投诉，或进入「专业绘图」产品定位时一次立项 |
| **数据 P1** | ④ 迁移框架（Runner+注册表，随下一个格式变更顺势立）+ 文件签名 ⑤ 冲突选择 UI（保留A/B）⑥ PIN 默认 ≥6 位引导（产品口径） | ④绑定版本 3；⑤随手批；⑥设置页文案批 |
| **长期 P2** | ⑦ Operation Log 统一（Undo/Sync/协作）→ CRDT ⑧ DNOTE Binary 容器 + 文件分层 ⑨ Storage Journal ⑩ native 密钥隔离 ⑪ kernel/services/platform 三分 | 各自有明确触发条件（见上表），不预设排期 |

## 八、验收标准摘要（采纳外部定义，校准到本仓口径）

- 性能：基线报告（`test/performance/performance_report.md`）证明目标规模（按真实产品定位定，不空谈百万笔）下加载/内存/FPS 达标；
- 数据：旧版本文件永久可开（迁移管线有逐级测试）、崩溃恢复窗口有测试钉住；
- 同步：冲突永不静默覆盖用户数据（现状已守住的底线，升级后必须保持）；
- 架构：dart_arch_test 9 规则 + 棘轮门禁在每次迁移后仍然全绿——**任何内核改造不得以放宽门禁为代价**。

## 九、变更记录

- 2026-10-10：初版。整合外部四轮审计意见，逐条对照代码核实，13 项已解决/不成立被校正，11 项列入 backlog（P0×3 组、P1×3、P2×5）。
