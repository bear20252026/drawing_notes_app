# 变更日志（Changelog）

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.17.61] - 2026-10-04

### 审计批 AK→AQ 收尾：切后台即锁全量落地、两处静默覆盖收口、门禁恒绿病灶加固

> 收 v1.17.60 之后的 11 个提交：`f23d445`（CI 触发）→ `8f3cd3d`（行数硬上限）
> → `1144f32`（README 校正）→ `5bc77e1`（AK）→ `9520f8d`（AK2）→ `51f81fb`
> （AL）→ `fa349f7`（AM）→ `8afe3e1`（AN）→ `9f33c86`（AP）→ `bbbf569` +
> `3f08ab5`（AQ）。各批本地 `flutter analyze` 均 No issues found、被改域测试
> 全绿；全量 `flutter test` 按 AGENTS.md §6 云端验证纪律交 CI 五工作流裁决
> （无一批跑过无文件参数的全量套件）。

**数据完整性**

- `keepBoth` 冲突下远端副本不再被静默覆盖（AK2）：远端副本在上传**之前**取回
  （`sync_service.dart:235-237`），而 keepBoth 在纯函数层被强制成 upload
  （`sync_conflict.dart:246-252`）；旧实现对 GET 返回 null 与 catch 两条分支
  都 `continue`、随后仍 PUT ⇒ 本地版本覆盖云端同路径唯一副本（AES 路径由当前
  密钥确定性导出），用户零可见性，直接违「冲突必须可见/禁止静默覆盖任一侧」。
  改为取回抛错/解密失败/本地落副本失败 ⇒ 计入**新字段**
  `SyncResult.unprotectedRemoteDocIds`（不并入 `unreadableDocIds`，后者语义是
  「执行失败」，此为「为保护远端而主动跳过」）并剔除本轮该文档的 upload op
  ⇒ 零 PUT；404（云端本无此对象）不跳过，否则永不能同步；基线退回本轮开始值、
  远端清单保留真实条目（不谎记进度，幂等与收敛不破）；每轮每文档仅 1 次 GET
- 图片裁剪的「文档几何更新」与「磁盘写入」成对（AK2）：原时序是写盘成功 →
  复查 `mounted` → 才改 `img.x/y/width/height` ⇒ 写盘期间退出编辑页则磁盘是
  裁剪后像素、文档仍是裁剪前矩形（永久拉伸/错位）。选型 A：先 `applyRect` +
  标脏（交既有 5s 防抖／退出兜底）再进闸门写盘，非成功结果码或异常一律回滚
  `applyRect` 并再标脏，`finally` 放行快照；几何更新不看 mounted、仅 UI 反馈
  看；`_persistArtwork` 编码快照前等闸门（上限 5s），防「快照先于写盘取、后于
  写盘落」。方案 B（把 doc 更新移到 mounted 复查之前）经核实**不成立**——
  `editor_page.dart` dispose 已 `unawaited(flushIfDirty)` 而 `save_scheduler`
  在 `_disposed` 后 `markDirty` 直接 return，缺陷只会换向复发
- 裁剪保留原图（AK）：`editor_image_crop.dart:203` 在 tmp+rename 之前先做
  `*.bak` 逐字副本（A-01 只修了原子性、原像素仍不可恢复）。选 `.bak` 而非
  「新路径 + 切换引用」的依据：DNV 的 AAD 经 `contextForPath` 绑定文件**基名**，
  换基名破坏绑定；UI 只按在档精确路径读图、从不自动读 `.bak`；`backup_service`
  已排除 `*.bak`；fail-closed 与 GPU 纹理释放逻辑未动
- 审计哈希链滚动裁剪后不再自证「已篡改」（AK，P3 提级为真实回归）：更正上一轮
  口头结论——`verifyIntegrity()` 在生产**有消费方**（`settings_page.dart:300`
  展示审计完整性），长会话写入超上限后正常日志会被 UI 误报为已被篡改。裁剪头部
  时记录 checkpoint（`_droppedCount` + 新链首条 `prevHash`，
  `audit_logger.dart:29-37`），`verifyIntegrity` 从当前链真实起点重放而非假装从
  genesis 起，`clear()` 归零锚点；「篡改既有条目必断链」不回退。本类严格仅内存、
  无文件 IO，checkpoint 单独落盘而 entries 不落盘无意义 ⇒ 未新增持久化路径/公共 API

**安全：切后台即锁（AP `9f33c86` + AQ `bbbf569`/`3f08ab5`）**

- 锁屏门补 `inactive`：抽出 `_isBackgroundSignal`（inactive/hidden/paused 三信号
  统一，`app_lock_gate.dart:207`）与 `_onBackgroundSignal()`，仅在 `!_locked`
  且非豁免期置锁并锚宽限表；回前台一律走同一条 `AppLockService.verify`——失败
  计数、指数冷却、v1→v2 透明升级、保险库解锁、快速解锁语义全部不变，冷却期内
  新路径不获得旁路；`hidden` 清 KEK/SessionSecrets 加 `!LockExemption.isActive`
  守卫（`:171`）
- 桌面宽限期起点重锚（此前事实上从未正确起表）：原锚 `paused`，而 Flutter
  桌面/Web 从不投递 `paused` ⇒ 宽限期形同虚设；改锚「首个非豁免后台信号」，
  同一后台会话的后续信号（resumed→inactive→hidden→paused 链）仅首个锚表、
  其余直接返回 ⇒ 不重锚、不吃免死金牌
- 豁免机制进程化：从 `SessionGuard` 私有态抽出共享 `LockExemption`
  （`session_guard.dart:28`，计数 + 单调 `Stopwatch` TTL 默认不豁免，TTL 5 分钟
  对齐原值——漏 `end` 即过期失效，不给无限期豁免），`runWithExemption` 改委托，
  消除「豁免只存在于 SessionGuard、门拿不到」的结构性缺口
- U 盘选择器单点根治（AQ）：`password_reset_disk.dart:51-56` 把原生
  `getDirectoryPath` 包进 `LockExemption.run` ⇒ 全仓该直调恰 1 处，
  `doc_page_password.dart` 与 `password_reset_common.dart` 三处下游经此自动进
  窗口；既有外层包法转为嵌套、成对复位已测
- 存盘对话框接入（AQ，实测 14 处而非上批报的 11：editor_exporter 11 +
  settings_page 2 + nb_manage 1）：新建单点封装
  `editor_exporter.dart:81-92` `_pickSaveLocation` 收 11 条导出路径、另 3 处
  就地圈住 ⇒ 改后全仓 `getSaveLocation(` 直调恰 4 处（封装内 1 + 就地 3），新
  门禁断言该数字并逐处判是否已圈住（与 AJ 批「vacuous 分母」同一思路，防接入点
  被静默回退）；上批挡住的一处（part 不能带 import）由库本体
  `editor_page.dart:59-61` 加 `show LockExemption` 打通，画布 `openFile`
  （`editor_page_editing.dart:260-261`）只圈那一次原生调用
- 窗口范围逐处自查：对话框一关即释放，readFrom/writeTo/绑槽/encryptAndSave/
  渲染/合成/报告构建/写盘/解密导出全在窗外 ⇒ 不存在「豁免吞掉 hidden 清 KEK」
  的情形，拒绝接入的点：无；取消 / 返回 null / 空串 / `PlatformException` 四条
  路径均断言豁免已释放且 `remaining==0`（这类代码最典型的缺陷是取消/异常时泄漏
  成永久豁免），拆掉 `LockExemption.run` 即 3 例转红（突变自证）

**安全：同步口令轮换诚实化 + 加密下沉（AK）**

- 根因证据链：`sync_controller.dart:112` 一侧复用 `existing.syncSalt` +
  `remotePath = HMAC(key, ctx|docId)` ⇒ 换口令即新 key、远端对象名整体错位、
  固定名 `manifest.json` 用新 key 解不开旧密文；原实现抛裸 `FormatException`
  中止整轮、退避重试满 4 轮后只给「请检查网络与账号」泛化文案，孤儿确无清理
  （`listLeafNames` 零生产调用方）。交付为**诚实化，非协议改造**：保存前零网络
  预检 `willRotateSyncKey` + `save(confirmKeyRotation:)`，未确认即抛
  `SyncKeyRotationConfirmationRequired` 且一个字节不上盘（https 门禁仍排最前）
  + 设置页二次确认弹窗
- `SyncKeyMismatchException`（文案逐字不变，以免破坏 `on FormatException`
  消费方）；认证类失败一轮即止不再空耗重试链；`SyncResult.unreadableDocIds`
  把「多少条远端数据解不开」写进摘要
- 同步 AES-GCM 从主 isolate 下沉：`sync_cipher.dart:115`
  `isolateCodecThreshold = 32 * 1024`（对齐文档存储侧 `_isolateCodecThreshold`
  同形态 JSON 字节档，取更低者——宁可早进不漏大文档；画布侧 2000 元素、
  StorageService 64 KiB）；≥阈值走 `Isolate.run`，闭包只捕获
  `Uint8List`/`String`，密钥以 32B 字节进 worker、不拼 String、不落盘、不进
  日志，AAD 绑定与 mode/v 分支原样，`finally service.close()` 未动

**可达性**

- README / README_EN 的「会话守卫」措辞两步收口：`1144f32` 先把名不副实的
  「失去焦点立即锁定」改为准确描述并**显式标注缺口为待办、不粉饰**（当时门只
  处理 hidden/paused/resumed、无任何窗口焦点监听，grep
  `FocusManager|onBlur|onFocus|WindowListener` 零命中）；`9f33c86` 补齐功能后
  改回「切后台/最小化/纯失焦(inactive) 全量锁定 + 宽限期锚首个后台信号 +
  原生对话框豁免窗口（默认不豁免、5 分钟 TTL）+ 回前台同一条 verify 管线」并
  删除 known-gap 段
- 口令轮换失败的 UI 文案给「填回旧口令 / 全量重传」的可执行指引，同步摘要
  新增条数上报（`syncRemoteCopyUnprotectedCount`）且只报条数不报 docId

**门禁与测试**

- CI 补 `push:branches[master]` 触发（`f23d445`，`pr-architecture.yml`）：原仅
  `pull_request`，而本仓走直推 master ⇒ 架构门里的 `tools/check_boundaries.sh`
  **从未在 CI 上执行过**（审计 2026-10-04 发现的门禁盲区）
- `notebook_storage.dart` 1027 行越 1000 硬上限（本批由媒体 fail-closed、SVG
  预检、独占区读写原语、会话口令回滚撑爆），按 ARCHITECTURE.md F9 的 O1 域分权
  纪律拆出 `notebook_storage_password.dart`（333 行，extension 收 9 个口令/信封域
  私有助手），本体降至 715 行、零行为变化；唯一必要文本改写是 11 处
  `_encryption.x` → `NotebookStorage._encryption.x`（extension 不能隐式访问被
  扩展类的私有静态）；拆分正确性以脚本证明（新本体 == HEAD 减 9 块 + 一行 part
  指令、整库成员名集合差集为空）
- 两处 vacuous 分母门禁加固（AL，纯 `test/`）：
  `test/security_static_access_gate_test.dart:74` 补被扫描文件数下限
  `_minScannedFiles = 120`（实测 217 = lib/features 195 + lib/shared 22，取
  ≈55%）；`test/focus_ring_coverage_test.dart:55` 补
  `expect(total, greaterThan(0))`（基线 38 处 `InkWell`）+ scannedFiles ≥180
  （实测 320）+ 4 条反向锁；判定逻辑各抽一份与主循环同源
- 突变实验取证（AL）：把 `maskDartLexically` 临时改为「非换行符全抹空格」，
  **加固前两份门禁均 +1 全绿（恒绿实证）**；加固后 C-06 -2、V-12 -4，主用例
  reason 为「分母为 0：扫了 320 个文件却匹配到 0 个 `InkWell(`」
- 纠正派单指令一处（AL）：原要求给 C-06 也加 `total > 0`——实查其中 `total++`
  与 `offenders.add` 在同一无条件循环体内、`total ≡ offenders.length`，合规时
  恒 0 ⇒ 照加即永久假红；真分母改用扫描文件数
- 「计数变量从无 expect」两处收口（AL，与 AJ 抓到的 `layerUndoRedoCount` 同类
  病灶）：`layer_editing_session_test` 补 1/2/2/1 精确通知数（逐条读码依据：
  `addLayer:77`/`moveLayerDown:132` 各 1、merge 仅 `rebuildAll:148`、
  `toggle:101` 两次、`clearCurrentLayer:160`/`clearAll:176` 不发通知、
  `setLayerOpacity:110` 发 1）；`m126_batch_test` 的 `purged >= 1` 改
  `equals(1)`，并把过期 sidecar 推到 31 天前、`retainDays` 用真实默认 30，新增
  「未过期兄弟项必须存活且不复活」
- 盲睡 oracle 消除（AL/AM）：`fix_regression_test` 三处 100×10ms 改为观测完成
  条件（上限 10s），`pumpUntil` 下沉为唯一一份
  `test/helpers/wait_until.dart` 的 `WidgetTesterPumpUntil` 扩展，`memory_p0`
  与 `editor_shortcuts_text_guard` 改引用；T-13 回退——AK2 新增两文件的裸
  `deleteSync` 改回共用 `test/helpers/temp_dir_cleanup.dart`（Windows 句柄锁
  flaky 类）
- 判据替代盲泵（AM）：webdav 设置页 4 处 2×100ms 改判据 `_formBuilt`/
  `_secretsLoaded`、2 处 2×300ms 改 `_saveSettled`；`app_shell_smoke` 三处改
  「首屏骨架退场 + DocPage 已推入 + 下层 GlassFab 已摘除」（实测原 500ms 是在
  赌路由过渡时长，过渡未完时 ⋯ 图标会数到 2 个，新判据严格更强）；`m126_batch`
  补盘上锁（`.json` 与配套 `.meta.json` 必须双双不存在/双双都在）
- T-09 潜伏雷复核（AM）：全库 52 文件出现 `pumpAndSettle`、42 有真实调用，但
  **同时**渲染 skeleton 的仅 `all_docs_page_test:94` 与 `u4_design_polish_test`
  5 处，且两处骨架在前置 pump 后已退场（实测全绿）；smoke/cuj_01 是真机实时钟、
  settle 即正确等待 ⇒ 结论无需改造
- 行数：`app_lock_gate` 779 / `session_guard` 171 / `editor_page` 884 /
  `editor_page_persistence` 453 / `notebook_storage` 715+333 /
  `editor_exporter` 919→900，均 <1000

**集成测试（AN `8afe3e1`）**

- 背景：集成测试不在 CI 覆盖范围（`flutter test` 不含 `integration_test/`，跑它
  要真机/模拟器）⇒ 文案改名零信号；`find.text('X')` 是运行时匹配，analyze 也抓
  不到。逐文件排查后按证据校正：`doc_lifecycle_test.dart:72`
  「新建笔记（打字）」→ arb `docsNewNote` 现值「新建笔记」（旧串在 `lib/` 零
  命中）；`toolbar_test` 13 串（画笔 (P)/橡皮擦 (E)/`toolEyedropper` 吸管工具/
  矩形选区 (R)/文字 (T)，证据 `editor_left_toolbar.dart:81/125/129/136/150`，
  旧串仅存在于**已删除的** `editor_toolbar.dart`）；`feature_test` 画笔与
  `barShowLayers`「显示图层」
- `cuj_01` 流程腐烂修复：原假设「FAB 直弹命名框」已不成立（起始页为 AllDocs、
  其 FAB 仅窄屏且弹三选项表），真路径是 HomePage `GlassFab.extended` →
  `_createCanvas` 两选项 → `_createDrawing` 弹 `_NameDialog`（见
  `integration_test/cuj_01_test.dart:24-31` 的证据注释）⇒ 补两步导航并把 finder
  限定在 HomePage 子树内
- **恒假断言修复**：`toolbar_test:61` 的 `isToolSelected` 原读
  `IconButton.isSelected`，而 `_tool` 从不传该参数 ⇒ 恒 false，「选中态」断言
  从未真的裁决过任何东西；改读真正的选中编码 Tooltip→Container
  （`BoxDecoration.color == AppleColor.actionBlue`）——命题不变，由恒假变为可
  裁决；`feature_test` 的 `if (evaluate().isNotEmpty)` 空跑守卫收紧为
  `findsOneWidget` 硬断言
- 新静态门禁 `test/integration_finding_text_gate_test.dart`（防复发）：语料 =
  两份 arb 非 @ 值（去重 1891）∪ `lib/**/*.dart` 字面量（3029）；匹配点 =
  `find.{text,textContaining,byTooltip,bySemanticsLabel}` 括号区间 ∪「形参直接
  喂文本 finder」的转发器区间；`enterText` 第二参登记为测试自备数据；变量实参
  计动态、插值/拼接计缺口并报警；复用 AJ 批修好的
  `test/helpers/dart_lexical_mask.dart`（未改动它）；分母下限
  4/20/1500/1891（实测 5/50/3029/1891）取保守比例并写明依据，避免正常重构随机
  变红；突变自证三条（注入两条不存在文案 / 只经转发器喂串 / 改回原漂移串）均
  精确转红；内置反向锁 A–F，**豁免表为空**

**i18n**

- arb 键数沿链推进且 zh/en 始终相等、零删除：1058（v1.17.60）→ 1064（AK 轮换 6
  键 `webdavKeyRotation*`/`syncKeyRotatedUnreadable`/`syncUnreadableRemoteCount`）
  → 1065（AK2 摘要 1 键）→ **1077**（AM +12 键，4 个插值键补 `@placeholders`）；
  gen-l10n 通过、`untranslated_messages` 为 `{}`
- L 域台账 22 条实查 20 条已闭环，AM 只补**真漏翻** 15 站：
  `embedded_block_view.dart:255`（L-08 唯一残留，新键 `docLinkNoHref`）、命令面板
  `hintText` → `paletteSearchHint`（同 widget 已接同族键，属不一致）、database 三
  视图同串归 1 键 `dbNoRecordsYet`、大纲栏复用现键 `docOutlineEmpty`、附件块
  `attachmentPlaceholder`/`attachmentNoUrl`、`tableGridSize(rows,cols)` /
  `docBacklinkCount(n)` / `propLineWidthValue(width)` 三插值、PDF 导出
  `pdfWholeBookHint`/`pdfRangeGroupLabel(n)`、`canvasTextOverlayHint`
- 判为**刻意不译**而未动：`main.dart:222-225` `_BuildErrorFallback`——类注释明文
  「兜底自身刻意零依赖，不取 `Theme.of`/`InheritedWidget`/`l10n`（出错上下文可能
  已损坏）」，ErrorWidget 兜底无 l10n 通道，硬接会引入新依赖风险
- AM 未改任何测试断言：所有 zh 兜底串与被替换硬编码逐字节一致，相关用例用裸
  `MaterialApp` 无 delegate 走 `??` 兜底，原 `find.text` 照常命中

**遗留与待裁决（本批未做，原样保留）**

- 规则 3b（承接 AJ / v1.17.60）的落地形态是**具名棘轮**：7 个 feature domain
  文件按实测 I 值钉上限（`test/architecture_test.dart:186` 起的
  `domainRatchet`，最高 1.00）、只紧不松，未列入者仍受 0.4 硬约束；**真正降耦
  （契约下沉 core / 组合根注入）未做**
- 同步口令轮换的「③一次性清理旧远端对象」**未做**，需协议/产品决策：要在保存
  路径新增网络腿并落盘旧路径清单（事实上的协议增补）；删除不可逆，其他设备可能
  仍持旧口令、远端文档可能是本地没有的唯一副本（与「禁止静默覆盖任一侧」直接
  冲突）；PROPFIND 非全服务器可用；清理与重传之间的崩溃窗口会让两端同时不可读
- 桌面**过度锁定**风险未消：Windows 多屏副屏、通知横幅、任务视图均投递
  `inactive` ⇒ 每次即锁；默认 30s 宽限可吸收 Alt-Tab 抖动，但长于宽限的遮挡会
  要求重验，真实多屏投递频率无法本地验证 ⇒ **需真机体验后再调**。Android 展开
  通知栏会锁（宽限内回来放行）；系统自发权限弹窗无我方接入点，仍可能假锁；长于
  宽限期的原生选择器（>30s）释放后回前台需重验（安全优先所致）
- **集成测试不在 CI 覆盖内** ⇒ 新加的文案门禁只防文案漂移、**不执行流程**；
  `find.byTooltip('返回')` 依赖框架 `backButtonTooltip` 能否 pop 无法静态证、
  `feature_test` 图层开关硬断言依赖窗口 ≥600dp、`cuj_01` 新增导航步与 `.last`
  覆盖层顺序——三条均待真机验证
- 门禁抓不到的两处产品侧疑点，均**待产品裁决**（按 AGENTS.md §7 保留入口铁律，
  本批未动）：①「插入图片」入口疑似在旧横栏重构中丢失——
  `integration_test/toolbar_test.dart:152` 的 `byTooltip('插入图片')` 入口已随
  旧横栏删除、`_insertImage` 无 UI 消费方 ⇒ 串在 arb 仍存活、门禁绿、真机必红；
  ②`integration_test/feature_test.dart:68` 断言 `LayerPanel` 常驻
  `findsOneWidget`，与 `editor_page_body.dart:90` 的 `if (_layersVisible)`
  （默认 false）冲突
- E-02（`dart_code_metrics` 5.7.6 上游停维护、要求 sdk <3.0.0）
  **处置未定**：CI 精确钉版 + `--disable-sunset-warning` 维持现状，备案论证见
  `.github/workflows/ci.yml:54-60`（残余风险仅「包被下架致激活失败」）；迁闭源
  dcm 需商业 license、移除门禁需用户同意
- 14 处 `getSaveLocation` 中 **2 处（备份 zip 与整本 PDF 导出）仅有静态门禁**——
  UI 级取消只在诊断 txt 站点实测；`openFile` 站点无 widget 级行为测试
  （`_insertImage` 私有且需整页装配），由债表门禁 + 封装行为测试覆盖
- AK2 残余：笔记本模式下整本落盘由父页 `_save` 承担（该批禁改 notes 域），闸门不
  覆盖，「卸载 + 写盘失败」同时发生才有理论残留、可经 `.bak` 复原；口令长期错配
  时每轮仍 1 次 GET（跨轮「已放弃」记忆需在基线谎记，风险更高，未做）
- AK 备案：审计链 checkpoint 仅内存，进程重启即空链（未加持久化，属加功能）
- 8f3cd3d 备案：`lib/` 下非 l10n 最大文件仍是 `editor_page.dart`（884 行，warn
  档既有祖父化，非本批引入）；`tools/cfg_notebook_storage.json` 是当年拆分用的
  一次性描述文件、无门禁消费，未随之更新

## [1.17.60] - 2026-10-04

### 全面审计批（AJ）：9 域并行审计 + 逐条读码复核，修 16 类已核实缺陷与 3 处门禁自身失效

> 审计基线 v1.17.59（`34133c8`），方法为 9 个专项域子代理并行扫描、全部结论由
> 宿主回读原始代码逐条复核后再定案（推翻 3 条误报）。分两个 commit 落地：
> `96261cc`（六包并行修复）+ `fbb2090`（收尾归因）+ 本批最后两处安全小项。
> 本机门禁：`flutter analyze` No issues found；`flutter test --exclude-tags kdf`
> 1974 通过/1 跳过/0 失败（03:29）；`--tags kdf --concurrency=1` 64 通过（04:25）；
> `tools/check_boundaries.sh` exit 0；架构九规则含修好的规则 3b 全绿。

**数据完整性（P0 两条）**

- 画布回收站过期判定由「文件修改时间」改为文件名携带的删除时刻（`rename` 不改
  mtime，原实现把「最后一次保存时间」当删除时间——30 天未编辑的画布一经删除
  即被物理清理，反悔窗口归零）；`listDocuments` 惰性清理补 1 小时节流。口径对齐
  块文档域 C14 备案
- 同一文件名解析另挖出第二处 P0：生成式 ID 本身含下划线，旧 `split('_').first`
  使 `restoreTrash` 把**不同文档**移回同一个 `documents/doc.json` 互相覆盖，
  且过期时间恒解析失败 → 改按最后一个下划线切分
- 块文档 / 分页画布共 7 个密码入口（设密/改密/绑盘/USB 重置/移除）的
  「读信封 → Argon2id 重绕 → 写回」整体移入同 id 独占区，消除重绕窗口内
  自动保存被陈旧快照反超覆盖的静默丢稿；口径对齐
  `StorageFilePasswordManager._readCurrentRaw` 既有纪律
- 懒迁移改在队列内重读磁盘，与入队快照不一致即放弃，不再反超较新保存
- 分页画布整本读改写在队列外完成的问题收口；`AppServices.dispose()` 接上
  调用点（此前注释承诺但全仓零调用，`dataVersion` 通知器泄漏）

**安全**

- 桌面收集模式不再接受空密码/过短密码（UI + 收集方 + store 三层 fail-closed），
  与移动端 `flexibleMinLength` 同口径；此前桌面可按两次回车把文档封成
  「显示已加密、回车即解」的空密码信封
- PinPad 字母/数字切换改为凭据单一真源（原切换后提交会静默丢弃已输入的数字段，
  导致设成非预期密码或永远解不开）；数字模式九宫格补高度自适应（矮视口下
  `0`/退格/确认被裁出屏幕，既不能提交也不能退格）
- 「新密码不得等于开屏密码」的探测改只读比对，不再消耗防爆破计数；无法判定时
  fail-closed 拒绝设密（原实现每设一次密记一次「开屏密码猜错」，且冷却期内
  静默放行同码）
- 加密笔记本媒体密封在锁定态改抛 `VaultFileLockException`（对齐画布域），
  再认证失败/无口令时不再谎报「会话已恢复」却不安装媒体密钥——该路径此前会
  把受密分页画布的新增图片明文写进 `notebook_images/`
- WebDAV 关闭自动重定向并逐请求化：原默认 `http.Client()` 跟随 3xx，而 https
  门禁只校验配置的 baseUrl，恶意/被劫持端点一句 302 即可把 Basic 口令带到
  非回环第三方，击穿「强制 https + 不经过第三方」
- 同步错误文案不再透传远端 `reasonPhrase`（服务器可控文本可直入 UI）；日志侧
  剥 `Basic <token>` 与 URL userinfo、折叠换行、截断
- 笔记本设密路径统一到三态只读探测；SVG 导入预检生产接线（此前只有测试引用，
  README 宣称的「导入隔离」实际未落地，白名单未删项）
- 会话口令缓存补写失败回滚（三处入口），对齐 `forgetFilePassword` 先例；
  桌面解锁输入框的 post-frame `requestFocus` 补 `mounted` 守卫

**正确性 / 可达性**

- 对象橡皮擦撤销还原原实例并按手势起始原始序号插回（原 `copy()` 追加致
  redo 失效、产生重复同 id 形状破坏箭头绑定、丢 z 序）；跨采样点索引基准同修
- 选区栏缩放/旋转滑块补提交笔画变换，且新手势边界「先结算再作废锚点」
  （此前把已改的几何变更从历史里抹掉：改了、存盘了、永远撤不回）
- 同帧多采样点脏区改并集（原覆盖留永久残影）；图层窄命令
  `afterLayerUndoRedo` 补真断言（此前计数变量从无 `expect`，删掉四行生产调用
  测试仍全绿）
- `mounted` 守卫补齐（同步设置页三处提示分支、`_openAllDoc`/`_newAllDoc`
  跨解锁弹窗复用陈旧 `Navigator` 引用）
- 桌面开屏锁补物理键盘通道（此前只认指针点击，违背三输入硬要求）；键盘与
  九宫格共用同一 `service.verify` 管线，冷却面板同样替换键盘槽，不获任何旁路
- 同步冲突判定加结构性「一端相对基线未动却在比大小中获胜」判据，时钟超前设备
  不再静默吃掉另一端的真实编辑
- i18n：未保存退出对话框正文、数据库单元格标题、批量移动 snackbar 接 arb；
  新增 `passwordEmptyHint` / `passwordTooShortHint`，zh/en 各 1058 对称

**门禁自身失效（危害面最大的一条）**

- `tools/check_boundaries.sh` 用纯文本 grep 把 C-10 迁移**文档注释**当 import，
  本地门禁恒红；且它只在 `pull_request` 触发，本项目走直推 master ⇒ CI 从未
  真正执行过它。已改为只匹配 import/export 语句行
- `architecture_test` 规则 3b 的 `Metrics.martin('domain/**')` 匹配零文件
  （`lib/` 无顶层 `domain/`），17 个 feature 领域文件从未被稳定性断言覆盖，
  注释里「实测 domain/core 最差 0.33」只基于 core 样本
- 两个静态门禁共用的注释/字符串遮蔽器不识别 `${...}` 内嵌引号，实证
  `conflict_resolution_dialog.dart:92` 使 `:95-99` 纯代码被整段抹成空格 ⇒
  错位区间内新增的裸 `InkWell(` 或被禁的 `VaultService.instance` 门禁看不见。
  已抽 `test/helpers/dart_lexical_mask.dart` 单份实现（补齐嵌套块注释、三引号、
  raw string、插值递归）并配独立回归
- 边界棘轮只认 `package:` URI，跨 feature 的相对路径 import 是盲区 → 补归一化，
  实测十条边与基线仍逐条相等

**本批两项治理决定（可回退）**

- 规则 3b 修好锚定后 7 个 feature domain 文件超 `I≤0.4`（最高 1.00）。逐条核实
  其出向依赖全部指向 `core/canvas_model` / `core/documents` 等内层共享数据模型，
  方向由洋葱规则判定合法，属 ARCHITECTURE.md §5 既定设计而非新增耦合。处置为
  **具名棘轮**：逐文件钉实测值为上限、只许调低，未列入者仍受 0.4 硬约束；
  真正降耦（契约下沉 / 组合根注入）另批
- 审计发现的「桌面失焦即锁不生效」未改：锁屏门 `didChangeAppLifecycleState`
  只处理 `hidden`（清 KEK 会话缓存）/`paused`/`resumed` 三个分支，**没有
  `inactive` 分支，整个门组件也没有任何窗口焦点监听**（grep
  `FocusManager|onBlur|onFocus|WindowListener` 零命中）。因此 Windows 上
  最小化能锁，但「窗口仍可见、只是焦点切到别的应用」以及 Win+L（通常只给
  `inactive` 甚至无 lifecycle 回调）**不会锁** ⇒ README 的「失去焦点立即锁定」
  在桌面名不副实（Android 的 paused/inactive/hidden 均投递，路径完整）。
  补齐需同步处理宽限期起点（现锚 `paused`）、文件选择器豁免（原生对话框抢焦点
  会假锁）与再认证代价（门走全 PIN 重输），属安全策略决策，待裁决

## [1.17.59] - 2026-10-03

### 维护批：import_request_guard 死模板删除（用户拍板）+ 图层显隐/换位撤销窄命令化

> 审计清零后的两项遗留收尾，同批发版；行为零变化（窄命令的可观测
> 语义与快照路径逐条一致）。

- **import_request_guard 删除**：`lib/core/import_request_guard.dart`
  （原 `import_guard.dart`，v1.17.54 C-12 更名消歧后实查 lib 内零生产
  消费方）+ 测试共约 190 行下架——异步请求代次过期守卫本意留作
  notebook 导入流接线预留，用户拍板删除（git 历史可随时找回）。
- **图层显隐/换位撤销窄命令化**（v1.17.53 P-05 批次明确留下的同病灶，
  彼时「不悄悄扩批」，本批收口）：
  - `LayerVisibilityCommand`（只记 索引/前/后 三个值）+
    `LayerReorderCommand`（只记 from/to 两个索引，undo/redo 互为反向
    removeAt+insert）——显隐是图层对象上的布尔翻转、换位不改图层集合
    成员与位图缓存（可见性/顺序是合成期参数），此前却各自提交全图层
    列表双份快照；
  - `DocCommandContext` 新增 `afterLayerUndoRedo()` 收尾钩子（钳制当前
    图层索引 + 通知，与快照路径 `_restoreLayers` 的钳制语义一致），
    DrawingController 实现；
  - **快照边界收窄**：图层增/删/合并/清空仍走快照（结构性/破坏性、
    低频用户动作，快照是最不易错的形式——P-05 对删除/粘贴的同款
    裁决）；`setLayerOpacity` 维持不进历史（既有行为）；
  - phase3 真控制器 move+undo 测试零改动穿过新命令（可观测行为
    一致的实证）；会话测试补窄命令载荷断言与显隐专测。
- 版本三处 1.17.59+128；门禁：本地 analyze 0；四道扫描门禁 + 受影响域
  37 用例全绿（图层会话/phase3/编辑历史/脏跟踪/事务/上下文桩）；全量
  按 AGENTS.md §6 云端验证纪律交 CI 五工作流裁决。

## [1.17.58] - 2026-10-03

### 跨端密码输入统一（C-14 兑现批）：UnlockFlow 全链路支持任意字符 + 笔记本设密路径统一

> 修复审计批次 AF 备案的跨端不对称——实查后根因比备案更严重：
> `DesktopUnlockField` 也带 `digitsOnly`（unlock_sheets:220-222），即
> UnlockFlow 全链路在**两端都只能收数字**；唯一字母密码通道是笔记本
> 自建 `_PasswordDialog`（无限制），而笔记本解锁又走数字-only 的
> UnlockFlow——**字母笔记本密码在任何端都无法解锁（自锁面）**。

- **① PinPadCore 文本切换模式**（429→457 SLOC）：新参数
  `enableTextInput`——底部动作区出现「字母/数字」切换键，文本模式下
  圆点与九宫格替换为 obscure TextField（任意字符、深色玻璃白字、
  AppleRadius.md），提交走与数字模式**同一校验管线**（验证失败
  heavyImpact+抖动+清空，成功/收集 → onAccepted）；空提交轻抖忽略；
  数字缓冲跨切换保留（文本输入不污染数字模式）；键盘弹出经
  viewInsets 避让 + SingleChildScrollView 防小屏溢出；模式切换不动画
  （解锁/设密属高频操作，频率闸门纪律）；减弱动效门控复用
  reduceMotionOf。
- **② DesktopUnlockField 放开字符**：新参数 `allowTextInput`——为
  true 时去 digitsOnly/数字键盘、不设长度上限；默认 false 时行为与
  既往逐字节一致（开屏 PIN 纯数字 + 4–12 计数）。
- **③ UnlockFlow 派生规则（21 处调用点零改动）**：`flexible: true` ⇒
  文本输入自动开启（移动端切换键 + 桌面端放开字符）。依据实查：
  flexible 当前仅被文件密码域使用（设/改/解锁/重置 21 处，密码可含
  字母），开屏 PIN 体系 8 处全部固定长度纯数字——一条参数完成场景
  分界；将来出现「可变长但纯数字」场景再加显式覆盖参数。
  **文本模式无 min/max 长度约束的原因**：既有超长/短密码（笔记本
  `_PasswordDialog` 时代所设）的**解锁**不能被 UI 挡在门外，业务校验
  由 onVerify 与收集方确认步骤承担。
- **④ 笔记本设/改密统一到 UnlockFlow（用户拍板；C-14 完全闭合）**：
  `_enablePasswordEncryption` 从 `_PasswordDialog` 单次收集改为
  UnlockFlow flexible **收集+确认两遍**（对齐 doc/重置流家族，消除
  obscured 误输无法察觉的自锁面）；改密的「会话密码免验旧密码」语义
  不变（两遍只收集新密码）；`_PasswordDialog` 类删除（80 行，含 C-14
  「记录不合并」裁决注释——前提已消失，裁决迁移至本条），原
  impSetHint/impChangeHint 的结果性信息由成功 snack 承载。
- **l10n**：新增 5 对（unlockKeyboardText 字母/ABC、unlockKeyboardDigits
  数字/123、unlockTextInputHint、impConfirmPasswordProtect、
  impPasswordMismatch）、删除 5 对孤儿键（nbPasswordHint/nbShowPassword/
  nbHidePassword/impSetHint/impChangeHint，删前实查零生产消费方）——
  净零，zh/en 1052=1052 对称；gen-l10n 生成文件同步提交。
- 版本三处 1.17.58+127；门禁：本地 analyze 0；四道扫描门禁（焦点环/
  安全 static/棘轮/架构九规则）+ 受影响域 451 用例全绿（新增
  pin_pad_text_mode_test 6 例 + desktop_unlock_field_test 4 例，
  pin_pad_flexible 回归、notes 全域、core/security、usability 回归、
  笔记本加密 v5）；全量按 AGENTS.md §6 云端验证纪律交 CI 五工作流
  裁决。

## [1.17.57] - 2026-10-03

### 审计批次 AI：C-07 装配机制统一 + app_shell 瘦身（架构域大项全部闭环）

> 子代理执行中因配额中断，宿主接手完成验证收尾；本批落定后
> 2026-09-27 全量审计 135 条全部闭环。

- **C-07 [P2] 装配四套机制收敛 + app_shell 三职责拆分**：
  - **装配收敛为「组合根单例 + Riverpod 作用域」两轨明文备案**
    （composition_root.dart 头注释即裁决原文）：服务单例装配唯一落点 =
    `CompositionRoot.createAppServices`——AppServices 的缺省装配体
    （blockDocStore/favoriteStore/tagStore/syncController/mediaCrypto
    实例创建）收进组合根，AppServices 构造器改 required 纯注入（门面
    不再隐式 new 缺省实现），AppShell 手工 new 就此清零（生产构造点
    全仓唯一：app_shell 经组合根装配）；Riverpod 维持页面/文档级作用域
    状态机制（drawingControllerProvider 等随页面生命周期），不属服务
    装配不进组合根；V2 可空 static 端口维持 S-005「IMPLEMENTED 未接线」
    现状，接线在 C-07 ID 下续批；
  - **app_shell 750→315 行**（远离 500 警告线）：路由装配职责
    （open* 方法群约 440 行）提取 `part 'app_shell_routes.dart'`
    （跟随 doc_page 六 part 库内拆分先例），主体只留导航 UI 与服务
    消费；**零行为变化**——路由参数、解锁拦截顺序、mounted 守卫、
    错误兜底逐条保持；
  - 子代理中断于验证环节，宿主接手：analyze 0 + 壳层/门禁 38 用例 +
    notes/all_docs 域 371 用例全绿（合计 409）。
- **同批收口（承 v1.17.56 CI 失败修复，先行 commit `fde9207`）**：
  C-08 拆出的四个服务协作类（写入管线/媒体资产/回收站/文件密码）在
  Martin 稳定层门禁（规则 3b，I≤0.4）命中——消费方唯一（门面，Ca=1）
  而 Ce=4~7，I 冲至 0.88。按门禁既有 vfs/document_codec 同款先例
  （「服务而非稳定数据层，不纳入稳定性断言」）具名豁免并注明理由；
  directories/secret_session 实测 I=0.17 达标保留在断言内——**基线未
  放宽，豁免面收窄到四个具名文件**，产品代码零改动。
- 版本三处 1.17.57+126；门禁：本地 analyze 0；架构九规则（含修复后
  Martin 门禁）+ 棘轮 + 安全 static 访问 + 焦点环四门禁绿；受影响域
  409 用例全绿；全量按 AGENTS.md §6 云端验证纪律交 CI 五工作流裁决。

## [1.17.56] - 2026-10-03

### 审计批次 AH：C-06 安全服务注入收敛 + C-08 StorageService 五职责分解（子代理执行 + 宿主 worktree 并行）

> 架构域大项第二波：C-06 由子代理执行，C-08 由宿主在独立 git worktree
> 与子代理并行完成（环境并发限一代理；两者文件所有权互不相交），宿主
> 合并门禁后统一提交。

- **C-06 [P2] 三个安全服务 static instance 全局可达收敛**：features 与
  shared 层**零 `.instance` 直取**（原 13 文件直取）——
  - 注入链：`MediaCryptoService` 经组合根（app.dart/AppServices 缺省
    装配）→ HomePage → SearchPage/NotebookViewPage（required 构造注入）
    → Reader/Presentation 页透传；编辑器链经 `EditorPageBuilder` typedef
    新增可选 `mediaCrypto`（tear-off 兼容）；`VaultService` 注入
    encrypted_file_image 与 NotebookPdfExporter；
  - `NotebookPdfExporter` 静态类改实例类（语义逐条保持）；
  - `notebook_storage`（infrastructure）可选注入：生产构造点唯一在
    组合根 app.dart:72，null 容忍降级与既有「会话密钥未注入」分支
    语义一致，生产恒注入行为不变——避免 25+ 测试构造点连锁；
  - **裁决**：`KekSessionCache` 的 5 个消费方全在 core 内部——解锁
    生命周期作用域的会话单例语义保留，三个服务文件仅落 C-06 裁决
    注释不改静态语义（对外 API 兼容优先，本体收敛留后续）；
  - **新静态扫描门禁** `test/security_static_access_gate_test.dart`：
    features+shared 全库遮蔽扫描三服务 `.instance` 零命中（core/app
    组合根豁免并写明理由），新增直取即红；
  - 未初始化分支同文 StateError 镜像原全局单例语义（生产不可达路径
    逐字保持）；EncryptedFileImage ==/hashCode 不含注入件（图片缓存
    键不分叉）。
- **C-08 [P2] StorageService 单类五职责分解**：原 639 行本体 + 4 个
  共享全部私有态的 part（O1 域分权 F9 只做了物理拆分，共 1371 行）
  分解为**六个真协作类**（各自持有自有状态，依赖无环）——
  - 目录域 `StorageDirectories`（四目录懒加载 + 路径推导 + ID 防遍历
    校验）/ 会话机密域 `StorageSecretSession`（文件密码 + v3 DEK/USB
    材料，D-2 擦除纪律原样保留）/ 写入管线域 `StorageWritePipeline`
    （per-id 写尾队列 + 三级密封分流 + 原子替换 + Windows 退避）/
    媒体资产域 `StorageMediaStore`（缩略图 + 受管图片，fail-closed
    读取）/ 回收站域 `StorageTrashBin`（M-06 移入/恢复/清理）/
    文件密码域 `StorageFilePasswordManager`（v2/v3 管理面）；
  - **门面保留**：StorageService 继续实现 DocumentRepository +
    SessionSecretsHolder，公共 API 逐一委托（含 `purgeTrash` 的
    retention 参数转发），**消费方与测试零改动**；媒体域经回调取
    密码域查询（构造序解环）；装配面注释「仅门面装配」；
  - 新文件全部 ≤411 行（≤500 警告线），core/storage 目录 19/40；
  - **同构病灶四处核实**：审计快照滞后——note_block_doc_store
    1234→647、drawing_controller 1118→730、notebook_view_page
    2051→627、doc_editor 库已分件，全部退至 1000 硬上限内（v1.17.47
    起的 C-04 系列批次实绩），本批不再重复动刀，落备案；
  - worktree 并行验证：analyze 0 + 存储域 221 用例全绿（文件密码
    v3/并发/回收站 retention/加密/安全回归全套）。
- 版本三处 1.17.56+125；门禁：合并后本地 analyze 0；三扫描门禁
  （安全 static 访问/棘轮/焦点环）+ C-06、C-08 受影响域合计 248 用例
  全绿；全量按 AGENTS.md §6 云端验证纪律交 CI 五工作流裁决。

## [1.17.55] - 2026-10-03

### 审计批次 AG：C-10 shared 伪共享归位 + C-05 WebDAV 设置页 DI 旁路根治（子代理执行）

> 架构域大项五条（C-05/06/07/08/10）的第一波，两单由子代理串行执行、
> 宿主统一验证提交；后续波次：C-06+C-08（批次 AH）、C-07（批次 AI）。

- **C-10 [P2] shared 层伪共享归位**：`shared/widgets/color_picker_dialog`
  与 `shared/application/search_service` 各自只有**一个** feature 消费方，
  伪共享解除——
  - 取色器迁 `features/drawing/presentation/dialogs/`（presentation 目录
    已满 sloc-guard 40 文件上限，落嵌套子目录；迁出后 39/40、dialogs/1，
    深度 5 合规），唯一消费方 editor_page 改引；其内部 4 条相对 import
    改 package: 绝对路径；
  - SearchService 迁 `features/notes/application/`，消费方
    search_page/home_page/390dp 门禁测试改引；
  - **core 契约实查零代码依赖**：`core/notes_accessor.dart` 无任何
    SearchService import/类型引用（只用自有 DTO，依赖方向本就
    features→core），仅第 83 行文档注释提及「shared 的」——随迁移更新
    措辞；`apple_palette.dart` 头注释里「取色器在 shared、边界禁止
    shared→features」的失效理由改写为归位后事实（结论不变）；
  - 测试随迁 ×2（search_service_test→notes/application、
    color_picker_rgb_input_test→drawing/dialogs），`test/shared/` 迁空
    移除；全库旧路径零残留。
- **C-05 [P2] WebDAV 设置页 DI 旁路根治**：审计三处构造点全部迁出
  presentation——
  - 实查确认：:112-113 `initState` new `WebDavConfigStore`/
    `SecureSyncSecretStore`；:231 `_syncNow` 全套装配 `SyncService`
    （transport+documentStore+baselineStore）；:341-345 私有
    `_buildCipher` 自选加密方案（Noop/PBKDF2 60 万次/AES）；
  - 新增 `notes/application/sync_controller.dart`（214 行，纯类门面，
    风格贴 AppServices）：四注入口缺省装配生产实现；`save` 收口
    S-03 空值沿用/盐复用/https fail-closed；`syncNow` 收口 cipher
    选择+装配+有界重试+`finally close`；`requireHttpsBaseUrl` 转发；
    页面所需纯值/异常类型经门面 `export ... show` 再导出——页面不再
    import 任何基础设施与传输实现文件；
  - 装配链：`AppServices.syncController`（可注入缺省装配）→
    `SettingsPage`（可选注入，null 仅测试装配）→
    `WebDavSyncSettingsPage`（required 注入）；app_shell 组合根传线；
    全仓页面构造点收敛为 settings_page 一处生产 + 4 处已更新测试；
  - 回归锁 +9：默认装配可构造/转发注入桩/S-03 空值沿用/盐复用/
    https fail-closed/requireHttps 转发/本地回环 HTTP 端到端一轮上传/
    500 按 SyncRetryPolicy 有界重试收敛等；
  - 刻意裁决：documentStore 缺省自建
    `NoteBlockDocStore(keyProvider: VaultKeyService...)` 而非复用
    `AppServices.blockDocStore`——后者无 keyProvider，语义不同。
- 版本三处 1.17.55+124；门禁：本地 analyze 0（子代理两单各自全量跑过，
  后单覆盖前单改动）；相关测试 129 用例 + 新增 9 用例 + 架构九规则
  单跑全绿；全量按 AGENTS.md §6 云端验证纪律交 CI 五工作流裁决。

## [1.17.54] - 2026-10-03

### 审计批次 AF：架构域小项包——C-09 四处跨 feature 直连清零 + C-12 更名消歧 + C-13/C-14 裁决记录

> 架构域余量 9 条（C-05~C-10、C-12~C-14），本批收口其中 4 条可独立
> 验证的小项；C-05~C-08、C-10 为大型重构专项（DI 收敛/装配统一/
> StorageService 分解/伪共享归位），留各自批次。

- **C-09 [P2] 四处跨 feature 直连收口（notes⇄all_docs 环解体）**：
  1. **doc→notes 展示件随迁**：`PdfAttachmentPreview` 全库唯一生产
     消费方是 doc 附件块视图（notes 自身从不使用），自
     `notes/presentation/pdf_preview.dart` 迁入
     `doc/presentation/pdf_attachment_preview.dart`（测试随迁
     `test/features/doc/`）——留在 notes 即一条无必要的 doc→notes
     展示层直连；
  2. **doc→security 注入化**：`DocPage` 新增
     `BlockDocPasswordResetLauncher`（签名只依赖 core 的
     `NoteBlockDocStore`），组合根（app_shell ×3、notes 首页 Tab
     ×1）传 security 的 `BlockDocPasswordResetFlow.show` tear-off，
     doc 内部反向链接打开路径透传——doc 展示层不再 import security
     展示层；launcher 为 null（测试桩）时解锁弹窗「忘记密码？」页脚
     不出现，与 allDocsLoader null 时隐藏反向链接面板同一先例
     （生产路径恒注入，入口不丢）；
  3. **notes⇄all_docs 环解体**：`AllDoc` 契约与 `buildAllDocs` 查询
     纯函数下沉 core（`core/all_doc.dart` / `core/all_doc_query.dart`
     ——首页与 All Docs 页两侧都消费，留任一侧都是环的一半）；笔记本
     输入改走新增只读契约 `core/documents/notebook_index_source.dart`
     （`Notebook`/`NotebookPage` 纯声明实现之，`List<Notebook>` 因
     Dart 泛型协变直接传入，调用点零改动），core 不反向依赖 notes
     领域实体。四处全清后 architecture_test 以 `shouldNotDependOn`
     双向锁死 notes⇄all_docs、锁死 doc→security 与
     doc→notes/presentation（同 C-01/C-03 解环先例）。
  - **棘轮基线四向下调**（只紧不松）：doc->notes 2→1（余为
    domain→domain 迁移映射，不在本批范围）、doc->security 1→0、
    notes->all_docs 2→0、all_docs->notes 1→0。
- **C-12 [P3] `core/import_guard.dart` 更名消歧**：实为「异步导入请求
  代次过期守卫」而非 import 方向治理（真门禁在 architecture_test/
  棘轮），文件与类更名 `import_request_guard.dart` /
  `ImportRequestGuard`（`ImportRequestToken` 不变），测试随迁随名。
  实查确认该件当前 lib 内零生产消费方（仅测试覆盖）——纯逻辑部件
  留作 notebook 导入流接线预留，删除另行征求同意。
- **C-13 [P3] 裁决：记录，不迁移**。`domain_display_labels` 依赖
  l10n 确属 core 方向例外，但该类就是「展示侧」契约（存储侧写空串，
  展示侧经 l10n 渲染），迁 shared 成 C-10 式伪共享、再往下沉拿不到
  AppLocalizations——裁决落文件头注释（审计 ID + 理由），零行为变化。
- **C-14 [P3] 裁决：记录，不与 shared UnlockFlow 合并**。两者仅在
  桌面端等价（DesktopUnlockField 是文本框）；移动端 UnlockFlow 走
  PinPadUnlockSheet **纯数字键盘**，而 `_PasswordDialog` 用于设置/
  修改笔记本文件密码（任意字符）——合并等于移动端只能设数字密码，
  属功能回退。裁决落 `_PasswordDialog` 头注释。顺带发现（备案不修）：
  doc 侧文件密码设置/解锁均经 UnlockFlow（flexible 12 位），移动端
  同样只能数字密码、桌面端可设字母密码——跨端不对称是既有行为，
  修复需给 PinPad 补文本输入模式，留待用户裁决。
- 版本三处 1.17.54+123；门禁：本地 analyze 0；architecture_test +
  棘轮门禁绿（新锁 4 条生效）；受影响域 110+ 用例全绿（all_docs
  全套/home_sync/doc_page/q0/u5/390dp 溢出门禁/焦点环门禁/更名守卫/
  锁定占位/PDF 预览迁移件）；全量按 AGENTS.md §6 云端验证纪律交
  CI 五工作流裁决。

## [1.17.53] - 2026-10-03

### 审计批次 AE：性能域清尾——P-05 选区撤销窄命令 + P-11 预览图封顶（P 域 13 条全闭环）

> 开工前逐条实查性能域五个待销账项（P-05/P-07/P-10/P-11/P-12），确认
> **P-07、P-10、P-12 及 P-11 的嵌入图半边早已闭环**——分别由 v1.17.47
> （批次 Y，#16 看板大列限高+卡片 builder）与 v1.17.37（批次 O，P-10
> 多槽缓存 / P-11 嵌入图量化 / P-12 焦点监听配平）修复，只是审计跟踪
> 未销账（同 R-10/S-08「已修但 commit 未写 ID」先例），故实际改 2 项。

- **P-05 [P2] 选区变换撤销窄命令化**：新增 `TransformStrokesCommand`
  （对齐同文件 `EraseStrokesCommand` 的增量先例，excalidraw StoreDelta
  式只存变更）——只记录受影响笔画的 (图层内位置, 变换前对象, 变换后
  对象) 三元组，内存 O(选中笔画数)；撤销/重做按索引直接覆写。此前
  变换经 `SnapshotCommand` 提交**全图层 before/after 双份快照**
  （O(全部图层全部笔画) 引用拷贝），撤销栈（容量 60）里每条变换常驻
  两份。配套：
  - 手势锚点 `DrawingSelectionSession.transformBefore` 从全图层快照
    `List<Layer>` 改为选中项 `(位置, 原对象)` 列表（字段为会话私有
    生命周期，全库仅 3 处读写，随契约改型）；
  - `endTransform` 按 identity 比对组装三元组——锚定后零变换即收笔
    不再产生空历史条目（原实现会提交一份无变化全量快照）；越界位置
    防御性跳过；
  - **范围裁决**：删除/粘贴等计数变更操作仍走快照桥接（低频用户动作，
    审计指向的是高频变换路径）；`layer_editing_session` 的层级操作
    同病灶不改（层结构变更的窄化属 C-08 分解专项，不悄悄扩批）；
  - **按索引覆写的 LIFO 正确性**落注释：命令栈按序回放，执行到本命令
    时文档必处于提交时状态（上方命令已忠实还原）——与
    `EraseStrokesCommand` 记录原位置插回是同一假设；
  - 回归锁 +2：会话级桩断言窄命令载荷（三元组位置/前后对象，且不再
    产生整层快照）；控制器级真命令栈锁「变换→删除交错 LIFO 撤销/重做
    按 identity 精确还原」。
- **P-11 [P2] 收尾半边：全屏图片预览解码封顶**：
  `image_preview_dialog` 的 `Image.network` 补 `cacheWidth`——按
  屏宽 × dpr 走 `ImageDecodeCap.quantizedCacheWidth` 量化（与嵌入图
  同源，2048 档封顶），数千万像素照片不再整幅进图像缓存。嵌入图半边
  v1.17.37 已修，预览为该条最后一处未封顶网络图通道；1:1 满屏物理
  像素内清晰，InteractiveViewer 4x 内放大由 GPU 上采样补足。
- 版本三处 1.17.53+122；门禁：本地 analyze 0（191.9s）；直接相关
  测试 13 个文件全绿（选区/撤销历史/命令/文档编辑/层合成域，含新增
  回归锁）；全量按 AGENTS.md §6 云端验证纪律交 CI 五工作流裁决。

## [1.17.52] - 2026-10-03

### 审计批次 AD：可达性 V-12 键盘焦点环全库覆盖 + 性能 P-06/P-09/P-13 三项

> 承接 v1.17.31~51 审计批次，本批闭环 2026-09-27 全量审计余下的可达性
> V-12 与性能域 P-06/P-09/P-13 共 4 条；零删改、纯增量包裹与参数传递，
> 用户可见行为除「键盘焦点环出现」外无变化。

- **V-12 键盘焦点可见性——全库 38 处裸 `InkWell` 统一包 `AppleFocusRing`**：
  审计实测「全库 0 处 FocusableActionDetector；裸 Semantics+Tooltip+
  InkWell 按钮键盘聚焦仅主题 focusColor overlay（深色底几乎不可见），
  无 2px Focus Blue 描边」——键盘用户 Tab 到按钮时看不出焦点在哪。
  本批按统一解法收口（`AppleFocusRing` 外扩绘制 2px Focus Blue 环，
  `canRequestFocus: false` 只观察不抢焦点，不多出 Tab 停靠；半径对齐
  各 InkWell 自身 borderRadius）：All Docs 行/侧栏/标签视图/移动端、
  块文档（编辑器工具条/斜杠菜单/大纲栏/表格勾选框与排序头/嵌入块/
  就地文本覆盖层）、画板（上下文工具条/顶栏重命名钮/图层面板/属性
  面板/形状库）、笔记本视图页、首页、共享件（取色器色板、PIN 码盘
  按键）。`core/theme/apple_focus.dart` 本身零改动（已是入库件）。
  - **新增静态扫描门禁** `test/focus_ring_coverage_test.dart`：扫描
    lib/ 全部 dart 文件，先做**等长遮蔽**（注释与字符串替换为空格、
    保留换行——否则 `apple_focus.dart` 文档注释里的用法示例会被当成
    真实调用，首跑即栽），再括号配对求每个 `AppleFocusRing(` 的覆盖
    区间，断言每个 `InkWell(` 都落在区间内——「新增裸 InkWell 即红」，
    与 architecture_test / 棘轮测试同一门禁思路。豁免表当前为空；
    将来加豁免须写明理由，不许为变绿删断言。
- **P-06 对象橡皮擦增量脏矩形重建**：`ObjectEraseStep` 新增 `dirty`
  字段 = 本采样点**被移除对象的包围盒并集**（笔画走
  `StrokeRenderer.strokeBounds` 含描边外扩；形状
  `rawBounds.inflate(strokeWidth)`——`rawBounds` 不含居中描边，宁可
  稍大不可偏小，否则大对象尾部残影）；`DrawingController.eraseAt`
  命中后把 region 传给 `_invalidateLayer` 做增量重建，null（无可见
  变化/包围盒不可得）安全退回整层。此前每命中样本整层重光栅化
  （层位图最高 ~24MB），拖擦大图层明显掉帧；书写路径早已传 region。
  回归锁 +1：断言脏区**下界**（覆盖对象原始外接范围）——比对象小就
  会在边缘留残影，故不与 strokeBounds 逐像素比对（那只证明同源，
  证不了不偏小）。
- **P-09 顶栏标题子树重建过滤**：新增 `TitleReadModel` 过滤型只读
  视图模型——在源通知回调里做签名比对（title + isDirty），**未变不
  转发**；标题子树（LayoutBuilder+Row+Chip）只在真变化时重建。此前
  直接挂整个 `DrawingController`，笔画提交/框选/图层切换等每次
  notifyListeners 都把子树白跑一遍。撤销/重做按钮仍挂全 controller
  （依赖历史可用性，且各只包一个 IconButton）。留 presentation 的
  part 而非 application：application 已 39/40 文件（sloc-guard 上限
  40），`editor_interaction_controllers.dart` 498 行（警告线 500），
  留在此处两者都不动。
- **P-13 拖擦进行中只 `tickFrame()` 驱动画布重绘**（对齐
  drawing_controller 既有高频路径纪律）：此前每命中采样点
  notifyListeners 整树重建，连续擦除手势随采样频率重建全页；改
  tickFrame 后顶栏标题/图层面板等全控制器监听者由 `endObjectErase`
  收笔时的唯一 notifyListeners 统一刷新。

## [1.17.51] - 2026-10-02

### 审计批次 AC：安全增量批——S-03 根治 + 令牌/间距/装配 16 项收口

> 承接 v1.17.31~50 审计批次，本批处理 2026-09-27 全量审计中**仍未闭环的
> 非架构类条目**（架构域 C-05~C-10、C-12~C-14 与性能 P-06~P-09、可达性
> V-12 留待各自专项批次）。开工前逐条实查过代码——审计快照已知会过时
>（先例 L-02/D-03），本次确认 **R-10、S-08 其实早已闭环**（分别由
> R-13、R-04 修复，只是 commit 未写 ID），故实际改动 17 项。

- **S-03 [P2] WebDAV 口令回填驻留内存——按「占位符模式」根治**：
  `webdav_sync_settings_page.dart` 此前把已存密码与 E2E 口令
  `?? ''` 回填进 `TextEditingController`，而 `SessionSecrets.clearAll()`
  （切后台触发）只清各 store 的会话缓存，**清不到 widget 树里的这份明文**
  ——堆转储可直接读出。改为：
  - `_loadConfig` 不再写口令框，只记 `_hasSavedPassword` /
    `_hasSavedPassphrase` 两个 bool，用 `hintText` 呈现「已保存 ·
    留空保持不变」（新增 arb 键 `webdavSecretKeepHint`，zh/en 对称
    1052=1052）；
  - **空值语义从「清空」改为「沿用已存」**：`_save` 先读已存机密再
    合并写回，`_syncNow` 的生效口令 = 表单非空 ? 表单 : 已存；
  - `formDirty` 同步改为「**非空且与已存不等**才算脏」——空框是常态
    而非未保存状态；
  - 代价：本页不再提供「删除已存口令」入口（该路径本就是 footgun：
    清空后同步要么认证失败、要么被 fail-closed 挡住）。
  - 回归锁 +3：明文不回填且不出现在可见文本 / 留空点保存不抹掉口令 /
    输入新值仍可覆盖（防止「留空沿用」把覆盖能力一起关掉）。
- **D-09/D-10/D-11/D-12/D-15/D-16 令牌与间距**：序号 `fontSize: 16`
  补离档论证（同 code 块 15px 的口径）；演示页 `EdgeInsets.all(40)`
  → `AppleSpacing.xl`；选区工具条触控算法统一为归档口径
  「20px 图标 + 12×2 = 44」（原 18+13×2 同为 44 但两套并存）；8 处
  2/3px 微间隙 + 删除列 28 归一 `AppleSpacing.xxs/xl`（表头占位与行内
  按钮**同步改**，否则列错位）；沉浸层 10 处 `Colors.white54/38/70`
  → `AppleColor.surfaceWhite.withValues`；画布域 `2 / scale` 圆角补豁免
  注释（除以缩放才恒定，AppleRadius 不参与换算）。
- **D-13 图片占位块去重**：`notebook_page_canvas_painter` 与
  `notebook_view_page_widgets` 各持一份逐字节相同的「底色+边框+对角线」
  绘制——收口为 rendering 层唯一实现 `drawImagePlaceholder(canvas, rect,
  {scale})`，`scale` 参数化保留两处原行为（忠实渲染器不除、缩略图除）。
  presentation→rendering 方向合法（`notebook_reader_page` 已有先例）。
- **M-05/M-10 动效令牌收编**：悬停 `1.012` → `AppleMotion.hoverScale`
  （悬停抬升，与 `pressScale` 0.95 方向相反不可混用）；tooltip
  `waitDuration` 450ms → `AppleMotion.tooltipDelay`（与 `tooltip`
  125ms 淡入是两件事）。`app_design.dart` 补 import `apple_motion.dart`
  （同域）——Martin I 实测 0.24，仍远低于 0.4 上限。
- **M-06/M-08/M-09 三项豁免裁决落注释**（审计给了「统一 or 记录」两
  选项，本轮取记录，不动行为）：路由转场**维持双轨制**——Material
  转场走平台默认（Zoom 显式钉住防回落），`AppleSheetFadeRoute` 只用于
  抽屉式几何转场；激光 700/1800/260ms **不迁入 AppleMotion**——那是
  UI 过渡令牌域（受 <300ms 硬约束），激光尾迹是画布内容的时间轴，
  混入会让令牌表出现违反自身规则的条目（同 skeletonPulse 先例）；
  easeInOut / linear / stagger 两件 / 三把弹簧 / enterOffsetY /
  flingVelocityThreshold / crossfadeMaskBlur 共 10 个零调用令牌标注
  **预留**并写明保留理由（成套配方与已定案的口径，避免将来另造裸值）。
- **P-08 最近文档 memo**：侧栏「最近文档」原每次 build 全量拷贝+排序
  +take(30)，打字搜索/切 Tab 都白跑 O(n log n)——改以 `_cached` 对象
  身份为键缓存，数据根不变即复用，仅刷新或收藏乐观更新时重算。
- **C-16 棘轮基线重立快照**：原「29/6」与实测「9/5」对不上是因**口径
  未注明**——补写计数单位（`import` 语句行数，非文件数；组合根不在
  扫描范围），基线全部收紧至 2026-10-01 实测值（notes→doc 29→9、
  notes→security 6→5、notes→drawing 7→6、doc→notes 3→2、
  security→* 与 drawing→notes 1→0），棘轮只紧不松。
- **R-12 [P2] 删零调用死模板**（用户已同意）：
  `svgExportErrorMessage(Object error) => '导出失败：$error'` 全库
  零调用，留着就是「接线即把原始异常带进 UI」的隐患——删除。
- **S-07 [P2] 安装包 per-user 安装**：`PrivilegesRequired=admin` 后补
  `PrivilegesRequiredOverridesAllowed=dialog commandline`——默认行为
  不变（仍管理员安装、升级路径一致），但触屏笔记本无管理员口令时可
  在向导改选「仅为当前用户安装」，静默装用 `/CURRENTUSER` 覆盖。
- 门禁：analyze 0 告警；全量 **1899 绿 + 1 skip**（含 3 条新回归锁）；
  架构门禁 9/9（含 C-16 收紧后的棘轮）；linecheck EXIT 0；SLOC 最高
  616 < 1000；结构门禁 presentation 40/40 未增文件；DCM no issues。

## [1.17.50] - 2026-10-01

### 审计批次 AB：C-04 第五批——图片裁剪写回管线迁 infrastructure

> 承接 v1.17.47~49 C-04 前三批与 Code Guard 修复批（第四批，壳层状态
> 单一真源化），本批把 `editor_page.dart` 的图片裁剪域（几何 + 字节
> 管线）整体迁出，主文件 980→911 行，远离 1000 行硬上限。

- **`infrastructure/editor_image_crop.dart` 新模块**（目录 4→5 文件，
  40 上限内；application 保持 39/40）：
  - `EditorImageCropHandle` + `EditorImageCropGeometry` 纯几何自
    presentation/editor_selection_geometry.dart 原样随迁（该文件同步
    瘦身 196→103 行）；
  - `EditorImageCropWriter.writeCrop`：解码（兼容 DNV 密文）→ 画布↔
    像素几何换算 → 重采样 → PNG 编码 → 按原密文状态重新密封 →
    tmp+rename 原子写；GPU 纹理 finally 释放（H-05）随迁；
  - `EditorImageCropWriteOutcome` 四态结果（sourceMissing / encodeFailed /
    vaultLocked / success）；意外异常不吞、上抛由调用方兜底（R-02
    脱敏审计日志留在页面层）。
- **`_confirmCrop` 改薄映射层**：守卫 + 调管线 + switch 结果映射 +
  setState / invalidateDocumentImage / notifyChanged；行为零变化，
  提示文案逐条对应。顺带把写回早退提示统一置于 mounted 守卫之后
  （原实现在 unmount 后调 `_showSnack` 有抛错隐患）。
- **import 收口**：主文件随迁移除 VaultFileCodec / VaultKeyService
  直连（LocalIdGenerator 仍由 part 共享使用，保留）。
- 测试：editor_image_crop_geometry_test 改引新模块，用例零改。
- 门禁：analyze 0 告警；全量测试绿。

## [1.17.49] - 2026-09-30

### 审计批次 AA：C-04 第三批——编辑器壳层 UI 状态 Controller 化

> 承接 v1.17.47/48 C-04 前两批，本批把会话级壳层开关收口到
> `EditorChromeController`（合入既有 `editor_interaction_controllers.dart`，
> 不增加 application 目录文件数）。

- **`EditorChromeController`**：全屏、阅读反相、图层面板、检查器、网格
  显示、网格吸附、命令面板最近命令 id——toggle/set 语义可单测。
- **State 接线**：顶栏 `_toggleLayers/Inspector/Fullscreen/ReadingInverted`
  经 Controller.toggle 并写回 State 私有字段（part 文件零改动）；
  CommandPalette 的 grid/snap/lastCommandId 赋值路径不变，Controller
  承载可测开关逻辑。
- 门禁：analyze 0 告警；C-04 相关测试全绿。

## [1.17.48] - 2026-09-30

### 审计批次 Z：C-04 第二批——就地文字会话与工具模式 Controller 化

> 承接 v1.17.47 C-04 首批（斜杠菜单/指针采样），本批把仍在 `EditorPage`
> State 的文字编辑会话与工具互斥状态机收口到 application 层。

- **`EditorInPlaceTextSessionController`**（application）：
  - 包装既有纯逻辑 `TextEditSessionStateMachine`（idle→editing→
    committing/settled）+ 会话字段（editingItemId / pendingTextItem）；
  - `beginEdit`（重复 begin 先 cancel 上一会话）、`completeCommit` /
    `completeCancel`、`reset`；
  - `_editingItemId`/`_pendingTextItem` 改为只读 getter；写路径统一
    `_beginTextSession`/`_endTextSession`（编辑器 part 零改字段语法）。
- **`EditorToolModeController`**（application）：手型/框选/形状互斥
  从 presentation `EditorToolModeState` 迁出并 ChangeNotifier 化；
  页面 `_toolMode` getter 返回该 Controller。
- **sloc-guard 收口**：C-04 各 Controller 合并进单一
  `application/editor_interaction_controllers.dart`（含画布混排交互/
  缩放旋转滑块暂态），presentation `editor_interaction_state.dart` 改为
  re-export + `EditorToolModeState` typedef——application 目录回到
  **39/40**，避免 Code Guard 结构门禁（42/40）。
- 门禁：analyze 0 告警；drawing 域测试全绿（含新 Controller 单测 +
  就地编辑快捷键闸门/键盘选中回归）。

## [1.17.47] - 2026-09-30

### 审计批次 Y：#16 完整虚拟化 + S-02 方案 B + C-04 交互状态机首批

> 三项产品决策项（用户 2026-09-30 指示继续推进）合并发版。

- **#16 数据库视图完整虚拟化**：表视图弃 DataTable 全量布局，改
  「粘性表头 + 数据行 ListView.builder」；看板大列（>50）整列限高 +
  卡片 builder。记录 >50 时限高内部滚动（与 list 同语义）；有界父容器
  下协调层 Expanded 吃剩余高度，避免「表头+480」溢出。测试 +2（表/看板
  视口外行不 build）。
- **S-02 方案 B：数据根迁 ApplicationSupport**：`AppDataRoot.root()` 基底
  从 `Documents/绘图笔记数据/` 改为 **ApplicationSupport/绘图笔记数据/**
  （Windows `%APPDATA%\<app>\`，默认不被 OneDrive Known Folder 管理）。
  启动期一次性迁移旧 Documents 根与收口前分散路径（目标已存在不覆盖）；
  备份标记/暂存改写在数据根父目录；`applyPendingRestore` 兼容 Documents
  在途标记仍交换到新根。云同步警示改为检测**实际数据根路径**（不触发
  迁移的只读解析）。README 数据存储位置同步。
- **C-04 交互状态机首批**：斜杠菜单开关/↑↓ 高亮与指针/压感采样暂态
  从 `EditorPage` 私有字段抽到 application 层
  `EditorSlashMenuController` / `EditorPointerSampleState`（State 经
  getter/setter 代理，part 零改）。编辑器 O1 域 part 与既有
  `EditorCanvasInteractionState`/`EditorViewModel` 继续承接剩余职责；
  后续控制器拆分沿用「窄协作者 + 不增 presentation 无边界 part」纪律。
- 门禁：analyze 0 告警；关键测试（#16/S-02/C-04/设置/编辑器快捷键/
  键盘选中）全绿。

## [1.17.46] - 2026-09-29

### 审计批次 X：E-05 收口——pdfrx 升级并移除 engine override

> 来源：`docs/audit_2026-09-27.md` 工程化备案待办 E-05（等上游修复后
> 移除 `pdfrx_engine` override）。134 条审计自此仅剩产品决策项
> （S-02 方案 B / C-04 等），无工程化未闭环项。

- **pdfrx 2.4.7 → 2.6.5**：上游 2.6.0 起要求 Dart ^3.13 / Flutter 3.47，
  本机 Flutter 3.47.0 自带 Dart 3.13.0，`pubspec.environment.sdk`
  对齐为 `^3.13.0`。2.4.7 时代的 `PdfFileCache` 可空性编译问题
  （曾靠 `dependency_overrides: pdfrx_engine: 0.4.6` 绕过）已被上游
  2.4.8+/2.6.x 正式修复——**override 整段删除**，engine 由主包解析
  为 0.6.1（transitive）。
- **API 兼容**：本应用仅用低层 PDFium 门面（`pdfrxFlutterInitialize` /
  `PdfDocument.openFile` / `ensureLoaded` / `page.render` /
  `PdfImage.pixels|width|height|dispose`），2.6.5 仍导出且签名兼容；
  未使用 PdfViewer 组件族，material_ui 仅作为 pdfrx 传递依赖出现
  （应用 UI 方言仍为 `flutter/material`）。
- **门禁**：`flutter analyze` 0 告警；PDF 相关测试 28 绿；全量
  **1879 绿 + 1 skipped**（含 architecture 9 规则）。

## [1.17.45] - 2026-09-29

### 审计批次 W：S-02 收口——云同步 Known Folder 未加密暴露警示（方案 A）

> 来源：`docs/audit_2026-09-27.md` 备案待办最后一条 P1（S-02）。
> 方案 A（启动警示）为审计列出的首选修法，纯增量零数据搬迁；
> 方案 B（迁 ApplicationSupport 迁移选项）留作独立功能批次待决策。

- **检测**：`AppDataRoot.isCloudSyncedKnownFolderPath`——文档 Known
  Folder 路径任一段含 OneDrive（大小写不敏感，KFM/组织后缀变体均
  命中；段内子串也命中，保守策略宁可多警不漏警）。
- **警示**：app.dart 新增 `CloudSyncNoticeHost` 挂在 AppLockGate 与
  AppShell 之间——命中 OneDrive 路径且**未设开屏 PIN** 时启动期弹
  玻璃对话框说明暴露面与两种缓解（云同步排除该文件夹 / 开启密码
  保护），「我知道了」写 SharedPreferences（`s02.cloud_sync_warning_
  dismissed`）永久记住；已设 PIN 落盘为保险库密文不打扰；检测/弹窗
  失败静默跳过不阻塞启动；arb 新键 3 对（zh/en 1051=1051 对称）。
- **测试** +5：检测单测 2（KFM 变体命中/常规路径与段内子串）；
  宿主 widget 测试 3（弹出+永久记住+重启不弹 / 常规路径不弹 /
  PIN 已设不弹——FakeAsync 下 Isolate.run 永不回投，按
  app_lock_gate_test 备案双保险：testPinKdfOverride 轻量档 +
  bypassIsolateForTests）。
- 门禁 analyze 0 告警、全量 1879 绿。v1.17.44 CI 七工作流全绿。

## [1.17.44] - 2026-09-29

### 审计批次 V：删除类待决收口（C-11/C-15 + 死分支微清理，用户已同意）

> 来源：`docs/audit_2026-09-27.md` 备案待办中「删需用户同意」三条；
> 至此 134 条审计全部闭环（余 E-05 pdfrx override 等上游、E-02 已备案）。

- **C-11**：删除 `features/drawing/infrastructure/sync_service.dart`
  （60 行，Saber 式 SyncFile/SyncService 三件套——零实现零消费，与
  core/sync 真实接线模块平行的未接线重复）；`test/sync_service_test.dart`
  同文件兼测存活的 SyncPathCipher，死三件套用例与 `_StubSyncService`
  随删、路径加密 3 用例保留，文件更名 `sync_path_cipher_test.dart`
  对齐实际覆盖面。
- **C-15**：删除 `core/di/providers.dart` 的
  darkModeProvider/DarkModeNotifier（注释自认「无 UI 消费点，纯示例」
  死代码；主题能力由 AppThemeController/themeModeProvider 承载）；
  riverpod 测试的 overrideWithBuild 演示载体改测试内本地 `_TestFlag`
  provider（不再借用生产代码）。
- **微清理（L-04 顺带收口）**：
  `block_doc_password_reset_flow.dart` 移除 `docTitle == '加密笔记'`
  死分支——旧默认标题自 v1.17.41 起不再产出（headers 列表期内存
  计算、从不落盘），历史版本亦无持久化载体，isEmpty 判断已覆盖。
- 测试 −3（死代码专测用例），门禁 analyze 0 告警、全量 1874 绿。

## [1.17.43] - 2026-09-29

### 审计批次 U：测试健壮性 T 域 P2 专项收尾（T-04~T-11/T-13/T-14，9 条）

> 来源：`docs/audit_2026-09-27.md` T 域剩余 P2（批次 Q 仅闭环 T-03）。
> 除 T-04 注入参数与 T-06 常量转公开外全部为测试域改动，产品行为零变化。

- **T-04 激光消退假时钟**：`DrawingController`/`StrokeInputSession`/
  `TemporaryInkSession` 加可选 `clock` 注入（默认 DateTime.now 行为
  不变；startedAt 与消退判定共用同一时钟源）；测试显式推进假时间——
  真实延时 3.8s → 0（fake_async 方案否决：fakeAsync 驱不动
  DateTime.now，消退进度会停在 0）。
- **T-05**：图层缓存空闲释放等待 80ms→200ms（idleReleaseDelay 50ms
  的 4 倍余量，慢机不击穿）。
- **T-06**：`DocEditorState._historyDebounceDelay` 转公开
  `historyDebounceDelay`，note_editor_page_test 两处 pump(600ms)
  硬扛私有常量改「常量+100ms」推导。
- **T-07**：q0_save_chain_test 22×300ms 固定泵改由
  `SaveScheduler.autoSaveInterval + historyDebounceDelay + 1.5s`
  推导总时长（生产改档位不再静默击穿），保留固定步长 pump 纪律。
- **T-08**：editor_shortcuts_text_guard_test 抽 `pumpUntil` helper
  （条件早退、50ms 步长、40 步上限）——初始化/提交/工具切换 8 处
  等待改早退式；「断言无变化」类保留固定步长；早退使总 fake 时钟
  变短致击键合帧 Timer 未到期，三用例收尾补 1s 冲刷泵
  （pending-timer 不变量不再随机爆）。
- **T-09**：home_sync_test 6 处 `pumpAndSettle` 全改固定步长
  （pump+400ms）——骨架屏 shimmer repeat 无止境，同屏即无限等待
  的潜伏雷拆除。
- **T-10**：pdf_hybrid_exporter_test 三个多页用例补页数断言
  （`/Type/Page(?!s)` 计数——pdf 包页面字典无空格格式经落盘字节
  校准），「页数被静默丢弃也全绿」闭合。
- **T-11**：security_regression_test 取色断言升级（红笔画采样点断
  r>0.9 且 g/b<0.1，取错像素不再全绿）+ renderToPng 补 IHDR 宽高
  断言（渲染尺寸取错不再是全绿）。
- **T-13**：临时目录清理收口 29 文件——13 处裸 `delete(recursive)`
  / 6 处 `deleteSync`（Windows 句柄锁 flaky）统一换
  `deleteTempDirWithRetry`；editor_exporter_tiled 补 tearDown；
  m126/provider 内联创建（app_shell_smoke/两个 home/home_sync）
  挂记录表 + tearDownAll；pages_390dp/pdf_import_service 8 处内联
  创建逐点 addTearDown。实证：m126 改造前 TEMP 堆积 119 个残留，
  改造后运行前后数量不变（新目录全部即时清理）。
- **T-14**：4 处整句文案断言改 `textContaining` 关键片段
  （app_lock_settings_page ×3、settings_page ×1），标点/措辞格式级
  耦合解除。
- 门禁 analyze 0 告警、全量 1877 绿。

## [1.17.42] - 2026-09-29

### 审计批次 T：i18n P3 六条清尾 + E-03 阈值数据驱动回调 + E-02 备案（L-14/L-17~L-22 + E-02/E-03）

> 来源：`docs/audit_2026-09-27.md` P3 零碎与工程化域收尾。

- **L-14/L-22 术语收敛（纯 arb 值替换，键不动）**：zh「单文件密码/
  文件密码」×8 归主流「独立密码」（en Per-file/file password 同步归
  Standalone password）；「重置盘」×4 归主流「重置密码盘」×35（en
  reset disk 本已统一）；「新建失败：笔记本」改「分页画布」（全库最后
  一处该域旧称）。
- **L-17/L-18 兜底对齐**：home_page 搜索 tooltip 兜底「搜索全部内容」
  →「搜索」（= arb search）；nbNoPages 兜底「该分页画布」→「这个
  分页画布」。
- **L-19**：zh `@homeDeleteNoteConfirm` 元数据补 {name} 占位声明
  （en 已有，工具链换模板语言即断的隐患）。
- **L-21**：省略号统一 U+2026——zh/en 各 2 处 ASCII `...`
  （hintTypeContent/sgSearchHint）归 9 处主流 `…`，lib 兜底串与测试
  断言同步。
- **L-20**：`time_format` 新增 `formatMonthDay`（MM-dd）；冲突弹窗
  `_fmt` 本地 two() 与回收站页两处 `yyyy-MM-dd` 手拼收敛到
  `formatMonthDay/formatShortDate` 唯一实现。
- **E-03 阈值数据驱动回调**：以阈值=1 全量实测重定基线——
  ①CC 唯一超标点 `KeyboardShortcuts.catalog`（67——33 条
  `x?.getter ?? '中文'` 闭包的空判分支累计）重构：label 改 catalog
  调用时直接求值（唯一消费方 settings_page 同帧传同一 l10n，延迟闭包
  无意义），null 走 const 中文兜底表/非空走直接 getter，两路径零分支
  （catalog CC 67→1）；②SLOC 唯一超标点 properties_panel.build（258）
  提取 `_brushSection`（回落 ~195）；③阈值 CC 60→55（现最高
  _onShortcutKey 54，按键派发状态机拆分留专项）、NEST 8→7（最高 6）、
  SLOC 250 已真实达标保留；metrics 全量复跑零违规。
- **E-02 备案**：dart_code_metrics 5.7.6 要求 sdk <3.0.0（项目
  ^3.12.2）——dev_dependencies 锁定不可行，迁闭源 dcm 需商业
  license；CI 精确版本钉死已内容不可变（pub.dev 已发布版本不可改，
  无 range 漂移），残余风险仅「包下架致激活失败」。ci.yml 注释固化
  论证 + `--disable-sunset-warning` 降噪。
- 门禁 analyze 0 告警、全量 1877 绿；arb 键数不变（1048=1048，纯值/元
  数据变更）。

## [1.17.41] - 2026-09-28

### 审计批次 S：i18n P1 三条收尾 + 工程化 E 域清扫（L-01/L-03/L-04 + E-01/E-04）

> 来源：`docs/audit_2026-09-27.md` 剩余 P1 与工程化域。

- **L-01 斜杠菜单 i18n 根修**：`BlockSlashMenu.options` 静态 const
  （中文写死 + 按中文串反查 key 的映射函数）改 `optionsOf(
  AppLocalizations?)` 工厂——label/description 直接产出当前语言，
  搜索过滤与展示同源（en 环境可用英文关键词过滤，此前只匹配中文兜底
  串）；顺带修复 v1.17.37 附件项漏配映射（en 下唯一穿帮点，反查式
  方案的固有脆弱性实证）+ 搜索框 hint 接 `sgSearchHint`；删除两处
  反查映射函数（分组头 `_slashGroupTitleOf` 保留）。arb 新键 3 对。
- **L-03 快速记录标题**：全局热键新建画布标题「快速记录 HH:MM」不再
  写进持久化标题（locale 相关数据落盘后无法随语言变化）——改存空串
  （E6 新建惯例，同图层空名），列表/标题栏经既有
  `DomainDisplayLabels.docTitle` 渲染。
- **L-04 锁定占位标题统一**：四处列表期装配（块文档头
  `note_block_doc_store`/块文档回收站/画布 `DocumentMeta`/分页画布
  `Notebook`）三种叫法（加密笔记/加密画布/加密分页画布）统一为
  **空串 + locked/encrypted 标志**；展示层新增
  `DomainDisplayLabels.lockedDocTitle/docTitleWithLock` 单一键
  （`docLockedTitle`），All Docs 行/移动端/侧栏/首页画布卡与笔记本卡
  （含读屏 label）/回收站页全量接线；`all_doc_query` 画布段补
  locked 映射（All Docs 此前对锁定画布不显示锁标）；块文档回收站
  `TrashEntry` record 增 `locked` 字段；顺带 home_page_tabs 锁定/
  页数副标题写死中文接 `nbLockedSubtitle`/`nbPageCountSubtitle`。
  arb 新键 3 对（zh/en 1048=1048 对称）。
- **E-01**：删除 `cupertino_icons` 死依赖（CupertinoIcons 全 lib/test
  零命中）；**E-04**：sbom/secret-scan 两工作流补 `timeout-minutes: 15`
  （原无超时默认 360 分钟占 runner）。
- 测试 +4（L-01 en 全量本地化无中文残留锁 + en 渲染/英文过滤 +
  L-04 锁定回收站空标题 + lockedDocTitle 单一键断言），存量断言随
  契约更新（锁定占位标题断言 '加密笔记' 等 → 空串 + locked 标志）；
  门禁 analyze 0 告警、全量 1877 绿。

## [1.17.40] - 2026-09-28

### 审计批次 R：可达性 / i18n / 令牌三域收尾（约 20 条）

> 来源：`docs/audit_2026-09-27.md` 批次 R——V-05~V-15 可达性、
> L-07~L-16 i18n、D-03~D-07 令牌收编；D-03/L-02 实查已闭环。

- **可达性**：V-05 ⋮ 菜单 GestureDetector→InkWell（热区+水波一致）；
  V-06 星标/⋮ 包 Tooltip；V-07 演示模式底部补 上一页/下一页 IconButton
  （边界禁用）；V-08 斜杠命令菜单 ↑↓/Enter/Esc 键盘驱动（Focus 冒泡
  拦截，菜单与回车同源 `_slashCommands`）；V-09 文档块 Ctrl/Cmd+D 复制、
  Ctrl/Cmd+Shift+Backspace 删除；V-10 数据库表格行 44px 命中高度+
  数字列右对齐；V-11 大纲行补纵向 12 padding；V-13 标签下钻行接通
  `onOpenDoc`（原死入口）；V-14 桌面搜索框补清除按钮 + Esc 清空
  （Focus 冒泡拦截，与 V-08 同模式）；V-15 阅读页 Enter 进入编辑 +
  Semantics onTap。
- **i18n**：L-07 右键菜单设链接、L-08 图片无来源占位、L-09 文本导入/
  PDF 页标题/移动对话框/克隆占位、L-10 首页画布卡片 Semantics、
  L-11 块文档搜索回退标题（服务层可选参数注入）、L-12 取色器通道
  Semantics、L-13 形状库标题/检索提示/图表菜单/小地图 Semantics/
  手绘 tooltip 共 7 处、L-15 文档信息日期走 `timeFullDate` 占位键
  （zh yyyy/M/d、en M/d/yyyy）、L-16 跨年时间标签——全部改走 arb 键，
  新增 zh/en 对称键 15 个。
- **令牌**：D-04 GlassSurface 阴影字面量收编 `AppleElevation.glass`
  档（亮 8%/暗 16%）；D-05 内容层预览卡去 `black26` 阴影（发丝线表
  层级）；D-06 12 色板与 D-07 画笔默认色收编新域文件
  `core/theme/apple_palette.dart`（shared 不可依赖 features，落 core
  双方可引）。
- 门禁 analyze 0 告警、全量 1873 绿；三处 async gap（L-09 引入）
  改 `_l10nSafe` mounted 守卫 getter。

## [1.17.39] - 2026-09-28

### 审计批次 Q：可达性 P1 收尾 + 测试探针加固（4 条）

> 来源：`docs/audit_2026-09-27.md` 剩余条目中可机械落地的一批；
> L-02（块工具条 tooltip）实查已被「E1 批 4」闭环（`_blockTypeTooltip`
> 全量接 t* 键，写死串仅为永不展示的 zh 兜底），审计快照过时。

- **可达性**：V-02 文档树行补纵向 12 padding（点击目标 ~22px → ≥44px，
  仿同文件导航行 U4a 先例）；V-03 顶栏排序按钮包 44×44 SizedBox+Center
  （图标视觉 20px 不变，热区达标）；V-04 图表/图片 overlay 补右键
  +长按上下文菜单——文字/形状已有、这两类漏配致行为不一致（触屏长按
  = 右键等价入口，同形状 overlay 既有接线）。
- **测试**：T-03 `security_regression_test` H1 用例的固定 50ms 真实延时
  oracle 改确定性探针——`rebuildAll()` 任务被排到协调器串行重建队列
  末尾（既有飞行中重建之后），dispose 后 await 它即等待整条任务链排空，
  dispose 防护缺失会在此确定性抛错，与机器快慢无关（慢机不再漏报）。
- 测试 +2（图表长按/图片右键弹出菜单——画布上下文菜单此前零覆盖，
  以最小 `EditorPageSession` 桩驱动页面模式渲染）；门禁 analyze 0 告警、
  全量 1873 绿。

## [1.17.38] - 2026-09-28

### 审计批次 P：键盘轮选画布对象（V-01，键盘可达性主缺口闭环）

> 来源：`docs/audit_2026-09-27.md` V-01。既有 Delete / Alt+方向键微调 /
> Menu 键上下文菜单等键盘链路的公共前提是「先用指针选中对象」，纯键盘
> 用户无法选中、因而无法删除或微调画布对象。

- **轮选与清除**：Tab / Shift+Tab 按 z 序轮选画布对象（无选中取首个、
  到边界循环、无对象放行焦点遍历），Esc 清除选中（与指针「点空白取消」
  等价）；选中对象落在视口外时平移视口使其可见（rotation ≠ 0 跳过）。
  轮选顺序与叠加层渲染同源（`EditorOverlayItemPlan`），「选中的顺序 =
  看到的叠放顺序」。实现落在 `editor_page_shortcuts.dart` 键盘域同域
  （presentation 目录文件数已抵 sloc-guard 结构门禁上限 40，不再新建
  part 文件）。
- **入口可发现**：命令面板新增 `selectNextObject`（Ctrl+K 可达，键位提示
  Tab）；设置页「键盘快捷键」速查目录补「Tab / Shift+Tab 轮选下一个
  对象」「Esc 清除选中」两条。
- **伴生缺口（画布模式 no-op）**：独立画布模式（`session` 为空）此前
  `_deleteSelectedItem` 与 `_nudgeSelected` 直接 return——Delete 与
  Alt+方向键对画布文字对象全是 no-op；两者回退到
  `document.textItems`（与 `forCanvas` 可选集合同源）。
- **测试抓到的真实缺陷**：画布模式删除时其余三类集合传 `const []`，
  `EditorPageObjectMutation.remove` 对四类集合一律 `removeWhere`——
  不可变空表抛 `UnsupportedError`，删除整个失效；改传可增长空表。
- arb 新键 3 对（`cmdSelectNextObject` / `scSelectNextObject` /
  `scClearSelection`，zh/en 1027=1027 对称）；测试 +4（轮选前进/反向与
  循环/删除与 Esc 清除/空画布放行）；门禁 analyze 0 告警、全量 1871 绿。

## [1.17.37] - 2026-09-27

### 审计批次 O：深度审计剩余项小修复清扫（17 条，数据安全 + 动效 + i18n + 性能 + 测试）

> 来源：`docs/audit_2026-09-27.md` 剩余 111 条中可独立小步落地的一批。

- **数据安全**：R-05 `migrateLegacyMedia` 原地重加密改 tmp+rename（写中
  崩溃不再产生半明文半密文媒体）；R-07 `ensureMediaSalt` 短盐文件从
  「静默换盐」改 fail-closed 显式抛错（旧盐派生媒体不再被批量报废）+
  盐写入原子化；S-04 `SyncService.cipher` 收紧为 required（消除
  NoopSyncCipher 默认 fail-open 陷阱）；S-09 保险库 tmp 孤儿清扫阈值
  1 小时 → 10 分钟（崩溃残留密钥副本滞留收敛）。
- **动效**：M-03 画布对象删除延迟与配对淡出同用 `AppleMotion.dropdown`
  （原 180ms 裸值致动画截断跳变）；M-04 残留两处（glass_surface/skeleton）
  统一 `AppleMotion.reduceMotionOf` 三信号判定；M-07 全屏图片预览时长
  对齐同族 modal 档；M-11 首页缩略图恒值 AnimatedOpacity 改
  TweenAnimationBuilder 真实 0→1 入场渐显。
- **i18n**：L-05 状态栏保存状态接线 `saveStateSaving/saveStateSavedAt`
  （键已有未用）；L-06 命令面板三条导出命令接线 `editorExport*` 键。
- **性能**：P-10 `paintStrokes` cull/plan 缓存单槽改 8 槽多槽表（可见
  图层 ≥2 时逐帧互踢命中率恒 0 的自击穿消除）；P-11 文档嵌入网络图按
  显示宽度量化解码（全库最后一个未封顶图片通道）；P-12 取色器 RGB 焦点
  监听器具名化 + dispose 配平；P-13 擦除拖拽中 `notifyListeners` 改
  `tickFrame`（面板重建与画布重绘解耦，收笔一次性刷新）。
- **健壮性**：R-08 反向链接打开 `.then` 链改 async/await + 异常兜底
  （非锁定异常不再静默无反应）；R-09 首页打开笔记补捕损坏文档
  （FormatException/TypeError → 明确提示）。
- **测试 + 功能补全**：T-12 斜杠菜单全集精确断言上线即抓到真实缺口——
  `attachment` 块类型插入链路齐备但菜单漏入口，补全「附件」菜单项
  （heading 三级菜单项为唯一合法重复例外，测试按此细化）。
- arb 新键 4 对（zh/en 1024=1024 对称）；门禁 analyze 0 告警、全量绿。

## [1.17.36] - 2026-09-27

### 审计批次 N：后审计改进第三批——快捷键速查面板 + docs 索引

> 来源：后审计改进建议（第 4、14 条）。纯增量。

- **快捷键速查面板（增量新增）**：新增 `KeyboardShortcuts.catalog`
  （lib/shared/application/keyboard_shortcuts.dart）——目录数据逐处核对
  代码注册点（editor_page_shortcuts 1-9 工具/Ctrl 组合/方向键微调、
  doc_editor Ctrl+S、block_slash_menu 斜杠菜单导航、apple_design Esc
  通道、app.dart 全局热键），非拍脑袋清单；设置页「通用」组新增
  「键盘快捷键」入口 → 分组滚动对话框（键位符号列 + l10n 说明列，
  tabular figures 对齐）。此前键盘支持散落代码里，用户无从发现——
  三输入投入自此可被感知。arb 新键 33 对（zh/en 1022=1022 对称）。
- **docs/INDEX.md（新增）**：116 个文档的分类导航——常用入口/现行
  治理与评估 21 / 审计报告 14 / 验收记录 16 / 实现设计 9 / 分析评估
  研究 16 / 其他日期记录 40；约定「无日期=现行规范、带日期=当时点
  存档（结论以最新为准）」，终结每次协作者（含 AI）考古成本。
- 测试 +1（设置页快捷键入口显隐 + 对话框分组断言，含视口折叠线
  ensureVisible 与对话框内滚动断言）；门禁 analyze 0 告警、全量绿。

## [1.17.35] - 2026-09-27

### 审计批次 M：后审计改进第二批——全量数据备份与恢复（产品最大缺口闭环）

> 来源：后审计改进建议第 1 条（高优先）。设置页「通用」组新增两个入口；
> 备份/恢复为纯增量能力，不触碰既有数据路径。

- **BackupService（lib/core/storage/backup_service.dart，新增）**：
  - 备份 = 数据根整体打包 zip（内嵌 `backup_manifest.json` formatVersion
    校验），遍历与压缩全部在 `Isolate.run` 执行（大目录不卡 UI）；排除
    `*.tmp`/`*.bak` 崩溃保护残留；失败清理半成品。
  - 恢复 = 校验 manifest（缺失/版本过新抛 FormatException）→ 解压到
    数据根旁暂存目录（**绝不触碰现网数据**）→ 写待恢复标记 → 用户强确认
    （GlassDialog dangerous 档）→ 退出应用；取消则自动清理暂存与标记。
  - zip slip 防护：拒绝绝对路径/盘符/`..` 上跳条目（静默跳过不落盘）。
- **AppDataRoot.applyPendingRestore（启动期原子交换）**：main() 早期
  （单实例检查后、任何存储打开前）检查待恢复标记 → 旧根改名 `.old_<ts>`
  → 暂存顶替为数据根 → 尽力清理旧目录与标记。fail-safe：暂存/清单缺失
  （上次中断）仅清标记放弃恢复，绝不用残缺暂存覆盖现网。
- **设置页「备份全部数据 / 从备份恢复」两行**：注入 AppDataRoot 后显示
  （测试装配未注入自动隐藏）；导出提示明确「含密钥文件，请妥善保管」；
  恢复完成退出应用、重新打开生效。
- 安全注记：备份内容与运行时落盘状态一致——保险库/文件密码开启时密文
  + 密钥信封；未设 PIN 时明文（与 S-10 备案的产品现状一致，导出提示
  已告知保管责任）。
- 测试 +5（roundtrip 全链路 1 / 无效包 1 / zip slip 1 / fail-safe 1 /
  设置行显隐 1）；arb 新键 10 对（zh/en 989=989 对称）；门禁 analyze
  0 告警、全量测试绿。

## [1.17.34] - 2026-09-27

### 审计批次 L：后审计改进建议第一批——应用内语言切换 + 诊断导出 + CI flake 对策 + 版本脚本

> 来源：审计收官后的补充建议（产品/发布/流程维度，14 条中的 4 条）。
> 备份/恢复（密钥信封设计）、release 自动挂载、Android 自适应图标待后续批次。

- **应用内语言切换（增量新增）**：新增 `AppLocaleController`
  （仿 AppThemeController：跟随系统/中文/English 三态、shared_preferences
  持久化、非法值回退）；`app.dart` MaterialApp 挂 `locale:` 覆盖并合并
  双控制器监听；`app_shell` 透传；设置页「通用」组新增「语言」行
  （控制器未注入时隐藏，测试装配兼容）。此前应用只跟随系统语言，
  977 个 arb 键的 en 能力对用户不可达。
- **设置页「导出诊断信息」（增量新增）**：新增
  `DiagnosticsExporter.buildReport`（纯函数）——平台摘要 + 生效语言 +
  AuditLogger 哈希链校验结果 + 近期条目（设计上仅错误类型级别，无路径/
  正文）；设置页一键经 file_selector 保存为 txt，异常走 AuditLogger +
  固定文案。本地优先应用的用户排障自此有自助出口。
- **CI 真 KDF flake 对策（实证修复）**：`block_doc_encryption_test`
  文件级超时 3→8 分钟（ed17992 CI run 36304750434 的「懒迁移」用例在
  满负载 runner 上真实 Argon2id 派生超时；重跑即绿属环境起伏）；
  注释固化「失败先重跑一次、连续两次红才立案」政策。其余 15 个 KDF
  文件维持 3 分钟约定。
- **tools/bump_version.sh（增量新增）**：版本三处同步自动化——pubspec
  （build 号自增）+ iss 同步改写 + CHANGELOG 顶部条目校验（缺条目仅
  警告，内容仍由人写）；修复两轮脚本自身 bug（依赖约束 "+1" 误入
  build 号捕获、本机 grep 不支持变长 lookbehind → 改 \K）。
- 测试 +9（locale controller 5 / diagnostics exporter 2 / 设置页语言
  与诊断行 2，含 ListenableBuilder 生产装配镜像）；arb 新键 9 对
  （zh/en 977=977 对称）；门禁 analyze 0 告警、全量测试 1860 绿。

## [1.17.33] - 2026-09-27

### 审计批次 K：深度审计（134 条）第三批修复——性能热路径 + 动效/令牌合规

> 来源：`docs/audit_2026-09-27.md` 第三批之性能 P-01~P-04、动效 M-01/M-02、
> 令牌 D-01/D-02/D-08（共 9 条）。V-01 键盘选画布、i18n L 系、P-05~P-13
> 留后续批次。

- **P-01（P1）对象橡皮擦包围盒预筛**：`object_eraser_session` 此前每次
  采样事件对全部图层×全部笔画逐点命中（O(总采样点)/事件），高采样率
  触屏笔拖擦明显掉帧。接入 `StrokeRenderer.strokeBounds` 缓存查询
  （O(1)/条，轮廓缓存同源）做相交预筛，单事件成本降为 O(笔画数)。
- **P-02~P-04（P1/P2）导出主 isolate 重活清零**：单页混合 PDF 的
  `encodeJpeg`（image 包纯 Dart 编码，大画布数百 ms~秒级冻结）包进
  `Isolate.run`（对齐 pdf_hybrid_exporter 既有先例）；PPTX 打包
  `ZipEncoder().encode`、JSON 导出 `JsonEncoder.withIndent` 同批迁出
  （纯 Dart 对象可安全跨 isolate）。
- **M-01（P1）影子时长令牌删除**：`AppDesign.quickMotion(140ms)/
  standardMotion(200ms)` 不在 AppleMotion 令牌表任何档位（140ms 离档）
  ——删除影子令牌，消费点 `home_page_widgets` 改 `AppleMotion.press`
  （120ms）且减弱动效判定统一走三信号合一的 `reduceMotionOf`（原直读
  `disableAnimationsOf` 漏 high-contrast 信号，顺带修复该处 M-04）；
  `app_design_test` 改锁 AppleMotion 两档防回归。
- **M-02（P1）键盘按压不再动画**：`ApplePressable` 键盘 Enter/Space 触发
  的按压此前播放 120ms 缩放过渡，违反「键盘触发的动作永不动画」频率
  闸门——缩放判定改为仅指针按压（键盘保留触感反馈与按压状态语义）。
- **D-01/P2**：`doc_page_widgets` 菜单项图标距 10→8 三处（昨日归档决策
  残留收尾）；**D-02**：对齐参考线 `Color(0xFFFF5252)` 具名收编
  （画布域数据色豁免注释）；**D-08/P2**：`pin_pad` 移除 `height: 1`
  覆写（行高 1 低于全库 1.47 硬底线，全库唯一一处 UI 文本违规）。
- 门禁：`flutter analyze` 0 告警、全量测试绿。

## [1.17.32] - 2026-09-27

### 审计批次 J：深度审计（134 条）第二批修复——架构门禁（防问题再生）

> 来源：`docs/audit_2026-09-27.md` 第二批（C-01/C-02/C-03；T-01/T-02 已随
> 批次 I 完成）。本批闭环架构域全部 3 条 P1，架构门禁自此覆盖 rendering 层
> 与 feature 级环；新增规则 3 条。**行为零变化**（纯依赖方向重构）。

- **C-01（P1）drawing⇄notes feature 级环解环**：此前
  `drawing/application/editor_exporter` → `notes/application/
  notebook_pdf_exporter` → `drawing/rendering/pdf_hybrid_exporter` 构成
  feature 级环（文件级无环，规则 2 测不到）。
  ①`NotebookPrintPageData` 打印页契约下沉 core（新建
  `core/rendering/notebook_print_page_data.dart`，纯 core 类型）；
  ②多页 PDF 合成引擎改注入——`EditorExporter.multipageComposer` /
  `EditorPage.multipagePdfComposer` / `EditorPageBuilder` 契约新增可选
  参数，由组合根 `default_editor_page_builder` 绑定
  `NotebookPdfExporter.exportPages` 实现（lib/app 是唯一组合点，可依赖
  features）；③architecture_test 新增规则锁死两侧 application 横向依赖。
- **C-02（P1）rendering/ 纳入架构门禁**：此前分层 glob 只认
  presentation/application/infrastructure/domain 四层，
  `features/*/rendering/` 对所有层规则不可见（notes→drawing/rendering
  的 7 条跨 feature 依赖全部逃逸）。实证定位（infrastructure→rendering
  存在、rendering→上层为零）后入层：`defineLayers` 与 `defineOnion`
  均列 rendering 于 infrastructure 之下、domain 之上；规则 1/规则 4 自此
  覆盖 14 个 rendering 文件。
- **C-03（P1）security→notes 契约化**：`notebook_password_reset_flow`
  （security 展示层）此前直连 `notes/infrastructure/notebook_storage`
  实现类（未备案横向倒挂，跨层最深）。core/notes_accessor 新增
  `INotebookPasswordResetPort`（hasNotebookUsbSlot /
  resetNotebookPasswordWithUsb），NotebookStorage 实现该端口，两个调用点
  （app_shell / search_page）经子类型零改动。architecture_test 补
  `security ↛ notes/infrastructure` 规则。
- 顺带清理：`notebook_pdf_exporter` 移除本地契约类后未用导入。
- 门禁：`flutter analyze` 0 告警；architecture_test 9/9 绿（含 3 条新
  规则）；全量测试绿。**运行时零行为变化**——导出/重置流经同一实现，
  仅依赖方向经 core 契约 + 组合根注入改道。

## [1.17.31] - 2026-09-27

### 审计批次 I：全项目深度审计（2026-09-27，134 条）修复——第一批（数据与用户安全）

> 来源：`docs/audit_2026-09-27.md`（9 域 134 条，1 P0 / 15 P1）。本批闭环
> 第一优先级 9 条 + 顺带 2 条，新增回归测试 7 个；其余批次按报告优先级后续跟进。

- **A-01（P0）裁剪保存原子性**：`editor_page.dart` 图片裁剪保存此前对唯一
  原图（含保险库密封件）原地 `writeAsBytes`（truncate+write），写入中断
  即永久截断原图。改走 tmp + rename + 失败清理（同
  `_writeNotebookBytes` 单一出口纪律）；密封分支先加密到内存再统一落盘。
- **S-01（P1）PDF 导入明文旁路密封**：`PdfImportService.renderPages` 新增
  可选 `sealBytes` 回调，页面 PNG 落盘前经 `NotebookStorage
  .sealMediaBytesForPath`（新增公开方法）三级密封分支（DAN / DNV 信封 /
  明文兼容）——保险库或加密笔记本开启时不再明文残留磁盘；未注入保持
  明文（未加密模式与测试兼容）。
- **R-01（P1）WebDAV 全链路操作超时**：`WebDavSyncClient` 五个操作
  （MKCOL/GET/PUT/DELETE/PROPFIND）全部 await 套 `operationTimeout`
  （默认 30s，可注入），服务器挂起不再令 `syncNow()` 永久卡死；既有
  `TimeoutException` →「连不上服务器」humanizer 分支自此可达。
- **R-02~R-04（P1）`$e` 拼用户文案反弹清零**：裁剪失败 / 粘贴失败 / 打开
  链接失败三处 SnackBar 不再透出原始异常（路径/URL/命令行），改固定文案
  + `AuditLogger` 记错误类型（H-04 脱敏口径）；arb 新键 `cropFailed`（zh/en）。
- **R-06（P1）标签颜色解析加固**：`tags_view.dart` 的 `int.parse(tag.color)`
  改 `tryParse` + 主题色兜底——损坏标签 JSON 不再于构建期抛 FormatException。
- **R-13（P2）构建期异常兜底**：`main.dart` 装配 `ErrorWidget.builder` →
  `_BuildErrorFallback`（零依赖静态排版），release 下不再灰 ErrorBox 无解释。
- **R-11（P2，顺车）PDF 导入原子写**：页面 PNG 落盘同步改 tmp + rename +
  失败清理，半导入残留窗口收敛。
- **T-01/T-02（P1）不可逆路径回归锁**：新增 `purgeFromTrash` 彻底删除
  测试（回收站清空 / 激活区不可见 / 幂等 false）；`policy_engine_test`
  补 `note.restore` / `note.purge` 白名单断言。
- 测试 +7（WebDAV 超时 4 / PDF 密封与明文兼容 2 / 回收站彻底删除 1）；
  门禁 `flutter analyze` 0 告警、全量测试绿。

## [1.17.30] - 2026-09-27

### 审计批次 H：god-page home_page.dart 拆分收敛（#37 闭环）

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）最后一项可执行
> 待办 #37。至此 44 条全部闭环（#44 备案不动作）。

- **home_page.dart 职责拆分（审计 #37，方案 A 文件级拆分）**：仿 F1 拆分
  先例把 732 行宿主按职责归位——创建流与编辑器导航（画布/分页画布/笔记
  新建、画布打开与解锁、模板图标，~290 行）迁 `home_page_create.dart`，
  回收站对话框（恢复/永久删除/清空，~120 行）迁 `home_page_trash.dart`，
  宿主收敛到 ~370 行（组件契约 + 生命周期 + 三源装配刷新 + build）。
  **行为零变化**：同库 `part`/`part of` + `extension on _HomePageState`
  迁移，不改任何运行时路径；import 全部留在宿主，棘轮 notes→doc 29 /
  notes→security 6 等基线**计数不变**（本批次为可读性收敛，跨 feature
  依赖的契约化倒置维持备案，待下次触及注入接线时顺车）。
  - 技术注记：`_refresh` 留宿主——extension 成员不可调用 `setState`
    （`invalid_use_of_protected_member`），曾试拆 refresh part 即触发，
    已回退并以注释留痕（新 part 的 setState 消费方若再出现，同此口径）。

## [1.17.29] - 2026-09-27

### 审计批次 G：间距令牌专项归一（#34 清零）+ KDF 威胁模型注释补全（#39）

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）遗留项批次 G。
> 44 条至此：#37 god-page 拆分维持待办（需设计讨论），#44 备案，其余全部闭环。

- **间距令牌专项归一（审计 #34）**：专项清单
  `docs/SPACING_TOKEN_SWEEP_2026-09-26.md` 101 处离档间距逐处视觉确认后
  归一到合法档位（96 处改动），提炼 14 条语义归一规则（菜单图标距 10→8、
  卡片间分隔 10→12、顶栏水平 20→16、紧凑卡 14→12 / 大卡 14→16、
  空态图标隙 20→24 等）写入清单文档。仅数值就近归档零结构变化；触控
  目标 44px 约束处归一后复核仍达标（doc 工具栏 20px 图标 + 24 = 44）。
  豁免保留 7 处并记录理由：`pw.*` PDF 版式域 4 处（v1.17.27 既定裁决）、
  画布内容 2 处（便利贴样式随导出产物呈现）、令牌层自身 1 处（不在清单内）。
- **同步 E2E KDF 威胁模型注释补全（审计 #39 顺车）**：按
  `docs/KDF_MIGRATION_EVALUATION_2026-09-26.md` 结论 3，`sync_cipher.dart`
  单句「批B 注」扩为完整威胁模型（PBKDF2 纯计算硬度 vs Argon2id 内存
  硬度的量化差距、双条件兑现前提、信封版本化 + 用户主动事件重绕的迁移
  路径指针）。未改任何加密代码，迁移维持「下次触及同步加密域时顺车」。

## [1.17.28] - 2026-09-26

### 审计批次 F（收尾）：flake 根治 + 虚拟化阈值 + 两份专项评估

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）遗留项批次 F。

- **光栅化测试 flake 根治（审计 #36）**：`paged_canvas_open_rasterize_test`
  两处 `picture.toImage`（走引擎光栅线程，真实完成时间不可控）由固定
  500ms pump 改 `runAsync` 轮询——脱离 fake clock 等真实异步，慢机不再
  赛跑。**审计复核修正**：`app_shell_smoke_test` 9 处固定 pump 经逐处
  核实为 FakeAsync 确定时序（文件头注明内存存储注入 + 常驻动画禁用
  pumpAndSettle，无真实异步参与），不存在慢机赛跑，保持原样。
- **数据库视图阈值虚拟化（审计 #16，P2 清零）**：记录 >50 条时——
  list 视图切换 `SizedBox(480) + ListView.builder` 行级虚拟化（不可见
  行不 build/layout/paint）；table 视图限高内部滚动（DataTable 一次性
  布局全部 DataRow 无法行级虚拟化，限高做视口裁剪防大表无限撑长文档
  页）。≤50 条（常见量级）保持自然高度、随文档页滚动的既有交互**零
  变化**——虚拟化收益集中在大数据集，交互语义决策按此折中落地。
- **KDF 迁移评估（审计 #39）**：新增
  `docs/KDF_MIGRATION_EVALUATION_2026-09-26.md`——威胁模型（服务器
  副本泄露 + 低熵口令双条件）、版本化信封 + 事件触发增量迁移路径
  （与块文档 v1→v5 演进同模式）、风险对策与工作量。结论：可迁移非
  紧急，建议下次触及同步加密域时顺车实施。未改任何加密代码。
- **离档间距专项清单（审计 #34）**：新增
  `docs/SPACING_TOKEN_SWEEP_2026-09-26.md`——42 处 EdgeInsets + 59 处
  SizedBox 的精确行号与就近档位候选。归一档位需逐处视觉确认（10 在
  8/12 之间等距，取舍取决于设计意图），留待带视觉验收的专项，本轮不
  机械替换。
- #37（home_page god-page 装配下沉）需要设计讨论单独决策，维持待办；
  #44（pdfrx 双锁）维持备案。
- 测试 +0（改造 2 处既有用例等待方式），全量 1844 绿。

## [1.17.27] - 2026-09-26

### 审计批次 E（P2 清零 + P3 批量）：可达性 + 性能待办 + 测试基建

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）遗留项批次 E。

- **导出总编排端到端测试（审计 #19，P2）**：新增
  `editor_exporter_tiled_test`——真 DrawingController →
  `exportPdfWithOptions(tiled)` → 逐页渲染 → isolate 合成 → 落盘全链路
  （file_selector mock 到临时目录真实写文件）：生产等价输入 2 页 PDF
  （%PDF + 进度信号序列 1/2、2/2、3/2）、isCancelled 静默中止、
  confirmTiles 取消、200 页上限前置分支。锁死「单测手选 scale 通过、
  生产恒单页」断层复发（v1.17.20/22 教训的端到端版回归锁）。
- **整本导出页脚接线 + 测试（审计 #38，P3）**：复核确认 notes 整本
  导出路径的 footer 并非缺测试而是**缺接线**（v1.17.22 只接了画布
  tiled 路径）——`exportNotebook/exportPages` 补可选 `footer` 参数
  （「页标题 · n / m」+ CJK 字体主题，与画布分页同源；默认 false 零
  行为变化），测试 +2（footer=false 无嵌入回归锁 / footer=true
  FontFile2 真字形嵌入 + 页数不变）。
- **可达性（审计 #10/#13）**：PDF 导出面板主按钮移除硬编码白字（深色
  主题对比度 ~1.7:1 → 主题 onPrimary 自适应）；画板顶栏色板钮与文档
  格式工具条图标钮补 `Semantics(button: true)`（label 复用 Tooltip
  message，读屏不重复朗读）。
- **性能待办（审计 #30/#32，v1.17.25 记账项）**：桌面侧栏文档树改
  `ListView.builder` 懒构建（索引布局：导航行/间隔/树头/文档行/空态，
  行为视觉不变）；回收站 `listTrash` 轻量化 + isolate 化——整棵文档树
  不再跨 isolate/进列表（沿用 listDocHeaders C4 的搬运反噬规避），
  返回 `{id, title, deletedAt}` 轻量记录（UI 仅消费这三个字段），
  jsonDecode 搬 `Isolate.run`，解密/信封判定依赖会话密钥留主 isolate；
  `TrashPage` typedef 与 3 个测试文件同步适配。
- **设计/交互小项（审计 #25/#26/#28/#29）**：切片预览画师页纸白色
  统一 `AppleColor.surfaceWhite`（原双写 0xFFFFFFFF）+ 页号字号随页框
  显示尺寸自适应；PDF 导出面板 5 组 SegmentedButton 触控高度 40→44
  （M3 默认 < 44 触控下限）；分页切片单页时内容居中于纸张（与单页
  大图档成页观感一致，消除「极小内容贴左上角 vs 居中」不一致——
  多页网格原点语义不变）；`glass_nav_bar` MediaQuery 全量订阅改
  aspect 化拼装（键盘弹出等 viewInsets 变化不再重建导航条子树）。
- **导出错误文案收敛（审计 #40）**：12 处 `e.toString()` 原始异常不再
  拼入用户可见 SnackBar——5 个 arb 键去 {error} 占位改安全文案
  （zh/en 双语），失败详情不再暴露内部路径。
- **#16 数据库视图虚拟化保持记账**：完整虚拟化需「限高内部滚动」或
  「自绘表格」的交互/布局语义决策，超出批量收尾授权，维持待办。
- 测试 +8（tiled 端到端 ×4、footer ×2、单页居中断言更新 ×1、
  侧栏/回收站适配既有用例全绿）。

## [1.17.26] - 2026-09-26

### 审计批次 D（需单项决策项）：架构收口 + 对话框 Esc 全库基建 + 依赖清理

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）批次 D。

- **架构收口（审计 #18）**：doc 16 文件 + security 4 文件自 feature 根目录
  迁入层子目录（doc：`doc_controller`→application，其余 15 文件→
  presentation；security：4 个密码重置流→presentation），架构测试的层
  方向/洋葱 glob 自此对 doc/security 生效（此前块文档编辑器核心与安全
  流程 20 文件完全不受约束，仅 ratchet 计数兜底）。part 文件与宿主同迁，
  `part of` 相对引用不变；全仓 import 同步更新；ratchet 按目录名键控，
  方向计数不变。
- **home_page 直连 infra 收口（审计 #17）**：`HomePage` 新增 required
  `blockDocAccessor` 构造参数（core 契约 `IBlockDocSearchAccessor`），由
  组合根 app_shell 注入 `BlockDocSearchAccessorImpl`（同一 store 实例，
  行为等价）——首页不再直接实例化另一 feature 的 infrastructure 实现；
  `notes_accessor.dart` 过时注释修正（实现已迁 doc）。棘轮基线
  notes→doc 30→29。
- **sync_fix 更名归位（审计 #43）**：`features/security/sync_fix.dart` →
  `core/navigation/app_refresh.dart`，`SyncFix`→`AppRefresh`、
  `SyncFixRouteAware`→`AppRefreshRouteAware`——以「Fix」命名的常驻
  production 代码（实为路由观察者 + 数据变更通知，与 security 无关）
  归位导航域；app.dart / home_page / 测试同步更新，行为零变化。
- **对话框 Esc 全库基建（审计 #12）**：`AppleDialog.escClosable` 统一挂
  `Esc→DismissIntent` 映射（Flutter 的 showDialog 不处理 Esc，Windows
  对话框惯例取消键全库缺失）——`AppleDialog.confirm` 与
  `GlassDialog.show` 共用一处、一次收口全库；Esc 经 `maybePop` 与系统
  返回键同一条路由 pop 通道，`canPop:false` 的进度类模态天然免疫
  （v1.17.24 基建）。测试 +2（Esc 关闭返回 null / canPop=false 免疫）。
- **依赖清理（审计 #21）**：删除零引用 direct main 依赖 `cupertino_ui: any`
  （全仓 lib/test/integration_test 0 命中，any 约束有版本漂移风险）。
- **审计 #20 纠错（不删代码）**：复核确认 `core/storage/vfs/` 并非零引用
  孤岛——`VaultService.instance` 已被媒体双轨（`encrypted_file_image`）
  与笔记本 PDF 导出（`notebook_pdf_exporter`）消费（2026-08-16 接线），
  另有 4 个 vault 测试覆盖；`architecture_test.dart` 中「尚未接线
  fan-in=0」的过时注释同步修正。原审计条目撤回，无需删除或接线里程碑。

## [1.17.25] - 2026-09-26

### 审计批次 C（按域批量）：手势重建收敛 + l10n 批量 + 设计令牌 + 性能

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）批次 C。

- **手势重建收敛（审计 #5）**：形状草稿/框选/拖拽/旋转/缩放手柄从
  全页 `_applyState`（setState）改 `_controller.tickFrame()`
  （ValueNotifier frameTick）——高频指针移动只驱动画布相关层自绘，
  不再逐帧重建 overlay/小地图/端点层；选区栏滑块走局部
  ListenableBuilder + 双显示 notifier。
- **临时墨迹频率分离（审计 #6）**：激光笔/标记的 16ms 淡出走独立
  `temporaryInkTick`，仅 CanvasPainter 监听——常态高频帧源不再驱动
  overlay/小地图/端点层全链重建。
- **l10n 批量收编（审计 #14/#41/#42）**：新增 23 个 arb 键（zh/en
  双语），冲突对话框 5 处、doc 导出菜单 3 项、画布编辑器 snackbar×5、
  PDF 域占位文案等约 20 处硬编码中文收编；`noteBlockDocToPdf` 加
  `emptyDocLabel` 注入参数（PDF 排版域无 BuildContext，调用点传
  l10n）；doc 工具栏可见标签走既有 `_blockTypeTooltip` 链路。
- **设计令牌收编（审计 #11/#33/#35）**：AppleType 新增
  `bold`(w700)/`semibold`(w600) 命名常量（DESIGN.md 字梯合法档唯一
  入口）；doc 域 4 处裸 FontWeight.w700 与 4 处裸 TextStyle（改
  DefaultTextStyle 继承）收编，沉浸式查看器覆盖层豁免；新增
  `AppleMotion.skeletonPulse` 骨架脉冲令牌（1.2s，持续状态动画归类）。
  离档间距 57 处（#34）需专项视觉验证，记待办。
- **性能（审计 #15/#31）**：`listDocHeaders` 冷路径头提取批量搬
  `Isolate.run`——原每文档主 isolate 解析两次（信封检查内部一次全量
  jsonDecode + 取头一次），N 文档冷启动 2N 次全量 JSON 解析出主线程，
  isolate 只回传头字段（body 树不跨 isolate 序列化避免搬运反噬）；
  MarqueePainter Paint 改 static final 共享、TrailPainter 循环内
  N 次 Paint 分配收敛为单实例复用。数据库视图虚拟化（#16）、桌面
  侧栏懒加载（#30）、回收站 isolate 解码（#32）记待办。

## [1.17.24] - 2026-09-26

### 审计批次 B（高优）：导出对话框生命周期统一收口 + 阅读页配色修复

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）批次 B。

- **返回键拦截基建（审计 #3）**：`GlassDialog.show` 新增 `canPop`
  参数（默认 true，既有调用点零行为变化）——`barrierDismissible`
  只拦 barrier 点击，系统返回键走路由 pop；进度类模态传 false，
  杜绝 finally 的 `navigator.pop()` 误弹栈顶编辑器路由。
- **逐页导出可取消（审计 #9）**：进度模态新增「取消」按钮，经
  `exportPdfWithOptions(isCancelled:)` 轮询在下一页渲染前静默中止
  （200 页 × 每页光栅 + isolate 合成可持续数分钟，此前唯一出口是
  问题 #3 的返回键 bug）。
- **进度 off-by-one 修正（审计 #23）**：`onProgress` 语义改为
  「当前正在渲染的页号」（1-based，渲染前回调）——原口径第 1 页
  渲染期间显示"第 1/m 页"实际在渲染第 2 页，末页 m/m 永不可达；
  合成阶段改发 `total+1` 信号（同值会撞 ValueNotifier 槽）。
- **dispose 时序修正（审计 #24）**：进度 ValueNotifier 在出场动画
  完成后才释放（复用 `_renameCanvas` 的 routeExited 手法）——原
  pop 启动动画即 dispose，动画期间对话框重建会触碰已释放 notifier。
- **切片确认框防误触（审计 #22）**：`barrierDismissible: false`——
  原误触弹窗外空白 → 返回 null → 整个导出被静默取消且无反馈。
- **翻页阅读页深色沉浸（审计 #4）**：Scaffold/AppBar 背景从主题
  surface（浅色 ≈ 白底）改为沉浸黑，与硬编码白系前景对比度从
  ≈1:1 恢复（对齐页码药丸黑系的设计意图，纸面仍白）。
- 测试 +2：GlassDialog canPop 返回键拦截 / 默认放行回归保护。

## [1.17.23] - 2026-09-26

### 审计批次 A（紧急）：分页导出三处功能性修复 + KDF 测试标签收口

> 来源：`docs/audit_full_2026-09-26.html`（全量审计 44 条）中的 P1 项。

- **分页导出恒单页修复（审计 #1，v1.17.20 引入）**：分页输出 scale 此前
  错用 `fitContentOnPaper`——它保证整幅内容放进一张纸（`content·s ≤
  纸宽`），代入切片公式 `cols = rows = 1`，导致「按纸张分页」自上线起
  在生产路径恒产出 1×1 单页，v1.17.20/22 的页序/页脚 n/m/200 页上限/
  逐页进度/切片预览全链路不可达多页。现改为固定输出 scale
  `kPdfTiledOutputScale = 1.0`（世界 px ↔ 纸张 pt 1:1，每页光栅 = 纸张
  分辨率，与单页档实际密度一致）——大内容真正摊开到多张常规纸。
- **页脚上限前置（审计 #27）**：`sliceContentIntoPages` 新增 `maxPages`
  参数，超限在切片网格物化前直接返回空表——固定输出 scale 后不再受
  fit 口径保护，防超大包围盒生成海量 Rect 卡主 isolate；导出侧超限
  提示语义不变。
- **中文页脚乱码修复（审计 #2，结论经实证修正）**：`exportMultiPage` 此前
  `pw.Document` 无字体主题，页脚落到 pdf 包默认 Type1 字体——其
  `isRuneSupported` 只认 ≤0xFF 码点，CJK 字形被静默画成 × 占位符
  （内容流实证：汉字变小叉、仅 ASCII 正常；不抛异常）。现新增
  `cjkFontData` 参数，分页导出开页脚时加载 DroidSansFallbackFull
  （与笔记本导出同一资产），CJK 字体主题在 isolate 内构建、真字形
  嵌入，中文标题页脚恢复可读。
- **页脚几何失真修复（审计 #8）**：页脚由 Column+Expanded 收尾改为
  Stack 覆盖层——tight flex 会把内容 Stack 钳到 pageH−18，光栅纵向
  压扁 ~2% 且矢量按整页坐标绘制溢出页脚带（错位最大 ~18pt）。现内容
  子树几何与无页脚时完全一致，页脚文字叠画于底部 18pt 带（≈6.3mm，
  打印机可打印区外；如内容侵入该带则文字叠于其上，已知取舍换几何
  零失真）。
- **KDF 测试标签收口（审计 #7）**：4 个真 KDF 套件
  （media_crypto / kek_session_cache / encryption_version / kdf_migration）
  补 `@Tags(['kdf'])`——此前绕过 v1.17.20 的 CI 分流（主套件
  `--exclude-tags kdf` 排除不掉它们），高并发下可能复发已根治的 flake。
- 测试 +5（maxPages 前置 3、输出 scale 回归锁 1、中文页脚 1）。

## [1.17.22] - 2026-09-26

### 分页导出体验闭环：页序档位 + 页脚页码 + 切片预览确认 + 逐页进度

- **页序档位**：分页导出新增「先横后纵（行优先，默认）/ 先纵后横
  （列优先）」——纵向长内容（时间线/笔记流）按书写方向排页；
  `sliceContentIntoPages` 新增 `columnMajor` 参数，页集合不变仅顺序
  不同（单列内容两种页序等价）。
- **页脚页码**：分页模式可选每页底部标注「标题 · n / m」（打印装订
  定位用）。pdf 3.x 的 `pw.Page` 无 footer 回调（MultiPage 专属），
  实现为 build 内 Column 收尾：Expanded 装既有 Stack（margin 为零、
  Stack 原点=页原点，contentRect/矢量坐标几何语义不变），页脚占底部
  定高条，与光栅/矢量内容互不重叠；`footerText=null` 保持零边距
  既有行为。
- **切片预览确认**：分页导出前弹网格预览对话框——自适应缩放展示每页
  覆盖的世界区域与页序号，用户确认页数后才进入逐页渲染（取消即放弃
  导出）。`PdfTilePreviewPainter` 从 part 私有类外提为独立文件以便
  直接单测。
- **逐页进度模态**：分页导出期间显示不可关闭进度对话框——「正在渲染
  第 n / m 页 → 正在合成 PDF」，`exportPdfWithOptions` 新增
  `onProgress` 回调；单页/笔记本导出走既有路径零变化。
- **CI 收尾**：`release-build.yml` 新增 `attach-android` job——
  Windows job 建好 Release 后自动 `gh release upload --clobber` 幂等
  补挂 APK/ZIP（此前四连发均手工补挂，还踩过 422 name 冲突），发版
  即 Windows/Android 4 产物齐。
- 附带：`.zcodeignore` 入库（同步自 .gitignore + ZCode 默认排除规则）；
  测试 +12（页序 3、页脚 3、预览画师 6）。

## [1.17.21] - 2026-09-25

### 死代码清理：移除 AFFiNE Edgeless 无限画布模块（用户批准）

- **背景**：排查发现 EdgelessPage/AFFiNE 风格无限画布模块自 M12（笔记
  模块重做，commit 3307994）起**无任何宿主实例化**——界面不可达的死
  代码。用户现役「无限画布」为 drawing 侧 `DrawingDocument.infinite`
  模式（编辑器内切换），不存在帧/散落墨迹概念，导出按内容包围盒、
  永不遗漏内容。
- **移除范围（27 文件，约 9000 行）**：
  - 展示层 5：`edgeless_page`（含 widgets part）、`edgeless_command_palette`、
    `edgeless_controller`、`edgeless_pdf_exporter`、`note_frame_preview`；
  - 域模型 5：`edgeless_doc/camera/connector/group/stroke` + `note_frame`；
  - 基础设施 1：`edgeless_doc_store`；
  - doc 侧孤儿契约 1：`note_block_doc_to_frames`（仅自身测试引用）；
  - 对应测试 13 件 + l10n 孤儿键 24 个（`edgeless*`/`ed*` 帧/便签工具族）。
- **剪线**：`DocPage` 移除 `onOpenInEdgeless` 参数与「在画布中打开」
  菜单项（宿主从未注入、菜单项恒禁用）；B11 语义锁测试撤销已删文件
  条目；ARCHITECTURE.md 模块表更新。
- **保留**：`THIRD_PARTY_NOTICES.md`（块编辑器/移动布局仍参照 AFFiNE，
  声明继续适用）；v1.17.16-18 共享的导出引擎（PdfHybridExporter 等）
  不受影响。
- 语义不变式：本删除为纯死代码清理，**零运行时行为变化**（不可达代码
  与恒禁用菜单项）。

## [1.17.20] - 2026-09-25

### 八项批次：退出/保存体验闭环 + 无限画布分页导出 + 导航玻璃收尾 + CI 根治

- **① 保存状态指示器统一驱动**：`SaveScheduler` 新增 `savingState`
  通知器——「保存中」状态现覆盖防抖自动保存、手动保存与退出兜底全部
  路径（此前退出兜底保存永不点亮；状态栏 M12 芯片改由调度器驱动）。
- **③ 退出缩略图后台补渲**：脏退出不再等 1024px 缩略图渲染——退出只等
  文档 JSON 落盘，缩略图由 `ThumbnailBackfill` 后台队列按文档快照独立
  渲染（退出即秒退；快照深拷贝防 dispose 后访问；渲染失败静默、下次
  自动保存重试）。
- **②+④ 无限画布「按纸张分页」导出**：导出面板（独立画布）新增布局
  档位「单页大图 / 按纸张分页」。分页模式把内容包围盒按纸张纵横比切片
  成常规纸多页——每页光栅只有纸张分辨率（导出不再卡顿），页尺寸恒在
  PDF 14400pt 规范限内（不再被查看器裁剪），且可直接打印装订。页数上限
  200（防失控导出）；`renderToPng` 支持区域渲染（`renderBounds`）。
- **⑥ 导航玻璃化收尾**：宽屏侧栏换装 `GlassNavigationRail`（与窄屏
  GlassNavigationBar 同配方：sigma 16 / 基底 0.72，M3 indicator 保留）。
- **⑦ CI flake 根治**：真 KDF（Argon2id/PBKDF2）套件打 `@Tags(['kdf'])`
  拆分——主套件 `--exclude-tags kdf` 不再被 KDF 排队拖慢，KDF 套件
  独占 `--concurrency=1` 串行（此前 15s→60s→180s 三次放宽等待只是撑大
  窗口；dart_test.yaml 注册标签）。
- **⑧ 退出性能回归防护**：新增性能测试——干净调度器 `flushIfDirty`
  50ms 内零 IO 返回（含 10 次连退场景），锁死「无改动退出秒退」语义。
- 附带：Rail 主题回归测试更新为锁定玻璃化行为；5 个 KDF 测试文件补
  `@Tags(['kdf'])`。

## [1.17.19] - 2026-09-25

### 退出编辑器卡顿优化：脏检查退出兜底

- **问题**：切换页面（退出编辑器）时无条件强制保存——即使本轮零改动，
  也要走「1024px 缩略图渲染 + 串行保存」全流程，体感明显卡顿。
- **修复三件**：
  1. `SaveScheduler` 新增 `flushIfDirty()` 脏检查版退出兜底：无改动且无
     飞行中保存时零等待直接返回，不触发任何 IO；有改动才升级为完整
     flush（防抖取消 + 兜底写盘语义不变）。
  2. `editor_page` 退出路径（`_flushBeforePop` 与 `dispose`）改用
     `flushIfDirty`，并提前置位关闭标记跳过缩略图渲染——退出路径最贵
     的一段在无改动时彻底免掉。
  3. 飞行中保存遇到退出时委托 `flush()` 合并补写，保证退出不丢改动
     （新增测试固定该语义）。
- 新增 `flushIfDirty` 三个调度器测试：干净退出零保存、脏退出完整落盘、
  飞行中合并补写。

## [1.17.18] - 2026-09-25

### 整图导出修复：内容裁剪 + 卡顿（v1.17.17 用户实测反馈）

- **内容缺失根因**：PDF 页尺寸直接用画布世界尺寸作磅值——超 **14400pt
  （PDF 规范 200 英寸上限）**的页面在部分查看器（Adobe 系等）被裁剪
  显示。修复：新增 `edgelessPdfPageBounds` 页尺寸归一——长边超限等比
  缩至 14400pt 内；光栅分辨率由光栅预算独立决定，视觉比例与内容完整度
  不变。
- **卡顿缓解三件**：
  1. 光栅长边预算 8192→4096（单张位图 268MB→67MB，栅格化 + PNG 编码
     时间 4×降；整画布一页的量级远超打印精度，观感无损）；
  2. `PdfHybridExporter.exportMultiPage` 的 `doc.save()`（纯 Dart CPU
     密集段）移入 `Isolate.run`——UI 线程不再冻结，笔记本整本导出同批
     受益；
  3. 导出入口加「正在导出 PDF…」模态进度提示（不可点按关闭，完成/
     失败统一 pop），不再像卡死。
- **测试**：缩采样预算断言更新 + 页尺寸归一新增 2 项。
- **门禁**：analyze 0；`--concurrency=1` 全量 1994 全绿。

## [1.17.17] - 2026-09-25

### 无限画布整图单页 PDF 导出（v1.17.16「真无限」的姊妹批次）

「真无限」修复后画布上帧外自由墨迹明确可见，但没有导出路径能带走它
（无限画布此前无任何导出入口）。本批补齐第一步能力——**整图单页导出，
语义为所见即所得（Excalidraw 同款）**；「按帧多页导出（分页画册）」留待
后续批次。

- **导出语义**：全场景包围盒（帧 + 帧外墨迹/形状 + 连接线含端点圆点与
  标签实测外扩）渲染为一页 PDF，页尺寸 = 包围盒世界尺寸；包围盒长边超
  光栅预算（8192px，对齐既有管线单边 clamp）时按比例缩采样。
- **渲染路径**（`features/notes/presentation/edgeless_pdf_exporter.dart`，
  置于 presentation 层——widget 树离屏栅格化属展示职责，application 不
  得反向依赖 presentation）：
  - 帧内块内容复用 `NoteFramePreview`（与屏上 `_FrameCard` 同一 widget
    渲染），只取纸面——帧头按钮/阴影/选中描边/群组框属 UI 铬，不进 PDF；
  - 墨迹/形状/连接线离屏 CustomPaint 重绘（视觉规则与屏上 painter 同源，
    剔除视口剔除/手势预览等交互态）；
  - 离屏栅格化用独立 RenderView 私有管线（无第三方依赖），theme/locale
    由页面在导出前捕获传入，深浅模式与语言所见即所得；
  - PDF 合成复用 `PdfHybridExporter` 单页管线（`EdgelessStroke` 与 core
    `Stroke` 模型不同构，v1 全光栅，页尺寸取世界尺寸保证缩放比例正确）。
- **入口（三输入兼容）**：顶栏新增「导出 PDF」按钮（鼠标/触屏）；Ctrl+K
  命令面板新增「文件 · 导出 PDF」命令（键盘路径）；空画布导出给出
  「无内容」提示。保存 UX 对齐 notebook 整本导出（保存对话框 → 写文件 →
  SnackBar 回显路径）。
- **测试**：+11（包围盒七例：空画布 null/帧并集/帧外墨迹/形状/连接线
  外扩/标签横向扩展/悬空线跳过；缩采样预算两例；产物契约两例：单页合法
  PDF 且 MediaBox=包围盒、空画布返回 null）。
- **门禁**：`flutter analyze` No issues；`flutter test` 全量全绿。

## [1.17.16] - 2026-09-24

### 无限画布「真无限」修复——消除看得见的世界边界

- **根因**：世界坐标（相机平移/元件/墨迹）本无边界，边界来自网格层的
  占位实现——旧 `_EdgelessGridPainter` 只画世界 ±4000 的固定格子，且
  不在相机变换层内（网格不随平移缩放滚动），平移远处后网格消失/错位，
  视觉上「画布到头了」。
- **修复**：网格改为相机感知即时求线——按当前可视世界范围画线、随世界
  平移缩放滚动、对齐世界 step 整数倍、缩小时步长自动倍增防密集成网
  （Excalidraw 同款行为）；世界坐标无边界。
- **适应内容（fitTo）修缺**：旧实现只统计帧、空帧硬编码跳 1000×1000
  固定区域——现纳入帧外自由墨迹包围盒，全空画布回原点附近单位视野。
- **与 PDF 导出无关**：PDF 按「帧」（分页画布页）组织导出是产品定义
  （分页画布=画册），不是画布边界的成因；帧外自由墨迹不进 PDF 属既有
  语义，本轮不改动。
- **测试**：+5（步长自适应/网格随世界滚动且对齐 step/±100 万平移仍全覆盖/
  线密度有界/shouldRepaint 契约）。
- **门禁**：`flutter analyze` No issues；`--concurrency=1` 全量 1981 全绿。

## [1.17.15] - 2026-09-24

### 内存优化批次（正常使用场景常驻下调，行为无感）

背景：外部确认启动 ~300MB / 绘画后 500–700MB 且稳定（无泄漏），本轮在历史
修复（v1.14.2/1.15.x/1.16.x）基础上继续压低正常使用中的常驻占用：

- **① 图片缓存预算 96→48MiB**：`DocumentImageCache.maxCacheBytesDefault`
  下调，LRU 淘汰框架不变；多图笔记场景最多再省 ~48MB。
- **③ 图层位图空闲自动释放**：`LayerRenderCacheCoordinator` 新增空闲计时
  （默认 30s，活动即重置）——分页画布每层最高 ~24MB 的离屏位图在空闲期
  自动释放，painter 走矢量回退保证内容始终可见，落笔后懒重建；无限画布
  无位图不安排计时；`idleReleaseDelay` 置零可整体停用。与既有「切后台
  释放」（v1.15.0 P1 #1）同机制，扩展到前台空闲场景。
- **④ Windows 工作集归还**：新增 `core/utils/memory_trim.dart`
  （`SetProcessWorkingSetSize(伪句柄 -1, -1, -1)`，dart:ffi）；编辑器切
  后台/最小化释放缓存后调用，任务管理器工作集立即回落。纯观感优化，
  非 Windows no-op、失败静默。
- **测试**：+5（空闲释放/停用/无限画布豁免/预算锁定/FFI 烟雾）。
- **门禁**：`flutter analyze` No issues；`--concurrency=1` 全量 1976 全绿。

## [1.17.14] - 2026-09-24

### F7 契约上移 + F9 超长文件域分权收口（授权专项，行为零变化）

- **F7 契约上移**：块文档契约五件（`note_block_doc` / `note_block` / `note_attachment` /
  `note_block_doc_store` 及其 trash/password part / `note_block_doc_sync_store`）由
  `features/doc` 迁至 **`core/documents/`**（仅依赖 core 的自洽簇），全仓 143 个引用文件
  import 同步改写；notes↔doc 最重组（29+3 处）的领域耦合就此消除，剩余为架构文档
  认可的页面级跳转白名单。Martin 基线与架构规则 1-3 全绿。
- **F9 拆分**（同 O1 part 域分权原则，extension 只收私有助手，public/字段/静态留本体）：
  - `storage_service` 966→638：媒体资产/写入落盘/删除回收站三 part；
  - `doc_editor` 983→598：历史保存/块操作/大纲对话框三 part；
  - `doc_page` 976→287：保存导出/大纲页链/文档密码/信息标签四 part；
  - `notebook_storage` 939→680：IO/编码落盘两 part；
  - `edgeless_doc` 942→744：`EdgelessCamera`/`NoteFrame` 抽独立文件 + re-export 兼容；
  - `editor_components` 899→5（export 桶）：`editor_painters`（8 painter）+
    `editor_widgets`（4 组件）真实文件。
  - 拆分配套小工具 `tools/split_members.py`（括号深度感知的成员级切割，配置驱动）入库备查。
- **门禁**：`flutter analyze` No issues；架构规则测试全绿；全量套件见同批门禁记录。

### 懒迁移/全量套件负载 flake 降噪专项

- **生产根因修复**：`StorageService._replaceWithTemp` 对 Windows 共享冲突
  （errno 32/5：杀毒/索引器短暂持句柄、delete-pending 窗口）加有界退避
  重试（5 次，25→100ms）——此前 delete/rename 裸失败会中断整次保存，
  是本机全量套件懒迁移用例偶发失败的单链根因；与既有 `_readWithRetry`
  同思路，`.bak` 先行落盘故重试不放大风险。新增 Windows-only 回归
  （句柄占用 40ms，第 3 次退避自愈）。
- **超时放宽**：`architecture_test` 全仓依赖图收集（setUpAll）放宽到
  5 分钟（库级 `@Timeout`，默认 30s 满负载下曾击穿）；`file_password_v3_test`
  真 KDF 排队 3→5 分钟（AGENTS 约定值之上的余量，仅测试）。
- **验证**：修复前 4 轮全量 3 轮各现 1-3 例随机失败（单跑均秒级通过）；
  修复后连续 3 轮全量 +1971 全绿。

## [1.17.13] - 2026-09-23

### 全量审计收口（问题清单见 docs/audit_full_2026-09-23.html，untracked）

- **裁撤记录补登**：M11 第二阶段裁撤日历页（`features/schedule`）与纯笔记占位页（`notes_writing_page`）于本周期提交（c5838ca），CHANGELOG 此前未记录，特此补登。
- **D12 续（61d72ba）**：marker 层增量脏矩形放行——区域重绘走 `InkLayerPainter` 计划（同色分组 darken 层），区域内先 `clear` 再从透明重绘与全量逐像素等价；整数对齐区域回归锁定全图零字节差异（含高亮画布落笔不再整层重建）。
- **CI 冒烟假绿根因修复**：2026-09-06 起无头环境 0/4 失败的真因是 runner 系统 locale 为 en_US 而 App 渲染英文、断言用中文文案（非当时误诊的「首帧渲染差异」）；smoke 强制 `localeTestValue/localesTestValue=zh` 并移除 `release-build.yml` 的 `continue-on-error`。
- **性能**：笔记本文本导入的 20MB 分段解析移入 `Isolate.run`（不再卡主 isolate 多帧）；数据库块 `jsonDecode` 补 64KB 上限（与附件块同纪律）。
- **重建收敛**：3 处 `MediaQuery.of` → `viewInsetsOf/disableAnimationsOf/highContrastOf/sizeOf` 专属访问器。
- **三输入/无障碍**：密码盘退格/确认键补 `Semantics(button:)`；画布图片/文字对象叠加层补语义与 button 角色；edgeless 便签框角柄与画板旋转手柄扩为 44×44 命中区（视觉不变）；表格编辑器 32px 按钮与文档分享 34px 按钮回到 44 最小触控；画板标题补「重命名」Tooltip；密码盘错误抖动接入减弱动效三信号（不位移）。
- **设计令牌**：15 处等值颜色字面量收编（`Color(0xFFFFFFFF)`→`AppleColor.surfaceWhite`、`0xFFFF3B30`→`errorRed`）；7 处 `FontWeight.w700/bold`→`w600`（DESIGN.md:369）；非法圆角归档（4→xs、10→md、2→0、FAB/导航胶囊→pill、skeleton 裸值→令牌）。
- **l10n**：新增 6 键（canvasKindImage/Text、frameCornerSemantics、pinBackspace/Confirm、edgelessTitle）；`'Edgeless'` 标题、`'Untitled'` 提示、命令面板 Tooltip 去硬编码；zh arb 补 39 键 `@` 元数据；`homeDeleteNoteConfirm` 占位符声明类型化。
- **测试稳健性**：`memory_p0_regression_test` 的 DocumentImageCache 用例由固定 20ms 魔法等待改为轮询等待（上限 2s）——满负载全量跑曾两次偶发失败、单跑通过。
- **工程卫生**：`.gitignore` 补 `/.mimosa/`、`/.workbuddy/`、`/.zcode/`、临时 codemod 脚本与 `/docs/audit_*.html` 约定；`ARCHITECTURE.md` 修复被 F9 段落截断的模块表并移除 schedule 行；`DESIGN_SYSTEM.md` 覆盖面清单移除已裁撤页；README 功能概览补块文档增强/文档互操作/工作台增强三行；4 处测试静默 catch 补理由注释；修复 `integration_test/smoke_test.dart` 的 `localeTestOverride`→`localeTestValue/localesTestValue` API 误用。

## [1.17.12] - 2026-09-20

### E6/E1 存储展示分离 + D11 通知分域 + D12 封顶增量 + F9 结构定调

- **E6/E1**：新增 `DomainDisplayLabels`——domain/codec 新建与缺省写 **空串**；历史落盘中文默认值在展示层映射 l10n；导出文件名回退 `untitled`。图层面板/各列表/回收站/导出 HTML·PDF 已接。
- **D11**：`EdgelessController.gestureTick` 与结构 `notifyListeners` 分域；相机/活动笔迹/形状预览走高频通道。
- **D12**：封顶画布启用增量脏矩形——`drawImageRect` 铺旧位图，文档坐标系脏矩形裁剪（marker 层仍全量）。
- **F9**：`ARCHITECTURE.md` 明确 editor_page **O1 part 域分权** 不再合并（避免超长文件回潮）。
- **F7**：`architecture_test` 零循环依赖保持通过；无新环则不做契约上移。

## [1.17.11] - 2026-09-20

### 审计收尾批次：E1 继续 + B11 叠加层 + F1 home_page 密码域拆分

- **E1**：`/` 菜单项显示文案 locale 化（`sgItem*`）；导出 snack / WebDAV 设置 / 锁屏门 / 首页「忘记密码」接入 arb（`exp*` / `webdav*` / `lock*`）。
- **B11**：画布图表/形状/旋转手柄叠加层补 `Semantics`（键盘与读屏可识别对象类型）。
- **F1**：`home_page.dart` 单文件密码与画布删除域拆至 `home_page_password.dart` part（行为零变化）。
- **F9 / D11 / D12 / F7**：**未在本批做大规模重构**——
  - F9 part 合并与 D11/D12 渲染架构、F7 notes↔doc 契约上移属专项；
  - 当前 `architecture_test` 零循环依赖**已通过**，说明 import 图无环；
  - DCM long-method 无红。避免「拆了但不简化」的无效重构。

## [1.17.10] - 2026-09-20

### 审计「全部」批次：F3 死代码 + E1 i18n（schedule/trash 批）+ B11 Semantics 样本

- **F3（已授权删除）**：
  - 删除未接入 UI 的 `HomeLockButton`（`lib/shared/widgets/home_lock_button.dart`）；
  - 删除无引用的 `ApplePillSearchField`（`apple_design.dart`）；
  - 删除未使用的 domain 模型 `ScheduleEntry` / `schedule_entry.dart`；
  - 删除 3.5MB 未引用源图标 `assets/release/app_icon_source_original.png`（构建脚本用的是 `app_icon_source.png`）；
  - **保留** `MemorySystemUnlockKeyStore`：接口实现 + 全量测试替身，非安全可删死代码。
- **E1 本批**：日程页/月历/回收站时间文案接入 arb（`sch*` + `homeDeletedAt`）；`flutter gen-l10n` 生成 zh/en。
- **B11 样本**：色板 S/V 方格与色相条补 `Semantics`（指针手势 + 键盘 RGB 等价入口提示）。
- **F1/F9**：长文件清单已盘（home_page 950 / doc_page 919 等）；DCM long-method 当前无红，**大规模拆分留专项**（避免未简化重构）。

## [1.17.9] - 2026-09-20

### 审计 P2-8/9：手写 fontSize 令牌化（UI 层）+ CI 懒迁移清理竞态加固

- 裸 `TextStyle(fontSize:)` 收敛到 `AppleType` / `AppleTypeScale`：
  移动端空态、文档行标题与头像字、图片预览说明、图表文字列表、
  日历星期标签、笔记预览标题/代码、演示 lead 28、密码盘数字键、
  文档状态 microLegal、项目符号 buttonLarge 18、胶囊搜索 caption/control。
- **domain 豁免并注释**：画布图表标签 9px、无边画布分组芯片 11px、
  PDF `pw.TextStyle`（print 排版不走 UI 梯子）。
- 列表标题等 UI 尺度覆写保留 `copyWith(fontSize:)`，但以令牌为基
  （承接字重/字距，避免再出现裸 TextStyle）。
- **CI flake（懒迁移）**：`deleteTempDirWithRetry` 宽限 3s→~15s；
  `waitEncryptedFile` 15s→60s（全量套件高并发下真 KDF 排队，run 35501293467
  击穿 15s）；批量用例末尾 settle 200ms，避免 Windows errno 32。

## [1.17.8] - 2026-09-20

### CI 门禁修复 + 审计 P2 落地

- **quality_gate DCM long-method**：`editor_page_canvas_surface._buildCanvasArea`（约 252 行）拆为 `_buildCanvasPainterLayer` 等短助手，过 `metrics analyze lib` 反模式门禁。
- **P2-4 小地图键盘**：Semantics + 方向键平移视口（Shift 加速）。
- **P2-5 搜索框焦点环**：`ApplePillSearchField` focusedBorder → Focus Blue 2px。
- **P2-6 连接线默认色**：新建 `kDefaultColor=0xFF0066CC`；JSON 缺省仍回落 `kLegacyDefaultColor=0xFF42A5F5`。
- **P2-7 纸型纹理具名常量**：`CanvasPainter.paperLineColor/paperDotColor`；小地图视口填充改 `actionBlue.withValues(alpha:0.13)`。

## [1.17.7] - 2026-09-18

### 增量审计闭环（AUDIT_2026-09-16/18）：三输入无障碍落地 + 设计令牌回归清理 + 门禁全绿

- **B3/B10/B13 三输入（未提交工作合入）**：
  - 色板 RGB 数字键盘取色（Enter 提交、digitsOnly、0–255 钳制、Focus Blue 2px、`Semantics` 通道标签）+ 回归测试；
  - 裁剪模式键盘微调（方向键 1px / Shift 10px，Enter 确认，Esc 复用 `clearCrop()`）；
  - 块文档顶层块 `Alt+↑/↓` 平移排序。
- **设计规范回归**：
  - 日程页月历/空态/事件卡去掉内容层玻璃（DESIGN_SYSTEM 内容层禁玻璃）；
  - 12 处 `OutlineInputBorder` 补合法圆角 `AppleRadius.xs`（禁止默认 4）；
  - `glass_surface` 注释与 recipe 对齐 regular 0.62。
- **异步一致性**：主菜单与命令面板 Future 动作显式 `unawaited(...)`（同步调度器 lint 盲区）。
- **门禁**：`flutter analyze` No issues；`flutter test` +1977 全绿。
- 审计报告：`docs/AUDIT_2026-09-16.md`、`docs/AUDIT_2026-09-18.md`。

## [1.17.6] - 2026-09-10

### lint 前置清零（审计未决 F12/C9）：unawaited_futures + avoid_slow_async_io 整改 200 处并启用防回退

- **avoid_slow_async_io（186 处）**：dart:io 小文件元数据操作全量转 Sync 版——
  `await X.exists()` → `X.existsSync()`（175 处）、stat/lastModified/FileSystemEntity.type
  （6 处）、跨行与测试文件残留（5 处）。小控制文件（密钥/清单/守卫记录）的 async
  dart:io 每次调用有固有调度开销，Sync 版更快；载荷级 I/O（readAsBytes/writeAs 等
  PDF/图片路径）本就不在此 lint 范围，未动。
- **unawaited_futures（14 处）**：fire-and-forget 调用显式化——首页 `_refresh()`
  5 处、密码盘触觉反馈 2 处、KEK 会话缓存/PDF 预览渲染/图片缓存移除/笔记本写尾
  各 1 处、测试 2 处，全部 `unawaited(...)` 包裹（丢弃意图可见、可 grep）。
- **await_only_futures（6 处）**：批量转换遗留的 `await File(...).existsSync()`
  去 await。
- **测试清理时序教训**：tearDown 里的 `await dir.exists()` 同步化会失去删除前的
  事件循环拍，与在途图片解码句柄竞态（errno 32 稳定复现）——5 个测试的
  「guard + delete」清理改用 `deleteTempDirWithRetry`（无 exists 调用，带重试，
  同时保住 lint 清零）；生产代码的 existsSync 转换不受影响。
- **启用防回退**：两条 lint 写入 analysis_options.yaml（附计量注释），
  此后新增违规会直接挡在 flutter analyze 门禁。

## [1.17.5] - 2026-09-10

### i18n 第四批（审计未决 E1）：doc 域——488 → 375 处硬编码（arb 712 → 829 键）

- **块文档编辑器**（doc_editor + toolbar/blocks/selection/outline parts）：块类型工具条
  15 个 tooltip（const 选项列表改为消费端按枚举映射）、富文本按钮、保存/放弃对话框、
  大纲空态、块无障碍语义标签（10 类）与输入提示（7 类）、选中工具条 6 项、
  「键入 / 添加块」占位与拖拽排序语义。
- **文档页**：顶部操作条 9 个 tooltip、文档信息/页面链接/在画布中打开/文件密码/分享
  菜单项、回收站页全套（标题/空态/恢复/彻底删除）、附件块（未命名兜底/编辑描述/
  备注对话框）、图片预览。
- **数据库块**：表/看板/列表三视图（视图切换分段、添加字段/记录、搜索、空态文案、
  无标题记录/未分组兜底、字段操作菜单、单元格编辑器）、表格编辑器行列操作 4 键。
- **内嵌块**：不安全图片拦截、加载失败、点击预览、画布/图表嵌入标签与宿主提示。
- **块文档模板**：四个内置模板的名称/说明展示端按枚举本地化（domain 保持 zh 兜底）。
- **/ 斜杠菜单**：分组头 5 项 + 空态本地化；条目 label/description 兼作模糊搜索
  关键词（与命令面板 keyword 同域），刻意保持 zh 待专项重构。
- 刻意不动：'加密笔记'/'未命名' 落盘默认、导出目录名/文件名 zh、infra 异常消息、
  markdown 导出兜底名。
- 行数纪律：doc_editor 983 / doc_page 975 / home_page 999（模板辅助函数移入同库
  part 文件 home_page_widgets，纯文件位置调整无 API 变化）。

## [1.17.4] - 2026-09-10

### i18n 第三批（审计未决 E1）：drawing 域全量——737 → 488 处硬编码（arb 473 → 712 键）；行数门禁回归修复

- **编辑器命令面板**：30+ 命令 label 与 6 个分类标签按 locale 解析（keyword 数组保留
  zh 混排——命令面板模糊匹配的输入辅助，非展示文案）。
- **导出全链路**：EditorExporter 注入惰性 l10n 闭包（mounted 守卫），PNG/PDF/SVG/
  Word/Markdown/PPTX/JSON 七种文件类型标签、复制/渲染失败/空画布等 20+ 提示、
  PDF 导出面板的纸张/范围/质量选项与说明。
- **编辑器表面**：顶栏（图层/属性/全屏/深色阅读/主菜单 6 项）、上下文条（橡皮/高亮/
  激光笔 7 种模式提示）、左工具栏与形状菜单（形状名展示端映射，搜索匹配仍走 zh 名+
  id）、图层面板、属性面板（画笔/图片/形状/文字四组 + 字体名）、选区工具条（锁定/
  删除语义 20 处）、状态栏（保存状态/压感说明/缩放菜单）、右键菜单、文字覆盖层。
- **画布操作**：图表生成对话框、统计面板、幻灯片、形状库、分布/分组/连线 snack、
  图片裁剪（4 角语义标签 + 引导提示）、番茄钟。
- `_canvasStatusLabel`/`_modeDescription` 等纯 getter 改造为带 context 的方法或
  l10n 注入；SelectionBar 五个辅助方法线程化 context。
- 刻意不动：命令 keyword、'未命名画布' 落盘默认、导出文件名 zh 后缀、infra 异常。

**行数门禁回归修复**：v1.17.3 的 i18n 展开把 home_page.dart 推到 1048 行（linecheck
error 档 1000），CI Code Guard 变红。本轮收敛回 999 行：home_page 全文件改用
`_l10nSafe` 短引用（含 mounted 守卫与跨 async 语义不变）、多行消息提为局部变量、
短单参调用去尾随逗号折叠——纯格式紧凑化，零行为变化。

## [1.17.3] - 2026-09-10

### i18n 第二批（审计未决 E1）：notes 域全量——972 → 737 处硬编码（arb 259 → 473 键）

- **首页**（home_page / tabs / widgets）：画布创建/打开/删除流、回收站（恢复/永久删除）、
  画布独立密码全套（设置/修改/绑定重置盘/移除，复用 doc* 键 20+ 处）、Tab 与分段控件。
- **分页画布页**（view_page + manage/imports/widgets 三个 part）：会话锁定/过期/恢复提示、
  新建/重命名/删除页面（含撤销 snack）、Markdown/PDF 导入全流、密码保护设置/修改、
  重置盘绑定、版本历史对话框、整本 PDF 导出。
- **edgeless 无限画布**：命令面板 label/group/hint 按 locale 解析（keyword 保留 zh 混排——
  供中文输入法匹配，非展示文案）、工具条/帧操作 tooltip、形状菜单。
- **WebDAV 同步页**：humanize 错误映射函数线程化 l10n 参数（8 种错误文案）、
  表单/按钮/摘要文案（含冲突计数组合句）。
- **杂项**：欢迎引导 8 条 tip、翻页阅读器标题与页码指示、演示模式、冲突解决对话框、
  块文档/分页画布加密解锁标题、PDF 预览占位、搜索结果 snippet 类型标签展示端映射
  （service 层 zh 常量作 marker）、页面模板标签与说明按枚举本地化。
- 跨 async 间隙的 l10n 取值统一走 `_l10nSafe`（mounted 守卫），满足
  use_build_context_synchronously。
- 刻意不动（等存储/展示分离专项）：模板内容文本项（会议/康奈尔/计划模板的画布文字）、
  版本历史 summary 标签（'文字修改' 等，落盘）、'未命名页面'/'便签' 落盘默认标题、
  infra 层异常消息（开发者面向）。
- 修复 v1.17.2 遗留：app_en.arb 缺 rootRefused 两键导致 zh/en 不对称（440/438）——
  已补齐，本轮末态 473/473 完全对称。

## [1.17.2] - 2026-09-10

### i18n 第一批（审计未决 E1）：共享组件 / 壳层 / 全部文档 / 密码重置流

- arb 198 → 259 键（zh/en 完全对称）；新增 docs 系列（搜索/排序/收藏/分组/空态）、
  unlock 系列（密码盘/解锁弹窗）、reset 系列（重置密码盘四流全量文案）、
  rootRefused（ROOT 拒启屏）等 61 键。
- 默认参数治理（默认值无法引用 l10n，改为可空 + 运行时解析）：`AppleDialog.confirm`/
  `GlassDialog.confirm` 的确定/取消（一处收敛全库 15+ 调用点）、`PinPadCore`/
  `PinPadUnlockSheet`/`UnlockFlow`/`DesktopUnlockField` 的标题与「紧急情况」、
  `AllDocsSidebar.workspaceName`、`PasswordResetSteps.confirm` 动作文案。
- 全部文档页（桌面 + 移动 + 侧栏 + 行组件 + 标签视图）：加载失败/快速搜索/清除搜索/
  最近文档/暂无文档/文档树/排序菜单/更多菜单/新建 sheet/收藏切换/上下文菜单全部接入；
  移动端 Tab 与侧栏导航由 static const 数组改为按 locale 解析。
- 分组标签「今天/本周/更早/从未更新」改为展示端按 `AllDocGroup` 枚举本地化
  （domain 的 `labelForGroup` 降级为 zh 兜底）。
- 明确日期标签（今天钟点/昨天/M月D日/跨年）线程化 l10n 参数。
- 密码重置四流（块文档/画布/分页画布/公共步骤）：说明确认、未绑定提示、插盘失败、
  新密码两遍（含 ≠ 开屏密码与两次不一致）、重置失败/成功提示全量接入。
- ROOT 拒启屏补挂 l10n 代理（原裸 MaterialApp），标题与说明文案接入。
- 刻意不动（等待存储/展示分离专项）：落盘默认标题 `'未命名'`（新建文档写入值）、
  search_service 的 snippet 类型标签（归 notes 批随 SearchResult 消费端一起处理）、
  `encrypted_file_image` 的 StateError（开发者面向）。

## [1.17.1] - 2026-09-10

### 审计未决项首批清偿：时区一致性、密码写队列、测试时钟收敛、CI 供应链 pin

**时区一致性（G15）**
- 新增 `lib/core/utils/time_serialization.dart`：写侧统一 UTC（`timeToIso` 恒带 `Z` 后缀）、
  读侧双格式兼容（`timeFromIso` 同时吃 `Z` / 带偏移 / 历史无偏移三种 ISO 串，归一为设备本地）。
- 全部持久化模型接入：画布文档、笔记本实体/页面/版本、日程、附件、块文档、全文档索引、
  vault 清单/标签库/存储服务/编解码——跨时区换机后 LWW（last-write-wins）比较不再被
  无偏移本地串扭曲；存量文件不强制重写，下次保存随 UTC 串自然覆盖。
- `timeFromIsoOrNull` 严格变体保留附件 tryParse 的 null 隔离语义。

**密码操作写队列串行化（G14 / E-17）**
- `storage_service_file_password` 六入口（设密/改密/移密/绑盘/盘解重绕）全部挂入
  per-document 独占队列（`_runDocExclusive`）——与在途保存/删除交错时按请求顺序执行，
  队列内重读最新落盘明文再重封，消除「密码重封以陈旧明文覆盖新保存」的竞态窗口。
- 新增 `test/core/storage/file_password_concurrency_test.dart` 并发回归（save 与
  set/change 交错串行、失败后旧文件仍可读、会话缓存与磁盘一致）。

**测试基建（H7）**
- 新增 `test/helpers/fake_clock.dart` 统一假时钟（毫秒推进 + Duration 推进双语义），
  收敛 `app_lock_guard_test` / `save_scheduler_test` 两套私有实现。

**CI 供应链（J5/J6）**
- 全部第三方 action 收敛为 commit SHA pin：gitleaks-action（v3）、
  action-gh-release（v3.0.3）、rust-toolchain（stable 分支头 + 显式 `toolchain: stable`
  声明，防 SHA pin 后 ref 推断失效）；checkout / flutter-action / setup-python /
  upload-artifact 此前已 pin，本次补齐后全仓 action 无浮动引用。

## [1.17.0] - 2026-09-07

### 全量审计发版：110 个审计大类、367 条带证据发现，280 项修复 + 102 项提升（台账见 docs/AUDIT_FULL_2026-09-07.md）

**可靠性（33 修复）**
- 全库 15 处 await 后无 mounted 保护的 setState 补齐；4 处对话框 TextEditingController 泄漏修复（等路由退出后再 dispose）；
  表格编辑器行列增删后 controller 索引错位/泄漏重建；11 处 fire-and-forget Future（保存失败无提示/假「已保存」/进程启动异常逃逸）收敛为 try/catch + 用户反馈；
  日程时间选择器对话框 ctx.mounted 防护。
- `DocEditor.onSave` 类型从 `ValueChanged` 改 `FutureOr<void> Function()`——手动保存现在真正 await 落盘，失败不再假报成功。

**存储安全与数据完整性（22 修复）**
- 6 个 store 补齐「随机后缀 tmp + 失败清理」原子写（缩略图/密封写/块文档/笔记本/edgeless/同步基线/标签）；
  `.bak` 备份复制失败改为 fail-closed 中止写入（防真实数据丢失窗口）。
- 远端同步 manifest / 笔记本 / edgeless 的 5 处 JSON 无防护强转改为类型检查 + FormatException（不可信数据不再 TypeError 裸抛砖化同步）；
  块文档 body/children 畸形元素过滤；笔记本版本历史加载截断到 8 版上限。
- 回收站 deletedAt sidecar 读写格式不匹配修复（30 天过期清理此前一直用错时间源）；标签名清洗（长度上限 + 控制字符剥离 + 重名幂等）+ TagStore 写尾队列串行化；
  画布/笔记本 delete 与 restoreTrash 挂入 per-id 写队列（消除「已删文档被在途保存复活」竞态）；storeImage 原子化；listAll 过滤畸形 id。
- WebDAV：远端异常消息不再透传到 UI（防不可信字符串注入）；「立即同步」补 https 预检与未保存配置拦截（杜绝口令/盐错配）。

**设计规范收敛（~110 修复）**
- 颜色：UI 层 17 处 0x 字面量收编（42A5F5→actionBlue 统一全 App 唯一强调色、F5A623/FF9800→favourite、30D158→noteGreen、深色面板→colorScheme.surface）；
  环境渐变收编为 AppleColor.ambientDark/LightGradient 令牌。
- 动效：14 处 Curves.easeOutCubic/easeIn 系与手写时长全部令牌化（AppleMotion.*）；键盘触发的翻页去动画（频率闸门）；PIN 抖动 400ms→250ms。
- 焦点环：3 处输入框 focusedBorder 统一 focusBlue 2px。
- 圆角：glass_dialog 28（非法档）→18、skeleton 6/12→5/11、手写合法值一律改 AppleRadius.* 引用。
- 排版：77 处手写 TextStyle(fontSize:) 令牌化（controlStyle/captionStyle/titleStyle/bodyStyle 分层映射，颜色字重原样保留）。

**三输入兼容与无障碍（~45 修复）**
- 触控目标：15 组 <44px 控件扩到 44×44 热区（裁剪手柄/便签复选框/图层小图标/选区工具条/色板圆点/表格 checkbox 等），视觉尺寸不变。
- Semantics：9 组纯图标控件补 label/button/checked/expanded 语义。
- tooltip：6 处补齐；GlassFab 支持 tooltip 透传。
- 对话框键盘可达：AppleDialog.confirm/GlassDialog.confirm 系统性 autofocus（危险操作焦点落安全侧），13 个具体对话框补首项/关闭钮 autofocus。
- 新入口：笔记本页卡「以块文档打开」进 ⋮ 菜单（原仅长按）；块文档编辑器 Ctrl/Cmd+S 手动保存快捷键。

**性能（10 修复）**
- 渲染缓存：笔记本文字块 TextPainter Expando 缓存、edgeless 连线/组标签 TextPainter 缓存、edgeless 笔迹 Path 缓存、图表标签 TextPainter 预建、
  墨迹层渲染计划单槽缓存、5 个 painter shouldRepaint 改字段比较（含视口快照）、小地图指纹重绘、framesSortedByZ 记忆化。
- 结构：分页预览 memo；分组文档列表打平为虚拟化 ListView.builder；骨架屏 24 ticker→共享单 ticker；数据库块搜索接入 SearchDebouncer；
  笔记本保存 JSON 编码移入 isolate（>2000 元素阈值）+ 去掉 pretty-print；同步元数据编码复用；排序短路。
- 内存：StrokePictureCache 加 32MB 字节预算双上限。

**代码质量（~49 修复）**
- 新工具 time_format（10 调用点收敛，删除 2 个逐字节重复的 _formatTime）、hexEncode（6 处）、escapeHtml（2 处）、AppSnack（7 处）；
  18 处空 catch 逐处标注意图（.bak 复制失败补 AuditLogger）；search_page 手写防抖改 SearchDebouncer；5 处魔法时长具名常量化；safe_url 4096 具名常量。

**新增测试（70 用例，总数 1870→1952 全绿）**
- vault_manifest（12）/plugin_registry（8）/file_sync_baseline_store（7）/local_id_generator（6）/session_secrets（6，含 DEK 清零语义）/
  sync_fix（7）/DocumentRepository 契约（8，含路径遍历防护）/WebDAV TLS 门禁（5）/HTML 导出消毒（11）；
  另有 Wave A 安全修复自带的 11 个回归用例。

**构建与文档**
- CI：9 个工作流补 concurrency 取消组（快速连推不再排队浪费）。
- 文档：README/README_EN 测试计数纠正（1255+/391+→1950+）、目录名说明改写、ARCHITECTURE 移除已废弃 features/home 行、
  新增 docs/README.md 索引（现行规范 vs 历史快照分界）、CHANGELOG 1.16.1 补测试小节。

## [1.16.4] - 2026-09-07

### 命名同源：同一文件在所有展示区同名、改名全端同步（用户需求）

**问题**：同一份内容以不同名字出现在多个展示区，且改了一处另一处不变。
根因是「同一逻辑文件」的多份标题各自演进、互不回写：

- **块文档改名不回写分页画布页卡**：从首页/全部文档打开笔记（块文档）
  改标题保存后，只落了块文档存储——分页画布里同 id 的页卡、搜索页路径
  标题仍是旧名（回写逻辑只存在于分页画布内打开的路径）。
- **分页画布页改名不回写块文档副本**：反向同样断链（此前只能借道画布
  编辑器改名，改完全部文档列表仍旧名）。
- **克隆引用页标题是创建时快照**：源页此后任何改名，克隆永不跟随。

**方案**：新增纯函数收敛服务 `NotebookTitleSync`（可单测），以
「打开时页标题快照」区分改名方向、防止双向回跳：

- **块文档改名（DocPage 保存）→ 即时回写源页 + 克隆快照跟随**（shell
  接线，两个 DocPage 打开点全覆盖）。加密分页画布跳过（无会话密码不可
  重加密落盘，由页内收敛在下次保存时补齐）。
- **分页画布每次整本保存前三向收敛**（`_convergeNamesBeforeSave`）：页卡
  ↔ 块文档副本 ↔ 克隆快照全部对齐后再落盘（加密本由 encryptAndSave 一并
  加密，安全无损）。
- **保存后定向回写**（`_convergeNamesAfterSave`）：本会话改过名的页把
  新标题回写块文档副本；跨本克隆快照跟随（仅未加密本，加密本等其自身
  保存时收敛）。
- 克隆创建标题统一走 `cloneTitleFor`，格式单一来源。

**边界与取舍**：加密且锁定的分页画布内容不可读、无密码不可写，相关收敛
fail-safe 跳过（不破坏加密边界），在其自身下次保存时自动补齐。收敛全部
幂等：无差异时零写入。

**测试**：`notebook_title_sync_test.dart` 7 例（doc-wins / page-wins /
克隆跟随同本+外部源 / 幂等 / 跨本快照 / 格式）。

## [1.16.3] - 2026-09-07

### 分页画布「松手后墨迹偏移」根因修复（用户实测 + HUD 诊断定位）

**症状**：分页画布上起笔时轨迹位置正确，**松手提交的瞬间墨迹整体跳向右下**；
离页面左上角越远偏得越多（≈ 位置 × 0.71），鼠标和手指完全一致。用临时
诊断 HUD（红十字准星 + dpr 信息条）确认：准星在光标正下方（输入→渲染
坐标系一致），偏移发生在「笔画提交进图层位图」这一段。

**根因**：`LayerCompositor.rasterize` 的位图长边封顶路径缺少坐标缩放。
`Picture.toImage` 按 **1:1** 把画布坐标系直接光栅化进位图、**不做缩放**：
A4 页（2480×3508）的笔画按文档坐标 1:1 画进 1448×2048 的封顶位图——
只有页面左上角被截进来，其余全被裁掉；显示端 `drawImageRect` 再把这张
小图拉伸 ~1.71× 铺满整页。净效果 = 墨迹呈现在「位置 × 1.713」处。
该缺陷自 v1.14.2 引入封顶即存在，但当时连线层吞指针（v1.16.2 已修）
根本无法落笔，故从未暴露。

- **`LayerCompositor.rasterize`**：录制前补 `canvas.scale(位图/文档)`——
  文档坐标内容等比缩入封顶位图；非封顶画布 factor=1，零行为变化。
- **`pickColorAt` 取色探针**：同类缺陷（v1.16.1 引入降采样探针时漏缩放）
  ——此前探针只截页面左上角、采样坐标与内容错位，吸管在分页画布上取色
  全错。补 `canvas.scale(probeScale)`。
- **回归测试** `layer_compositor_scale_test.dart`：像素级验证——已知文档
  位置的笔画，封顶光栅化后墨迹质心必须落在等比缩放后的位置（±8px）；
  非封顶路径质心 = 原位置（防 scale 破坏正常语义）。

## [1.16.2] - 2026-09-07

### 分页画布「白纸、无法作画」双根因修复 + 绘画内存治理

用户报告：分页画布打开后只有一张白纸，画笔画不了、所有功能不可用；内存仍有三百至五百 MB 且随打开画布/绘画上升。

**分页画布白纸·根因一（无法作画）——连线层吞掉全部指针事件**
- `editor_page_canvas_surface.dart` 的连线层（`ConnectorPainter`，分页模式常驻）
  与对齐参考线层（`SnapGuidePainter`）是裸 `CustomPaint`——`CustomPainter.hitTest`
  默认返回 true，这两层 `Positioned.fill` 盖住整块画布，**命中测试止于其上**，
  画布 `Listener` 收不到任何指针：画笔/橡皮/文字/形状/选区全部失效。
  独立画布（画板）没有连线层，故不受影响。既有测试全部直驱 controller 绕过
  手势层，所以一直测不出来。修复：两层包 `IgnorePointer`（与网格层等既有惯例一致）。
  新增回归测试 `paged_canvas_pointer_repro_test.dart`：鼠标/触屏/触控笔三种
  真实指针事件经完整命中链落笔（修复前 0/3，修复后 3/3）。

**分页画布白纸·根因二（既有内容不可见）——打开文档无首次光栅化**
- `CanvasPainter` 对非无限画布只画图层位图（`image == null` 直接跳过该层），
  而此前**没有任何代码**在打开已含笔画的文档时触发光栅化——所有层位图恒为
  null，重开页面 = 白纸（历史「打开空白」症状的另一半）。修复：
  - `LayerRenderCacheCoordinator` 构造即触发 `rebuildAll()`（非无限画布）；
  - `CanvasPainter` 新增**矢量回退**：位图未就绪（首次光栅化中/全量重建窗口/
    光栅化失败自愈期间）直接绘制笔画，内容始终可见；
  - `LayerPaintView` 携带图层笔画引用供回退使用（O(1) 引用共享）。
  新增回归测试 `paged_canvas_open_rasterize_test.dart`（打开即光栅化 /
  无限画布不产生位图 / 空层不持有位图）。

**绘画内存治理（不影响体验的前提下削峰）**
- **重建任务队列串行化**：原 `_rebuilding` 布尔守卫在重建飞行中到来的失效请求
  会直接跳过并提前返回（await 语义被破坏；`rebuildAll` 飞行中调用会整批跳过
  其余图层）。改为任务链排队，await 语义 = 轮到并完成。
- **全量重建先释放旧位图**：封顶画布（A4 分页）每笔落笔都是全量重建，此前
  `toImage` 期间新旧两张 ~24MB 位图并存、瞬时峰值翻倍；现在旧位图不再作为
  增量底图时在分配前释放（回退窗口由矢量回退兜底显示）。
- **空图层/隐藏图层不再持有位图**：空层光栅化只会得到全透明位图（A4 封顶后
  ~24MB/层纯浪费）；隐藏层位图 painter 不绘制。落笔/重新显示时按需重建。
- **`rebuildAll` 补无限画布守卫**：此前桌面端每次窗口切走再切回（onResume）
  都会把无限画板每层光栅化成 painter 永远不用的位图（~24MB/层，随窗口切换
  反复发生）。与 `invalidateLayer` 同口径：无限画布直接返回。
- **自动保存缩略图限长边 1024**：首页网格最多 ~256px 显示，无限画布内容包围盒
  ×0.2 仍可达数千像素（~48MB 瞬时分配），画画期间每 5s 自动保存重放一次；
  `renderToPng` 新增 `maxLongEdge` 参数（默认 4096 不变，仅缩略图调用收紧），
  峰值降到 ~3MB。

## [1.16.1] - 2026-09-07

### 瞬时内存尖峰修复（用户报告：1.16.0 下瞬间内存仍冲上 1GB+）

尖峰与常驻是两类问题：v1.15.1 修的是常驻（Impeller），本轮修的是**单次操作的无界分配**——

- **`renderToPng` 输出无尺寸上限（尖峰根因）**：无限画布按「内容包围盒」渲染，
  一个误触落点在很远处（如 50000,50000）就会让包围盒爆炸——scale 0.2 的缩略图
  尝试 `toImage(10000,10000)`（400MB），scale 1.0 的导出是 10GB 级分配尝试。
  现钳制：单边 ≤ 4096 且总像素 ≤ 4096²，超限同比例缩小（几何不变，只降分辨率）。
  自动保存缩略图 / 导出 PNG / 复制 PNG 全部经此路径受益。
- **取色探针降采样**（`pickColorAt`）：此前每次取色整文档原尺寸渲染
  （A4 ≈ 35MB 位图 + 35MB rawRgba 副本，吸管连续移动时反复 70MB 峰值）；
  现探针按 1024 长边等比缩放后采样坐标。

### 测试

- 全量回归绿；新增 `renderToPng` 尺寸钳制与探针降采样的回归断言
  （见 `test/` 下 1.16.1 相应用例）。

## [1.16.0] - 2026-09-06

### 整体代码审计修复（资源生命周期 / 加密边界 / 保存策略 / 架构门禁 / 发布一致性）

按四路只读整体审计（架构、内存、安全、工程质量）意见完成的修复批：

**资源生命周期（原生泄漏清零）**
- **整本 PDF 导出**（`notebook_pdf_exporter.dart`）：页面图片此前**全分辨率**解码且导出后从不 dispose、Codec 从不 dispose；现套用 4096 长边封顶、Codec 用后即释放、全部解码位图登记并在 finally 统一 dispose（含异常路径）。混合导出 Future 必须在 try 内 await（lint 抓到的真实提前释放 bug）。
- **复制 PNG 到剪贴板**（`editor_exporter.dart`）：Codec 此前任何路径都不 dispose、Image 释放不在 finally（剪贴板被占用/像素解码失败即泄漏全尺寸位图）；现统一 finally 释放。
- **图片裁剪**（`editor_page.dart`）：解码 Codec 此前从不 dispose；现入 finally。并修复审计发现的**裁剪后画布仍显示旧图**问题——裁剪重写磁盘后按 id 失效 `DocumentImageCache`（新增 `invalidate`/`invalidateDocumentImage` API），画布下次绘制重新解码新内容。

**加密与安全边界**
- **主密钥锁定断点**（`app_lock_gate.dart` + `vault_key_service.dart`）：此前切后台只清 KEK 缓存与会话口令，**主密钥整会话驻留**（`vault.lock()` 生产零调用）——「锁定」只是 UI 门。现超出宽限期（或宽限关闭）回前台时保险库掉锁（主密钥 fillRange 清零），加密文档读写 fail-closed；宽限期内不掉锁，无缝恢复不受影响。重解锁走 PIN/快速解锁既有路径。
- **WebDAV 同步 fail-closed**：未设置同步密码时，此前同步层是 Noop 透传——**笔记正文明文上云**，而 UI 宣称「云端仅保存加密后的数据」。现未配置同步密码直接拒绝同步并提示；文案改为「必填」。
- **写路径 fail-open → fail-closed**（`storage_service.dart`）：保险库已启用但锁定时，此前 `_sealDocBytes`/`_sealMediaBytes` 静默**明文落盘**；现抛 `VaultFileLockException`，由 SaveScheduler 退避重试、解锁后自愈。未启用加密（无 keyProvider）不受影响。
- **图片回收误删防护**（`storage_service.dart`）：`_deleteUnreferencedManagedImages` 此前跳过解码失败的文档（含锁定态密文文档），其引用的图片可能被误判孤儿删除；现任何文档解码/解密失败即**保守中止整轮回收**。

**保存策略（用户要求）**
- **自动保存最小间隔 800ms → 5 秒**（`SaveScheduler.autoSaveInterval`）：改动后最多每 5 秒落盘一次；无修改不保存（决策器 skip）；手动保存与退出兜底（flush/saveNow）不受影响，仍是立即落盘。

**导航与解码策略**
- **Lazy IndexedStack**（`app_shell.dart`）：4 个顶层标签此前全部常驻构建；现未访问过的标签零成本占位（不构建不保活），首次访问后保持 IndexedStack 保活语义（切走再切回不丢状态）。
- **图片解码预算并发**（`document_image_cache.dart`）：已用预算超过一半后，批量解码从 4 张并发收缩为逐张串行，避免极端大图（单张 ~64MB）在淘汰介入前出现 150MB+ 瞬时峰值。

**架构与发布门禁**
- **跨 feature 依赖棘轮门禁**（`test/architecture_boundary_ratchet_test.dart` 新增）：审计发现 52 处跨 feature import 而架构门禁只护 drawing↔notes 两个方向。现以基线快照钉死全部 10 个方向——新增越界 import 即红灯，修复后基线只紧不松。
- **版本一致性门禁**（`tools/check_version_consistency.dart` 新增 + quality_gate 接入）：pubspec 为唯一版本源，校验安装器 MyAppVersion/VersionInfoVersion（修复了 1.1.0 历史残留）、CHANGELOG 条目、Android/Windows 平台注入。
- **发布 workflow**：Android job 权限降为 contents:read 且不再并发写 GitHub Release（消除与 Windows job 的 Release 竞态），keystore 秘钥缺失时尽早失败；Windows job 增加版本一致性校验、integration smoke（真实启动 App 验证首页/编辑器/Tab）、安装器命名/SHA256 校验。

## [1.15.1] - 2026-09-06

### 根因修复：禁用 Impeller 渲染器（Windows/Intel 集显上 1.4GB 私有内存 + CPU/GPU 双高的真正元凶）

- **定位方法**（profile 构建 + VM Service 实测）：
  | 实例 | 工作集 | 私有提交 | Dart 堆 |
  |---|---|---|---|
  | Impeller 开（v1.15.0 安装版） | 1110MB | 1401MB | 25MB |
  | **Impeller 关（同一份代码）** | **295MB** | **288MB** | ~25MB |
- **结论**：Dart 堆只有 ~25MB、external ~14KB——此前 1GB+ 的占用与业务代码无关，
  全部落在 **Impeller OpenGLES 后端在 Intel 集显上的 GPU 内存行为**（大量离屏
  玻璃表面 + 画布位图放大了它）。这也解释了为什么 v1.14.x 的 App 侧修复
  （位图封顶/LRU/泄漏修复虽真实有效）都无法让总占用回落。
- **修复**：`windows/runner/main.cpp` 调用 embedder 的
  `project.set_impeller_switch(flutter::ImpellerSwitch::Disabled)`，
  渲染回退到成熟稳定的 Skia 路径。LiquidGlass L3 折射罩、铅笔颗粒着色器等
  dart:ui FragmentProgram 在 Skia 下均正常工作。
- 实测 Impeller 关闭后：私有内存 **1401MB → 288MB（约 1/5）**，App 正常启动运行。
- 若后续 Flutter 版本修复 Windows/Intel 集显上的 Impeller 内存问题，删除
  main.cpp 中标记的一行即可重新启用（`ImpellerSwitch::Default`）。

## [1.15.0] - 2026-09-06

### 内存专项（按外部专家审计意见全面落地，见 docs/MEMORY_TROUBLESHOOTING_2026-09-06.md）

外部专家确认：1GB 占用 = 引擎基线 + 多处常驻策略 + 2 处真泄漏叠加。本版按审计优先级 P0→P2 逐项修复：

- **P0 #3 真泄漏·StrokePictureCache 淘汰不释放原生 Picture**（`stroke_picture_cache.dart`）：
  LRU 淘汰条目时改为 `removeAt(0).picture.dispose()`——此前只 removeAt 不 dispose，
  被淘汰的 Skia 原生 `ui.Picture` 长期累积泄漏。
- **P0 #2 半泄漏·文档图片缓存无 LRU**（`document_image_cache.dart`）：加入 **LRU + 字节预算**
  （默认 96MiB）。此前 `_images` 是无淘汰的 Map、单张可解码到 ~64MB，多图笔记累积到几百 MB；
  现超预算按最久未用淘汰并 `dispose`（近期渲染=可见性高，符合审计「按可见性优先保活」）。
- **P1 #1 后台/最小化释放图层位图**（`layer_render_cache_coordinator` + `drawing_controller` +
  `editor_page`）：新增 `releaseForBackground()`（置空并释放所有图层离屏位图、保留缓存索引），
  编辑器注册 `AppLifecycleListener`（onHide/onPause 释放、onResume 懒重建）。空载/切后台时
  不再常驻整张 A4 图层位图。
- **P1 #4 块文档撤销历史 100→50 步**（`note_block_history.dart`）：每步持整份 NoteBlockDoc
  深拷贝，长文档 × 100 步纯文本数据累积可观；下调到 50（文本编辑有 800ms 合并窗，仍覆盖绝大多数撤销）。
- **P2 #5 首页缩略图常驻**：已在 v1.14.2 通过 `cacheWidth` 档位化（256/512/1024/2048）封顶每张解码
  尺寸；更深的「离屏卡片卸载」属多文档场景的后续优化，本版不再引入风险性改动。
- 新增回归测试：StrokePictureCache 条数有界、DocumentImageCache LRU 淘汰/按需重解码、
  LayerRenderCache 后台释放→前台懒重建；相关模块测试全绿，analyze 零告警。

> 与 v1.14.3（已发）叠加：液态玻璃边缘罩停止永续 60FPS 着色（CPU/GPU 打满根因）。本装包
> 1.15.0 已包含该修复，一次安装到位。

## [1.14.3] - 2026-09-06

### 紧急修复：CPU / GPU 异常打满 + 内存堆积（用户报告：画图软件却三高，实机确认 Abnormal）

- **根因**：`LiquidGlassRim`（液态玻璃 L3 边缘折射罩）的 State 里无条件执行了
  `AnimationController(duration: 4s)..repeat()`。即便 `animated:false` 分支不挂
  `AnimatedBuilder`，一个处于 *repeat* 状态的 Ticker 本身仍会持续逐帧向引擎申请帧。
  而 `GlassSurface` 传 `animated: !reduceEffects`（普通机器恒为 true）、且玻璃表面
  遍布全 App（导航条 / 顶栏 / 工具岛 / 面板），再叠加 `IndexedStack` 常驻全部标签页
  ——于是同时存在**几十个永续 60FPS 的 fragment shader 动画**在后台跑：GPU、CPU
  双打满、每帧着色/回读又推高内存。这与绘画操作无关，是持续的背景渲染。
- **修复**：
  1. `LiquidGlassRim`: 仅当 `animated` 为真时才 `_time.repeat()`（initState / didUpdateWidget
     门控），`animated:false` 时 controller 不启动、不再逐帧申请帧；
  2. `GlassSurface`: 边缘罩**默认静态**（`animated: false`）——保留玻璃折射罩的
     静态观感（backdrop 模糊/折射仍生效），但停止 4s 循环闪烁这种高频率表面上的
     永续着色。确需闪烁的地方可显式为 `LiquidGlassRim` 传 `animated: true`。
- 验证：`flutter analyze` 零告警；玻璃表面 / 外壳 / 液态玻璃配方测试全绿。
- 实测（用户在运行版本 1.14.2）：WorkingSet ~615MB / 私有提交 ~1.9GB、CPU/GPU 高；
  本修复移除最主要的逐帧着色源后，重装 1.14.3 应显著回落。

## [1.14.2] - 2026-09-06

### 画板内存治理（用户报告：分页画布内存占用 ~600MB、全场最高，且伴随画面冻结）

- **根因**：分页画布（固定 A4 纸 2480×3508）每画一笔都 `LayerCompositor.rasterize`
  整张全页离屏位图——一张 RGBA ≈ 35MB；增量路径还会把旧全图当底、再分配一张新全图。
  连续绘制时多张 35MB 图在途堆积（冻结时主线程停摆、`dispose` 来不及回收）→ 内存
  升到 600MB、弱 GPU 上反复 `toImage(2480×3508)` 卡顿冻结。无限画布走矢量路径
  （`invalidateLayer` 直接返回），不分配这些位图，故只有分页画布重/冻结。
- **修复**：`LayerCompositor.rasterize` 给图层位图**长边封顶到 2048**
  （`LayerCompositor.maxBitmapLongEdge`，与 `ImageDecodeCap` 显示上限同量级）。
  小画布（≤2048）scale=1、行为零变化；大画布（A4 分页）单张位图 35MB → ~12MB，
  且封顶时不再持有旧全图当底（改整层重建），显著降低峰值与逐笔 toImage 开销。
- **绘制端统一缩放**：`CanvasPainter`（画布 + 小地图）与 `drawing_controller_render`
  `_paintDocument`（导出/取色）改用 `drawImageRect`（src=位图实际尺寸，dst=文档尺寸），
  无需感知封顶比例。
- 新增测试：小画布保持原尺寸（scale=1 回归护栏）、A4 大画布位图长边封顶到 2048 且
  内存上限 16MB；render/compositor/canvas 相关测试全绿，analyze 零告警。

## [1.14.1] - 2026-09-06

### 分页画布命名修复（用户报告：分页画布永远显示「未命名」、无法命名）

- **创建即命名**（home_page `_createNotebook`）：此前新建分页画布硬编码 `title: '未命名'`、无命名弹窗，与「新建无限画布」的 `_NameDialog` 不对称。现创建前先弹命名对话框（`新建分页画布`），取消/空名则取消创建。
- **已建画布可重命名**（NotebookViewPage）：此前页面管理菜单没有任何重命名入口，旧的「未命名」画布无法补取名。现菜单新增「重命名分页画布」项，改名后整本落盘（复用页内 `_PageNameDialog`）。
- 同步更新 `home_create_notebook_failure_test`（保存失败路径现在先过命名弹窗）；analyze 零告警。

## [1.14.0] - 2026-09-06

### 直线/箭头几何交互重构（审计二）+ 画布 chrome 接入设计语言（审计三）+ v1.13.0 复查项（审计四）

**直线/箭头「难画、经常偏移」六项改进（审计二-1~二-7）**：

- **角度吸附**（二-1）：拖拽创建直线/箭头时，偏离 0°/45°/90° 在 ±5° 内自动磁吸（保持长度）；桌面 Shift 键无视容差强制吸附最近 45° 方向；预览与落定共用同一换算，所见即所得。吸附数值单一来源上移至 `ShapeBindingGeometry`（rendering 层，application 层可复用且不破洋葱规则）
- **端点编辑手柄**（二-2）：选中直线/箭头后显示两端 12px 圆形拖柄（44×44 热区），拖动即改端点——「画歪了重画」变成「画歪了微调」。无限画布与分页笔记双端落地；无限画布箭头拖柄支持拖入/拖离目标时实时建立/解除绑定
- **端点磁吸形状 + 绑定重投影**（二-3/二-4）：端点距目标外接框 ≤8px 即吸附到框周界（替代分页笔记旧的「按中心 50px」判定——大形状边缘绑得上、小形状不再被旁边大形状抢绑）；绑定时刻端点重投影到目标边上，箭头尖不再悬在形状内部/留视觉缝；无限画布箭头命中容差同步从「点在框内」放宽为「8px 邻域」
- **线性元素命中改点到线段距离**（二-5）：命中带宽 = 线宽/2 + 6px，外接框只留给封闭形状——细斜线外接框的大片空白不再拦截点击，也不再挡住叠在其后的元素（双画布一致：会话层 hitTest + 分页笔记 LinearShapePainter.hitTest）
- **拖拽读数气泡**（二-6）：创建/编辑线性元素时显示「长度 px · 角度°」玻璃胶囊，触屏手指遮挡落点时至少看得见自己在画什么
- **单击阈值 4px→8px**（二-7）：轻微手抖不再意外弹出 160×110 默认形状
- 顺带修复：分页笔记线性元素缩放 ≠100% 时端点错位（显式 lineStart/lineEnd 未乘 viewScale 的潜伏 bug）

**画布页 chrome 接入自家设计语言（审计三）**：

- **编辑器左工具条 → 浮动玻璃岛**（三-1）：GlassSurface（σ12/0.62）+ AppleRadius.lg 胶囊，画布内左侧离边 12px 垂直居中、限宽 56px 限高可滚；选中态 Action Blue 底 + 白图标；图标统一 `_rounded` 系（三-5）
- **状态栏改版**（三-2）：缩放百分比 → 胶囊按钮（50/100/200/适应画布 菜单，视口中心不漂移）；保存状态 → 图标+文本色芯片，状态切换带 toastIn 微动效（0.96 缩放 + 淡入，减弱动效降级为纯淡入）；画布坐标读数收进「仅桌面 + 默认关」的按钮开关
- **属性面板色板**（三-3）：画笔/文字色点的 Colors.black26 硬描边 → outlineVariant 发丝线（v1.10.8 色板同款）
- **网格重做**（三-4）：点阵画在画布坐标（经视口变换投影），平移缩放时纸动格子也动，修掉旧版视图坐标错位；步长 20px 与 `_snapToGrid` 拖动吸附/创建吸附同源（网格即吸附档位的视觉真相）；缩放过密自动倍增步长
- **分页画布页卡美化**（三-6）：缩略图区发丝线描边 + 极浅双层纸影 + AppleRadius.sm；Card 圆角对齐 AppleRadius.md、零海拔；标题/元信息走 17/11.5 排版梯子；网格间距对齐 AppleSpacing.md；按钮图标 rounded 化
- **页卡 → 编辑器转场**（三-8）：新增 `AppleSheetFadeRoute`（AppleMotion.sheet 300ms + easeSheet，淡入 + 0.96 起始缩放 + 4% 轻上升；退场 250ms；减弱动效 → 纯淡入）替换平台默认转场
- **笔记本顶栏**（三-7）：核实已是 GlassAppBar + extendBodyBehindAppBar（v1.10.x 已接入），无需改动——审计描述过时

**v1.13.0 复查项（审计四）**：

- **宽限期说明文案**（四-1）：设置页档位对话框写明「宽限期只免锁屏，加密文件与笔记的密码仍会重新要求」（中英 ARB 同步）——管理「锁屏没锁、文件却要密码」的预期
- **缩略图 cacheWidth 档位化**（四-2）：目标宽取整到 256/512/1024/2048 档（`ImageDecodeCap.quantizedCacheWidth`），窗口连续 resize 不再在图像缓存里堆多档位图
- **vault tmp 清扫**（四-3）：审计结论「可接受，无需改」，未动

**其他**：

- **块文档锁定不再静默消失**（审计一-3 体验缺陷）：会话 DEK 被清时改为明确提示「该笔记已加密且会话已锁定，请重新解锁后再打开」
- 新增/更新测试：角度吸附（容差内/外、force、45°）、网格档、边框投影、8px 邻域命中、距离命中带宽（含粗线/旧文档回退/封闭形状对照）、applyLinearEndpoints 规范化、局部-全局逆变换往返、cacheWidth 档位、宽限期文案；绑定端点期望值随边框重投影语义更新

## [1.13.0] - 2026-09-06

### 锁屏宽限期（U1 尾项·用户 2026-09-06 拍板）+ 审计遗留收尾

- **切后台回锁 30s 宽限期**（审计二-8；推翻 v1.12.0「暂不实施」记录——用户本轮拍板）：paused 起在宽限期内回前台自动放行，Windows 任务视图扫一眼不再弹锁屏。默认 30s，应用锁设置页可调（关闭 / 30 秒 / 1 分钟 / 5 分钟，`AppLockService.graceChoices`）
  - 宽限判定用单调秒表（Stopwatch），系统时钟回拨绕不过；仅适用于「切后台触发的锁定」，冷启动锁定不吃宽限；每次后台只评估一次——超宽限锁定后快速再切不会重置资格
  - 安全边界不变：hidden 即清 KEK 会话缓存 / 文件口令（N3 决策）不受宽限影响——宽限只作用于锁屏 UI
- **首页缩略图解码降采样**（审计三-10 / U4 收尾）：卡片缩略图按「布局宽 × dpr」解码（`cacheWidth`），大画布上千像素的存储缩略图不再全尺寸进内存；PDF 预览此前已在渲染源头限宽（≤480px），无需重复处理
- **删除笔记本连带清理 .bak**（审计三-5）：旧内容不再残留磁盘（隐私）；「仅剩 .bak」的崩溃形态现在也能正确删除，已删笔记本不再凭备份复活
- **保险库 .tmp 崩溃残留清扫**（审计三-6）：读取路径一次性清扫修改时间 >1h 的 `vault.json.tmp.*` 孤儿（内含被包装主密钥——隐私残留）；新近 tmp（并发写入中）不误删
- **WebDAV 配置解析失败落审计日志**（审计低-11）：降级为空配置不再完全无痕，同步「凭空消失」可诊断
- **弹窗 TextEditingController 释放**（审计低-9 收尾）：图表生成（editor_page_actions）与添加待办（schedule_page）两处对话框 controller 改为 finally 统一释放，返回即捕获文本不再触碰已 dispose 对象
- **选框族蓝统一为品牌 Action Blue**（审计四-2）：缩放手柄（原 Material 蓝 #42A5F5）、套索遮罩/描边、选框（原 #2F80ED）、小地图视口框、演示箭头、文字虚线选框——编辑器内两种游离蓝归一为 `AppleColor.actionBlue`。边界（刻意不动）：页面连接线默认色属持久化文档内容（`page_connector.dart`），改默认值会变更已存文档渲染，留待实机对比验证
- **应用锁设置页 l10n 补漏**：该页残留 12 处硬编码中文接入既有键（验证当前密码 / 保险库解锁失败 / 应用锁已开启 / 系统验证开启成功等）；`lockDescription` 文案随宽限期行为更新（中英双语）
- 新增测试：宽限期 service 持久化 / gate 生命周期三场景（宽限内免锁、超时必锁、冷启动不豁免）/ 设置页档位切换 / 笔记本删除清 .bak 三形态 / 保险库 tmp 清扫

## [1.12.0] - 2026-09-05

### 空态规范 + 死代码清理（审计收尾批次）

- **空态统一组件 `AppleEmptyState`**（审计二-4 空态两极分化）：共享单一来源「图标 + 标题 + 引导语 + 可选行动按钮」，尺寸/颜色对齐既有规范形态（记下第一笔）
- **8 处空态收编**：全部文档页页面级/Tab 级空态、首页画布/笔记两 Tab、分页画布空页、标签过滤无匹配、标签视图暂无标签——原「图标 + 一行字」与「一行灰字」统一为规范层级
- **边界（刻意不动）**：空间受限的嵌入场景保持紧凑一行字——全部文档侧栏、移动端分组内嵌、大纲 rail、编辑器内嵌提示、日程日内嵌提示、数据库视图卡片内提示
- **死代码清理**（用户批准）：删除 home 版 `_PasswordDialog`（home_page_widgets.dart，零实例化，实际使用 notebook 版同名类）
- **用户决定不实施**：锁屏 30s 宽限期（审计二-8）——切后台立即锁屏的安全行为保持原样

## [1.11.3] - 2026-09-05

### 性能优化（审计 U4 批次）

- **块文档编解码/加密 isolate 化**：`NoteBlockDocStore` 保存路径的 JSON 编码与信封加密、加载路径的 JSON 解析——超过 32K 码元阈值的大文档进 `Isolate.run`（对齐画布侧 `encodeSnapshotAsync` / `_sealDocBytes` 先例），大笔记保存/打开不再卡主线程；小文档维持主线程零往返开销。边界：v5 信封 rewrap 与解密依赖 `EncryptionService` 实例/会话缓存，留主 isolate
- **无边画布视口剔除**：`_ElementPainter` 按世界坐标可见区（`getLocalClipBounds`，与主画布 painter 同机制）剔除视口外的形状与笔迹——`EdgelessStroke` 新增 `bounds` 包围盒（含线宽外扩）；数百元素画布平移/缩放只绘制可见部分
- **RepaintBoundary 隔离**：无边画布连接线层/元素层各包 `RepaintBoundary`（对齐主画布 `editor_page_canvas_surface` 先例）
- **核查澄清（审计项已达标不再动）**：搜索防抖（all_docs `SearchDebouncer` + search_page 300ms Timer）；图片降采样（解码端长边 4096/2048 封顶；磁盘存原图属数据完整性特性，保留）

## [1.11.2] - 2026-09-05

### l10n 收编（审计 U3 批次·第二期）

- **国际化基建落地**：`l10n.yaml`（gen_l10n）+ 中英双语 ARB（`app_zh.arb` / `app_en.arb`）；可空回退模式 `AppLocalizations.of(context)?.key ?? '中文'`——测试与缺 delegate 场景自动回退中文
- **5 页面收编约 160 字符串**：应用锁设置页（约 20 处）、设置页（主题/密码三层卡等 23 键）、app_shell（导航 8 处 + 编辑器兜底）、笔记页 doc_page（分享/导出/策略拒绝/独立密码全流程/信息弹窗/标签编辑约 60 处）、全部文档页（面包屑/排序菜单/新建四入口/三 Tab/空态文案）
- ARB 共新增 141 键（81 + 12 + 40 + 8），含占位符键（导出路径、策略操作、独立密码标题、保存时间等）
- 中文视觉零变化：所有回退值与原字符串逐字一致

## [1.11.1] - 2026-09-05

### 视觉统一（审计 U3 批次·第一期）

- **双令牌源收编**（四-1）：`AppDesign` 中与 `AppleColor` 同值的 7 个颜色常量改为别名引用（单一事实来源，改令牌全消费文件同步生效）；`lightSubtleSurface`（systemGray6）与 `AppleColor.subtleSurface` 是刻意保留的两个灰阶，不合并；新增 `identical` 锁定测试防止回退
- **骨架屏接入**（二-6）：标签视图 / 回收站 / 搜索结果 / 日程议程 4 处列表加载由裸 spinner 换为 `SkeletonList`（形态先行）；PDF 预览与图片查看器的 spinner 刻意保留（传输进度语义，非布局骨架）
- **核查澄清（审计第 4 轮旧快照项）**：三-8 `withOpacity` 迁移已完成（全库 0 处，`withValues` 89 处）；二-5/四-3 弹窗语言统一已随 v1.10.2-4 dialogTheme 覆盖模式收口（现存 `AlertDialog(` 均为 GlassDialog.show 的玻璃内容层）
- l10n 收编 5 页面（三-7，约 50+ 字符串 × 双语）单独成批，另行发版

## [1.11.0] - 2026-09-05

### 触控与反馈（审计 U2 批次）

- **统一触感**：`ApplePressable` 按下即 `HapticFeedback.selectionClick()`——全库按钮基座一处改动全库受益（指针与键盘同反馈，禁用态不触发）
- **无障碍**：`ApplePressable` 语义树始终暴露 button 角色与启用状态（不再依赖 label 存在，读屏可遍历全部按压目标）
- **热区收尾（≥44px，视觉不变）**：画笔/文字颜色圆点（28/22→热区 44）、标签视图返回钮（补足 44）、无边画布帧头部背景色点（溢出命中法，帧头布局零变化）
- **上下文菜单三输入可达**：画布元素菜单新增触屏长按入口（与右键等价、锚定触发点）与键盘入口（Menu 键 / Shift+F10）；菜单位置改为锚定指针/长按触发点（废除硬编码 100,100），键盘触发落在画布中央偏上
- **顺带修复**：`ApplePressable` 禁用态键盘 KeyUp 仍会触发 onTap 的既有泄漏

### 新增

- 新增 `ApplePressable` 触感/语义测试 4 项

## [1.10.9] - 2026-09-05

### 稳定性（审计 U1 止血批次）

- **日程页**：三处事件操作（添加 / 勾选完成 / 删除）补 `mounted` 守卫——等待写入期间退出页面不再 `setState() called after dispose()`；写入失败补 try/catch + SnackBar 人话提示（原表现为「什么都没发生」）
- **画布编辑器**：裁剪保存的加密写入 await 后补 `mounted` 守卫（审计三-1）
- **核查澄清（审计第 4 轮两处「高」为旧快照误报）**：`schedule_event_store` 写链串行化（`_enqueue`）与 `document_transaction` 回滚 `AuditLogger` 化均已在 2026-09-04 `6f0074a`（P0-P2 闭环）修复，本轮复核确认无需再改

## [1.10.8] - 2026-09-05

### 体验修复（来源：docs/AUDIT_UX_ROUND4_2026-09-05.md 第 4 轮审计）

- **颜色选择器**：二维色域框取色与视觉左右镜像颠倒——叠加渐变方向修正为「左白右饱和」，对齐 Excalidraw S 方块与取色映射（点饱和处取到 s=0 的所见非所得 bug，合入前复查追加发现）
- **颜色选择器**：RGB 读数恒为 0/1（`Color.r/g/b` 为 0–1 double，修正为 ×255 取整）
- **颜色选择器**：色相条渲染宽 320 与取色换算宽 300 不一致（约 6.7% 色相偏移），触控热区 22→44px（视觉不变）
- **颜色选择器**：预设色板补选中态（强调色外圈 + 勾选 + 触感反馈）；色域框/色相条圆角 + 发丝线描边统一；`_sameColor` 补 alpha 比较
- **画布缩放手柄**：命中区 10×10 → 44×44（视觉手柄保持 10×10 居中，桌面观感零变化；HIG/WCAG 最小触控尺寸）

## [1.10.7] - 2026-09-05

### 液态玻璃 G3：backdrop 真折射位移 + 色散落地

- **新增 `shaders/liquid_glass_backdrop.frag`**：backdrop 滤镜着色器——
  圆角矩形 SDF 边缘带内对背景做径向位移采样（liquid-glass-react
  displacementScale 70 配方）+ RGB 三通道递减位移色散（aberration 2），
  经 `ImageFilter.shader`（Flutter 3.47）绑定为 `BackdropFilter` 的 filter。
- **GlassSurface 管线升级**（G3 → G1 回落）：
  - G1（默认兜底）：`saturate(blur(source))`，缓存 key = sigma|saturation；
  - G3（L3 + `ImageFilter.isShaderFilterSupported` + 着色器就绪 + 已测得
    实际尺寸）：`saturate(blur(displace(source)))`——真位移、真色散。
  - 回落链完整：任一条件不满足静默回落 G1，视觉不中断。
- **GlassSurface → StatefulWidget**：新增 `_MeasureSize`（RenderProxyBox
  零开销层）测量实际渲染尺寸——G3 位移采样需真实尺寸（LayoutBuilder
  约束在弹窗/FAB 等 loose 场景不可靠）。首帧 G1、次帧起 G3，切换差异
  细微不可感。
- **平台诚实边界收尾**：`glass_surface.dart` / `liquid_glass.frag` 头注释
  的「backdrop 自定义采样无公开 API」过时断言全部更正。
- **真机目视验证点（y 轴翻转）**：GLES 后端 backdrop 纹理 y 轴翻转是
  已知差异源（技术方案 §4）——Impeller 各后端方向以真机为准：若边缘
  折射上下反相，shader 内 uv 的 y 一行反相修正（已入 shader 注释）。
- 测试：liquid_glass_shader_test 4 项（init 幂等 / bindBackdrop 一致性 /
  isShaderFilterSupported 口径 / G3 分支测试环境回落不炸 + 一层
  BackdropFilter 红线）。

## [1.10.6] - 2026-09-05

### 液态玻璃覆盖面：画布编辑器顶栏（沉浸式）

- **EdgelessPage 顶栏玻璃化**（edgeless_page.dart）：原生 `AppBar` →
  `GlassAppBar`（title + 8 个操作按钮原样保留），开启
  `extendBodyBehindAppBar: true`——画布帧卡片/连线/网格从玻璃顶栏下
  穿过被模糊（沉浸式；画布不是滚动视图，无需让位 padding，视口直接全屏）。
- **坐标系影响评估（已入注释与测试）**：`_viewport` 高度变为屏幕高
  （原为屏幕高 − appBar），世界原点上移 appBar 高度、缩放焦点中心偏移
  appBar 高度的一半（≈28px，fitTo/缩放无感）；所有坐标转换经
  `_cameraMatrix(_viewport)` 自洽；顶栏区域手势由 AppBar 拦截，画布
  该区域可见不可点（iOS 同款行为）。
- **NavigationRail 决策记录（不改代码）**：宽屏侧栏维持 M3 原生——
  完整玻璃化需 Row→Stack 布局改造 + 全部页面左侧让位（改动面大收益低），
  保守玻璃化则 Rail 背后是纯背景色、玻璃无物可模糊。
- **G3 真位移 shader 决策记录**：`ImageFilter.shader` 方案已验证可行，
  y 轴翻转效果需真机目视确认后再铺开（避免不可视回归直接进主干）。
- 测试：edgeless_page_glass_bar_test 4 项（玻璃顶栏在位 /
  extendBodyBehindAppBar 断言 / 8 按钮保留 / 缩放回调不炸 /
  一层 BackdropFilter 红线）。

## [1.10.5] - 2026-09-05

### 液态玻璃覆盖面：导航类控件域（底部导航条 + FAB）

- **新增 `GlassNavigationBar`**（shared/widgets/glass_nav_bar.dart）：
  iOS 26 liquid glass tab bar 语义的**悬浮胶囊**底部导航条——高 64 +
  底部留边 12 + 左右留边 12，胶囊全圆（32）；内部复用原生
  `NavigationBar`（材质四件套全透明，indicator 保留——它是选中交互态
  非条体材质），系统手势区 / 3 键导航由组件内 `SafeArea` 消费，
  胶囊永远悬浮于系统栏上方；再向内清零注入，防 `NavigationBar` 的
  内部 SafeArea 二次膨胀。
- **新增 `GlassFab`**（shared/widgets/glass_fab.dart）：`FloatingActionButton`
  的材质替换壳——圆形 / extended 两个构造，参数与原生对齐（onPressed /
  child / heroTag），调用点零迁移成本；FAB 材质全透明（elevation /
  highlightElevation / hoverElevation / focusElevation 全零），ink
  state layer 保留交互反馈。配方与玻璃弹窗同家族（sigma 16 / 基底 0.72）。
- **app_shell 接入**：窄屏 Scaffold 开启 `extendBody: true`——内容延伸到
  玻璃条之后，BackdropFilter 才有东西可模糊（与 settings_page 顶栏注释
  同一原则）；输入法弹出时隐藏导航的行为不变。
- **4 页底部让位**（各按结构消费 `MediaQuery.padding.bottom`）：
  - 设置页：ListView bottom 改**可滚动让位**（注入值 + 24）——内容能
    滚到玻璃条背后被模糊，外层固定 Padding 会让玻璃退化成脏板子；
  - 首页：body 外层 Padding 加 bottom（AmbientBackground 仍延伸到条后）；
  - 全部文档（移动端）：`SafeArea` 恢复消费 bottom——共享列表组件
    `_GroupedDocList`/`_SortedDocList` 桌面移动两用，不侵入其内部；
  - 日历：`SafeArea` 默认消费，自动让位（零改动）。
- **接入点**：首页 FAB ×2（新建画布 / 新建笔记，extended）、全部文档
  移动端 FAB（圆形，`heroTag` 保留）。
- **范围外不动**：NavigationRail（宽屏侧边栏，后续单独评估）；滑块 ×8
  全在面板/弹窗内部（内容层红线，禁止玻璃化）。
- 测试：glass_fab_test 7 项 + glass_nav_bar_test 8 项 + app_shell 集成
  3 项（extendBody 断言 / 设置页让位断言 / FAB 状态断言——顺带锁定
  IndexedStack「同屏只保留当前目的地子树」实测行为）。

## [1.10.4] - 2026-09-05

### 液态玻璃覆盖面：弹窗域收口（showDialog 全量迁移）

剩余 20 处 `showDialog` 全部迁移到玻璃外壳，**弹窗域收口**——
全库除 core 内部实现外不再有直连 `showDialog` 的弹窗。

- **迁移 20 处**：SimpleDialog ×5（移动分组/收藏夹/版本历史等菜单式
  选择——`SimpleDialog` 构造参数同样默认 null，dialogTheme 覆盖同效）、
  AlertDialog ×11（文档打开、形状库、PDF 导出面板、命令面板、引导页、
  设置页、密码重置流程等）、自定义 Dialog 类 ×5 的 build 全部返回
  `AlertDialog`，dialogTheme 覆盖无障碍。
- 迁移后全库 `GlassDialog.show` 共 37 处 + `GlassDialog.confirm` 12 处；
  直连 `showDialog` 仅剩 core 的 `AppleDialog.confirm` 内部实现 1 处
  （单一事实来源本体，本就该保留）。
- **范围外刻意保留**：图片预览（沉浸式查看器，black87 深屏障 +
  可点按消失，玻璃化反而破坏观感）维持原样。

### 测试

- 全量回归 1778 项全绿（v1.10.3 的 16 项玻璃弹窗测试覆盖
  show/confirm 两条入口，本轮为纯调用点迁移，零新增逻辑）。

## [1.10.3] - 2026-09-05

### 液态玻璃覆盖面：内容定制弹窗接入玻璃

confirm 之外的第二类弹窗——带输入框、色板、模板选择等定制内容的裸
`AlertDialog`——现在也走玻璃外壳。

- **新增 `GlassDialog.show<T>`**：内容定制弹窗的通用迁移入口。调用点
  最小改动——`showDialog<X>(...)` 换成 `GlassDialog.show<X>(...)` 即可，
  builder 内部照常返回 `AlertDialog`（乃至 StatefulBuilder），零参数改动。
- **外壳统一结构（单一事实来源）**：`confirm` 与 `show` 共用同一外壳——
  留白 → 玻璃 → `dialogTheme` 覆盖。透明化（backgroundColor/surfaceTint/
  shadow/elevation）与 `insetPadding` 置零全部由 `dialogTheme` 提供：
  `AlertDialog` 构造参数默认全为 null，解析顺序
  `显式参数 ?? dialogTheme ?? M3 默认`，调用点未定制表面时覆盖必然生效。
- **切换 17 个弹窗**：文本/URL/重命名输入、页码跳转、页眉页脚、
  模板选择、收藏夹移动、密码保护（应用锁/笔记本/分区）、导入分页、
  WebDAV 冲突裁决、颜色选择器（两个入口）、新建页面、数据库单元格。
- 范围外（保持原样）：`SimpleDialog`、无 actions 的提示类弹窗等
  22 处 `showDialog`——后续按需迁移。
- **发现一处死代码**：`home_page_widgets.dart` 的 `_PasswordDialog`
  在 home library 内无任何实例化点（密码保护弹窗实际用的是
  notebook 版同名类）。本轮不删，待确认后处理。

### 测试

- `glass_dialog_test.dart` 新增 3 项（累计 16 项）：show 包裹裸
  AlertDialog 零参数改动 + 红线单层 BackdropFilter + 返回值透传、
  StatefulBuilder 动态内容形态、barrierDismissible=false。

## [1.10.2] - 2026-09-05

### 液态玻璃覆盖面：弹窗接入玻璃

顶栏之后，把玻璃铺到确认弹窗——全库使用频率最高的浮层。

- **新增 `GlassDialog`**（`lib/shared/widgets/glass_dialog.dart`）：玻璃材质
  的弹窗外壳。弹窗专用配方——blur 16（Apple HIG regular 20–40 下沿与
  clear 10–20 上沿之间，弹窗面积大需更强抹平）、基底 0.72（regular 区间
  中位，正文对比优先于通透）、饱和沿用全库默认 1.4、圆角 28（对齐 M3）。
- **架构：core 不反向依赖 shared**。`AppleDialog`（排布与平台按钮顺序的
  单一事实来源）只新增一个**可选**的表面注入参数 `surface`
  （`AppleDialogSurface` typedef），不传时行为与从前完全一致（裸
  `AlertDialog`）；玻璃皮在 `shared/widgets/glass_dialog.dart`，经
  `GlassDialog.confirm` / `GlassDialog.surface` 注入回 core。依赖方向
  恒为 shared → core，符合稳定依赖原则。
- **切换 12 处调用**（8 个文件）：应用锁门、文档页、回收站、应用锁设置、
  首页、笔记本页导入/管理域、密码重置流程。`AppleDialog.actions(...)`
  的裸弹窗按钮行不受影响（它们是内容定制的弹窗，另行处理）。
- **弹窗不算玻璃叠玻璃**：模态弹窗与页面之间有 barrier（black54）隔开，
  总纲红线针对的是内容层内直接叠加。
- **坑（已写进代码注释）**：内部 `AlertDialog` 的 `insetPadding` 必须置零、
  与屏幕边缘的留白由玻璃外壳接管——否则玻璃会被撑成全屏大板，中间只有
  一小块内容。窄屏自动收窄留白，保证最小宽 280 装得下。

### 测试

- 新增 `glass_dialog_test.dart` 13 项：返回值语义（确认/取消/dismiss）、
  dangerous 错误色、内部 AlertDialog 全透明、inset 外壳接管、配方常量、
  **红线：整棵树只有一层 BackdropFilter**、平台按钮顺序（Windows 主按钮
  在左 / Android 在右）、未注入时裸 AlertDialog 回归保护、窄屏不溢出。

## [1.10.1] - 2026-09-05

### 液态玻璃覆盖面：顶栏接入玻璃

上一版把配方调对了，但玻璃只用在 6 处小控件上，打开 App 依然看不到。
本版把玻璃铺到顶栏（面积最大、最显眼的位置）。

- **新增 `GlassAppBar`**：复用原生 `AppBar` 承担全部布局行为（status bar
  避让、标题/操作按钮排版、bottom 插槽），只在它背后垫一层玻璃。
  替换 `AppBar` 不会引入布局回归——玻璃是纯附加的背景层，不参与测量。
- **接入 7 个页面**：首页、设置、应用锁、WebDAV 同步、搜索、笔记、笔记本。
- **内容延伸到顶栏之后**（`extendBodyBehindAppBar`）：这是玻璃生效的前提。
  否则顶栏背后是纯色 Scaffold 背景，BackdropFilter 采不到东西，
  玻璃会退化成一块脏兮兮的半透明板。

### 两个容易踩的坑（已写进代码注释）

- **顶部让位必须用「可滚动」的 padding**（ListView 自身的 padding），
  不能用外层固定 `Padding`。外层固定 Padding 会限制视口，内容永远滚不进
  顶栏背后，玻璃同样没有东西可模糊。
- **红线：禁止玻璃叠玻璃**。首页分段控件原本自带一层玻璃，顶栏接入玻璃后
  必须摘掉，否则两层玻璃叠在一起（DESIGN_SYSTEM.md:218）。
  笔记本页的筛选框同理——加了让位 padding，确保它不与顶栏重叠。

### 两个页面故意不接玻璃

- **翻页阅读页**：沉浸式深色场景，玻璃会干扰阅读（Apple HIG 明确要求
  玻璃用于区分控制层与内容层，不是到处铺）。
- **画布编辑器**：视口坐标系需要单独评估，暂不改动。

## [1.10.0] - 2026-09-05

### 液态玻璃：补上缺失的三块（本次改动的主题）

用户反馈「苹果那种透明玻璃质感看不到」。核查后确认是三处叠加，本版全部处理：

- **补上饱和度 `saturate(140%)`**：此前**完全没有实现**。旧文档断言
  「BackdropFilter 无自定义采样 API，真饱和不可做」，该结论已过时——
  `ColorFilter` 本就是 `ImageFilter` 子类，用 `ImageFilter.compose` 与
  `blur` 合成即可。现在玻璃背后的内容会被提饱和，不再是灰扑扑一片。
- **默认档 L2 → L3，折射罩终于真的渲染**：着色器、组件、启动预加载此前
  全都写好了，但全仓库**没有任何一处传 `level: l3`**，导致折射环、RGB
  色散、镜面高光一次都没画出来过。现在默认即 L3（仍有性能闸门，
  未就绪/减弱动效自动回落）。
- **基底不透明度 80% → 62%**：80% 几乎不透明，背后的内容透不出来，
  观感退化成「灰白板」而非玻璃。62% 取 Apple HIG regular 变体下限
  （0.6–0.8）偏通透侧；另提供 clear 变体常量 0.45（HIG clear 区间 0.3–0.5）。

### 规范侧更正

- 修正 `DESIGN_SYSTEM.md` 两处历史错误：① 参数表引用的是库内部组件
  `GlassContainer` 的默认值，而非对外组件 `LiquidGlass` 的默认值
  （70 / 0.0625 / 140 而非 25 / 12 / 180）；② `blur 12` 是**系数**不是
  像素，真实模糊 = `4 + blurAmount × 32`，代错会变成 388px。
- 新增 `docs/LIQUID_GLASS_TECHNICAL_PLAN_2026-09-05.md`：三来源参数对照、
  参考实现的真实机制（中心原图 + 边缘折射，不是整块毛玻璃）、
  Flutter 3.47 的能力清单、G0–G3 落地分档与红线。
- 配方常量收编进 `LiquidGlassRecipe`，调用点不再硬编码数值。

### 用户可见

玻璃浮层（首页分段导航、日程页浮块、画板上下文工具条、笔记本筛选）
现在会更通透、背后色彩更饱和，边缘能看到折射高光。

## [1.9.9] - 2026-09-04

### 排版（本次改动最大，直接作用于打字与阅读）

- **落地 DESIGN.md 的完整排版梯子**：新增 `AppleTypeScale`，15 个档位的
  字号 / 字重 / 行高 / 字距**逐格照抄**规范表，四元组绑定成一个整体，
  杜绝「只抄字号不抄行高」的半吊子落地（此前 `bodyStyle` 的字距就是自己
  拍的 -0.1，规范要求 -0.374）。
- **笔记正文 16px → 17px**：DESIGN.md:379 明确「Body copy at 17px, not
  16px — Apple breaks the SaaS convention」，此前用的是 16px。
- **笔记正文行高补齐 1.47**：原先走 Flutter 默认（约 1.2~1.3），中文在
  这个行高下明显拥挤。现在打字、待办、引用、标注、代码块都有正确行距。
- **标题字重 700 → 600**：DESIGN.md:369「Weight 600, not 700, for
  headlines」。h1-h6 同时补上了行高与字距——展示档收紧（h1 为 1.14）、
  17px 以上带负字距。

### 修复

- **列表 / 卡片的多行文字补行高**：看板卡片标题（最多 2 行）与表格多行
  单元格原先没有行高，走样后两行会贴在一起。

### 说明

- DESIGN.md:366 的散文说「17px 以上都带负字距」，但它自己的数值表里
  display-lg(40px) 是 0、lead(28px) 与 tagline(21px) 都是**正数**。
  本版**以数值表为准**（表是逐格量过的，散文是归纳），并在测试中把这条
  裁决固化下来，避免以后有人按散文去「修正」表里的值。

## [1.9.8] - 2026-09-04

### 界面精细化（DESIGN.md 静态视觉域）

- **次级信息色统一**：同一个「次要信息」语义此前在全库被写成
  0.4 / 0.45 / 0.5 / 0.52 / 0.55 / 0.6 **六种透明度、共 20 余处**，深浅
  模式下观感各不相同。现收敛为两级——元信息文字走语义色（明暗自适应，
  白底对比度 5.3:1），图标与装饰走 55% 淡化（非文本 3:1 达标）。
- **容器底色统一**：附件卡、嵌入块、数据库块、看板列、设置卡片、缩略图
  占位等原先各写各的「容器色再叠 0.35~0.5 透明度」，深色模式下几乎
  看不见；改用 M3 语义容器档，与画板浮层面板保持一致。搜索框与行内
  代码高亮改用满底填充（M3 规范），不再做二次衰减。
- **字重回到 Apple 梯子**：清理 6 处 w500。DESIGN.md:504 明确 Apple 的
  字重梯子只有 300 / 400 / 600 / 700，**500 刻意缺席**。正文类（小字
  说明、日历日期）回到 400，标题与强调类（空态主文案、画布量标注、
  密码盘标题）走 600。

### 修复

- **引用块不该被淡化**：引用文字原先套了 60% 透明度，使正文字号下的
  对比度低于 WCAG 对文本的 4.5:1 要求。斜体已足够表达引用语义，不再
  额外压暗。
- **拖拽把手双重淡化**：编辑器行内拖拽图标同时被降透明度与套 opacity，
  实际几乎不可见，现只保留一层。

## [1.9.7] - 2026-09-04

### 界面精细化（依据 DESIGN.md 与六来源按域分权总纲）

- **发丝线与海拔**：卡片 / 分割线改用 1px 发丝线（亮 8% 黑、暗 12% 白，
  DESIGN.md:395），替代原先约 18% 灰的描边；新增海拔三档——内容层
  零阴影、浮层 10%、模态取规范里唯一那条真阴影。
- **键盘焦点环**：补上 2px 焦点蓝环（DESIGN.md:300）。此前主题层完全
  没有焦点态，键盘用户 Tab 到按钮看不到任何指示。
- **圆角统一**：78 处硬编码圆角收编到 5 / 8 / 11 / 18 / 胶囊五档，
  消除 DESIGN.md:511 禁止的「混圆角语法」。
- **对话框排版**：标题 17px、正文 15px 行高 1.47，说明性文字降一级灰度
  形成信息层级（此前完全吃系统默认）。
- **弹窗按钮顺序按平台**：Windows / Linux 主按钮在左，macOS / iOS /
  Android 在右（17 处双钮弹窗已迁移，AppBar 工具条与多钮弹窗不动）。

### 无障碍

- **Windows 高对比度第三档**：此前只有浅色 / 深色两档，系统开启高对比
  度后 8% 发丝线会淡到看不见。新增跟随系统 / 强制开 / 强制关三态开关
  （设置 → 通用 → 高对比度），边框与文字在该档位推到 100% 不透明。

### 修复

- **版本位补同步**：v1.9.5 打 tag 时漏了 pubspec 与 Inno Setup 脚本两处
  版本位，导致该版安装包内嵌 1.9.4。v1.9.6 起三处同步（v1.9.5 已发布
  不回溯改写，故版本位顺延）。

## [1.9.6] - 2026-09-04

- **修正版本位（发版流程 bug）**：v1.9.5 打 tag 发版时漏同步
  `pubspec.yaml` 与 `tools/drawing_notes_setup.iss` 两处版本位，导致
  v1.9.5 的 Windows 安装包文件名与内嵌版本号仍是 `1.9.4`。本版按
  「三处同步 bump」规范把 pubspec 提到 `1.9.6+37`、iss 提到 `1.9.6`
  （v1.9.5 tag 已发布，不回溯改写，故版本位顺延一档）。

## [1.9.5] - 2026-09-04

- **外部审计修补（H1·高）**：Android release 构建补上 `INTERNET` 权限——
  此前仅 debug/profile 清单有，release 包 WebDAV 同步必然
  `SocketException`。Windows 端无影响。
- **外部审计修补（M1）**：拆除 `lib/fix/`——843 行 `security_and_sync_fix.dart`
  拆分迁移至 `features/security/sync_fix.dart` + `shared/widgets/`
  （pin_pad / unlock_sheets / home_lock_button），密码重置流程四件套归位
  `features/security/`，行为零变化（1639 测试全绿）。
- **外部审计修补（M2 + 防误删）**：同步单操作失败隔离——单个文档上传/
  下载失败不再中断整轮，失败项进 `SyncResult.failedDocIds`、两端不回写、
  下轮自动重试；并修复伴生数据丢失边界：下载失败的仅远端文档不入本地
  基线，防止下轮被误判删除墓碑而删掉远端文档（含 5 个回归测试）。
- **外部审计修补（M6）**：修复 LWW 时钟依赖导致的静默分叉——两端
  `updatedAt` 相同但 `size` 不同时（同毫秒双端编辑 / 时钟偏移巧合），
  旧实现被 planner 的「== → 忽略」分支吞掉，两端版本静默分叉到下次编辑；
  现 detector 新增 `sameTsDiverged` 条件、planner 裁决器为「计划里没有
  操作的冲突文档」补一条 LWW 默认操作（ts 相等 → keepLocal → 上传），
  含 2 个回归测试（同 ts 不同 size 报冲突 + 同 ts 同 size 不冲突）。
- **外部审计修补（M4·M5·L1）**：keepBoth 冲突副本当轮入本地基线（远端
  清单不写，避免其他设备 404 空转）；写事务 AAD 上下文统一 UTF-8 编码
  （该类无生产调用方与解密端，零兼容成本）；README 中英文安全定位改为
  「本地优先 + 可选 WebDAV E2E 同步」的准确表述。
- **依赖升级**：`flutter_secure_storage` 9.2.4→11.0.0（仅用默认构造，
  API 零破坏；⚠️ 老用户需重新配置 WebDAV 口令与快速解锁，保险库数据
  不受影响）、`pointycastle` 3.9.1→4.0.0（PBKDF2 派生一致性有测试保证）。
- **依赖锁定**：`pdfrx` 锁定 2.4.7——2.5.0 上游发布不完整（包内引用
  自身不存在的符号，编译失败），待上游修复后再升。
- **构建加固（L2）**：Android release 启用 R8 混淆 + 资源收缩
  （`proguard-rules.pro` 保留 secure_storage / biometric 桥接类），
  减小包体并增加逆向成本。

## [1.9.4] - 2026-09-04

- **核心操作读屏语义（审计 R6）**：文档行的收藏星标与「⋯ 更多操作」按钮
  补上状态化读屏标签（添加收藏／取消收藏／更多操作），读屏软件可正确朗读；
  密码框的「显示／隐藏密码」按钮补状态化提示。功能与视觉零变化，仅对
  读屏与键盘用户生效。
- **CI 稳定性（第三类）**：修复加密懒迁移测试在慢机器上偶发失败——等待
  密文落盘的上限由 2 秒放宽到 15 秒（是用例内部轮询上限，不是单测超时，
  故此前放宽到 3 分钟无效）；三处重复的等待逻辑合并为公共 helper。

## [1.9.3] - 2026-09-03

- **桌面窗口最小尺寸（审计 R2）**：Windows 窗口最小 360×560，拖得过窄
  不再挤坏界面（窄屏布局由顶栏减负与自适应分级兜底）。Android 零影响。

## [1.9.2] - 2026-09-03

- **画板顶栏窄屏减负（审计 R3）**：手机或窄窗口（<600dp）下，图层/属性/
  全屏/深色阅读 4 个低频开关收进右上角主菜单顶部（带状态文案），顶栏
  只留撤销/重做/主菜单——画布标题从 22px 缝隙恢复到约 200px 可读宽度；
  桌面宽屏布局零变化。
- **同步错误提示人话化（审计 R1）**：WebDAV 同步失败不再显示英文异常
  堆栈，按认证失败/服务器错误/目录不存在/网络/HTTPS 握手等六类给出
  可读文案，原始错误进调试日志。
- **界面颜色统一收尾（审计 R5）**：11 个文件约 20 处零散硬编码颜色
  收编进 Apple 设计令牌，全库硬编码色清零。
- **窄屏布局防线补齐（审计 R2）**：回收站/搜索/标签/日程/设置/笔记/
  分页画布 7 个页面加入 390dp 溢出门禁探针（实测全部无隐藏溢出）。
- **CI 稳定性**：修复 Windows 云端构建两类偶发失败——加密懒迁移测试
  临时目录清理竞态（统一带退避重试）与真 KDF 派生测试 30 秒超时
  （放宽到 3 分钟）。

## [1.9.1] - 2026-09-03

- **审计残留收口（U5）**：新建分页画布保存失败（如磁盘不可写）不再静默
  丢稿——明确提示并停留在当前页；回收站条目读取改为后台异步（大回收站
  不卡列表）；笔记反链面板改为缓存索引（打开反链不再重复全量读盘）。
- **确认弹窗统一（U6）**：全应用 11 处「标题+内容+取消/确认」双钮确认框
  收编为统一确认弹窗（视觉与交互对齐 Apple 风格，删除类确认钮红色警示）；
  输入型/滑杆型/自定义弹窗保持原样。
- **画板顶栏精简与 390dp 修复（U6）**：删除与主菜单重复的快捷键帮助
  图标（主菜单入口保留）；修复手机窄屏下画板顶栏标题/保存状态/画布
  类型被挤没的既有问题——窄屏自动按可用宽度分级显示，标题优先可见，
  桌面端显示不变。

## [1.9.0] - 2026-09-02

- **分页画布归位与阅读（W1+W2）**：画布 tab 改为整本粒度展示分页画布，
  笔记 tab 不再混列；分页画布支持上下滑动翻页阅读，并可整本导出
  多页 PDF（每页一页，顺序装订）。
- **止血四项（U1）**：异常退出/崩溃后重新打开自动恢复上次编辑现场；
  错误提示改为人话（不再弹技术术语）；删除操作支持撤销（误删可找回）；
  root/越狱设备从强制拦截改为风险提示页。
- **画布性能四项（U2）**：视口剔除（大画布只绘制可见区域，拖动更流畅）、
  省略不必要的 saveLayer、保存改为后台 isolate 加密（不再卡界面）、
  大图自动降采样（省内存）。
- **编辑器与列表性能（U3）**：搜索输入防抖（输入不再卡顿）；打字改为
  静默同步（长文击键不掉帧）；锁屏倒计时模糊降档（低配设备更顺）；
  切后台/锁门仅在有未保存变更时才落盘（无变化不重复加密）。
- **设计精修（U4a）**：全部交互目标提升到 ≥44px 触控标准（星标、菜单、
  Tab 栏、工具栏）；文档列表与首页加载改为骨架屏（弱网不闪转圈）；
  文档行与画布卡片支持右键/长按呼出上下文菜单（打开/收藏/密码/删除）。
- 工程修复：Windows 构建去噪（STL1011）、CI 门禁红灯修复、设计 token
  收编（all_docs/notes 层 9 处硬编码色值统一）。

## [1.8.0] - 2026-09-02

- **系统验证快速解锁（批D1+D2）**：设置 → 应用锁新增「系统验证快速解锁」
  开关（默认关闭）。开启后锁屏出现「系统验证解锁」按钮——Windows 走
  Windows Hello（人脸/指纹/PIN 由系统统一弹窗），Android 走系统
  BiometricPrompt（指纹/人脸），验证通过直接进入应用，无需输开屏密码。
- **口径**：快速解锁仅作用于开屏锁；文件密码绝不进入系统安全区，解锁
  一律手动输密码（第二道锁不降级）。系统安全区只存开屏保险库主密钥
  副本（Windows = DPAPI 绑定当前用户账户；Android = Keystore 体系）。
- 关闭开关瞬间立即删除密钥副本，恢复纯密码模式；PIN 密码通道永远保留。
- 工程修复：QuickUnlockService 平台门可注入（Linux CI runner 环境差异
  两连修）。

## [1.7.0] - 2026-09-02

- **Argon2id 密钥派生升级（批B）**：密码槽位从 PBKDF2-HMAC-SHA256×600k
  （≈3 秒）升级到 Argon2id 64MiB t2 p2（≈0.35 秒）——解锁明显变快，
  且内存硬参数对 GPU 暴力破解的抗性更强（OWASP/Bitwarden/KeePassXC
  2026 年业界首选）。
- **旧数据零迁移**：升级前加密的画布/分页画布/笔记照常打开（只读
  兼容，解锁不改写文件）；修改文件密码或改开屏密码时自动升级到
  Argon2id，画布内容与重置密码盘全程不受影响。
- 工程修复：CI 门禁两处误报处理（Skylos 新规则下的 shell=True 清理、
  基准测试变量改名）。

## [1.6.2] - 2026-09-02

- **加密分页画布列表占位**：保险库锁定时，DNV 密文分页画布不再从
  列表静默消失——以「加密分页画布」占位条目显示（带锁标、标题不
  泄露），与笔记（块文档）的锁定占位同口径；解锁后恢复真实标题与
  页面。搜索与页面引入选择器同步跳过锁定条目。

## [1.6.1] - 2026-09-02

工程门禁修复版本（功能与 1.6.0 完全相同，无运行时行为变化）。

- 质量门禁：移除 `_buildResetDiskTile` 未使用的 context 参数
  （dart_code_metrics `avoid-unused-parameters`）
- 秘密扫描：新增 PNG base64 魔数前缀白名单（测试夹具 1×1 PNG
  高熵误报豁免）
- 测试稳定性：懒迁移轮询 helper 容忍 Windows 文件句柄瞬态占用
  （errno 32 重试，修复 CI 偶发红）

## [1.6.0] - 2026-09-02

本版本完成**命名体系统一**与**密码体系补全/提速**。

- **命名统一**：无限画布=「画布」；旧笔记本=「分页画布」；
  打字内容一律=「笔记」；底部导航更名「画布·笔记」；新建画布
  按钮弹出「新建无限画布 / 新建分页画布」两个选项（分页画布
  新建入口恢复）
- **笔记支持独立文件密码**：三种内容（画布/分页画布/笔记）现在
  都可以单独设密码。设密笔记在列表显示锁形标记、标题不泄露；
  打开时输密码解锁，一次解锁本会话内免重复输入；锁定笔记在
  搜索/同步/反向链接中一律跳过（内容零泄露）；回收站中的受密
  条目同样只显示「加密笔记」占位，可正常恢复（恢复后仍是锁定态）
- **忘记密码可救回**：笔记/分页画布/画布的文件密码都能用
  「重置密码盘」重设（插盘 → 点忘记密码 → 设新密码），内容
  原样保留、无需旧密码
- **解锁提速**：密码派生计算移到后台线程，输入密码解锁期间界面
  不再卡死；同一会话内重复解锁直接命中缓存（毫秒级）；切到后台
  即清空敏感缓存（安全不倒退）

测试：新增 22 条（密码体系 17 + 提速 5）；全量 1500 绿，analyze 0 问题。

## [1.5.1] - 2026-09-02

本版本完成**统一数据根目录收口**与首页/全部文档同步修复。

- **统一数据根目录**：所有业务数据（画作/笔记本/打字笔记/缩略图/
  图片副本/收藏/标签/日程/保险库密钥）从 Documents 下 11 处散落
  位置统一收进 `Documents\绘图笔记数据\` 单一根目录——重置、
  备份、卸载只需处理这一个文件夹；首次启动自动把旧位置数据
  搬入新根（幂等迁移，目标已存在绝不覆盖）
- **首页/全部文档同步修复**：v1.4.11 装配时漏传刷新信号线，
  导致"全部文档"页在 IndexedStack 保活下永远停留在首次快照
  （新增内容要退出重进才可见）——补接与首页相同的 dataVersion
  信号源，写盘后两页实时同步
- **AllDocs 装配对称化**：收藏/标签/日程存储改为组合根统一创建
  注入，不再散点构造

测试：新增迁移测试 6 条；全量 1468 绿，analyze 0 问题。

## [1.5.0] - 2026-09-01

本版本完成**加密底座六批次**：全部画作与笔记默认加密落盘，
密码体系集中管理。

- **全盘加密底座（批次①/①b/①c）**：AES-GCM 主密钥保险库——
  开屏密码派生密钥解开主密钥，画作/笔记/块文档/缩略图/图片
  全量加密落盘；老数据首次访问自动迁移，无需手动操作
- **自定义密码长度（批次②）**：开屏密码支持 4–12 位自由选择；
  新增单文件密码——给特别重要的画作再加一道独立的锁
  （设密后缩略图隐藏为锁形占位）
- **防爆破守卫（批次③）**：连续输错 10 次后进入指数冷却
  （1 分钟起、最长 24 小时）；失败计数签名持久化，重启/调系统
  时间都绕不过冷却；锁屏期间显示倒计时
- **U 盘恢复钥匙（批次④）**：LUKS/BitLocker 式双槽位设计——
  U 盘只存随机钥匙文件、主密钥副本不出设备；忘记开屏密码时
  插 U 盘即可免旧密码重设（锁屏「忘记密码？」入口，冷却期也可用）
- **设置集中管理（批次⑤）**：新增第四界面「设置」——三层密码
  关系一目了然，应用锁/密码盘/单文件密码/外观/WebDAV 全部收编，
  首页顶栏只留搜索与回收站
- **root 拒绝启动（批次⑥）**：检测到已 root 设备时拒绝启动，
  保护加密数据不暴露在破损环境
- 全量 1462 项自动化测试覆盖；诚实边界：设备+U 盘同时失窃
  等价于本人（与 KeePass 密钥文件威胁模型一致）

## [1.4.11] - 2026-09-01

- **应用启动锁（新功能）**：一进入应用即展示 iOS 锁屏风格全屏密码盘，
  解锁后才能进入；切到后台再回来也会重新上锁
  - 在首页「⋯ 菜单 → 应用锁」里设置 PIN 开启；支持随时修改密码
  - 密码采用加盐哈希存储，不落明文
  - 密码盘与锁屏共用同一键盘核心（PinPadCore），手机/桌面双端适配；
    顺带修复桌面端密码输入框不校验密码的安全漏洞
  - 首版如实提示：忘记 PIN 无法找回
- **首页刷新修复**：笔记本内新建/画布保存后首页列表不再延迟更新——
  - 三个存储层写成功统一通知（单一事实来源下沉到存储层）
  - 从子页面返回时 RouteAware 兜底刷新
  - 缩略图按文档 updatedAt 失效重载，不再显示旧图

## [1.4.10] - 2026-09-01

- **打字笔记选区浮动工具条黑幕修复**：选中文字弹出的浮动格式条被
  Overlay 的 tight 全屏约束拉伸成覆盖全屏的深色黑幕——浮层内容外包
  `Positioned` 提供松约束，恢复为贴合内容的小胶囊
- 新增胶囊尺寸回归测试（修复前 800×600 必红）
- 仓库清理：删除无引用的旧横栏工具栏（活契约迁至 editor_toolbar_contracts）

## [1.4.9] - 2026-09-01

- **画板打字整页冻结修复（双根因）**：
  - 就地编辑文字聚焦时禁用全部单键快捷键（数字 1-9 / 退格不再被工具切换
    与删选劫持，对齐 Excalidraw isEditingText 闸门）
  - 文字叠加层 `Positioned` 移至最外层——此前渐显动画包裹 `Positioned`
    导致提交文字瞬间 ParentDataWidget 崩溃、整页冻结（真凶）
- **箭头/直线方向修复**：真实端点（lineStart/lineEnd）与 flip 镜像叠加
  导致四个对角方向全部坍缩为"左上→右下"（从右上往左下画箭头方向丢失）。
  渲染端有显式端点时跳过 flip，绑定箭头端点单一来源化，新增 8 条方向
  回归测试（含像素级验证）
- 单击放置直线/箭头不再退化为零长度线段，回退为默认对角线

## [1.4.8] - 2026-08-31

- **移动端「全部文档」布局重构**（参照 AFFiNE，见 THIRD_PARTY_NOTICES.md）：
  - 新增响应式断点：宽度 <900 渲染单栏移动视图，≥900 沿用桌面双栏（桌面零改动）
  - 移动端头部：全部文档/收藏夹/标签 tab 切换 + 搜索 + 排序 + ⋯ 菜单（回收站）
  - 文档树改由底部「最近文档」sheet 承载，列表占满全宽（修复手机端被 248px
    固定侧栏挤成 1/3、时间/标题被截断的问题）
  - 移动端右下角新增「新建文档」悬浮按钮
  - 输入法弹出时自动隐藏底部导航栏（对齐 AFFiNE VirtualKeyboard 行为）

## [1.4.7] - 2026-08-31

- **图标优化**：应用图标背景改为透明（去除白色边框——jpg 源图不支持
  透明已自动抠图，仅外围白底转透明、图标内容完整保留）

## [1.4.6] - 2026-08-31

- **应用图标更新**：Windows/Android 全平台替换为新版画笔图标
  （Windows ICO 全尺寸 + Android 全密度 mipmap）

## [1.4.5] - 2026-08-31

- **架构重构收官**（行为无变化，内部质量提升）：
  - AppServices 服务门面——store 实例/数据版本/全量缓存收敛一处，
    AppShell 瘦身至 394 行
  - 块编辑域模型 16 文件迁入 doc 模块（依赖方向反转，"doc 寄生 notes"清零）
  - doc_editor 2119 行拆分：主文件 1400 + blocks 渲染 617 + 工具栏 133
  - 存储实例全库统一（shell 注入，消除多实例缓存隐患）
  - AppleDialog 公共确认对话框组件

## [1.4.4] - 2026-08-31

- **修复**：新笔记在「画板·笔记本」页可见但「全部文档」页不显示——
  根因是 HomePage 自建存储实例（与 shell 实例的头信息缓存互不相通）且
  新建后未通知数据版本；现注入同一实例并在新建/删除后统一刷新
- 重构 R2 收尾：AppServices 服务门面（store 实例/数据版本/缓存收敛）、
  块编辑域模型 16 文件迁 doc 模块（依赖方向反转）、AppleDialog 公共组件

## [1.4.3] - 2026-08-31

- **紧急修复**：正文输入不触发自动保存——用户输入的正文从未落盘
  （v1.4.0-1.4.2 受影响；Windows 真机集成测试发现，根因为 onDirty
  边沿通知被 _isDirty 门控短路）
- 新增 Windows 真机集成测试：新建→输入→退出→自动保存落盘完整生命周期

## [1.4.2] - 2026-08-31

- **紧急修复**：文档页退出即崩溃（app_shell `_bumpDataVersion` 无限递归，
  v1.4.0/v1.4.1 受影响；架构审计发现，含完整生命周期回归测试）
- 随附架构专项审计报告：docs/ARCHITECTURE_AUDIT_2026-08-31.md

## [1.4.1] - 2026-08-31

- 发布流水线：所有安装包生成后自动压缩为 zip 随 Release 双轨提供
  （Windows `drawing_notes_windows_setup.zip` / Android `drawing_notes_android_release.zip`）
- CI Actions 运行时升级：upload-artifact v4→v7、gh-release v2→v3（Node 24，
  消除 deprecation 警告）
- 发布规范立档：docs/RELEASE_PIPELINE.md（版本三处同步 + 发版检查清单）

## [1.4.0] - 2026-08-31

### 审计整改（2026-08-31，报告 docs/CODE_AUDIT_2026-08-31.md）

- **P0 数据零丢失**：保存链统一（DocController Future 化、消除自动保存双写、
  「已保存」由写盘完成驱动、失败用户提示）；退出 flush（防抖窗口内编辑不丢）；
  存储写尾队列 + 软删除 rename 原子化（回收站双格式兼容，存量免迁移）
- **P1 性能与门禁**：反向链接索引内存缓存 + 回收站清理节流；导出/回收站操作
  补 PolicyEngine 门禁（fail-closed）；slash 菜单 Overlay 泄漏修复
- **P2 大库体验**：列表头信息缓存（listDocHeaders，写后失效）；编辑器击键
  合帧（撤销粒度变为输入 burst，结构操作仍即时）；TagStore 上收 core/storage；
  PIN 下限 4→6 位
- **P3 低危清理**：导出全异步 IO；文件名尾点/尾空格清理；标签对话框
  controller 释放；DocPage 增 blockDocStore 统一兜底装配——反向链接/
  标签能力在搜索/笔记本管理/首页各入口全部生效；**修复反向链接面板 UI
  缺失**（M12.7 提交遗漏，本轮补齐）

### AFFiNE 对齐第三批（M12.7-M12.8）

- **反向链接**：`[[标题]]` 双链语法，顶栏「插入页面链接」选文档即追加引用；
  被引用笔记底部自动显示「反向链接 · N」面板（点击跳转）；
  索引每次从文档集推导，与内容天然一致
- **PDF 导出**：照 AFFiNE PdfAdapter（pdfmake PR #14057）框架，
  以 Dart `pdf` 包实现 A4 渲染（标题/列表/待办/代码/引用/提示/分割线），
  中文使用项目已打包的离线 CJK 字体；⋯菜单与 Markdown/HTML 并列

### AFFiNE 对齐第二批（M12.6）

- **回收站**：笔记删除改为软删除（保留 30 天，自动过期清理），回收站页支持恢复/彻底删除
- **标签系统**：标签注册表（颜色/重命名/删除）+ 文档标签编辑（文档信息对话框）+ 标签 Tab 过滤
- **Toggle list**：可折叠列表块（展开态随文档持久化）
- **HTML 导出**：与 Markdown 导出并列，⋯菜单一键导出
- **模板库**：新建笔记可选 空白/会议纪要/每日日志/待办清单 模板

## [1.3.4] - 2026-08-31

### 修复：首页与笔记页列表同步（用户实测反馈）

- **根因是双数据源分裂**：首页「笔记」Tab 只列打字笔记（NoteBlockDoc），
  而笔记页新增的是笔记本页面（NotebookPage）——两处列表读不同存储，
  首页永远显示不了新页面
- **统一数据来源**：首页笔记 Tab 改用与 All Docs 完全相同的装配器
  （画布 + 笔记本页面 + 打字笔记三源合并），两处列表天然一致
- 打开路径统一（与 All Docs 同回调）；行条目标注来源类型
  （打字笔记 / 笔记本页面）
- 新增/删除/重命名落盘后返回即自动刷新，无需手动刷新
- 新增 3 项契约测试；1301 项测试全绿

## [1.3.3] - 2026-08-30

### 架构重构（代码健康整改全清，功能零变化）

- **画布引擎域上收 `core/canvas_model/`**（B 方案）：document/layer/stroke 等
  12 个纯模型文件从 drawing/domain 迁出——笔记与画板 feature 间零依赖，
  为"笔记嵌画布/画布嵌笔记"双向镶嵌铺平道路（镶嵌契约已入 ARCHITECTURE.md）
- **UI 方言统一**：退役 material_ui fork（经逐文件 diff 确认行为等价），
  51 个文件迁移至单一 flutter/material；根除同名异型导致的解析歧义与
  本地化冲突
- core 纯度达成：`lib/core/` 对 `features/*` 零 import
- 死模块删除、块编辑 UI 归位 doc 模块、DocEditor 更名、选择框绘制去重、
  大页面 part 化拆分、保存机制统一 SaveScheduler、新增 docs/ARCHITECTURE.md
- 1298 项测试全绿；dart analyze 0 问题

## [1.3.2] - 2026-08-30

### 命名持久化 + 自动保存 + 保存状态可视化（用户反馈五项）

1. **命名持久化**：笔记标题编辑即标记脏状态并入自动保存；画布新增
   「重命名」入口（顶栏点标题 ✎）→ 走自动保存调度落盘
2. **自动保存**：笔记页编辑后 1.2s 防抖自动保存（DocController→store）；
   画布沿用 SaveScheduler 防抖自动保存
3. **手动保存**：笔记页顶栏新增 💾 保存按钮；画布保留退出兜底 + 调度
4. **保存状态可视化**：笔记页与画布顶栏均显示
   未保存（橙）/ 保存中…（蓝）/ 已保存 HH:mm（绿）
5. **刷新加载**：名称与内容持久化后，全部文档列表按 updatedAt
   排序展示最新版本，刷新即得最新已保存内容

## [1.3.1] - 2026-08-30

### 修复（用户实测反馈）

- **橡皮擦画出黑色线条**：根因是图层不透明（opacity=1）时笔迹直接绘制在主画布上，
  橡皮擦的 `BlendMode.clear` 把主画布连同纸面背景一起清穿，露出底层黑色。
  修复后所有图层统一 `saveLayer` 隔离——clear 只清除本图层墨迹，擦除处露出纸面。
  新增逐像素回归测试锁定该语义
- **首页列表不同步**：新增笔记/画板后首页与全部文档列表不刷新。新增 shell 级
  数据版本通知器（`_dataVersion`），任何文档新增/编辑（经 shell 路由返回后）自增，
  HomePage 与 AllDocsPage 订阅并自动重载列表

## [1.3.0] - 2026-08-30

### 笔记模块重做（AFFiNE Page 1:1，与画板彻底分离）

- **新模块 `lib/features/doc/`**：DocPage（白底、居中窄栏 ≤720px）+ DocHeader
  （返回/标题/☆收藏/ⓘ信息/⋯在画板中打开/分享）+ DocOutlineRail（右缘大纲条）
  + DocController（独立状态）——与画板零交叉引用
- **笔记本=笔记**：新建菜单合并为「新建笔记」「新建画板」；HomePage 笔记本 Tab
  更名「笔记」，列表为打字笔记（新建/打开/删除），点击进 DocPage
- **退役**：note_doc_modes_page 双模容器删除；画板帧内嵌文档编辑移除——
  帧内文档改为跳转独立笔记页（修复"画板中输字即冻结"）
- 块编辑核心迁移至 `doc/doc_editor.dart`（含无 chrome 模式供 DocPage 宿主）
- 加密笔记本数据保留：可经全部文档（笔记类型行）进入
- 1301 测试全绿（+4 DocPage 契约）；dart analyze 0 问题

## [1.2.4] - 2026-08-30

### AFFiNE 1:1 对齐（用户拍板 ①②③ 全做）

- **① 大纲（Outline）面板**：编辑器 AppBar 新增大纲按钮，按标题层级（H1-H6，含嵌套块）
  生成大纲，点击跳转到对应块（对标 AFFiNE Outline）
- **② 正文大标题**：标题从 AppBar 移入正文顶部（26pt 加粗，AFFiNE 式"标题即正文第一块"），
  编辑与保存链路不变
- **③ 侧栏文档树**：全部文档侧栏新增可折叠「文档树」（最近文档按更新时间倒序，前 30 条），
  点击直接打开——补齐 AFFiNE 侧栏文档树语义
- KindVisual/visualForKind 抽为公共 API 供行组件与侧栏共用

## [1.2.3] - 2026-08-30

### 恢复 + 合规

- **恢复笔记本入口**（用户明确要求保留，此前误删）：新建菜单恢复「新建笔记本」；
  画板·笔记本页恢复笔记本 Tab 与新建 FAB
- 新增 `THIRD_PARTY_NOTICES.md`：保留 AFFiNE/BlockSuite（MIT, (c) toeverything）
  版权声明与致谢——笔记交互对标 AFFiNE 的合规依据

## [1.2.2] - 2026-08-30

### 功能去重 + 真日程（用户决策）

- **日历页只管日程**：移除「文档动态」看板（与主页列表重复），标题改为「日历 · 待办」
- **待办升级为真日程**：事件可设置**几点几分**（minuteOfDay，0..1439），新增对话框内置时间选择器
- **24 小时时间轴**：选中某天后展示 00:00–23:00 每小时一行，事件按时刻归位，
  每行右侧 ＋ 可在该小时内添加；不设时间则为全天待办
- **主页承接时间线**：All Docs 文档条目显示明确日期（今天 HH:mm / 昨天 / M月d日 / 跨年年份），
  取代原相对时间
- 删除无引用的 time_ago 组件；SchedulePage 与 shell 解耦（不再注入文档数据）

## [1.2.1] - 2026-08-30

### 关键修复

- **全新安装无创建入口**（用户报告"打开后点不动/功能是空的"的根因）：空文档时
  All Docs 顶栏与新建按钮不渲染的问题修复；空态内置「新建笔记（打字）」/「新建画板」按钮
- **打字为主**（对齐 AFFiNE Page 语义）：新建笔记 = 直接打字的块文档（不再产生画布式笔记本）；
  画板 Tab 收敛为「无限画布」单项；导航更名「画板」
- 冒烟测试锁定关键链路：空态 CTA 新建→编辑器打开、目的地切换

## [1.2.0] - 2026-08-30

### 产品清晰化（M11：IA 收敛，对照 AFFiNE/Excalidraw/Saber）

- **信息架构收敛**：导航 4→3（全部文档 / 画板·笔记本 / 日历）；删除纯笔记占位页、HomePage「最近」时间线 Tab（并入日历）、零引用孤页 home_dashboard_page
- **All Docs 真实化**：快速搜索实时过滤；收藏夹持久化（FavoriteStore）；侧栏精简为真实可达项；新增排序（时间分组/更新时间/创建时间/标题）
- **日历真实化**：新增待办/日程事件（ScheduleEventStore 持久化），新增/勾选完成/删除；月历活动点含事件
- **块编辑器（AFFiNE 1:1）**：选中块浮动工具条（B/I/U/链接 + 复制块/删除块）；嵌套子块拖拽与跨层级移动
- **Edgeless 工具面板**：选择/便签/画笔/橡皮/形状（矩形/椭圆），笔迹与形状随文档持久化
- **发布**：release-build.yml Android job 对齐 tag 触发，Release 同时挂载 Windows 安装包与 Android APK

### 质量

- 1303 项测试全绿（较 1.1.0 +48）；dart analyze 0 问题
- 新增 docs/M11_PRODUCT_CLARITY_PLAN_2026-08-30.md 产品收敛方案

## [1.1.0] - 2026-08-16

### 安全（专家审计闭环——P0-P2 封堵 + 军工审计链 A-H + 专家审计包）

- 路径遍历 / 任意删除封堵：受管路径 + 非跟随链接检查 + 运行时校验（CVE-2026-55667 同源）
- 加密 v4 AAD 载荷（NIST SP 800-38D 上下文绑定）+ 严格封装校验（密钥包裹/固定字段长度）
- 媒体加密双端闭环：DAN 文件头 + K_note 每笔记密钥 + 明文兼容读取 + 幂等迁移
- 回收站（30 天保留 + 恢复/清空）+ PIN 保护（v2 KEK——OWASP 模式）
- 不可篡改审计：SHA-256 哈希链（prevHash 链接——篡改断链）+ verifyIntegrity
- 错误边界：FlutterError/PlatformDispatcher + 脱敏记录（仅错误类型/库名）
- 导入隔离：PDF 页数/大小配额 + 文本 20MB 配额 + **SVG 预检**（XXE/Billion Laughs/脚本注入/膨胀防护）
- 搜索加密安全：未解锁加密内容不可读（标题明文可搜——私有笔记先例模式）

### 架构（解耦 + 可测——官方渐进节奏）

- God Class 拆分：**8 个纯计算服务**提取（选区中心/变换/绑定判定/取色/图片缩放/形状缩放/线段相交/点线距离——权威算法对齐 tldraw/掘金）
- **PolicyEngine** 策略层：操作白名单默认拒绝（fail-closed）+ enforce/monitor 模式 + 审计——导入/删除门禁接入
- **SessionGuard** 会话守卫：失去焦点立即锁定（内存密钥清零）+ 文件选择器豁免 + 再认证
- **VFS 加密对象仓库**：对象清单 + 版本回溯 + AAD 绑定 + 原子提交（临时文件+rename——崩溃安全）——VaultService 接入层 + **媒体双轨接入**（新媒体 VFS 对象 + 旧 DAN 文件兼容——s3eg 双读窗口）

### 国际化

- gen_l10n 框架 + **75+ 中英语义化 key**（home/editor/note/disk/search/paper 六域全覆盖）
- untranslated-messages-file 排查配置（54/54 对齐无缺失）

### 工程化

- **SBOM 生成**（CycloneDX 1.5——145 组件）+ **秘密扫描**（Gitleaks 模式——引号内高熵检测）+ CI 集成（gitleaks-action@v3 + sbom.yml）
- actions/checkout/upload-artifact 升级 Node 24（修复弃用警告）
- 依赖锁定（pubspec.lock）+ CVE 核查脚本（check_deps.sh）

### 修复

- dispose 内存清零（D-2）/ 缓存竞态 / 位图泄漏 / 历史上限 / 路径校验（审计回归）
- 搜索去抖 + 依赖注入 / 性能基准（1200 笔画编解码）
- 全量验证门禁：`flutter analyze` 零问题 / **391+ 测试全过** / 架构规则 +5 全过 / 边界通过 / 行数 0 错误 / 涉密自查无涉密

---

## [1.0.0] - 2026-08-14

- Phase 1-7 全部完成（画布/绘图工具/图层/选区变换/笔记/持久化/体验打磨）
- 基础安全：删除确认/路径校验/自动保存
- 平台：Windows 桌面 + Android
