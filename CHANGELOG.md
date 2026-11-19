# 变更日志（Changelog）

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.17.68] - 2026-11-05

### P4 架构收口：AST 门禁基建（2026-11-18，同版本增量，未 bump）

**三轮审计 M-7/H-4 收口**：

- **M-7 字段集机器判据**：新增 `mixed_model_field_set_ast_gate_test`——用
  analyzer AST 解析四混排模型（PageTextItem/PageShapeItem/PageImageItem/
  PageChartItem）的可变字段 ∪ 公开 setter，与 copy()/restoreFrom() 覆盖集
  比对，差集非空即红。机器跟随模型，**双双漏跟也红**（旧手抄清单测试的盲区）。
  含 2 项突变自证（注入漏跟字段/只改 copy 不改 restore，验证判据非恒真）。
  旧 `mixed_model_copy_restore_test` 注释如实改写：只钉已列字段恢复正确性，
  不声称自动跟随新增字段（机器判据由 AST 门禁承担）。
- **H-4 棘轮 part 正则双引号盲区**：part_library_ratchet / editor_page_line_ratchet
  两处 `^part\s+'([^']+)';` 改 `^part\s+['"]([^'"]+)['"];`（三引号 raw string），
  单/双引号 part 同口径——`part "x.dart";` 不再逃逸行数分母。
- analyzer ^11.0.0 加入 dev_dependencies（AST 门禁用，对齐 lock 版本）。

新增门禁 6 项（4 模型字段集 + 2 突变自证）；架构套件 152→159。

### P3 架构收口：密钥作用域 + 写腿世代闸（2026-11-18，同版本增量，未 bump）

**三轮审计 M-1/M-2 收口**：解锁时发起的加密写，若密封/编码期间回锁
（SessionEpoch.bump），在途写腿提交前世代比对作废——密文不得写进锁定态磁盘。

- `_KeyScope`（密钥 + 发起时会话世代成对携带）+ `_currentKeyScope()`；
  五条写腿（懒迁移/save/密码补丁/独占写/storeImage）提交前世代闸。
- save 锁定态 fail-closed（与媒体写 `_plainMediaOrLock` 同口径）：已建库
  锁定拒绝保存，防锁屏自动保存把密文笔记本降级明文覆盖；单笔记本密码
  流程（encryptAndSave 等）独立于保险库，不受影响。
- 新增回归 6 项（notebook_write_epoch_gate_test）：在途 save 作废 /
  正常密文落盘 / 无保险库明文兼容 / storeImage 作废无半成品 /
  锁定 save 拒绝且密文不被覆盖 / 未建库锁定明文兼容。

棘轮：notebook_storage 库 1502→1543（+41，_KeyScope+世代闸+fail-closed，
含注释）；三处交代（ratchet 注释/本条/commit message）。



### P2 架构收口：笔画平移专属路由（2026-11-18，同版本增量，未 bump）

**三轮 M-3 功能回归修复**：M-9 守卫堵死 input 拖拽分支后，笔记套索笔画
无任何平移路径（选区栏无平移控件、_nudgeSelected 只动混排对象）。
收口为**独立路由**而非撤守卫（撤守卫会复发双记）：

- 选区栏补四向微调按钮组（左/上/下/右，步长 4px 画布坐标），仅笔记模式
  且笔画选中时渲染；独立模式走指针拖拽不渲染（防双路由）。
- 每按一次 move+end 成对提交一条 selectionSession 窄命令——**不进
  MixedDragSession**，与混排拖拽事务解耦不双记。
- input 的 !_isNotebookMode 守卫保留（M-9 双记修复不倒退）。

新增回归 4 项（stroke_nudge_route_test）：按钮渲染+平移+单条撤销 /
连续微调 LIFO / 独立模式不渲染 / 一次微调恰一条历史不双记。

棘轮：editor_page 7281→7294（+13，body 接线含注释）；按钮组落
selection_bar 独立 Widget 不计。

### P1 架构收口：拖拽事务会话化（2026-11-18，同版本增量，未 bump）

**根因**：三轮审计反复抓到「约定失守」——depth+group+快照三态靠记得配对
维持，dispose/切页早退漏关组（H-1）、closeGroup 返回值被丢弃吞掉窗口内
Delete 命令（H-2，删除撤不回+自动落盘）、漏 flush 挂起通知（M-1）。
收口为**结构上不可能违反**：

- **MixedDragSession 会话对象**（取代静态 Recorder）：begin 时捕获四列表
  引用+host——commit/cancel/abort 不依赖页面存活（H-1 构造性消除）；
  depth/快照私有化进会话，交互态三裸 public 字段收为单槽；abort 供
  dispose 兜底（任意嵌套强制还原+回滚，幂等）；isClosed 幂等守卫
  （焦点失焦+panEnd 双触发不重复关组）。
- **DrawingController 公开 commitGroup()/rollbackGroup()**：复用图层事务
  样板语义（closeGroup→pushTransaction→flush / discard→逆序 undo→flush），
  **消费窗口内命令**成为入口结构保证——聚焦期 Delete 冒泡 push 的命令
  合成事务入栈不再被吞（H-2）；挂起通知必然补发（M-1）。不经 layerService
  通道（保其 _transactionDepth）。
- **CanvasDragHandle/ResizeHandles 补 onPanCancel/onDragCancel 通道**（L-1）：
  取消不再被当提交；overlays 接线。
- 键盘逐键 begin/end 嵌套在聚焦会话内**自然合并为一条历史**（M-2 栈膨胀
  随会话嵌套语义消解）。

**新增回归 7 项**（mixed_drag_session_test）：窗口命令合成入栈/cancel 回滚
窗口命令/abort 任意嵌套幂等/会话不依赖页面/挂起通知补发/嵌套递减/双触发幂等。

**棘轮交代（P3-3）**：editor_page 库 7268→7281（+13：dispose 兜底+4、
会话路由+8、cancel 接线+1）；drawing_controller 1380→1409（+29：公开
关组入口含注释）。会话本体落独立库不计。零新 UI、零新 part。


### 第二轮审计批 D：M-1 密封降级 + pdfrx 3.x 升级 + L-10 留档（2026-11-18）

**M-1 密封判定单调性**：`isEncryptedNotebook` 改直读主文件，不再走
`load()`（load 回退陈旧明文 .bak → 误判 false → 媒体按全局保险库钥而非
K_note 密封，保护降级到开屏 PIN）。主文件不存在 → false（新本）；
DNV 外层锁定 → 抛 VaultFileLockException（fail-closed）；主文件损坏 →
抛 FormatException（不据此判「未加密」）。新增回归 3 项（备份不降级 /
损坏 fail-closed / 锁定 fail-closed）。

**pdfrx 2.13.0 → 3.0.1**（主版本升级，评估后安全）：本仓仅用
`pdfrxFlutterInitialize()` + `PdfDocument.openFile()`（pdf_preview_renderer /
pdf_import_service），**零 PdfViewerParams / 布局策略 / 缩放参数使用**——
3.0 破坏面（layoutStrategy 取代 layoutPages/margin、移除 maxScale/minScale/
calculateInitialZoom、PdfPageLayout 接口扩展）全部不触及。编译零问题。
依赖门禁可升级数 8→7（pdfrx 主版本项消除）。

**L-10 窄快照性能——留档不实施（评估结论）**：每次手势 begin/commit 各
全页四类深拷贝 + 撤销栈每条常驻两份全页副本（60 条上限）。窄快照（只快照
选中对象）理论上可降内存，但**会破坏跨命令组合正确性**：① 箭头绑定跟随
（_dragItem 移动 boundElementId 关联箭头，非选中对象也改）；② 删除命令
持全页快照，与窄拖拽快照 LIFO 组合时恢复范围不一致；③ 分组展开
（_expandGroup）使实际影响集大于选中集。全页快照是**跨命令组合正确的
前提**（PR #75 深快照设计决策），不是内存优化选项。性能开销在可接受范围
（几百对象 × 60 条 ≈ 数 MB 级），留待真实 profiling 数据驱动再评估。

### 第二轮审计批 B：拖拽专项边界收尾 7 项（2026-11-18，同版本增量，未 bump）

**H-2 seed/_dashLegacy 漏恢复**：四模型补 `restoreFrom`（copy 的逆，全字段）；
`_restoreFields` 手抄清单删除，委托模型单点；注释撒谎纠正。新增
mixed_model_copy_restore_test 门禁（5 项：全字段 copy→改→restore 回到快照值，
含 seed/dash legacy 投影）。dash 恢复顺序修正（先 legacy 后 strokeStyle）。

**H-3 拖拽中途 Ctrl+Z 幻影条目**：事务 begin 首层开 history group（手势中
undo/redo 被拒绝）；commit/cancel 最外层关 group。嵌套 depth 计数（内层
commit/cancel 只递减不结算）。新增嵌套双 commit 回归。

**M-6 每帧通知残留**：ResizeHandles onChanged 移 onDragEnd（无 onDragEnd
退化为每帧兼容旧宿主）；overlays onChanged 改 noop；宽度柄每帧
_notifyChanged 删除（onPanEnd commit 已含）。

**M-7 键盘微调不入撤销**：CanvasDragHandle 键盘路径每次按键自起自结
（begin→update→end），嵌套 depth 保证与指针会话不冲突。端点柄/八向柄
键盘测试断言同步。

**M-8 cancel 浅写回破坏身份**：cancel 复用命令层 restoreCollections（同 id
写回原实例），不再自持 clear+addAll 副本；嵌套内层 cancel 不还原。

**M-9 笔记模式双记**：笔画移动分支加 !_isNotebookMode 守卫（笔记套索选笔画
后拖对象不再同时移笔画+push 两条命令）。

**M-10 图表接线不全**：命中几何补图表第四类（idsInRect/idsInPolygon/idsInPath
可选 charts 参数）；框选/套索调用补 charts；对齐吸附 refs+当前元素边界补图表；
等距分布补图表。

**棘轮交代（P3-3）**：editor_page 库 7230→7268（+38），逐文件明细见棘轮注释
（drag_ops +29 图表接线 / input +8 守卫+参数 / text_overlays +1 注释）。
事务 group/depth 落独立库、模型 restoreFrom 落 core、命中几何落 infrastructure
均不计棘轮。零新 UI、零新 part。

### 第二轮审计 H-5 依赖门禁评估（2026-11-18，同版本增量，未 bump）

可升级依赖 11 > 阈值 7（上游一天内新发布）。处置：
- 升级 3 个安全传递依赖：pdfium_dart/pdfium_flutter 0.4.3→0.4.4、
  pdfrx_engine 0.9.3→0.9.4（patch，无破坏性变更）。
- 剩余 8 个全部被上游约束钉住，非本仓可升：material_color_utilities/
  test_api/cross_file/package_config（Flutter SDK 或父包钉版）、qr（父包钉）、
  pdfrx 2.13→3.0.1（**主版本，待评估破坏性变更**）、analyzer/
  _fe_analyzer_shared（DCM 5.7.6 钉）。
- 安全公告核验：archive GHSA-9v85-q87q-g4vg 影响 v3.3.7（锁 4.7.1 不受
  影响）；http GHSA-4rgh-jx4f-qfcq 影响 <0.13.3（锁 1.6.0 不受影响）——
  **两条均误报**。
- 阈值 7→8（pr-security.yml + weekly-evidence.yml，附评估注释）：8 个
  约束钉住项非安全漏洞，pdfrx 3.x 评估后应降回。

### 第二轮审计批 A+C：安全收口 + 治理投资（2026-11-17，同版本增量，未 bump）

**批 A 安全收口（5 项 H/M，全部既有纪律补漏）**：
- **H-1 锁屏豁免路径落锁清密钥**：`_lockWithoutGrace` 补
  `_clearSessionSecrets()`——TTL 到期/宽限关闭/宽限到期三条路径此前只掉
  主密钥不清 KEK/会话口令/K_note（注释自称「与超宽限同一收口」但那条有
  清理这条没有）。新增 2 项 widget 回归（TTL + grace=0 落锁即清 KEK）。
- **M-2 笔记本解密 DEK 零化**：`_decryptNotebookEnvelope` 补 try-finally
  fillRange，与 blockdoc 同构路径同口径（此前笔记本侧漏擦）。
- **M-3 续写 DEK 零化**：`notebook_storage_password` rewrap 后 finally
  零化调用方独占副本（此前用后弃置不擦）。
- **M-4 K_note 懒补槽抛错零化**：`_ensureOnce` attachMediaSlot 抛错路径
  补 try-finally 零化已生成密钥；`encryptWithPasswordV5` 自动生成的
  K_note 副本包裹后即零化（调用方传入的不擦）。新增 1 项 kdf 回归
  （抛错后传入密钥全零 + 重试后媒体可解）。
- **M-5 审计锚加载失败可重试**：catch 分支不再置 `_anchorLoaded=true`
  ——下一条 log() 重试加载。此前一次读失败即整会话永久降级无密钥
  SHA-256（攻击者可整链重算伪造）。新增 1 项回归（目录占锚→降级→
  障碍移除→恢复 HMAC）。

**批 C 治理投资（零行为变更）**：
- **H-4 五库补棘轮**：doc_editor 2747 / notebook_view_page 2108 /
  home_page 1928 / doc_page 1528 / all_docs_page 1402 补进
  part_library_ratchet（分母 7→12）。上轮「8 库破千」本身漏数。
- **M-11 文档同步**：STATE_MANAGEMENT_DECISION_TREE.md 与 AGENTS.md
  仍称 drawing_notifiers 为现存示范单元（R5 已删）——同步改写。
- **M-12 sloc 注释**：presentation 40/40 触顶、application 38/40 如实更新。
- **L-3 孤儿注释四处**：overlays 尾部已迁方法注释删除、drag_ops 引用
  不存在的 _findSnapTarget 改如实描述、editor_page _linkSourceId 上挂错
  的薄包装注释纠正、object_mutation 过期棘轮数 7127→7235 纠正。
- **L-6 kdf 卫生门禁**：双引号 @Tags(["kdf"]) 纳入合规标记（6 文件在用）。

**棘轮交代（P3-3）**：app_lock_gate 1048→1053（H-1 +5）；
notebook_storage 1466→1472（M-3 +6）；editor_page 库 7235→7230（L-3 -5）。
抬升均为安全修复成本，下调随净删——三处交代（棘轮注释/本段/commit）。

### 混排拖拽域统一入撤销专项（2026-11-17，同版本增量，未 bump）

### 混排拖拽域统一入撤销专项（2026-11-17，同版本增量，未 bump）

**整域缺口**：笔记模式的移动/旋转/缩放/文字宽度柄直改对象字段，结束只
`_notifyChanged`（排自动保存）不 push 任何命令——拖完既撤不回又立刻落盘，
与删除（EUI-02 已修）是同一形状。独立画布模式的指针链路早已走 session
事务，本批把同一语义补给 overlay 手势链路。

**事务层（补编排层而非逐个加守卫）**：
- `MixedObjectDragRecorder`（editor_page_object_mutation.dart，独立库不计
  棘轮）：begin 拍四类集合**深快照** / commit 逐字段比对有变化才入栈 /
  cancel 还原不入栈。嵌套 begin 首个为准；空拖拽不白吃撤销步。
- 三类模型补 `copy()`（PageTextItem/PageImageItem/PageChartItem，与
  PageShapeItem.copy 同纪律）；`MixedObjectCollections` 浅→深——浅快照
  捕获不到原地字段变更，且与变换命令 LIFO 组合时会放回被后续拖拽改脏的
  旧实例（值语义是跨命令组合正确的前提）。
- **恢复身份写回**（实测踩坑修复）：深快照条目是 copy 副本，直接 addAll
  会让 overlay 闭包捕获的旧实例与列表脱钩——撤销后屏幕对象停在旧位置。
  `_writeBack` 改为同 id 写回原实例（restoreFrom 语义），快照有/活列表
  没有的条目（删除撤销）才放副本。身份连续性保住，「撤销在屏上成立」。
- 主文件三个便捷入口 `_beginMixedDrag/_commitMixedDrag/_cancelMixedDrag`；
  四类 overlay（文字/图片/形状/图表移动）+ 旋转手柄 + ResizeHandles
  （新增 onDragStart/onDragEnd 可选参数）+ 文字宽度柄全部接线。

**顺带修复两个既有缺口**：
- 图表拖拽是**死手势**：overlay 早挂 `_dragItem(chart.id)` 回调但方法内
  无图表循环（回调空转）——补齐与形状同口径的移动循环。
- 独立模式单图片 pointerUp **结算分支缺失**：pointerDown/Move 都有单图片
  分支，唯独 pointerUp 漏了（落 else endSelection，懒快照永不结算）——
  补齐与形状分支对称的 `endDocumentImageTransform` 结算腿。

**测试**：事务语义单测 11 项（mixed_object_drag_recorder_test）+ 真手势
链路回归 8 项（editor_mixed_drag_undo_test：形状移动/旋转/缩放、文字移动、
图表死手势、图片移动、空拖拽不入栈、独立图片结算）+ 既有命令测试更新
（identical 断言改钉 id+字段值，深快照值语义）。

**棘轮交代（P3-3）**：editor_page 库 7149→7235（+86），逐文件明细见
test/editor_page_line_ratchet_test.dart 注释（主文件 +48 事务入口、
overlays +10 接线、text_overlays +6 接线、drag_ops +15 图表循环、
input +7 结算分支）。事务本体落独立库不计棘轮。零新 UI、零新 part。


### 棘轮反向锁收紧 + 过期注释纠正（2026-11-17，同版本增量，未 bump）

R5 落地后的复查收尾（零行为变更，仅测试与注释）：
- provider_reader_ratchet 基线上限 1→0：基线已清空，上限同步收紧——
  任何「没人读的 provider」想进豁免存档区当场红（原上限 1 是清空前残留，
  留着等于给反向锁留一格后门）。头部判据注释与自证用例注释同步。
- editor_viewmodel_link_mode_test 头注释纠正过期装配描述：「这套 API 目前
  由 EditorToolbarActionFactory 与页面各自委托」已不属实（生产工具条走
  _toolMode 路径，意图 API 生产零消费）——改写明现状与保留理由（互斥判据
  单一载体），防下一轮审计把注释当事实。

### R5 裁决落地 + VM 双轨收口（2026-11-17，业主批准，同版本增量，未 bump）

**R5 · 示范派生层删除**（业主裁决：删，不接线）：
- drawing_notifiers.dart 整文件删除（256 行，三域 Notifier：视口/历史/选区，
  生产零消费仅测试在读）——已移入废纸篓。
- di_providers.dart 裁剪 84→26 行：删 drawingDirtyProvider /
  drawingCanUndoProvider / drawingCanRedoProvider / drawingCurrentLayerProvider
  四个零消费派生 provider + notebookAccessorProvider 空装配点（恒落
  _EmptyNotebookAccessor，真实笔记访问走 NotebookStorage 实现接口后直接传参）。
  **容器本体 drawingControllerProvider 保留**（已生产接线：editor_page
  initState / editor_statusbar ref.watch）。
- riverpod_providers_test 裁剪：删 B2~B4 与三域 Notifier 示范测试；保留
  themeProvider/themeModeProvider（生产在用）与 B1 容器测试。
- provider_reader_ratchet 棘轮同步：分母 11→4（随净删下调）、具名基线
  notebookAccessorProvider 一格清空——**该棘轮目标形态达成：lib/ 里不再有
  任何「没人读的 provider」**。反向锁仍有效（基线加格即红）。

**VM 双轨收口**（R5 连带裁决）：EditorViewModel 此前 extends ChangeNotifier
且每个 setter notifyListeners()，但全库无任何订阅者——页面刷新从来都靠
调用方包 _applyState（PR #72 已钉成唯一入口）。死通知轨道整体删除：
VM 变**纯状态协作者**（去 ChangeNotifier 继承、去全部 notifyListeners、
dispose 不再 super.dispose），可见性由 _applyState 单点负责。
leaveLinkMode 幂等守卫与成对清判据保留；select* 意图 API 保留为互斥判据
载体（link_mode_test 逐格钉住，生产工具条走 _toolMode 路径）。
link_mode_test 通知计数用例改钉状态语义（幂等/成对清），互斥纪律不放宽。

**净删行**：6 文件 +60/-446（净 -386）。application 目录 39→38 文件
（脱离 40 上限 warning 档）。editor_page 库 7149 不变（VM 不属本库）。

**顺带依赖升级**：url_launcher_android 6.3.33→6.3.35（flutter.dev 官方
一小时内新发布，changelog 核验为 Kotlin 转换 + Robolectric 测试更新，
无安全公告；6.3.34 起 minSDK Flutter 3.41 本仓 3.50 满足）。依赖门禁
复查时撞 8>7 阈值，升级后回到 7≤7。

### 架构审查路线图 R1 剩余域（2026-11-17，同版本增量，未 bump）

**R1 · 裁剪交互域归并**（逐字搬移零逻辑变更）：_buildCropHandles（4 角手柄
UI）自 drag_ops、_nudgeCropRect/_exitCropMode（键盘平移/Esc 退出）自
shortcuts 搬入 persistence，与 _confirmCrop 团聚——裁剪「手柄→键盘→确认」
全链一处可见；写盘管线仍在 infrastructure/editor_image_crop.dart。
persistence 310→403 行，职责声明与 part 导航同步。

**R1 · 文字编辑域归并**（逐字搬移零逻辑变更）：11 个纯文字方法（新建/画布
新建/双击分发/提交/取消/便利贴/字号/分页预览/改色/批量改色/进入编辑，约
261 行）自 editing 搬入 text_overlays，与就地编辑渲染/斜杠命令同域。
editing 798→470 行脱离五类杂烩，只剩图片插入/链接/点选/菜单/层序/删除等
跨对象混排动作。顺手归位：缩放三法→input（视口手势同域）、分组两法→
drag_ops（与 _expandGroup 同域）。

**R1 · _applyState 收口单点**：主文件 5 处裸 setState（4 个顶栏开关 + 退出
保存流）收编进 _applyState；persistence 的 notify() 第二包装删除（6 处调用
统一 _applyState(() {})）——整页重建从此只有一个入口。新增门禁
test/editor_page_setstate_single_entry_test.dart 钉死：_EditorPageState 作用域
（class 体 + 全部 on _EditorPageState extension）内 setState 只许出现在
_applyState 定义行；独立对话框 State 合法豁免按作用域判定自然排除；配塌空
下限 + 探针自证防门禁空转。

**诚实边界（本批不动，留档）**：① _addTextItem/_addCanvasTextItem 的
「_commitTextEditing + 紧接 _applyState」双刷是**有意时序**（原注释：避免
setState 内再 setState 造成输入框失焦），不合并；② EditorViewModel 的
notifyListeners 全库无订阅者（页面刷新全靠 _applyState 包裹 VM 调用）——
VM 通知机制与页面刷新的双轨是设计意图问题，同 R5 须业主裁决，不擅动。

**棘轮**：editor_page 库总量 7149 不变（纯搬移 + 等行注释更新 + 接缝清理），
基线不动。D-14 裸间距台账随文字域搬移同步（editing 的 1 处分页预览弹窗
SizedBox 移往 text_overlays：5→6、editing 归零删行，总量不变非新增）。

### 架构审查路线图 R2/R4/R3 + R1 首域（2026-11-17，同版本增量，未 bump）

**R2 · 7 个破千 part 库补棘轮**（零行为变更）：doc_store 1600 /
notebook_storage 1462 / sync 1389 / controller 1380 / app_data_root 1259 /
webdav_settings 1052 / app_lock_gate 1048——新增
test/architecture/part_library_ratchet_test.dart 台账（主文件 + part 合计
只许减不许增，分母 7 防静默缩水），补上此前仅 editor_page 有库级棘轮的盲区。

**R4 · 重复/死码净删**（行为零变化）：
- text_span_editor：toggleLink 的 40 行 clamp/交集/前后段切分循环收敛进
  既有 _mapSelection（与 clearStyle/_toggleStyle 共用，差异只在交集段变换）。
- skeleton：SkeletonList/SkeletonCardGrid 两份相同的脉冲 controller
  创建/dispose/Semantics 样板收敛进 _SkeletonPulseMixin。
- document_object_editing_session：_DocumentObjectSelectionState（私有类）
  的 containsShape/containsImage/selectMixed 私有化——「谁能碰选区内部」
  成为机器事实，5 处调用点同步。

**R3 · 手势域收敛**：
- 框选/套索两处三类同构命中循环（约 60 行）收敛进 infrastructure 纯函数
  MixedItemHitGeometry（idsInRect/idsInPolygon，口径逐字一致：文字宽 =
  fontSize*2、套索取中心点、文字→图片→形状顺序），_onPointerUp 净降 20 行；
  新增 6 项单测把边界口径钉成机器事实（此前散在手势巨方法里不可单测）。
- 旋转手柄保存链通知移到 onPanEnd（+onPanCancel 兜底）：此前每帧
  _notifyChanged 打防抖自动保存 + updatedAt 改写，与移动/缩放的「结束才
  通知」语义不一致。旋转角度计算逐字未动。
- 诚实边界：「混排拖拽不入撤销」是整个拖拽域既有缺口（移动同样不入命令
  历史），单独给旋转加撤销会造成语义分裂——留待拖拽域统一事务化，不本批打补丁。

**R1 首域 · 导出职责归并**（逐字搬移零逻辑变更）：PNG/PDF/SVG/RTF/TXT
导出方法群原散在 editor_page_persistence（保存域），与 actions 的 PPTX/JSON
同一职责两处安放——归并进 editor_page_actions 导出域；persistence 只剩
保存/自动保存/重命名/裁剪（480→311 行），职责声明同步更新。

**棘轮**：editor_page 库 7161→7149（-12，R3 净删行收益；R1 搬移行数中性），
基线随净删下调——只紧不松（test/editor_page_line_ratchet_test.dart 注释交代）。

### 全面升级 + 架构审查 + 高置信度修复（2026-11-16，同版本增量，未 bump）

**升级**：Flutter 3.50.0 已是最新 stable（verify-only 确认）；pdfrx 链
2.12.1→2.13.0（pdfium_dart/pdfium_flutter 0.4.2→0.4.3、pdfrx_engine
0.9.2→0.9.3）。7 个传递依赖受 SDK/约束钉住不可升（analyzer/qr/cross_file
等），非遗漏。升级后全量门禁复验通过。

**架构审查结论（屎山判定）：宏观不是，微观局部是。**
- 宏观健康：四层占比 features 50%/core 30%/shared 3.5%/app 1.6%；
  跨层倒挂 0、源码环 0、横向 feature 隔离 0 违规；9 规则 + 14 专项门禁 +
  边界脚本 + DCM 真实覆盖；TODO/FIXME/HACK 真实 0 处。
- 微观泥球：editor_page 库 7158 行（15 part，主文件自认「切的是位置不是
  逻辑」），扇出 73 全仓最高；_applyState 散见 11 文件 92 处；7 个破千
  part 库无棘轮（仅 editor_page 有）。详见 docs/ARCHITECTURE_REVIEW_2026-11-16.md。

**高置信度修复（本批落地，全部读码复核 + 回归护航）**：
- **DEK 用完即焚补齐 5 处**（encryption_service）：新生/改密/重置盘/绑盘/
  块文档解密路径解出的 DEK 此前无 finally 零化，与 KEK/media 槽「用完即焚」
  纪律不一致——补 fillRange（只擦方法内独占副本；unwrapPasswordSlotForRewrap/
  rewrapPayloadV5 的 DEK 归属调用方，未擦，回归钉住可二次复用）。
- **明文外层取钥守卫**（notebook_storage_password.dart
  _encryptedPayloadOnDiskInsideExclusive）：保险库有钥但笔记本未设密时外层
  是明文 JSON，此前有钥即无条件 decrypt 撞「不是 DNV 信封」抛错，阻断
  ensure/改密/绑盘——补 !isEncrypted 放行（对齐同文件 patch 路径既有口径）。
- **死代码删除**：encryption_service.formatVersionOf 全仓零引用（旧格式
  提示用途，v5 收口后失效）。
- **mounted 守卫补齐**（editor_page.dart 退出裁决）：第二个异步间隙
  （确认弹窗）后未复查 mounted 即 setState——弹窗期间页面销毁会抛异常。
  补 if (!mounted) return（+3 行，棘轮 7158→7161 按 P3-3 纪律三处交代）。

**回归**：新增 notebook_review_fixes_test（6 项：明文外层 ensure/绑盘 +
改密/重置/块文档解密/rewrap DEK 复用全链路）。

**门禁复验（本机实测）**：严格 analyze No issues found；主套件 3068/5/0；
KDF 串行 97/1/0；架构+棘轮 154 项/边界/版本/依赖（7≤7）全过。

### material_ui/cupertino_ui 迁移完成（2026-11-16，探针实测推翻「等上游」原判，同版本增量，未 bump）

> 外部核查指出原评估「等上游类型收敛」前提不成立——官方从未有兼容层/
> 类型别名计划，路径就是全量迁移。本地探针实验（可回退分支）证实：
> 原「52 处编译错误」是迁移步骤没走完的标准中间态，不是上游缺陷。

- **官方三步路径实测走通**：① `dart fix --apply --code=migrate_design_widgets`
  209 处修复/206 文件（lib 全部 + test + integration_test 的 import 切到
  material_ui/cupertino_ui）；② 35 处 localizationsDelegates 改
  `GlobalMaterialLocalizations.delegates`（含 l10n 生成码、历史双 GML
  重复注册残留、if 条件混排等 6 种形态）；③ bridge **未使用**——实测
  本项目直接依赖（pdfrx 2.12.1/riverpod/window_manager 等）零 SDK
  Material 类型暴露，无遗留子树需要兜。
- **依赖**：material_ui 1.11.1 + cupertino_ui 1.1.7 由传递依赖升为直接
  依赖（精确钉版；1.11.0→1.11.1 后黄金基线重跑全等价，升级纪律兑现）。
- **主题适配层价值兑现**：dart fix 连适配器一起切到 material_ui ThemeData，
  AppThemeSpec 色板/四档决策零改动；黄金基线四档逐字段等价（仅 fontWeight
  序列化 index→value 随 dart:ui 弃用同步换算，基线 JSON 同式更新）。
- **收尾**：26 处旧 flutter_localizations 导入移除；2 处前缀导入补 m. 前缀；
  既有 unawaited_futures（doc_editor_history）一并修复；**CI 4 处
  --no-fatal-infos 移除，analyze 恢复严格口径（No issues found）**。
- **gen_l10n 生成码处置**（探针实测发现的持久化陷阱）：生成模板硬编码
  flutter_localizations 三件套 delegate（SDK 3.50 起弃用），且生成码每次
  `flutter pub get` 被模板重写——手改不可持续（实测被覆盖两次）。生成器
  无 delegates 覆写选项（l10n.yaml 全选项核过）。收口：新增
  `lib/l10n/app_l10n_setup.dart`（App delegate + material_ui 新源三件套），
  4 个消费文件改经 AppL10nSetup；l10n.yaml 经官方 header 选项注入文件级
  弃用忽略（生成成员零消费，忽略随再生成持久，pub get 复验不再回退）。
- **文档更正**：MATERIAL_UI_MIGRATION_ASSESSMENT 原「当前不做/等上游」
  结论标记失效，留档作误判教训；新增升级纪律——material_ui 周更+semver
  （1.6~1.11 已带 M3 Expressive 变化），每次升级必须重跑黄金基线回归。


### CI 口径收口（M-9）+ 发版说明补记（M-10，2026-11-16，同版本增量，未 bump）

**M-9 CI 四处**：
- weekly-evidence 依赖过期检查补 `--threshold 7`（此前走脚本默认 10，
  劣化 8~10 项时周证据漏检，与 pr-security 口径分叉）。
- pr-platform Windows 证据构建移除 `--obfuscate --split-debug-info`——
  出货命令已回滚混淆（release-build.yml），证据必须与出货**逐字同形**。
- code-guard 六个 Python 工具钉版（ruff==0.17.5 / ty==0.0.14 /
  bandit==1.9.4 / vulture==2.16 / radon==6.0.1 / interrogate==1.7.0，
  PyPI 实查当日最新稳定版）——同段 pyscn/py-cq 已钉，此前六工具未钉
  即规则漂移面（P3-7）。
- code-guard 涉密预检：`github.event.before` 改经 env 收口（消脚本注入
  面）；回退基线从 HEAD~1（只扫最后一笔）升级为与 origin/master 的
  merge-base（首推分支多提交整段覆盖），仅 merge-base=HEAD 时退 HEAD~1
  并显式告警。

**M-10 发版说明补记**（以下改动已在 master，此前 1.17.68 段漏记）：
- **冲突中心（SYNC-003）**（1d66915f + c3ba7296，2026-11-11）：持久冲突
  台账 + 改判入口 + 下一轮生效——冲突不再「弹窗一关就永久消失」；
  resolvedResolution 记实际生效裁决。配套过 CTL-03 落盘枚举门禁
  （ConflictResolution 补 WireEnum，wireName 与 .name 逐字同 ⇒ 磁盘零迁移）。
- **app_data_root 拆分**（2f9352bf，2026-11-11）：1099→717+542 行
  （恢复/暂存职责域拆 part），34 个公开静态成员全保留转发，调用点零改动。
- **10 万笔剔除标定 + 首份性能基线报告**（54c55c23，2026-11-11）：B-4
  补 10 万笔档（纯内存口径 100 万点；codec 单文档预算 ≤5 万笔按设计
  不可落盘），补齐 EXPERT_REVIEW §八 验收物 performance_report.md。
- **死代码清理四项**（17194617，2026-11-12，业主点名同意）：零生产
  消费者常量/方法删除（含 AppDesign.navyInk/navyAccent），运行时行为不变。
- **S-002 PIN 下限收至 6 位**（3545dfbe，2026-11-13）：4 位纯数字可离线
  爆破——下限 4→6（此前仅 1.4.0 旧段有记录，本段补记现行口径）。

### 主题适配层：内部主题模型与 Material 实现解耦（2026-11-16，迁移评估步骤 2，业主批准先行）

> material_ui 迁移评估（docs/MATERIAL_UI_MIGRATION_ASSESSMENT.md）第五节
> 步骤 2「先建主题适配层」——唯一可先行、有独立价值的一步。本批落地，
> **不做** material_ui 切换本身（步骤 1 等上游收敛仍是前提）。

#### 新增（core/theme/）
- **app_theme_spec.dart**：内部主题模型——`AppColorSpec`（28 槽语义色板，
  纯 const 数据）+ `AppThemeSpec`（四档决策：明暗 × 对比度，画布/次级表面/
  焦点/发丝线/圆角）。**只 import dart:ui**，零 Material/widgets 依赖——
  将来切换 material_ui（平行实现，两套 ThemeData 类型不兼容）时本文件
  零改动，新增平行适配器消费同一模型即可。
- **material_theme_adapter.dart**：模型 → Flutter ThemeData/ColorScheme 的
  **唯一转换点**（应用级 ThemeData(/ColorScheme( 构造全 lib 只准在此）。

#### 收编（行为零变化）
- app_design.dart 468→143 行：_theme 与四套 ColorScheme 构造改薄委托
  （决策→AppThemeSpec，装配→适配器）；公开签名（lightTheme/darkTheme/
  lightThemeFor/appleLightScheme/navyScheme）全部不变，227 处 Theme.of
  消费点与 provider 链路零改动。
- pagePadding 权威收编进 AppThemeSpec（斩断适配器→app_design 循环边），
  AppDesign.pagePadding 保留别名。

#### 等价性证明与门禁
- **黄金基线回归**（theme_adapter_equivalence_test）：重构前实机捕获四档
  ThemeData 全字段快照（28 色槽 + 10 组子主题 + textTheme + 转场，共
  18 字段组 × 4 档），重构后逐字段比对——实测踩中并修正一处发丝线 alpha
  手写常量与 withValues 动态计算的舍入分叉（改为同式计算）。
- **接缝门禁**（theme_adapter_seam_test）：①模型零框架依赖（只准 dart:ui）；
  ②应用级主题构造唯一落点=适配器；③薄委托三方台账防空转；判据正反自证。
- 架构规则 3b：适配器按 document_codec 同类先例列为输出适配器豁免
  （Ca=1 Ce=4 天然高 I）；稳定数据层 app_theme_spec I=0.00 留在断言内。
- D-14 间距棘轮：2 处 Material 装配裸间距随代码原样搬移登记（app_design
  归零删行→适配器同值 2），总量不变非新增。

### 低危批收口（L-1~L-10，2026-11-16，同版本增量，未 bump）

> 全面审计残留的低危项随手清掉（H/M 已在前序批次收口）。

#### 代码项
- **L-1 VFS 媒体配额**：`storeImage` VFS 写分支补 50MB 源文件配额预检，对齐
  DAN 分支——此前仅 DAN 分支有限制，VFS 分支可入库超大资产。
- **L-2 KDF 安全下限**：`KdfParams.fromSlotJson` argon2id 槽位补下限
  （m≥8MiB/t≥1/p≥1，恰容纳 testLight 与生产）——防恶意分享文件用 `m=1KiB`
  瞬爆参数伪装合法槽位。**PBKDF2 读路径不设下限**（历史弱槽位兼容，且写入
  路径已删 M-06，新数据不可能产生弱 PBKDF2 槽）。补下限回归（弱参拒绝 +
  testLight 不误伤 + PBKDF2 兼容）。
- **L-7 空 catch 补审计**：`backup_service` 暂存清理失败、`notebook_view_page_imports`
  设密/改密失败两处空 catch 补 `AuditLogger.log` 留痕（错误码走 errorCode，
  守 CTL-03）——安全相关操作失败不再静默。

#### CI / 脚本 / 文档项
- **L-4 覆盖率脚本**：`measure_coverage.sh` 平台分派 flutter 路径（对齐
  kyzn_workflow.sh M-12 口径，macOS 不再硬编码 /d/flutter/bin）；awk 分层名
  对齐现行 Feature-First 结构（core/features/shared/app），替换早已不存在的
  engine/models/storage/ui 旧层名（旧 awk 全部落空、门槛空转）。
- **L-5 persist-credentials**：quality_gate / sbom / code-guard（6 处）的
  checkout 补 `persist-credentials: false`——token 不残留 runner git 配置。
- **L-6 AGENTS 过期表述**：删 §CI 边界里「--obfuscate 防逆向构建」过期表述
  （混淆已回滚，出货命令不再混淆）。
- **L-10 失败产物范围**：quality_gate 失败产物 `**/*.json` 限定到
  `**/reports/**/*.json`——原过宽会夹带 pubspec/package_config 等环境 json。

#### 子包测试（L-9）
- **notebook_domain**：三端口契约测试零的突破（fake 实现钉签名可满足 +
  notebookId 隔离语义 + 纯 Dart）——adapter 未接线（C-07）但契约先锁。
- **editor_core**：几何引擎补轴对齐/退化/负坐标/近退化段边界用例（既有
  golden 只测对角线）。

#### 说明项
- **L-3**（docs/README K_NOTE 索引）已在 PR #64 修过，本批核实无残留。
- **L-8**（editor_page 行数棘轮 7158 零余量）属「只许减不许增」纪律的设计
  使然，非缺陷——下次改动按纪律三处交代动机即可，不擅自放宽基线。

### 残余攻击面收口：审计链后缀截断 + VFS 侧车强制（2026-11-16，同版本增量，未 bump）

> 框架级收口（PR #64）后残留的两个攻击面（M-6/M-7），本批堵死。

#### M-6 审计链后缀截断检出
- 此前整删 `audit.log` + `.1`（保留归档）后归档链自洽，`verifyIntegrity` 仍返回
  true——锚定条目之后的历史被整段抹掉无法检出。
- 收口：`verifyIntegrity` 额外校验**本进程内存链尾哈希必须在文件链**（归档 +
  .1 + 当前）。整删活跃段后尾哈希哪儿都不在 ⇒ 判红。
- 两个守卫防误报：在途追加计数 `_pendingAppends`>0 跳过（内存领先文件属正常态）；
  最近一次落盘 IO 失败跳过（不把自己的 IO 失败当篡改）。**实测教训**：不能用
  「内存条数 ≤ 活跃段条数」做在途守卫——轮转把历史挪进归档后内存条数天然多于
  活跃段，该判据恒跳过（已弃用，改在途计数）。
- 外部锚 `entryCount` **不参与判定**（复核维持原设计）：计数下界在轮转语义下
  误判（git 历史已记载「位置序号/计数下界/世代号覆盖均误判」教训），哈希锚定
  是唯一可靠判据。
- 残余窗口（如实）：进程崩溃丢尾与截断在落盘侧无法区分；重启后内存链重置，
  重启前已被整删活跃段且归档自洽的情形本判据无从锚定——靠外部锚凭据哈希锚定兜底。

#### M-7 VFS 清单侧车强制验签
- 删除「无侧车=历史遗留放行」分支——删掉 `manifest.hmac` 即免验签、可回滚
  version 指向旧版本对象（旧版 AAD 自洽）的攻击入口被堵死。缺侧车一律 fail-closed。
- 业主已确认无存量数据（与删旧版加密同口径），不留兼容缝。

#### 回归与文档
- 新增 M-6 回归组（整删活跃段判红/仅删当前判红/重启不误报/在途不误报/外部锚
  哈希删改绝不判 true）+ M-7 回归（删侧车+回滚清单正确密钥也 fail-closed）。
- SECURITY.md 补后缀截断检出口径与侧车强制口径。

### 会话密钥生命周期框架级收口（2026-11-15，同版本增量，未 bump）

> 业主指示：**先从框架上修复，不要打补丁**。审计（K_note 接线后复审）发现的
> H-1/H-2/H-3 + M-1~M-5 全是「缺失会话密钥生命周期权威层」的不同症状——
> 本批补上该层，让缺陷被**结构消解**，而非逐点加守卫。

#### 新增取钥权威编排器（core/security/notebook_media_keys.dart）
- **加密意图与密钥可得性分离**：消费方只问「给我这本的媒体密钥」，由编排器
  依据笔记本加密声明决定——加密笔记本缺钥/锁定一律 fail-closed，**绝不把
  「明文」选项交给加密笔记本**（H-1：消灭 hasKeyFor 内存嗅探当加密判据）。
- **会话世代令牌 SessionEpoch**：SessionSecrets.clearAll（回锁）先递增世代；
  跨 await 的密钥操作完成时校验，过期即作废（M-3/M-4 竞态构造性消除）。
  另有 per-id 遗忘世代（forget）防页面退出后在途 ensure 复活密钥。
- **per-id 并发去重 + 独占队列内补槽**：同本并发 ensure 只生成一把 K_note；
  懒补槽经存储独占写队列重读最新落盘内容、只替换 encryptedPayload 字段
  （H-3：非整本陈旧快照回写）。
- **三态契约**（H-2）：EncryptionService.unwrapNotebookMediaKey 改为——无 media
  槽返回 null（懒补）；密码错误/槽损坏抛 FormatException（fail-closed，绝不
  生成未持久化临时密钥）。

#### 加密原语加固（MediaCryptoService）
- 加解密入口复制密钥快照、用完即焚——构造性消除 use-after-zero（M-3：
  await 期间回锁/逐出清零同一活缓冲可能以全零密钥产出「合法」密文）。

#### 消费方全部收口到编排器
- 写：storeImage/sealMediaBytesForPath → _sealIfEncrypted → sealMedia；
  读：EncryptedFileImage/NotebookPdfExporter → openMedia（LRU 逐出自动重解包，M-2）；
  解锁：5 处 ensureNotebookMediaKey 委托 ensure；清理：页面 dispose/会话锁 →
  forget，删除笔记本 → forget + VFS removeObject（M-5，新增按 id 删全部版本能力）；
- EncryptedFileImage 缓存键纳入 notebookId（M-1 跨本不命中绕过 AAD）；解锁收口
  imageCache.clear()（跨会话明文位图不驻留）；
- search_page/app_shell_routes/default_route_services 补捕获 ensure 抛出的
  锁/IO 异常（M-8：不再未处理异步异常/点击无响应）；
- 组合根 app.dart 以真实 NotebookStorage 为信封端口装配编排器，注入存储与
  AppServices（同源）；AppServices/CompositionRoot/EditorPageBuilder 契约及
  全部页面字段 mediaCrypto → mediaKeys。

#### 门禁与文档
- presentation_io_seam_test H1-② 收紧为**零豁免**（表现层不得持有加密原语），
  H1-③ 钉住原 6 持有方已改持编排器（防假收口）；
- 新增 docs/SESSION_KEY_LIFECYCLE.md（契约与划界，挂索引）+ AGENTS.md §10；
  SECURITY.md 补取钥权威层口径；docs/README.md K_NOTE 索引改「已实施」。
- 新增结构性回归 test/core/security/notebook_media_keys_test.dart（H-1/H-2/
  H-3/M-2/M-4/M-5 各一条，防被结构消解的缺陷复发）。

### K_note 媒体独立密钥生产接线（2026-11-16，业主批准，同版本增量，未 bump）

> 业主决策（2026-11-15）：**现在还没有用户、不存在旧格式数据**——不做迁移
> 向导/双轨兼容/回滚，K_note 直接作为唯一媒体加密口径；LRU 上限 32 本。
> 原 K_NOTE_WIRING_PLAN 四批方案中的批 4（存量迁移）因此消解。

#### 信封层：v5 新增 media 槽（K_note 封存）
- `encryptWithPasswordV5`（笔记本 scope）自动生成随机 32B K_note，用 payload
  DEK 包裹封入 `slots.media`（AAD 绑定笔记本 ID——槽位密文不可跨本移植）。
- 新增 `unwrapNotebookMediaKey`（密码→DEK→K_note，DEK 用完即焚）、
  `attachNotebookMediaKey`（懒补槽，幂等）、`hasMediaSlotV5`。
- **改密/重置盘重置保留 media 槽**（LUKS 语义：只重绕 pw 槽，K_note 不动）。

#### 媒体服务：LRU 密钥映射（替换全局会话密钥）
- `MediaCryptoService` 改按 notebookId 的密钥映射（**上限 32，逐出即零化**，
  命中刷新 LRU 序）；加解密一律 `encryptFile(notebookId,…)` /
  `readMediaFile(notebookId,…)`，AAD 恒含 notebookId（**无全局回退**）。
- **删除全局会话密码派生路径**（setSessionPassword/setSessionKey/MediaSalt/
  ensureMediaSalt/media_crypto_salt 盐文件）——无旧格式兼容（业主确认无存量）。
- 页面锁定/销毁只清本笔记本密钥（其他已打开笔记本不受影响）；全局回锁仍经
  SessionSecrets 清全部。

#### 生产接线（写/读/渲染全链路）
- `NotebookStorage.ensureNotebookMediaKey`：解锁时解包注入；无 media 槽懒补
  （生成 K_note→补装信封→原子落盘）；无会话密码 fail-closed。
- 5 处解锁/设密/重认证注入点改走 ensureNotebookMediaKey；storeImage /
  sealMediaBytesForPath / INotebookMediaStore 接口加 notebookId；PDF 导入
  密封回调绑定笔记本上下文。
- 渲染链：EncryptedFileImage / 阅读页 / 放映页 / 编辑器浮层 / PDF 导出器
  全部穿线 notebookId（EditorPageBuilder 契约 + DefaultEditorPageBuilder
  绑定笔记本上下文导出）。DAN 密文无笔记本上下文一律 fail-closed。
- 独立画布（无笔记本）走文档存储 DNV 主密钥路径，不受影响。

#### 测试
- 重写 media_crypto_service_test（K_note 口径：跨本隔离/LRU 逐出与刷新/
  覆盖不占名额/SessionSecrets 联动/DAN 封装）。
- 新增 notebook_media_knote_test（9 项：信封往返/错密码/跨本解包拒绝/改密
  保留 K_note/懒补槽持久化/无密码 fail-closed/明文无操作/跨本媒体隔离）。
- 同步更新 storeImage 签名涉及的 6 个测试文件。

#### 门禁基线调整（按 P3-3 纪律显式交代）
- `editor_page` 库级行数棘轮 **7144 → 7158（+14）**：K_note 安全接线的必要
  穿线成本（notebookId 字段/构造 +7、图片入库笔记本上下文守卫 +6、图片
  provider 传参 +1），非展示件增长；part 数与边界不动。

### 外部锚补强 + 同步密钥清零 + 迁移可行性定案（2026-11-15 第二批，同版本增量，未 bump）

#### 审计链外部追加锚（M-05 残余边界补强）
- 新增 `AuditLogger.exportExternalAnchor()` / `verifyAgainstExternalAnchor()`：
  导出**不含密钥**的凭据（格式版本 + 世代号 + 文件链尾哈希 + 条目计数 + 导出
  时刻），用户可抄存到**独立介质**（另一设备/打印/密码管理器）。
- 事后比对校验**凭据记载的历史哈希是否仍在链上**（恒定时间比较）——覆盖
  「攻击者同时取得锚密钥与文件写权限」的整链重算：重算后的哈希不可能与独立
  介质凭据吻合。
- 追加新记录不影响校验；凭据格式非法判 false；找不到哈希返回 **null
  （无从判定，不谎报通过）**。新增 9 条回归用例（含 2 条轮转场景实测）。
- **归档段（append-only，第三批 2026-11-15）**：轮转时先把当前文件追加进
  `audit.archive`（不删不覆盖，上限 8 MiB 超限停止归档）再轮转。外部锚校验与
  完整性重放都纳入归档（按哈希去重避免归档/.1 重叠假断链；仅容忍文件边界的
  轮转缺口，段内删除仍检出）。由此「前缀被轮转丢弃」的 null 变回确定 true，
  null 窗口收窄到「超归档上限/归档也被破坏」。修复了多次轮转后
  `verifyIntegrity` 因 `.1` 起点 mid-chain 误报断链的既有局限。
- **实测修正（重要工程教训）**：初版按「位置序号」定位历史前缀，轮转测试当场
  判红。逐次验证三种判据**均不成立**：①位置序号——轮转是整文件搬移
  （`sink.rename(.1)`），`.1` 被新一代覆盖后「第 N 条」已是另一条记录；
  ②条目计数下界——轮转后剩余总数可能仍大于凭据计数（实测凭据 2 条、剩 4 条）；
  ③世代号覆盖——同世代内也会多次轮转。**最终定案**：哈希锚定 + 诚实三态——
  命中 true；找不到一律 **null**（「被篡改」与「被轮转丢弃」落盘信息不足以
  区分，宁可报无从判定也不谎报）；格式非法 false。核心不变量「重算后绝不判
  通过」由门禁钉死。SECURITY.md 与用户指南同步此语义。
- 接入设置页「导出诊断信息」：凭据随报告给出并附留存指引；未落盘时不伪造凭据。
- **顺带修一个真实用户可见 bug**：诊断导出此前用
  `writeFileBytes(report.codeUnits)`——`codeUnits` 是 **UTF-16 码元**，当字节
  写会让报告里的**中文全部乱码**（每汉字两个裸字节、无 BOM），中文说明与凭据
  留存指引都读不了。改用 `writeTextFile`（`writeAsString`，UTF-8）。新增回归
  用例锁住「UTF-8 往返逐字一致」并用反面对照证明该 bug 真实存在。
- **诊断报告口径修正**：此前文案仍写「无密钥 SHA-256 / 尾截断不可检」（上批
  加固后漏改），现同步为带密钥 HMAC 锚 + 世代单调 + 残余边界如实声明。

#### 同步主密钥会话清零（M-04 同类收口）
- `AesSyncCipher` 此前 `key` 为 `final` 且无清理点，同步主密钥整会话驻留内存。
  现改为自有可变缓冲 + 实现 `SessionSecretsHolder` 并注册统一清理注册表，
  回锁随 `SessionSecrets.clearAll()` 清零。
- 清零后 `key` 读视图抛 `StateError`（fail-closed）——不静默返回全零密钥产出
  「看似成功实则不可解」的密文。构造时复制入参，兼容不可变列表。
- 新增 5 条回归用例（注册联动/幂等/清零后加解密拒绝/自有缓冲/不可变入参）。

#### material_ui 迁移：实测定案「当前不做」
- 两次尝试失败根因已查清并留档 `docs/MATERIAL_UI_MIGRATION_ASSESSMENT.md`：
  - 尝试 1（自动 `dart fix`）：52 处 `ambiguous_import`——两包同名导出 Localizations。
  - 尝试 2（单文件 + 精确 `show` 导入）：歧义解决，但暴露**更深阻塞**——
    `material_ui` 是**完整平行 Material 实现**（自有 `ThemeData`/`ThemeMode`/
    `MaterialApp`，仅复用 `flutter/widgets`），两套 ThemeData **类型不兼容**。
- 真实工作量：227 处 `Theme.of` + 39 处 `ThemeData` + 11 处 App 根 +
  115 个测试文件 + 高扇入主题枢纽（apple_design 被 80 文件依赖）。
- 判定：收益仅消除 **info 级**提示（不影响编译/运行，CI 已放行），代价是整个
  UI 层换框架 —— **收益/代价严重失衡，不做**。文档给出将来若做的前置条件与
  正确顺序（先建主题适配层，再切 App 根，最后批量换导入）。

### 侧信道收口 + 零化补齐 + 架构文档（2026-11-15，同版本增量，未 bump）

#### 恒定时间比较收敛（防时序侧信道）
- 新增 `core/utils/constant_time.dart` **单一事实来源**：此前 3 处各自复制
  （`app_lock_service` / `app_lock_guard` / `encrypted_vault`），其中 2 处因长度
  不等**提前返回**——强度不一致。收敛版取最严谨口径：长度差折进 diff、按较长者
  遍历，不泄露长度信息。三处改薄委托。
- **补齐审计链时序缺口**：`audit_logger` 的 HMAC 校验与 prevHash 链接比较此前
  用裸 `==`（短路可计时），全部改走恒定时间工具。
- 新增门禁 `test/architecture/constant_time_gate_test.dart`（10 项）：实现唯一性
  + 调用面覆盖 + 审计链禁裸比较 + 行为正确性，防将来回退。
- **保证边界如实声明**：Dart 层无法提供 C `CRYPTO_memcmp` 的严格恒定时间
  （JIT 优化空间），本工具是纵深防御，不声称抵抗微架构侧信道。

#### 密钥零化补齐（20 → 28 处）
- 4 个此前**完全无零化**的文件补齐 8 处，全部 `try/finally` 覆盖异常路径：
  `encryption_service`（v5 槽位包裹/解包 KEK）、`vault_file_codec`（v3 加密/
  解锁/重绕 KEK）、`app_lock_service`（PIN 派生字节）、`sync_cipher`（v1→v2
  迁移的两把临时密钥）。
- **遗留如实记录**：`AesSyncCipher.key` 为 `final` 且经 isolate 传参，加清理需
  动接口契约（另立专项）；Dart GC 移动式堆与不可变 `String` 是语言级限制，
  应用层 mlock 无法真正生效（不做虚假加固）。

#### 架构文档（防后续开发混用）
- **AGENTS.md §8 状态管理划界** + `docs/STATE_MANAGEMENT_DECISION_TREE.md`：
  明确 Riverpod（配置/偏好、域独立纯状态）与手工协作者（画布高频、业务流水线）
  的边界、反模式、迁移纪律。实测边界：Riverpod 仅 7 文件/10 provider，
  drawing 域是「容器接入 + 示范单元」，DrawingController 内部仍 ChangeNotifier。
- **AGENTS.md §9 part 命名与导航规范**：核实 57 个 part 命名 **100% 合规**
  （`主名_职责.dart`，无编号命名）；补齐 3 个最复杂主文件的导航目录
  （editor_page 15 part / doc_editor 8 part / drawing_controller 4 part）。
- `docs/PACKAGES_BOUNDARY.md`：**更正上轮误判**——`notebook_domain` 不是空壳，
  它有 3 个六边形端口契约、被组合根引用、受 2 条架构门禁保护；两个子包都保留。

#### 门禁基线调整（按门禁纪律显式交代）
- `editor_page` 库级行数棘轮 **7127 → 7144（+17）**：动机**不是功能增长**，
  而是补 part 导航目录的纯注释投资（15 个 part 逐个标注职责，零逻辑变更）。
  按 P3-3 门禁要求「改大须随附结构裁决说明并在 commit 单独交代」执行；
  part 数与边界不动，下一次**逻辑**增长仍须先拆或点名。

### 安全加固批（2026-11-14，删除旧版加密 + 审计链/MK/VFS 加固，同版本增量，未 bump）

> 依据全方位审计遗留清单逐项加固。本批**未 bump 版本**（发版时按 AGENTS §7 三处同步）。
> **破坏性变更**：删除旧版加密格式支持——存量 v2/v3/v4 密文与 PBKDF2 旧槽/旧盐
> 不再可解（fail-closed 拒绝），须先升级最新格式。新写入早已全走最新格式，不影响新数据。

#### 删除旧版加密支持（M-06，统一最新安全格式）
- **EncryptionService 仅 v5**：移除 v2/v3（PBKDF2 无 AAD）加解密、v4 密码模式
  （`encryptWithPasswordAad`）与 PBKDF2 旧槽解包；解密分派仅认 v5 双保护器信封
  （Argon2id + AAD），旧版一律抛 `FormatException`。`encryptNotebookPayload`/
  `decryptNotebookPayload` 作为 v5 载荷原语保留。
- **VaultFileCodec 删 v2**：移除 v2 单文件密码信封（PBKDF2）加解密；文件密码仅
  v3 双保护器（Argon2id）。5 处生产读路径（列表/读字节/验密/改密/移除密码）的
  v2 分支改 fail-closed 拒绝。v1 主密钥信封（带 AAD，安全）保留。
- **MediaSalt 仅 v2**：移除版本 1（纯 16B 盐，PBKDF2-600k）解析与 `legacy`/
  `setSessionPasswordLegacy`；旧盐 fail-closed 拒绝，仅 Argon2id 版本 2。
- 测试同步：旧版兼容用例改为「旧版拒绝」验证（手工构造旧信封字节断言 fail-closed）。

#### 审计链带密钥锚加固（M-05）
- 无密钥 SHA-256 链升级为**带密钥 HMAC-SHA256 锚 + 世代号**：锚密钥（32B CSPRNG）
  独立持久化于 `security/audit.anchor`（0600，与主密钥不同源）；每条记录 HMAC 绑定
  世代号，每进程启动 +1 并落 `audit.genesis` 世代标记。堵住「整链重算/整段删除/
  跨段拼接」三个无密钥链盲区（无锚密钥无法重算 HMAC，世代单调约束检出删段/拼段）。
- `verifyIntegrity` 落盘就绪时以文件链为权威（重启后内存链重置不误判历史）；
  旧无密钥条目仍按 SHA-256 校验（升级前历史可读）。组合根启动预热锚（`warmUpAnchor`）。
- 残余边界如实记录：锚密钥与日志同盘，同时取得两者仍可重算（彻底防篡改需外部锚）。
- 新增 5 条 HMAC 锚回归用例（篡改断链/无锚伪造被阻/世代单调/锚持久化复用）。

#### MK 副本生命周期管控（M-04）
- VFS 会话密钥（主密钥副本）实现 `SessionSecretsHolder` 并注册进统一清理注册表——
  回锁（hidden/超宽限）随 `SessionSecrets.clearAll()` 一并清零（此前 `lock()` 只清
  权威 MK，VFS 副本整会话驻留）。新增 2 条清理回归用例。

#### VFS 生产接线（M-01）
- 组合根解锁收口（`AppLockGate.onUnlocked`，覆盖 PIN/快速解锁/U 盘重置三路径）
  装配 VFS：`configure`（数据根 vfs/）+ `setKey`（主密钥）+ 注入 NotebookStorage。
  新媒体写 VFS 对象、旧媒体 DAN/DNV 文件兼容读（双轨）；回锁经 M-04 清零。
- **M-02 K_note 媒体接线留待专项**：密码学原语已实现有测试，生产接线需每笔记 DEK
  派生+存储+全量媒体重加密迁移（数据迁移专项）。

#### 安全链静默失败可观测出口（M-08）
- 密钥槽迁移失败、孤儿 tmp 清扫失败、防爆破守卫落盘/删除失败——4 处安全降级点
  从静默空 catch 改为落审计（只记错误类型，不带凭据），降级可见而非藏进黑盒。

### 工具链与依赖全面升级（2026-11-14，业主批准「全部升最新」，同版本增量，未 bump）

> 目标：所有版本升到 2026-11-14 的最新版；被 SDK/上游约束挡住的升到「可兼容的最新版」。

#### Flutter SDK
- **3.47.9（Dart 3.13.7）→ 3.50.0（Dart 3.14.0）**——2026-11-11 发布的当前最新
  stable。`pubspec.environment.sdk` ^3.13.0 → ^3.14.0；**全部 12 处 CI 钉版**
  （ci / quality_gate / pr-architecture / pr-platform×2 / pr-security / pr-quality /
  macos-build / release-build×2 / weekly-evidence×2）同步 3.50.0。
- README / README_EN / CONTRIBUTING 环境要求同步 3.50.0。

#### Android 工具链（Flutter 3.50 硬性最低，DependencyVersionChecker）
- **Gradle 9.1.0 → 9.3.1、AGP 9.0.1 → 9.1.1、Kotlin 2.3.20 → 2.4.10**——
  原版本均低于 3.50 门槛，Android debug 构建报「Gradle version lower than
  minimum 9.3.1」。Java 17 / minSdk 23 已达标无需改。

#### CI analyze 适配
- Flutter 3.50 起 `flutter analyze` 默认 info 也致命（3.47 不会），271 条
  material_ui 弃用 info 致 macOS 构建 Static analysis 退出码 1。4 处 analyze
  （ci / quality_gate / pr-quality / macos-build）加 `--no-fatal-infos`：
  info 放行、error/warning 仍致命；material_ui 迁移完成后移除旗标恢复严格口径。

#### 依赖（解锁上一批被 Dart 3.13 挡住的包）
- **hotkey_manager 0.3.0 → 0.4.0、window_manager 0.6.0 → 0.7.0**（需 Dart ^3.14，
  本次随 SDK 升级解锁）。
- **nativeapi / nativeapi_flutter / cnativeapi 0.5.10 → 0.6.1**（window_manager 0.7.0
  联动）；**test_api 0.7.12 → 0.7.14**。
- 直接依赖与 dev 依赖全部最新（`dart pub outdated`：direct/dev all up-to-date）。

#### 停在「可兼容最新版」的传递依赖（上游约束/SDK 钉死，无法再升，如实记录）
- **analyzer 11.0.0 / _fe_analyzer_shared 97.0.0 / package_config 2.2.0**：
  dart_arch_test 0.3.1（其最新版）约束 analyzer `>=9.0.0 <12.0.0`，11.0.0 即该范围最新。
- **qr 3.0.3**：pdf 3.13.1 → barcode 2.2.9（最新）约束 qr `^3.0.0`。
- **cross_file 0.3.5+5**：file_selector 平台包（均最新）约束 `^0.3.x`。
- **test_api 0.7.14 / material_color_utilities 0.13.0**：Flutter 3.50.0 SDK 钉死。
- 依赖门禁可升级数 12 → **7**（全部为上述约束项），阈值 12 内通过。

#### 兼容性验证（本机实测）
- `flutter analyze`：**0 error / 0 warning**（271 条 info 级弃用提示，见下）。
- 全量测试：主套件 **2990 通过 / 5 环境跳过 / 0 失败**；KDF 串行 **84 通过 / 1 跳过 / 0 失败**。
- 边界检查 / 版本一致性 / 依赖门禁：全过。

#### 已知遗留（不影响运行，独立任务处理）
- **material_ui 设计系统迁移**：Flutter 3.47 起 `package:flutter/material.dart` 弃用、
  推荐 `package:material_ui`。本批尝试官方 `dart fix --code=migrate_design_widgets`
  自动迁移（208 处），但引入 52 处 `GlobalMaterialLocalizations` 命名冲突
  （flutter_localizations 与 material_ui 同名导出，需 Localizations 委托重构），
  **已整体回退**以保住「0 error」干净状态。271 条 info 级弃用提示保留，迁移作为
  独立任务另行处理（涉及 205 文件 import + 25 文件 Localizations）。

### 全方位审计修复批（2026-11-13，同版本增量，未 bump）

> 依据《绘图笔记应用全方位审计报告》（2026-11-13）逐项修复。本批**未 bump 版本**
> （发版时按 AGENTS §7 三处同步）；门禁复验结果见本条末尾。

#### 安全

- **H-01 快速解锁生物识别回查**（`quick_unlock_service.dart`）：H1 用
  `getAvailableBiometrics` 回查只查「设备注册过哪些生物识别」，不查「本次验证
  方式」——注册过生物识别的设备用设备 PIN 回退仍被判 `biometric: true`，MK 副本
  保护强度降级为 4 位 PIN。改为按平台 `biometricOnly` 强制语义判定：Android
  BiometricPrompt 强制该开关（通过即生物识别）；Windows Hello 忽略该开关且
  local_auth 无「本次验证方式」查询，**fail-closed 判非生物识别**（拒绝落副本/
  解锁）。新增可注入 `biometricOnlyEnforced` 判据 + 4 条回归用例。
- **L-06 快速解锁副本 TTL**：旧格式（纯 base64 无 TTL）副本改按「已过期」处理
  （拒绝读取，须重新开启）；时钟回拨到写入时刻之前视为已过期（不得延长有效期）。
  新增 4 条回归用例；锁屏组件测试改用新格式 TTL 信封。
- **L-04 防爆破冷却时钟**（`app_lock_guard.dart`）：冷却剩余改按**单调经过时间**
  计量（生产 = Stopwatch，不受系统时钟调整影响；可注入 `monotonicElapsedMs`），
  起点锚点 + 时长随记录落盘，重启按锚点重算——会话内向前/向后拨钟、拨快再重启
  都压缩不了冷却。新增「向前拨钟 + 重启」回归用例；FakeClock 增加独立单调累计量。
- **L-01 SVG 事件属性正则**（`svg_preflight.dart`）：`\son[a-z]+\s*=` 要求前置
  空白，`<svg/onload=…>` 以 `/` 分隔即绕过。改为 `[\s/]on[a-z]+\b\s*=`。
- **L-02 PROPFIND XML 深度**（`webdav_sync_client.dart`）：`XmlDocument.parse`
  自身递归，4MiB 字节帽内深嵌套可在结构闸门前爆栈。解析前增加线性原始文本深度
  预扫描（保守上界，fail-closed）。
- **L-05 备份轮转原子性**（`storage_write_pipeline.dart`）：`.bak` 各级此前直接
  `writeAsBytes` 覆盖，崩溃写一半即损坏。改为 tmp + flush + rename 原子换入
  （提取静态 `_replaceWithTempImpl` 与主文档共用），失败旧备份原样保留。
- **L-03 PDF 输出预算前置**（`pdf_import_service.dart`）：500MB 输出预算从落盘
  循环移入默认渲染器**逐页累计**，超限即停，不再整本渲染进内存后才拒。

### 文档与口径对齐（宣称 vs 实际）

- **SECURITY.md / README.md / README_EN.md**：审计链口径更新为「内存链 + 落盘
  文件双段重放」（2026-11-10 已实现），如实列出尾截断/整段删除/跨段拼接盲区；
  媒体 K_note 与 VFS 标注「已实现、生产未接线」；会话守卫密钥清零时机如实描述
  （宽限期内主密钥仍驻留，超宽限落锁才清零）；README 编排数 7→8（补 macOS Build）；
  支持版本 1.1.x→1.17.x；测试规模 391+/2750→3000+。
- **diagnostics_exporter.dart**：诊断报告完整性声明与文件侧重放实现对齐（原文案
  「不读落盘文件」与实现相反），同步更新测试断言。
- **AGENTS.md**：§6 工作目录铁律由 Windows `D:\Workbuddy\` 更新为 macOS
  `/Users/bear/Documents/CatPaw/drawnote`；旧 Windows 路径/代理假设降级为历史备忘。

### 工具与 CI

- **bump_version.sh**：`grep -oP`（GNU 扩展）改 sed 捕获组；`sed -i` 按 uname 分派
  BSD/GNU——macOS 可运行（M-12）。
- **kyzn_workflow.sh**：PATH 注入不再硬编码 `/d/flutter/bin`，优先用已在 PATH 的
  flutter，按平台补候选（M-12）。
- **sync_github.sh**：`git add -A` 前增加 >5MB 未跟踪文件护栏，命中即中止（L-14，
  防 spikes/ 268MB 类险情重演）。
- **release-build.yml**：SHA256SUMS.txt 补入 windows-setup-installer artifact 与
  GitHub Release 附件（M-14，此前生成后不随产物分发）。
- **quality_gate.yml**：移除未使用的 `actions: write`（L-11，upload-artifact 走
  运行时 token，不依赖该权限）。
- **THIRD_PARTY_NOTICES.md**：许可表移除 pubspec 未引用的 cupertino_icons /
  cupertino_ui（L-13）。

### 依赖升级（2026-11-14，业主批准「全部进行升级」）

- **pdfrx 2.6.5 → 2.12.1**（PDF 解析攻击面跟进上游安全修复），联动
  pdfium_dart / pdfium_flutter 0.3.1 → 0.4.2、pdfrx_engine 0.6.1 → 0.9.2；
  低层 API（openFile / ensureLoaded / page.render）经 analyze + 全量测试复验兼容。
- **archive 4.6.0 → 4.7.1、image 4.12.0 → 4.13.0、objective_c 9.6.3 → 9.6.4、
  shared_preferences_android 2.5.4 → 2.5.5、shared_preferences_foundation
  2.5.7 → 2.6.2**；file_selector 约束放宽至 ^1.1.0。
- **SDK 上限所阻、留待 Flutter 3.50 升级**（当前钉 3.47.9 / Dart 3.13）：
  hotkey_manager 0.4.0、window_manager 0.7.0（需 Dart ^3.14）；analyzer 14.x、
  test_api 0.7.15、nativeapi 0.6.x、qr 4.x 等受 SDK 钉版传递约束——
  `dart pub outdated` 口径可升级数 21 → 12，全部为 SDK 上限项。
- **pr-security.yml**：补装 Flutter（此前 job 只有 Python，check_deps.sh 因
  dart 缺失 fail-closed 恒红——PR 流程首跑暴露的既有缺陷）；依赖门禁阈值
  显式置 12 并注释 SDK 上限基线（升级 Flutter 后应清零回调）。
- **pr-quality.yml**：补 editor_core 子包 pub get（漏了 ci.yml 2026-11-10
  已有的修复，根 analyze 解析子包 package:test 报 33 处 undefined）；
  「全量测试」按 kdf 标签拆分串行（v1.17.20 flake 根治同构）+ 补
  editor_core dart test 步骤。
- 注意：pdfium_dart 0.4.x 构建钩子需从 GitHub Releases 下载 PDFium 二进制；
  本机 DNS 将 release-assets.githubusercontent.com 解析到 127.0.0.1（污染），
  已用 DoH 查真实 IP + curl --resolve 取回放构建缓存（未改系统 DNS/hosts）。
  CI（ubuntu/macos runner）无此问题。

### 仓库卫生

- **M-13**：3 个历史审计报告（`docs/audit_round2/round3/ux_*.html`）`git rm --cached`
  移出索引（本地保留，.gitignore 已覆盖），落实 AGENTS §7「audit_*.html 不入库」。

### 待业主决策（本批未动）

- VFS / 媒体 K_note **生产接线**（涉及加密装配，需专门设计与回归）；
- 审计链**带密钥锚**加固（能力升级，代码注释明确业主尚未裁决）；
- **Flutter 3.50 升级**（解锁剩余 12 个 SDK 上限依赖）；
- 行数门禁 max_files 放宽 / 死 DI 缝隙与空壳 V2 包处置（删改须业主同意）。

### 门禁复验

- `flutter analyze`：No issues found。
- 受影响域 + 架构守护：140 项全绿（quick_unlock / app_lock_guard / app_lock_service /
  audit_logger / svg_preflight / webdav_sync_client / response_budget / backup_rotation /
  pdf_import / diagnostics_exporter / architecture_test）。
- 全量 `flutter test` 复验（2026-11-13 本机实测）：主套件 **2990 通过 / 5 环境跳过 /
  0 失败**，KDF 串行套件 **84 通过 / 1 跳过 / 0 失败**；`flutter analyze` 零问题、
  边界检查通过。本批不 push，云端编排未触发。

### CTL-03 ② 落盘枚举显式 wire 名（混淆解锁第二步）

> 2026-11 审计。混淆（`--obfuscate`）此前被回滚，回滚原因里的「① 诊断面字面量码」
> 已由 R50 完成，剩下的 ② 由本批完成。① ② 都带机器判据；③（真正加混淆）仍待业主点名。

**为什么要做**：Flutter 文档对枚举的原话是「Enum names are not obfuscated **currently**」
——"currently" 不是承诺。`--obfuscate` 之后 `Enum.name` 与 `values.byName()` 会跟着 Dart
标识符一起被改名，而 `flutter test` 与 `-d windows` 的 smoke 跑的都是**非混淆**编译
⇒ 这类失效 CI 天生看不见，只有装到用户机器上才现形（与 ① 同一类「本机看不见」失效）。

**落盘格式零变化**：16 个落盘枚举的 `wireName` 与改造前的 `.name` **逐字相同** ⇒
磁盘格式不变、老文件照读、无需迁移。变的是「格式不再由 Dart 标识符派生」——
以后改 Dart 标识符不再等于改格式。

**改动面**：

- 新增 `lib/core/utils/wire_enum.dart`：`WireEnum` 接口 + `wireEnumOf` / `wireEnumOfOrThrow`。
- `ThemeMode` 是 SDK 枚举、不能 `implements`，单独走 `themeModeWire` / `themeModeFromWire`
  （回落口径与改造前逐字相同：未知/缺失 → 跟随系统）。这两个函数放在
  `lib/core/theme/theme_mode_wire.dart`，是 `app_design.dart` 的 **part** 而不是独立库——
  因为 `core/di/providers.dart` 也持久化主题模式，而那个文件的 Martin 棘轮是 0.33，
  多一条 import 边就变成 0.50、撞上路 3b 的 0.4 基线。
- 16 个落盘枚举实现 `WireEnum`：`ShapeType` / `StrokeStyle` / `FillStyle` / `PaperType` /
  `TextAlignType` / `BrushType` / `ChartType` / `AttachmentKind` / `NoteBlockType` /
  `EncryptionMode` / `PageTemplate` / `NoteFieldType` / `DatabaseViewType` / `EraserMode` /
  `AllDocKind` / `SingleInstanceStatus`。
- 20 处编解码改走 `wireName` / `wireEnumOf`：14 处 JSON encode（`paperType`/`shapeType`/
  `strokeStyle`/`fillStyle`/`type`/`align`/`chartType`/`kind`/`encryptionMode`/`template`/
  `viewType`/`fieldType`/块 `type`/笔刷预设簿）+ 4 处 prefs（主题模式 ×2、橡皮模式、
  笔刷预设簿）+ **收藏键**（`AllDoc.dedupKey` = `kind:id`，写在 `all_docs_favorites.json`）
  + **审计 action id**（`app.instance_*`，写在 `security/audit.log`）。
- 后两处是**调研时补漏**的：原台账只记了 14 处 JSON encode，没记「枚举名被拼进另一个
  持久化键」这一族——它们的失效方式与 JSON 那 14 处完全一样。

**门禁**：`test/architecture/persisted_enum_wire_gate_test.dart`（62 条）

- 契约层：16 个枚举的每个取值 `wireEnumOf` 往返成立、wire 名唯一，且与 `.name` 逐字相同
  （「零迁移」的自我证明）。
- 源码层：`lib/` 里五种落盘形状（`values.byName(` / `setString(…name…)` / map 值位置
  `.name` / `.name ==` 比较 / 枚举 map 键 `.name:`）零命中。
- 自证：五种形状分别用合成源喂一遍都必须被抓到；`Tag.name` / `File.name` 这类 String
  属性不误伤（名单里每条都要写理由）。

### macOS 平台支持

> 提交链：`0b2ee44c`（macOS 平台 + 算法/依赖升级）→ `a2d98000`（CI 补齐 editor_core 依赖）。
>
> 本版本正式引入 macOS 平台支持：新增 `macos/` Xcode 工程（Runner / 部署目标 13 / Entitlements / Info.plist）、
> `macos-build.yml` CI 构建流水线（macos-latest runner，产物归档为 workflow artifact）、
> 以及 `check_version_consistency.dart` 的 macOS 版本源校验（Info.plist 必须使用 FLUTTER_BUILD_NAME/NUMBER 宏，
> AppInfo.xcconfig 必须含 PRODUCT_BUNDLE_IDENTIFIER）。macOS 产物暂不签名/公证，本地可跑。

### R53 审计三条：同步删除复活 / 加密损坏假死 / `.bak` 恢复失效

> 提交链：`3774842`(fix(blockdoc)) → `d49abff`(CHANGELOG) →
> `4be57c2`(R53 三条修复)。
>
> 三条都按本仓的「突变自证」手法做：**先写回归测试证明现状会红、再修到绿、
> 然后把修复撤掉确认测试又变红**。附一条自我更正：R53 第一版修复把同步的
> **否决语义**（veto）丢了，`tombstone_causality_test.dart:365` 立刻变红——
> 补回否决条件后 251 条同步测试全绿。

**1. 远端「裸 `deletedIds`」被静默丢弃 → 删除复活（HIGH）**

`SyncManifest` 里 `deletedIds` 是「是否已删」的**唯一裁决源**，`tombstones`
只是它的富信息侧（且 `toJson` 只写**带因果**的墓碑）。合并时旧实现只遍历
`remoteManifest.tombstones.values`，把「只有 id、没有 tombstone 条目」的裸记录
全丢了；写回时 `deletedIds: newTombstones.keys` ⇒ 记录彻底消失。下一轮另一端
看到该文档「仅本地 ⇒ 上传」⇒ **删除被复活**——正是墓碑功能要终结的乒乓。

- 改为遍历 `deletedIds`，同时**保留** `!uploadedIds.contains` 的否决语义
  （本地还留着该文档并上传 = 明确主张这版仍在用，远端那条删除记录要被这次
  有据的否决移除）。两处（首轮合并 + CAS 重试）同口径。
- 旁证：第 626-628 行注释声称两处表达式「必须逐字同构」，但远端那支其实
  **少了一半**——注释与代码不符，本仓 R44 修过同类。

**2. 加密文件被截断 → 解锁界面「假死」（HIGH）**

`VaultKeyService.aeadDecrypt` 对 `payload.length <= 28` 抛的是
`VaultUnlockException('密文长度不合法')`，而 `VaultFileCodec` 的对外契约是
`VaultFileException`。调用链：`StorageFilePasswordManager.verifyFilePassword`
只 catch `VaultFileException` → `VaultUnlockException` 逃逸 → `PinPad._submit`
没有 try/catch → **未处理异常**。用户看到的是解锁框没反应（不抖、不报错），
而不是「文件损坏，请重试」。

- 四处 decrypt 路径（`decrypt` / `decryptWithPassword` / `unlockWithPasswordV3`
  / `_decryptPayloadV3`）补 catch `VaultUnlockException` → 转 `VaultFileException`。
- 与本仓已修过的 P2-2 是同一类（`encryption_service.dart:266-280` 有记录），
  在这里还开着。

**3. `.bak` 备份恢复对加密文档失效（MEDIUM）**

`.bak` 回退旧实现只 `on FormatException`（明文解码失败）。加密文档主文件损坏
（载荷截断/被篡改）抛的是 `VaultFileException` ⇒ 注释声称的「正式文件损坏时
尝试备份恢复」**根本不会触发**。加密的正好是它该保护的那类数据，偏偏用不上。

- 补 catch `VaultFileException`；**不** catch 两类 LockException——它们的语义是
  「保险库/文件密码已锁定，读不了」，不是损坏；`.bak` 同样是加密且锁定的，
  回退过去一样读不出，不该静默吞掉。

**验证**：`flutter analyze` 0 issue；`flutter test` **2824 passed / 0 failed**
（+5 条新测试）；CI 全绿（SBOM / PR Architecture / 质量门禁 / Code Guard /
Secret Scan / Push / CI）。

### 批次 2（2026-11-11）：死代码清理 · 混淆回滚 · 文档校验和 · v1 信封迁移

> 本批四项改动不含新功能。**其中第 4 条要求用户手动执行一步**——
> PBKDF2 时代上传的同步数据需要走一次迁移才能继续解密，见该条末尾。

**1. 删除两处死代码（全仓零引用，已逐个 grep 确认）**

- `lib/features/drawing/presentation/editor_viewmodel.dart` 的 `clearTools()`；
- `lib/features/drawing/application/gesture_math.dart` 的 `distanceBetween()`
  （`pinchCenter` / `canvasToViewPoint` 保留）。

两处均无任何调用点、也没有测试引用，删除不改变任何行为。

**2. 回滚 `--obfuscate` 构建参数（HIGH）**

`release-build.yml` / `macos-build.yml` / `weekly-evidence.yml` 的发布命令
原来带 `--obfuscate --split-debug-info=build/symbols`，但全仓仍有 28 处
`runtimeType` 未改造——混淆后审计面与错误文案会变成随机字符串，**CI 抓不到**
（构建成功即绿）。本批回滚参数，并把注释改成回滚理由 + 恢复前置条件
（先完成 CTL-03 ①② 的 `runtimeType` 改造，再单独恢复混淆）。
`build/symbols/` 随之不再产出，对应的三个 "Upload symbols" 步骤一并移除
（注释保留说明）。`--obfuscate` 相关说明同步更正。

**3. 文档整本校验和 `contentHash`（H1）**

`document_codec.dart` 原来对文档正文**没有任何整本完整性校验**：明文模式下
一个比特翻转不会被发现，损坏会静默进 UI。本批给编码快照加 `contentHash`
字段（正文规范化 JSON 的 SHA-256：键递归排序、`int`/`double` 等价归一、
紧凑编码），解码时**在迁移之前**校验——迁移会改写正文（补 `textItems`、
补 `version`、补笔画 `id`、剔除非法 style 键），放到迁移后会把全部存量
哈希误判成不符。校验失败抛 `FormatException`，由存储层沿用既有 `.bak`
回退链（无备份则如实抛出，不静默返回）。

**向后兼容**：老文档没有 `contentHash` 字段时**跳过校验**（空串同样跳过），
打开行为与本批之前完全一致；只是从下次保存起才带上校验和。

**4. ⚠️ 需要用户执行：v1 → v2 同步信封迁移**

同步 KDF 从 PBKDF2-HMAC-SHA256 600k 切到 Argon2id 之后，同口令同盐产出
**不同**密钥，PBKDF2 时代上传云端的老信封全部解不开（解密侧还强制只认
`v == 2`）。修复前唯一的出路是「重新配置同步口令 + 全量重传」——
**云端历史就此丢失**。

本批在 `sync_cipher.dart` 新增迁移工具（`migrateSyncDocumentEnvelopeV1ToV2`
/ `migrateSyncManifestEnvelopeV1ToV2`）：用旧口令派生 PBKDF2 v1 密钥解开
老信封，再用当前 Argon2id 主密钥重封成 v2。迁移**只认 v1**（版本收窄
不可绕过，v2 信封会被拒），失败是确定性的 `SyncKeyMismatchException`
（旧口令已改 / 数据损坏），调用方据此提示重新配置同步口令，不退避重试。
生产解密路径的 fail-closed 口径未被放宽。

> **用户必做**：升级后请用**当年上传时那个同步口令**跑一次迁移
> （入口随下个版本提供；在此之前，老云端数据仍不可见）。若口令已改，
> 迁移会确定性失败——此时只能重新配置同步口令并全量重传，云端历史无法恢复。

## [1.17.67] - 2026-10-15

### 同步处置入口 + 操作日志接入自动保存（收 `v1.17.66` 之后 15 个提交）

> 提交链：`1189a63`(L4 侧车写完必回读) → `79cb349`(Spike C 双实现重放夹具) →
> `35401c3`(A2 接线) → `e1772a5`(豁免层) → `e1b41fb`(处置入口) →
> `9aa44d7`(兜底换入成功分支) → `db581e2`(`syncNow` 抽 part) → `ca9105f`(桌面工具条断言)。

**同步（用户可见）**
- 「云端已删除、本机留着的正是被删那一版」的笔记，现在在同步设置页逐篇给三个动作，
  全部要用户点：另存为新笔记 / 仍要上传 / 认云端删除（进回收站，唯一破坏性的一项，
  必须二次确认并写明 30 天窗口与那个不破坏的替代选项）。程序不替你删本机的任何内容；
  「仍要上传」是一次性豁免——上传成功即失效，读不出豁免时永远偏向继续按住。

**协同地基（用户无感）**
- 画布自动保存把本轮操作追加进 `oplog/<docId>.jsonl`（只在真有新操作时），写完必回读
  校验：不一致就抛错并保住上一份。这是下一阶段增量同步的存储面，本轮没有读者。

**界面（用户可见的真缺陷）**
- 画布左工具条不再两格同时高亮。有**四种**可达组合会同时亮两格，也就是「现在用什么画」
  说不清：吸管 + 橡皮擦、平移手型 + 任一绘制档、形状 + 任一绘制档、连线 + 任一绘制档。
  根因是这条互斥判据被抄了四遍（钢笔/铅笔/高亮/激光各一份，且四份都漏了手型、形状与
  连线），而橡皮擦读的是另一处算好的快照值。现在收成一个判定（`writingActive`，且算在
  `ListenableBuilder` 里面，不再依赖宿主是否重建）。连线模式这一条另有旁证：
  `editor_context_bar.dart:301` 早就把吸管/文字/连线认作同一族「模式激活」，工具条
  那份副本漏了 `linkMode`——同一判据两处各写一遍，就会分叉。
- 形状档补上 `Semantics(selected:)`：它此前只有蓝底视觉、没有语义，读屏用户拿不到
  「形状已选中」（P1-9 补语义时漏了这一格）。
- 同一条命题现在有两处落点：`test/features/drawing/…selected_state_test.dart`
  （CI 会跑，7 条）与 `integration_test/toolbar_test.dart`（真机）。

**验证与工程质量**
- 写路径「改名被拒 ⇒ 删目标再换入」这条兜底腿的**成功分支**第一次有了确定用例。
  原注释声称的前提（Windows 拒绝覆盖已存在目标）经本机实测不成立，所以只能注入。
- `sync_service.dart` 972 ⇒ 896 行：两段最密的对账判据抽成同库 part。抽取过程中的
  突变自证现形一个覆盖空洞——DN-107 那条腿的既有断言只钉「不删云端」，把它摘掉
  247 条全绿；补上「本轮不产生下载」后同一突变当场红（否则受密笔记每轮被重下并覆写）。
- 桌面工具条选中态断言改为读语义（蓝底 + `Semantics.selected`）而非嵌套层数：它在真机上
  自 10-10 起红 5 条，因 CI 从不跑 `integration_test` 而无人察觉（产品侧一行未改）。

### 第四轮审计 R26→R33（2026-10-17，「按推荐档执行」的第一批）

> 提交链：`ef550ea`(R26 拆锁屏 UI + R28 STO-001) → `c02931b`(R30 STO-004) →
> `19fad46`(R31 加密口径) → `84a87e9`(R27 策略死分支) → `0dbe4d5`(R32 文档更正) →
> `9945f1a`(R33 U 盘错映射)。

**用户可见**
- **设过密码又「像没设过」的情形不再被静默重建**。主文件被删/被杀软隔走/崩溃后只剩
  `.bak` 时，输 PIN 的界面长得和「从没设过密码」一模一样，而以前这一步会直接生成一支
  全新随机主密钥——既有加密内容从此永久解不开，旧副本还会在下一次保险库写入时被盖掉。
  现在先用同一个密码**试解旧那一世**（解得开就一支新密钥都不生成），试解失败才弹
  确认框问你要不要重建；你选「先不重建」就什么都不写、照常进界面（导出/恢复的入口
  给你留着），并留下一条「已保留旧保险库」的回执与审计。
- 标签或收藏「文件在、但读不出来」时，界面不再答成「一个都没有」：**覆盖之前已另存的
  那份原件现在会说给你**（带保留件文件名）。拒写那半边按裁决**没做**——损坏的注册表
  被拒写就等于功能永久不可用且没有修复入口，而旧字节已经在 `.corrupt-*` 里，损失可逆。
- **U 盘恢复钥匙坏了，不再报「PIN 错误或密钥载荷被篡改」**。你输入的 PIN 是对的，
  错的提示会把人推向「反复重试开屏密码」这条不对的恢复路径；现在给一条说清是什么坏了
  的具名文案。这条之所以一直没现形：错误文案映射的测试**全部**只走无本地化兜底串，
  13 个 `vaultErr*` 键一次都没被执行过。
- 导出 / 恢复 / 彻底删除被策略拒绝时，真的有提示了。此前那三处判的是恒不成立的分支
  （引擎在拒绝时先抛异常，不返回「不允许」），所以那句提示从没执行过，真被拒时是
  一次未捕获异常。放行路径的行为与白名单一字未改。

**数据安全**
- 上一项把「拒绝重建」变成一种长期状态，而写路径按「主文件在不在」判断有没有建库 ⇒
  三条写腿（画布 / 笔记本图片 / 块文档）会把一个加密世代的内容**静默降级成明文**。
  本轮同时收掉：口径改为「主文件在 **或** 盘上有旧信封」都算已建库（锁定态照常拒绝写入，
  且失败可见），从未设过密码的新用户仍是明文落盘、语义零变化；顺手把原来三行逐字相同
  的闭包收成一处判据，并用「注入点必须恰好 3 处」的分母下限钉住。

**验证与工程质量**
- 锁屏 UI（桌面键盘密码槽 / 冷却倒计时 / 倒计时文本）搬进同库 part，门组件 956→744 行；
  判据与状态机一行没动，只是给上面那些改动腾出行数空间。
- 新增两条形状门禁：`enforceCheck` 的每个调用点必须被 `try` + `on PolicyDeniedException`
  接住（跨全文找 catch 会被自己的 canary 打回——那正是「匹到另一个动作」的假证据）；
  错误文案的具名分支「与通用兜底同形的条数」用计数判据钉（只改 arb 文案的突变 M3 能红，
  逐条比对抓不到）。
- 第四轮 §2 剩下的 9 条 P1 全部逐条回读：推翻 3 条（SYN-01 条件写窗口、TE-TST-01
  root_guard Android 分支、TE-TST-02「生产函数未被调用」）、1 条证实已闭环
  （CTL-02/TE-TST-05 的「算不出变更集就判失明」）、5 条成立或改判并登记。
- 《代码评审规范》四处与代码不符的陈述按逐行回读更正（`--fail-on-review` 实参、测试条数、
  artifacts 保留期「永久」、以及那条从来不存在、下游承诺也落空的「门禁运行周报」）。
- 门禁实录：`19fad46` 与 `9945f1a` 各 **7/7 全绿**（含跑全量的 `CI`）；纯文档提交
  `0dbe4d5` 实测 **6/6**（质量门禁的 `paths:` 不吃文档提交，这条预期写进提交信息并当场对上）。
  每批都做了突变自证：R28 三条、R30 两条、R27 一条、R31 一条、R33 三条，全部从备份还原后
  复跑绿并 grep 确认无残留。

### R35 / R36（2026-10-17，发布链路两道闸门 + 单实例检测诚实化）

> 提交链：`266b356`(CTL-04 前置校验与草稿 + CTL-09 周期补证) → `26728ce`(ASM-02) →
> `5bd9eca`(上一笔 CI 红的根因修复 + 机审门禁)。

**发布（维护者可见，用户无感）**
- **推 tag 不再等于对外发布**：Release 以草稿创建，四件资产挂完之后要人在 GitHub 点 Publish 才公开；
  tag 过滤也从 `v*` 收紧到 `v[0-9]*`（`v-test` 这类误 tag 不再触发构建）。连带效果是有意的——
  `Latest` 只认已发布的版本，所以推 tag 之后公开面上仍是上一个版本可下载。
- 出包前多了一道机器校验 `preflight`：先把 tag **剥成提交**（本仓 annotated / lightweight 两种混用），
  再要求那个提交「没有未通过的编排」**且全量 CI 那条 job 的成功记录在册**——「结论表是空的」不算
  通过。此前这条只是口头纪律（「先确认编排全绿再推 tag」），机器上没有任何闸门。
- 新增每周 + 手动的补证编排 `weekly-evidence.yml`：依赖清单 / 秘密扫描 / SBOM / Windows 发布形态构建 /
  Android 构建。它**不是门禁**——红了不阻断 master，只开一条去重后的待办 issue。
- **出货产物仍未混淆**（`--obfuscate` 没开），这是主动挡下来的：本仓有 28 处在运行时读类型名，其中
  三条错误提示（粘贴 / 插图 / 打开链接）、「保存失败」芯片的错误类型、审计日志的 detail 与 action id
  都会变成每次构建都不同的随机串；而 `flutter test` 与桌面 smoke 跑的都是非混淆编译 ⇒ CI 看不见这个
  坏法，只有装到用户机器上才现形。解锁要先改诊断面，细节写进 `docs/RELEASE_PIPELINE.md`。

**安全与稳健（行为一行未改）**
- 单实例检测（ASM-02）：`main.dart` 文件头与调用点的注释都写着「检测到已有实例则直接退出」，而代码在
  用户反馈「应用打不开 / 工具栏全用不了」之后早已改成永不阻断启动 ⇒ 那条 `return` 是恒不成立的死分支，
  两句注释是对读者的谎。现在把状态拆成三态（拿到锁 / 确认有活实例 / **判不了**）：保守动作不变
  （判不了就不删别人的锁、任何情况都照常启动），说法变诚实（不许把「我不知道」说成「有另一个实例」），
  非「拿到锁」时落一条审计。**没有**把「同机第二个实例」提示给用户：锁文件路径是应用全局而非数据根级，
  且 PID 会被系统复用 ⇒ 判据有固有误差，要先补「同根判定」才谈得上提示。

**验证与工程质量**
- 上一笔的 CI 红（2667 passed / 1 failed）查到根因，**不是 flake**：`home_refresh_fix_test` 的
  `encryptAndSave` 腿吃的是**生产** Argon2id（64MiB t2 p2），而它既没打 `kdf` 标签也没注入轻量参数 ⇒
  多秒级密钥派生被放进「并行主套件 + 30 秒默认超时」。按批B 口径补注入后该用例从 >30s 降到 1s 内；
  同族第二格 `usability_regression_test`（只放宽了超时、没注参数）一并补上。
- 新增机审门禁 `kdf_suite_hygiene_test`：调 `encryptAndSave(` 的测试文件必须二选一（注入 testLight 或
  声明 `kdf` 标签），带分母下限（扫描面 ≥300、认出 ≥5）。分母那条不是装饰——把触发词写坏的突变
  让「判据」用例照样全绿、只有分母用例红，正是「空集即通过」的形状。
- 门禁实录：`5bd9eca` **七编排全绿**（含跑全量的 `CI`）；`26728ce` 之所以没有任何编排记录，是因为它
  与前一笔在**同一次 push** 里（GitHub 只在最后那个 SHA 上开编排），既不是被取消也不是跳过。
  突变自证：ASM-02 两条（M3 不回收陈旧锁 / M4 把探测失败谎报成有活实例）、新门禁两条
  （M1 触发词写坏 / M2 判据空转），各红在预期用例，还原后复跑全绿。

### R38（2026-10-17，DRW-08：分组事务与会话操作日志）

- `_pushCommand` 在分组窗口开着时不再逐条记 op：以前一次图层事务会把同一批操作落**两遍**
  （窗口内单条 + 最外层闭合时聚成的 `OpBatch`），而回滚那条腿只 `undo()` 文档改动、撤不掉
  已经写进日志的 op——A2 那条腿是按水位线把「新 op」追加进磁盘侧车的，所以这段从没生效过的
  操作会真落盘，将来重放/增量同步就吃进去。现在记录点只有一处（窗口闭合）。
- 顺带修掉台账没记的第三处：窗口里混进一条无法表达为操作的命令（形状/图片/快照桥接）时，
  旧写法会留下「半批」——而 `DocumentTransaction.operation` 本来就是**故意**整批不进日志，
  注释写的理由正是「部分记录回放不了」。
- 撤销权威仍是命令栈：历史条目数、undo/redo 语义、通知合并全部未变（既有 8 条事务用例原样绿）。
- 新增 5 条用例（提交=恰好一条 `OpBatch`、回滚不留痕、事务外照旧逐条记的反向锁、嵌套只记最外层、
  混批整批不进）。两次突变各自红在预期用例；本地定向 44/44 绿。

### R40 / R41（2026-10-17，CUJ-01 契约第一次被执行 + 第二族孤儿临时文件开始回收）

- **R40（TST2-04 的 CI 落点）**：回读时发现比「恒真断言」更糟的一格——
  `integration_test/contracts/cuj01.json` 声明了五条断言（`same_document_id / same_stroke_id /
  same_point_count / same_bounds / revision_increases_once`），而**全仓没有任何代码读那份 json**，
  唯一命中是集成用例里那句「由真实存储往返验证」的注释。新执行侧
  `test/core/storage/cuj01_contract_test.dart` 读那份声明、按名逐条跑，且
  「实现名集合 == 声明名集合」**双向**钉死；往返走真实存储并**换一个实例读回**（照 json 里的
  `terminate` + `reopen`，同一实例可能读到进程内缓存）。六现场自证 + 两次突变。
  集成侧那条恒真断言没动：CI 从不跑 `integration_test`，改完当场无法验证 ⇒ 归业主点头。
- **R41（R18 同族的剩余五处）**：`<目标>.tmp.<微秒>.<十六进制>` 这一族有 5 个生产者没人回收
  （标签 `tag_store.dart:217`、收藏 `favorite_store.dart:103`、同步基线
  `file_sync_baseline_store.dart:68`、推送豁免 `file_sync_push_waiver_store.dart:60`、
  保险库对象 `vfs/encrypted_vault.dart:345`）。R18 当时刻意不伸手，因为它需要另一套授权边界；
  现在补的是那条边界（`isStaleSuffixTempName`），**不是**把两族并成「含 `.tmp.` 就删」。
  边界比第一族更窄：十六进制尾巴钉死 16 位（实测五处全部来自 `hexEncode(8 字节)`），年龄线与
  前缀清扫同值（10 分钟，在途写入不抢删），形状不符的一律不碰（正式 `.json`、`.bak`、裸 `.tmp`、
  8 位或 17 位、大写、非十六进制、尾巴还跟着扩展名、目标名为空）。**宁可将来生成器改长度时
  停止回收，也不放宽去误删**。回收由既有的数据根递归扫那条腿执行，五个生产者不必各加触发点。
- R41 的已知缺口如实写着：一个会话只动侧车、从没保存过画布或块文档时，数据根的递归扫不会触发，
  那枚孤儿活到下一次保存——与 `notebooks/` 那两枚同一条已知缺口，不是永久残留。
- 突变自证：M1（16 位放宽成「至少一位」）红在判据表；M3（把第二族从清扫里摘掉）红在接线用例；
  两族互斥那条同时抓住「并成一条」的写法。原有 8 条一条没动，本地定向 11/11 绿。

### R42（2026-10-17，EUI-12 重采的第一条落地：新建的打字笔记补齐「管理密码」与反向链接）

- **用户可见**：从首页新建一条打字笔记后，编辑器里以前**没有**「管理密码」入口、也没有反向链接面板——
  刚写完的笔记想加密得先退回首页再点进去。根因不是能力缺失，是首页那条**新建**腿构造文档页时
  一个相关参数都没传（其余入口都传了）。现在补上 `blockDocStore`，两项能力当场回来；
  既有行为一行没改（首页「打开已有笔记」那条腿一直是好的）。
- EUI-12 那条台账数字更正：skylos 报的「27 个无读者回调」既不是全集也不准——
  真正的无读者契约面是**工具栏契约的 40 个成员**（29 个回调 + 11 个状态字段，能力本身都还在，
  走的是左工具条与属性面板那两条活路）；另有两份 `migrateNotebookPage` 实现，
  活的那份只搬标题与文本、全的那份没人调用（属「迁移不完整」，不是数据丢失）。
  **清理动作一个都没做**（删字段/换实现都归业主点名），台账 §30 记了逐条依据与未复核清单。
- 新门禁 `test/features/doc/doc_page_entry_wiring_test.dart`：判的是 `doc_page.dart` 里那句
  「各入口无需各自接线即可获得完整能力」的**承诺本身**——8 个文档页构造点每个都得拿到这两项能力，
  带分母下限与四形状自证。M2（把新建腿的接线下掉）红在判据用例并指名位置。
- 本地定向 33/33 绿（文档页 / 反向链接 / 密码 / 首页三套件 + 新门禁）。

### R43（2026-10-17，装配类「注释撒谎」四条坐实并改成实话 + 一条新棘轮）

- 用户无感，但关系到「谁还能相信注释」。EUI-12 重采里有四条声称「已装配」的注释，逐条回读代码后
  **全部不成立**：`notebookAccessorProvider` 说「正式装配由 app 层 override 注入」——除注释外全仓零引用，
  恒落空实现；`NotebookAccessorImpl` 说「app 装配点创建本实现」——lib 内零构造，
  真实装配走的是「存储对象自己实现该接口再直传」，这个类因此是冗余包装；
  `drawingDirtyProvider` 说「UI 层可经 ref.watch 自动刷新」——UI 零命中，脏标记是状态栏直读控制器；
  `drawingCurrentLayerProvider` 说「供图层面板接线」——图层面板是无 `ref` 的 `StatelessWidget`。
  **四段注释都改成带 file:line 依据的实话；代码一行没动**（接上或删除都是产品决定，归业主点名）。
- 新增棘轮 `test/architecture/provider_reader_ratchet_test.dart`：`lib/**` 里每个
  `final *Provider` 都必须被 lib/test 的**代码行**引用一次；今天唯一的违规进具名基线（上限 1，只紧不松），
  基线里的名字一旦真有人读就必须删行。分母下限：provider 数 ≥11、扫过行数 ≥20000（实测 39881）。
- 踩到并当场修掉的两格（都进了自证用例）：注释行会被算成读者（我的更正注释里就写着那个 provider 名）；
  门禁自己的基线字面量也会被算成读者（扫描要排掉本文件）。
- 突变：M4（新增一个没人读的 provider）红在判据用例并指名声明位置；M3（往基线塞第二个名字）
  红在自证用例。还原后 `test/architecture` + `riverpod_providers_test` + 文档页接线 35 条全绿。

### R44（2026-10-17，注释类：两条「声称已接线其实没接」改成实话，四条误报被推翻）

- **对用户有一层含义的一条**：整本笔记本导出 PDF **今天没有页脚**。「导出整本」那段文档注释
  原本写着「审计 #38 已接线」，实际唯一的生产调用不传 `footer`（默认关闭），
  真接上的只有画布分页那条路径；测试里传了 `footer: true` ⇒ 绿灯测不到生产缺不缺这一步。
  注释已改成实话，**要不要真的补上这一行接线归业主决定**（会改掉用户拿到的导出件）。
- 另一条：会话操作日志的 JSONL 原本写成「供历史压缩 / 会话导出 / 未来增量同步消费」，
  读起来像至少有一条腿接了——三个消费方今天都不存在（`toJsonl`/`fromJsonl` 只有测试在用，
  诊断导出里没有它）。落盘那条腿是**写入**（A2 已接）。措辞已更正。
- **四条被推翻的子代理误报**（记进台账，不再当待办）：`stroke_service`、`layer_service`
  的注释原文本来就写着「future / reserved / until the next migration stage」；旧
  `plugin_registry` 的「与 core 引擎统一」属实、它声明的是「未来接线用」；
  `doc_link_index.buildBacklinkIndex` 的注释早已自认「生产暂无调用方」。
  ⇒ 教训：子代理报「零调用」基本可信，报「注释撒谎」必须让它引用**注释原句**。
- 本批只改注释：`dart format` 一度把 6 处既有代码折行进 diff，已回退并验证
  「非注释行变化为空」；`test/operation_engine_test` + PDF 导出 + 记录器接线共 30 条全绿。

### R45–R48（2026-10-17，业主「全部推进推荐档」授权的四批：页脚接线 / 样式标灰 / 契约冻结 / 迁移合一）

- **R45 整本 PDF 页脚接上了**（用户可见）：以前从笔记本管理页导出整本 PDF **没有页脚**——
  导出器的注释写着「审计 #38 已接线」，但调用方不传 `footer`，而测试传了 ⇒ 绿灯常年盖住这件事。
  现在整本导出默认带「标题 · n / m」页脚（画布分页导出仍是用户在面板里自己勾，两条口径不同是有意的：
  整本是一步式菜单动作，不再加一层弹窗）。并加了一条**接线**用例：扫 `lib/` 里每个整本导出调用点，
  必须真的传 `footer: true`——注释说接了不算，代码传了才算。
- **R46 打字笔记的粗体/斜体/下划线/链接改成禁用 + 说明**（FDC-03，用户可见）：这四个入口写的行内样式
  今天没有任何读者（块编辑面每块是单一 `TextField` 样式，MD/HTML/PDF 导出都不读 `props['spans']`），
  点下去只有数据变了、界面和导出都看不见。以前是「按了没反应」。现在按钮变灰、tooltip 直接说
  「暂不参与渲染，导出也不会带上」（中英双份新键），已存的样式一行不动。
  判据只有一份：`inlineStylesAreRendered`（domain）+ 共享 helper `styleEntryEnabled`/`styleEntryTooltip`，
  工具条与浮动选区条都从这里取——**接上渲染那天改这一份判据，两个入口自动恢复**。
  用例钉三件事：判据今天为 false、两个入口都接在这份判据上、浮动条四个样式按钮点不动而同一行
  「复制块」照常能点（灰不许顺手把别的能力一起关掉）。
- **R47 工具栏契约字段冻结增长**：实测 `EditorToolbarActions` 43 个字段、`EditorToolbarState` 23 个，
  其中 **40 个没有任何读者**（真用的是左工具条与属性面板那条路）。清理归业主点名，所以本批只加棘轮：
  再往这两个类里加字段必须先删一个或给已有的接上读者，否则当场红。
- **R48「打开为块文档」的两份迁移实现合一**：活的那份（笔记本管理页私有的）只搬标题与文本，
  domain 那份会连画布/图表/图片一起搬（M4 规则 3/4）却只有测试在调 ⇒ 一份判据两份副本、活的偏偏是窄的。
  现在调用点直接用 domain 那份纯函数，私有的删掉；差异如实登记（标题不再多一个 heading 块、
  空白 textItem 不再被丢、块 id 变成确定性形状、画布/图表以占位卡片进块文档、原笔记本页不受影响）。
  加了一条「`lib/` 里只许有一份 `migrateNotebookPage` 实现」的门禁，防止以后再内联第二套。

### R49–R50（2026-10-17，R45–R48 推上去后 CI 红的根因修复 + CTL-03 第①步）

- **R49 修的是自己上一批造成的 3 条 CI 红**（如实登记，不遮）：
  - `notes->doc` 棘轮被 R48 的合一顶到 10>9。**没有抬基线**：那份合一实现住在
    `features/doc/domain` 而它唯一依赖的是 notes 的 `NotebookPage`，本来就放错层——
    搬到 `features/notes/domain` 之后 `doc->notes` 从 1 归 0（棘轮**收紧**），
    R48 新增的那条越界也随之消失；实现「住在哪个目录」进了门禁。
  - FDC-01 的两条用例（点粗体→打字→点斜体）被 R46 的标灰打断：那两条要**点得动样式**
    才造得出 spans 形状。判据从 `const` 改成可读、只允许测试临时置 true 的顶层值，
    用例在 `setUp` 开门、`tearDown` 还原；生产默认仍然点不动（由 R46 的用例钉）。
    「谁能写这份判据」新加门禁：`lib/` 里除声明行以外任何赋值即红。
  - 迁移文件路径断言在 Windows 上被反斜杠判红（本地与 CI 同为 Windows）——路径统一成正斜杠。
- **R50 CTL-03 解锁第①步：诊断面不再运行时读类型名**（出货产物相关，今天不改行为）。
  `lib/` 里 28 处 `e.runtimeType.toString()` / `${e.runtimeType}` 全部改走新增的
  `core/utils/error_code.dart`（`io_file_system`、`backup_integrity` 这类编译期字面量码），
  覆盖 18 个自定义异常 + 7 个标准库类型。形状是**异常自己报一个码**（`CodedFailure` 接口），
  不是「一个文件写一条 `is` 链」——第一版就是 `is` 链，被本仓自己的
  `规则2：零循环依赖` 当场判红：异常类散在六个模块，而这些模块全都 import `core/utils`，
  一份「认识所有异常」的枢纽文件必然与它们互引。改成派发之后枢纽只剩**一条**出向依赖
  （`document_budgets.dart`——它自己立了「零项目内 import」的纪律，那两个类结构上不可能
  实现接口，所以由枢纽单向认识；「出向依赖的每个文件必须零项目内 import」也进了门禁），
  覆盖再无「core 之外算不算」的尾巴：18 个类同一套判据。
  门禁 `error_code_coverage_gate_test.dart` 钉：读名形状归零、每个自定义异常要么实现接口并
  **自己**写码（子类不许继承父类的码）、要么走枢纽那条只限「零项目内 import 文件」的单向链，
  码全库唯一、造得出实例的返回正确且**不带 message/路径**、枢纽的每条出向依赖都必须是
  「自己零项目内 import」的文件（不成环才允许存在）；另有三条合成形状自证。
  `--obfuscate` 仍然没开：解锁顺序的②（落盘枚举显式 wire 名）没做完，开了就是拿
  14 处磁盘格式赌一句 "currently"。
  代价如实说：snackbar 上以前印 `FileSystemException`，现在印 `io_file_system`——
  读起来更陌生，但换到的是「混淆后仍然可读、且每次出包都同一个键」。

### R51（2026-10-18，ASM-02 剩下那一半：同根判定 + 把事实说给用户看）

- 单实例检测的状态从三态改四态：`acquired / sameDataRootRunning / otherDataRoot / undetectable`。
  以前锁文件是**应用全局**的（`<ApplicationSupport>/app.lock`），两个各开各数据根的实例也会
  被判成「同机第二个实例」⇒ 那一格不能对用户开口。现在锁的第二行写数据根路径，
  只有**确认是同一个根**才提示；老版本留下的只有一行 PID 的锁 ⇒ 根未知 ⇒ `undetectable`，
  不猜也不提示。路径比较只做必要的归一化（分隔符、尾斜杠、Windows 大小写）。
- **提示照旧不阻断启动**，而且这次是判据不是承诺：`test/app_shell_instance_notice_test.dart`
  扫 `lib/main.dart`，从取锁调用点到 `runApp` 之间出现任何 `return` 即红（旧写法
  「已有实例就退出」正是用户投诉「应用打不开」的形状）。
- 取锁多了解析一次数据根（会顺带跑「旧位置→ApplicationSupport」的一次性迁移）⇒ 整段包进
  try，失败就退回「根未知」并落一条 `app.instance_root_resolve_failed` 审计
  （detail 用 R50 那份 `errorCode`，顺手 dogfood）。
- 措辞留「可能」：PID 会被系统复用，这条判据有固有误差，只够提示、不够下结论（中英各一条新键）。
- 写入面也钉住了：`instanceStatusAtLaunch` 在 `lib/` 里只允许**一个**赋值点且必须在 `main.dart`，
  `??=` 也算写（漏了它这条就能被绕过去）。

### R52a（2026-10-18，第五轮重新采集 F-01：删笔记失败不再留明文残骸）

- 第五轮 P2 重新采集（上一轮那 ≈80 条正文从未落盘，那条欠账已作废）回来的第一条，
  查的是**我自己 R41 写下的那句注释**：「这几处裸 `.tmp` 的清理归各自那条腿的失败路径」。
  回读代码：媒体那条腿确实有 try/catch 清 tmp；块文档回收站那两条**根本没有失败路径**——
  两枚临时文件（`.meta.tmp` 装着删除时间、回退那枚装着**整篇正文**）的
  `writeAsString` + `rename` 裸在外面。而全仓那套孤儿清扫的判据**故意不收**不带生成器 id
  的形状，`listTrash`/`purgeExpiredTrash` 又只认 `.json` ⇒ 三双眼睛都看不见它。
  磁盘满或杀软占用时，用户删一次笔记就在回收站目录里永久留一份明文残骸。
- 修法：两枚各配一条 `_discardTemp`（尽力删、删不掉也不盖原始异常，与画布那条腿同纪律）。
- 双重落点 `test/core/documents/block_doc_trash_tmp_test.dart`：① 真造一次失败——把侧车的
  目标位置预先做成一个目录，`rename` 到目录上 Windows/POSIX 都会失败（不用往生产代码塞故障钩子），
  然后要求盘上**一枚 `.tmp` 都不留**；② 源码级判据：这条腿每枚裸 tmp 都必须有自己的
  `_discardTemp`（分母下限钉「实测 2 枚」，抽取塌了就红）。
- 突变自证两枪两格红：删掉 `metaTmp` 那条 ⇒ 行为用例红 + 源码判据红；删掉 `tmp` 那条 ⇒
  源码判据红（那一枚今天没有行为触发路径，只有静态判据看得见它）。逐字还原后 5 项全绿。
- `stale_tmp_cleanup.dart` 文件头那句承诺改成如实的「当时只有一条腿成立」并写明本轮补了什么——
  「引用规范文档当理由之前先 grep 那句话在不在」，这条这次轮到自查。

### R52b（2026-10-18，第五轮 UI 采集的两条 P1：按了没反应）

- **全部文档行的 ⋮「更多操作」键盘完全无效**：那颗 `InkWell` 只给了 `onTapUp`。
  `InkWell` 的键盘激活（Enter/Space → `activateOnIntent`）与读屏的 `Semantics.onTap`
  **只回调 `onTap`**，`onTapUp` 是纯指针路径 ⇒ V-05 那次「改 InkWell 自带焦点」只补上了
  Tab 焦点：焦点环亮着、按 Enter 什么也不发生，而这颗钮正是被指定为「长按/右键等价入口」
  的那一颗（AGENTS.md §3 硬性要求）。改成鼠标/触屏/键盘**同一条** `onTap` 路径
  （两条并存时一次指针点击会各命中一次 ⇒ 弹两个菜单），菜单位置从整行 rect 右下角推。
  全仓同形只剩 `apple_pressable.dart` 里那处按压动画记账用的 `onTapUp`（不是可达性入口）。
- **从全部文档/反向链接点开一篇刚被会话锁定的笔记时毫无反馈**：路由层把「锁了」和「没有」
  折叠成同一个 null ⇒ 调用点只能静默 `return`，看起来就是条目坏了。笔记本那条腿在审计一-3
  已修过同一个坑（`notebook_view_page_manage.dart` 那句「但不再静默消失……明确告知需重新解锁」），
  这条腿漏了——本仓的「一修就漏九处」。helper 改成三态返回，锁定那一格复用既有
  `nbNoteEncryptedLocked` 文案（不新造键、不给同一件事第二个说法）。
- 落点：`test/features/all_docs/presentation/all_doc_row_keyboard_test.dart` 五格——
  ① 那颗 InkWell 必须 `onTap != null` 且 `onTapUp == null`（按语义层圈定，整行本身也是
  InkWell，`widgetWithIcon` 会一次抓到两颗）；② **真发一次 Enter**，断言上下文菜单开出来；
  ③④ 路由层的两条源码级判据（三态 + 必须出声）；⑤ 判据自证两种塌法。
  突变两枪三格红：把 ⋮ 退回 `onTapUp` ⇒ 判据格 + 真 Enter 格一起红；
  删掉锁定分支 ⇒ 「必须引用既有文案键」格红。逐字重放后 15 项全绿（含原有层级测试与
  `doc_page_entry_wiring_test`）。
- 本轮踩到一处自己的流程错，如实记：突变用的备份是在**改代码之前**拍的，
  于是「还原突变」把这一批的修复本身也一起撤回了——靠 grep 关键符号（`nbNoteEncryptedLocked`
  计数变 0）才发现。正确做法是备份点必须在「修复完成之后、注入突变之前」，
  且还原后要 grep 的是**修复的标志物**而不是「文件还在」。

### R52c（2026-11-04，一个没用到的局部变量把 analyze 步骤打红）

- `test/features/security/...` 一处局部变量声明后从未被读，`flutter analyze` 的
  `unused_local_variable` 把它标红——**CI 抓到，这是同一类第三次**（前两次分别在
  `test/` 与 `lib/` 各一处）。删掉即可，行为不变。
- 如实记：这条不是「审计发现」，是 CI 的 analyze 门禁发现的；登记在此是为了让
  「同一类第三次」这个事实有落点（前两处都没进 CHANGELOG，只在提交信息里）。

### 修复（2026-11-04，`fix(blockdoc)`：全部文档打开块笔记时的类型错误）

- **现象**：Windows 发布构建与 Android 构建**同时**编译失败（Weekly Evidence 连红两轮，
  开出 issue #54 / #55）。报的是同一个错：
  `app_shell_routes.dart(411,25): error GC2F972A8: The argument type
  '({NoteBlockDoc? doc, bool locked})' can't be assigned to the parameter type 'NoteBlockDoc'`
- **根因**：`_loadBlockDocGuarded()` 早已改成三态返回（`({NoteBlockDoc? doc, bool locked})`），
  而同文件里 `_openBlockDocById()` 是按三态正确解的（先判 `locked`、再取 `doc`）；
  「全部文档」那条分支没跟上，把**整个记录**传给了 `DocPage(document:)`。
  这与 R52b 修的是**同一个坑的另一条腿**——R52b 修的是「锁定那一格被折叠成 null 后
  静默 return」，这条腿是「三态改成记录后调用点没跟着改」。本仓的「一修就漏九处」再次现形。
- **修复**：与 `_openBlockDocById()` 逐字同口径——先判 `loaded.locked`（被锁要出声，
  复用既有 `nbNoteEncryptedLocked` 文案，不新造键），再取 `loaded.doc` 并处理
  null / 未挂载。**没有放宽判据、没有豁免、没有删功能。**
- **验证**：`flutter analyze` 全项目 0 issue；`flutter test` **2818 条全绿**
  （0 failed / 6 skipped）；Android debug APK 本地构建成功；
  Weekly Evidence 三个 job（Windows 发布构建 / Android 构建 / SBOM）全绿；
  push 后的 CI（analyze / code_guard / pr_arch）全绿。
- 落点：`lib/app/app_shell_routes.dart`（`AllDocKind.blockdoc` 分支）。

## [1.17.66] - 2026-10-14

### 第三轮外部专家审计整改（DN-201→DN-208）+ 协同地基 A2/A3 + 批次 D（确定性验证）

> 提交链：`c4e00a1`(DN-203) → `4008647`+`57352b5`(DN-208) → `238136c`(DN-204) →
> `6d0eff7`(DN-201/202) → `45b4674`(DN-206) → `2c1ed2d`(行数硬上限拆分) →
> `c7a97df`(DN-205) → `4d81b1e`(DN-207) → `a091d9b`(A2) → `5c85810`+`6758f69`(A3-1) →
> `8db8a5e`(A3 读者) → `c55dd3b`+`b32e8d1`(批次 D 故障注入与矩阵) →
> `22fa35b`(换入失败回滚) → `b85db3d`(kdf 等待确定化) → `8580c25`(A3-2 甲)。
> 台账：`docs/COLLABORATION_ROADMAP_2026-10-13.md`（§9/§10）、
> `docs/BATCH_D_WRITE_FAULT_MATRIX_2026-10-14.md`。

**数据安全（两条真缺陷）**
- 失败的保存不再让笔记从本地列表与云端一起消失：Windows 兜底「先删目标再改名」在第二次
  改名失败时，以前盘上只剩 `.bak`——读路径能回退所以没人发现，但列表只认 `.json`，
  同步侧「基线有、清单无」会推成用户删除并 `DELETE` 云端副本。现在两条腿（画布/块文档）
  的失败出口都把上一版复制回正文位并留审计痕迹。
- 删除一定带走 `.bak`：回收站两族的删除入口以前会「只剩侧车就判为无此文档」（删不掉）、
  回退分支不清侧车、侧车删除失败要么静默要么把整次删除抛断。现在都能删、都留审计。
  曾考虑的「列表把侧车当成存在」经逐条核实**被否决**——那会复活用户真删的内容。

**同步正确性**
- 同步指纹加内容摘要（DN-206）：同一毫秒、字节数恰好相同的两次不同编辑不再隐形。
- 文档级条件写入（DN-201/202）：正文覆盖写带 `If-Match`/`If-None-Match`，被 412 挡回时
  两份都保留并上报；恢复换根后旧基线先隔离（DN-204），不再触发云端误删。
- 删除墓碑带上因果锚（A3-1），且随清单一起活着（以前每轮全量重写把删除历史抹平）。
- 甲方案（A3-2）：云端已删除、本机留着的正是被删那一版 ⇒ **不再推回云端**；
  本机有独有内容或无从比对时照常上传；全程不删本机任何文件，摘要每轮重复提示。

**协同地基**
- 操作日志磁盘侧车（A2）：`oplog/<docId>.jsonl` 落在数据根内（恢复旧备份时日志跟着回退）、
  按 `seq` 幂等、以盘上文档 revision 为权威截断、锁定态绝不落明文；崩溃窗口用时序屏障钉死。
  尚未接进保存路径（棘轮库只剩 1 行余量，且现在没有读者）。

**验证**
- 写路径崩溃/故障窗口矩阵入库；批次 D 补上「正常保存腿」的故障注入与崩溃残留一格。
- CI `--tags kdf` 分片随机红的根因修掉：等懒迁移从掐表改成确定信号，诊断改报实际用时。

**托管图片回收认侧车**：处于「正文缺失、只剩 `.bak`」形态的画布，其图片以前会被当
无引用孤儿回收掉（画布还能读回来、图真没了）。现在引用面认这一格，同时保留
「正文在时上一版侧车不算引用」的边界，免得回收退化成只增不减。

**仍未做（诚实清单）**：A3 乙（让删除赢、清掉本机那份——会移除用户内容，需点名）；
A2 接线；批次 D 剩余
（块文档腿的 tmp 写入注入未铺开、Windows 删除-换入成功分支仅 Windows 可验、
写完回读校验未加、双端互通）；三个 spike；tag 与 Release 未推（等业主点名）。

## [1.17.65] - 2026-10-13

### 内核升级（P0a→P1）+ 两轮外部专家审计整改（DN-001→DN-009、DN-101→DN-108）+ 工程文件格式 v4

> 收 v1.17.64 之后的 32 个提交：`907557a`(AW21) → `cf34bd8`…`3f1a91b`（内核 P0a/P0b/P0c/P1）→
> `a90176b`…`dd7a740`（第一轮外部再审 DN 批）→ `7084be9`（第二轮专家审计 8 项，PR #53）→
> `c7aa7a4`(格式 v4) → `0b6c697`+`3c56e55`（跨端契约夹具）。
> 台账：`docs/EXPERT_REVIEW_REMEDIATION_PLAN_2026-10-10.md`（逐条对照代码核实，13 项校正、11 项列 backlog）。

**用户可直接感知**

- **形状线型与填充各多一档（格式 v4）**：新增点线（dotted）与交叉线填充（crossHatch），
  手绘形状也能显式关掉斜线——这三样此前被 `dash`/`rough` 两个布尔挡着，表达不出来。
  入口沿用工具条与属性面板上原有的两个按钮：线型三档循环（实→虚→点）、填充四档循环
  （无→实心→斜线→交叉），鼠标 / 触屏 / 键盘同一条路径。**旧文件重存不长任何新键。**
- **新文件不再被旧版本悄悄改样**：`latestVersion` 升到 4，旧版本读到 v4 文件明确拒绝并提示升级，
  而不是把点线画成实线、把交叉线画成实心（本仓纪律：严禁静默丢数据）；v3 及更早照常打开。
- **受密笔记锁定后不再被同步误删云端副本（DN-107，P0）**：读不出来的文档一律不算「用户已删除」，
  按基线快照原样带回清单——此前锁定一次，云端就被真删一次。
- **恢复失败不再「笔记全没了」（DN-103）**：换根失败时把旧根回滚回原名并落持久化留痕
  （不用内存态 AuditLogger——恢复失败恰恰是跨重启才需要看的事件）。
- **画布文档不再「写出自己都读不回」（DN-003，P0）**：9 项防御预算此前只在解码侧，编码侧一条上限
  都没有 ⇒ 一层画满 1 万笔后重开就静默截断，5 秒防抖还把截断内容覆盖回正式文件。现在读写对称、
  截断态失去覆盖原件的资格，并给用户处置入口（DN-003ui）；`flush` 也返回真实落盘结果（DN-005）。
- **备份与同步的六处口径**：打包改流式不再全量吃内存（DN-105）、换根必须真是可用数据根且有界解压
  （DN-004/DN-006）、失败不再删掉用户选中的既有备份（DN-R04）、多设备并发不再互相覆盖清单
  （DN-104，`If-Match`/ETag 条件写 + 412 重读合并重试）、基址少写尾斜杠不再被误拒（DN-106）、
  WebDAV 响应体分档流式限额 + 同步轮次单飞互斥（DN-008/DN-002a）。
- **审计口径诚实化（DN-009）**：对外表述改为「篡改可检测」，不再写「不可篡改」；
  `AuditLogger` 自此落盘 `security/audit.log`，真机可事后取证。
- **真机**：数据根加构建期隔离口，集成测试不再写用户真实库（AW21）；锁定/生命周期真机用例 3/3 绿
  （AW22），台账 §六 开放项 1 关闭。

**内核（P0a→P1）**

- 渲染热路径接入 `StrokeBuffer` 紧凑视图 + 性能基线套件（P0a）；`_computeStrokeBounds` 摘除失效参数。
- 格式 v3 给笔画补持久 id + v2→v3 迁移（P0b）；文档迁移框架落地并接进 codec，v1→v2 兼容语义显式化（P1）。
- Operation Engine 第一阶段：可序列化操作模型 + 影子日志 + 命令提交点接线（P0c）；
  等价性测试固定文档时间戳，Windows 毫秒粗时钟曾掩盖的 CI 微秒差不再误绿。

**门禁与安全**

- 安全扫描拆域（DN-102）：secrets 域恢复阻断、死代码域仅归档报告并写 job summary——此前 job 级
  `continue-on-error` 把 definite 安全问题吞成 workflow success，与《部门级 Code Review 规范》冲突；
  `docs/CODE_REVIEW_POLICY.md` 口径同步。经 `workflow_dispatch` 突变自证：旧失败条件下
  `--gate --secrets` 退出码 1、`--gate --danger` 0，SARIF 复核拆域零损失。
- 监听器拆除源码守卫（DN-101 / DN-003ui-r）：extension 成员代次曾让 `removeListener` 失效
  （监听累积、云端 20 条红的真因），收口成 State 稳定字段，守卫测试突变自证 9 → 0。
- `tools/code_guard.py` 行数门禁对齐 `.sloc-guard.toml` 已有的 `lib/l10n/**` 生成代码豁免
  （PR Quality 由恒红转绿，error 3 → 0）——对齐项目自己已裁决的决定，不是放宽门禁。
- **跨端契约夹具（新增可执行门禁）**：11 个夹具 + 同一份 `manifest.json` 期望值，桌面端
  `test/fixtures/v3/` 与网页版 `tools/interop/fixtures/` 各跑一遍，网页侧 runner 另做逐字节目录比对。
  `eraser-stroke.json` 钉住像素橡皮的格式口径——擦除轨迹就是一条 `type:"eraser"` 的普通笔画
  （`BrushType.eraser` 同一键），某一端丢了它，等于把用户擦过的地方重新画回来。
  `.gitattributes` 把这套夹具钉死 LF / 二进制不转换：否则 autocrlf 检出会把「两端同一份」
  这条断言自己改红（本批 rebase 后当场复现过一次）。

**验证**

- 本地（rebase 到 `7084be9` 之后）：`flutter analyze` 全树 No issues found（51s）；
  全量 `flutter test --exclude-tags kdf` **2303 条全绿、1 跳过**（294s）；版本一致性校验通过。
- 云端（裁决源）：`3c56e55` 七项全绿——CI（2303 tests）、软件质量工程门禁、PR Architecture、
  Code Guard、SBOM、Secret Scan、Push on master。
- 网页版（同工作区 `drawing_notes_web/`，不进本 CHANGELOG 的门禁口径）：`tsc` 0 错；
  同一批契约夹具 11 例 + 预算 14 项；`.excalidraw` 旁路回归（导入 / 导出 / 往返幂等）；
  离屏画布实测像素擦除——擦除带少掉 14,459 个墨像素、纸面背景未被穿透、撤销后逐像素复原。
- **一次红，判定为既有脆弱点**：本 SHA 首跑软件质量工程门禁红在
  `storage_staleness_guards_test`「迁移排队后文档被删除 → 不复活」（`Expected: false / Actual: true`）。
  同 SHA 重跑转绿、本地单跑与全量均绿；该用例的失败窗口是「入队迁移的重读校验通过后、真正落笔
  之前文件被删掉」⇒ 归因为**既有竞态脆弱测试**，非本批引入。
  对照记录（免得以偏概全）：该工作流 10-12 的另五次红**不同因**——四次红在静态分析
  （analyze）步（`a5a4887` / `b7b70bf` / `0d20acb` / `58a5e62`），一次红在 `sync_service_test`
  的 DN-104 并发用例（`0380dff`）。也就是说本 SHA 这条脆弱测试是**首次现形**，不是已知旧红重现。

**仍待处置**

- `roundness` / `frame` / bound text 三项语义未定，v4 刻意不加键；`crop` 明确**不做元数据字段**
  ——桌面端裁剪是烘焙像素覆写同一文件并留 `.bak`，再加一份 crop 等于造第二套真相。
- 上述脆弱测试应改成确定性（给排队写入加显式屏障，而不是靠删除抢时序）。
- 桌面端样式入口仍是循环式（两按钮轮流切档）；显式三选面板属 UI 排期，未随本批做。
- 网页版像素擦除轨迹与 `.excalidraw` 旁路的已知损失（官方无透明擦除笔画、无图层概念）
  已在网页版导出对话框内写明，桌面端无需重复承载。

## [1.17.64] - 2026-10-08

### 审计批 AW14→AW20：v1.17.63 发布说明里挂的 4 条「仍待处置」全部销账（无新功能，全是数据与锁定收口）

> 收 v1.17.63 之后的 9 个提交：`6a3b1a4`(AW14) → `61792e2`(AW15) → `1436a6b`(AW15b) →
> `eb48ad4`(AW16) → `f7332e3`(AW17) → `0771283`(S-05) → `885e06a`(AW18) →
> `2e172e5`(AW19) → `ba02945`(AW20)。台账：`docs/audit_2026-10-05.md` §五–§六。
> 至此 AJ→AW19 两轮审计的 **P1/P2 无挂账残留**。

**用户可直接感知**

- **导出不再静默缺图（AW14）**：页面图片总字节超过 48MiB 缓存预算时，PNG/PDF/整册/缩略图
  产物会缺图且没有任何提示。导出腿改为逐张「解码→绘制→立即释放」，并按**输出光栅真正需要
  的分辨率**定档解码。预算数值一字未动——没有靠调大预算掩盖边界。
- **切后台/最小化这条锁更准（AW15 / AW15b / AW17）**：原生文件对话框抢焦点期间失焦仍不算
  切后台（不假锁）；但**对话框关闭时人已离席**的情况下，宽限期从那一刻起表，等满宽限没回前台
  就真的落锁且不给宽限资格（修复前是「既不锚表也不置锁 ⇒ 永远不锁」）。选择器调用方漏复位时，
  5 分钟 TTL 到点由锁门自己复核失效（免死金牌不会永续）。笔记本媒体密钥链路同口径补齐。
  宽限内回来（每次正常导出/导入的主路径）**全程不出现锁屏闪现**。
- **保险库解锁失败不再全程无感（AW18）**：PIN 已通过但密钥没到手时，除了审计留痕还会弹
  可见提示（复用设置页同款文案）。取舍是**降级进入 + 可见警示**，不把人关在门外——
  否则保险库文件损坏的用户连导出/恢复的入口都没有。
- **打字笔记（块文档）不再被锁定态自动保存覆盖成明文（AW16）**：`DocPage` 的防抖/退避定时器
  在锁屏期间照常开火，此前会把密文笔记静默写成明文（标题、标签从此在锁定列表里可见）。
  现在与画布/媒体同口径 fail-closed，解锁后自动重试自愈。

**架构与清理**

- 两套插件注册表收成一份引擎（AW19）：`core/plugins` 的 DrawingPlugin 引擎为单一事实来源，
  drawing 域的 B3 注册表降级为笔刷/工具**类型化门面**，公开 API 与「同 id 覆盖」语义不变，
  既有 10 条测试零改动。
- 按授权删除零生产调用的 legacy 明文媒体迁移器（S-05 收尾，102 行 + 其唯一消费方测试）。
- `cuj_01` 真机用例与真实 profile 解耦（AW20）：画作标题带运行时刻，不再被上一轮残留的同名
  文档撞断言。

**验证**

- 云端（裁决源）：`6a3b1a4` 7/7 success；`2e172e5` 7/7 success；`61792e2` 首推
  **2 项红**（进程级静态自持 TTL 定时器 ⇒ 无关 widget 用例被「Pending timers」判红），
  `1436a6b` 修好后 7/7 success。
- 真机（Windows）：`smoke_test` 4/4 绿；`cuj_01_test` 修复后 1/1 绿。
- **未验**：Android 设备级（本轮无设备可连）；`toolbar/feature/doc_lifecycle` 三条真机用例未跑。
- 仍待处置：① 锁定与生命周期在 `integration_test` 里**仍零正向覆盖**——本轮写过一条真机锁定
  用例后**主动撤回**，因为它会把调试窗口弹到使用者屏幕并往真实数据根写文档，需先做数据根隔离
  再重开；② 插件能力接口（`PluginContext` 目前只有 `log()`）待产品/架构口径，因此注册表
  仍无生产装配点；③ `AuditLogger` 只在内存（真机不可事后取证）。

## [1.17.63] - 2026-10-06

### 审计批 AV→AW13：修好「从未设置 PIN 的用户完全存不了画布」这个 P0，真实落盘测试补上三条静默丢数据

> 收 v1.17.62 之后的 16 个提交：`dd6cd41`（AV 防抖取证）→
> `694e5d7` + `7c4e14f`（drawing v2 服务与渲染阶段接入）→
> `542ea5a`…`af4bb37`（AW1–AW12）→ `1ccbb8e`（AW13）。
> 台账：`docs/audit_2026-10-05.md` §四–§五。**P1 四条（P1-1…P1-4）全部闭环，
> P2 五条中四条闭环，仅剩 P2-1**（锁定期限归零时主动置锁，属「安全策略变严」方向，
> 需设计确认，本批未动）。

**用户可直接感知的修复**

- **P0 `9cda07b`（AW8）**：从未设置过 PIN / 保险库的用户，画布文档一次都存不进去，
  首页也没有缩略图，往笔记页面插图同样当场失败。真机取证（`cuj_01_test` 由红转全绿）
  确认根因是写路径把「取不到密钥」一律判成「保险库已锁定」并抛异常，而「未建库」是合法稳态。
  现在两条口径分开：**未建库 → 明文落盘**（与笔记块文档同口径，产品设计）；
  **已建库但本会话未解锁 → 继续 fail-closed**（写明文会把该用户既有密文降级）。
  未注入探测器的默认值仍按「已建库」处理，新增的可选参数不是 fail-open 后门。
- **`1ccbb8e`（AW13）**：保存失败从「只有日志知道」变成用户看得见的常驻状态——
  第一次失败就点亮状态芯片并提示一次，退避放弃后措辞升级为「请重试或手动保存」。
  上面那个 P0 能潜伏两个月，直接原因就是重试链静默：调度器一直在重试、审计一直在记，
  只有用户不知道，于是继续画、继续丢，直到重开才发现内容没了。
- **`677ec3b`（AW9）**：遗留 v4 笔记本密码信封输错密码时异常穿透到 UI，
  表现为「点了没反应」；现在归一成 `FormatException('密码错误或数据已损坏')`。
- **`ab23dcc`（AW5）**：图层面板的显示/隐藏、透明度、重命名、合并、删除等操作
  **不置脏、也不排保存**——改完关掉就丢。由真机集成测试抓到并修好（同时把工具条
  的存储注入换成真实临时目录，见下）。
- **i18n 残项清账（AW10–AW12）**：备份/恢复 12 键、同步进度 12 键、
  画布左工具条 8 个 tooltip 全部接入 arb；同步进度文案原先写死在 `core` 层的中文里。
  AW12 保持 zh 输出串逐字不变，因此三个按 tooltip 文案定位的集成测试一行未改。

**静默丢数据（由新写的真实落盘测试逼出）**

- **`2015663`（AW2）**：`DocumentCodec` 反序列化漏掉图层的 `seed` / `version` /
  `versionNonce` 与页面 `textItems` ⇒ 保存重开后程序化填充图案与文字项静默消失。
  补两条真实落盘往返回归（绘制→撤销→重做→保存→重开，逐字段核对内容）。
- **`542ea5a`（AW1）**：图片缓存只有一张图且它自己超预算时会被「自我淘汰」，
  于是每帧反复解码；`invalidate` 也不作废在途解码。修边界，**没有靠调大预算掩盖问题**。
- **`bd0f2b7` + `87d7cc7`（AW4/AW6）**：集成测试的存储注入原本是 `throw`，
  任何真走保存的动作都会当场炸——于是所有断言只能停在「界面没抛异常」。
  ⇒ 结构性教训：**被注入成「一定炸」的依赖 = 该条链路等于没有测试**。

**架构与门禁（AW3 / AW7）**

- 图层事务 `beginLayerTransaction / commit / rollback` 落成真实语义
  （一批操作 = 一次撤销；回滚按逆序撤销并丢弃分组），不是加一个布尔标记就宣布完成。
- drawing v2 服务层与 5 段渲染管线接入（`694e5d7` / `7c4e14f`），控制器对外 API 保持。
- 消掉两处 DCM `Long Parameter List`：按职责收敛参数（图层面板改传 `Layer` 本体，
  事务钩子拆成 `bindTransactionOperations`），**没有压阈值、没有加 ignore、没有放宽断言**。

**验证口径**

- 云端（裁决源）：`9cda07b` + `677ec3b` → 7 编排全 success；`af4bb37` → 7/7 success。
  AW13 与本号提交的全量以本提交自身的 CI 为准，不超前声明。
- 本地：`flutter analyze` No issues；`metrics analyze lib`（DCM 5.7.6，332 文件）no issues；
  非 KDF 全量 2137 通过 / 1 跳过；KDF 串行 67 全绿；真机
  `cuj_01` / `doc_lifecycle` / `toolbar_test` / `feature_test` / `smoke_test` 全绿
  （各批对应的断言数见台账）。
- 仍待处置（不影响本号发布，见台账）：P2-1；`NoteBlockDocStore` 写路径在
  「已建库但锁定」时仍明文落盘（fail-open 方向，需先证锁状态下笔记正文可达性）；
  导出缺图的逐张解码方案；插件注册表与 B3 旧注册表统一。

## [1.17.62] - 2026-10-05

### 审计批 AR→AU2：审计收尾五项落地、D-14 两梯队棘轮化、E-02 决策实施、集成测试真机归绿 + 六域并行复核报告入库

> 收 v1.17.61 之后的 9 个提交：`260179a`（AGENTS 工作目录改指 D 盘）→
> `6d0a033`（AR）→ `c8de3ca`（AS）→ `8e387ff`（E-02）→ `ca70319`（AT）→
> `13942ea`（AU）→ `613e6a5`（CI 预算）→ `2c983d2` + `344912b`（AU2）。
> 各批本地 `flutter analyze` 均 No issues found、被改域测试全绿；全量按
> AGENTS.md §6 云端验证纪律交 CI 裁决。本发版日 CI attempt 1 在 Real-KDF
> 套件单测超时（懒迁移用例），attempt 2 同代码重跑全绿归因 flake——结构性
> 诱因（wait_encrypted 内部 deadline 与库级超时等长）已立台账
> `docs/audit_2026-10-05.md`（T-P2①）待下批修复。

**审计收尾（AR `6d0a033`）**

- 插入图片入口补回：编辑器工具条恢复插图入口（`edInsertImage` 等 3 对 arb 新键，zh/en 各 1080）
- S-10 明文感知：未设 PIN 时设置页常驻「未加密形式保存」明示（`app_lock_settings_page.dart:111-125`）+ 首启引导补 `obSecurityTip`（`onboarding.dart:122`）
- S-05 迁移器 fail-closed：`migrateLegacyMedia` 增加 DNV 信封与未知头部判定（`notebook_storage.dart:484-494`），非明文 DAN 载荷一律跳过并记审计——拆掉「接线即双重加密」的雷；仍保持生产零调用，删除需用户授权（与台账一致）
- T-01 孤儿收口：回收站孤儿 `.meta.json` sidecar 回扫清理路径补回归锁
- D-14 间距棘轮门禁立表：`test/spacing_token_ratchet_test.dart` 具名基线 + 未登记文件上限 0 + 表腐化双向防护 + 反向锁

**设计令牌 D-14 两梯队收敛（AS `c8de3ca` + AT `ca70319`）**

- 第一梯队：15 文件 82 个裸间距调用点换 AppleSpacing 令牌，零数值改动（档位映射逐一对上 xxs4/xs8/sm12/md16/lg24/xl32）
- 第二梯队：44 触控热区立 `AppleTouch.minTarget` 具名常量（`apple_design.dart:166/181/194`），棘轮基线 329→310（=当前实测，诚实口径）

**工程化（E-02 `8e387ff` + CI `613e6a5`）**

- E-02 决策实施（钉版+降级）：DCM 激活失败从静默通过改为 `::warning::` + Step Summary 可见告警，门禁工具可用时真违规照常红拦截（`ci.yml`/`quality_gate.yml` 拆 `dcm_install` 两步）
- CI job 预算 30→45 分钟：慢 runner 日不再把 DCM 步骤连带砍掉

**集成测试真机归绿（AU `13942ea` + AU2 `2c983d2`/`344912b`）**

- 修集成测试运行时类型假设：toolbar_test 真机由 5 红转 7 绿
- 三处真实缺陷修正（不掩盖剩余红）：数据根（集成验证路径与生产 `_baseDir()` 回退源错位）、图层面板断言（改 findsNothing→tap→findsOneWidget 更强断言）、真实时钟等待（抽 `integration_test/real_wait.dart` 共用）
- 新增 CI 判据：`doc_autosave_roundtrip_test.dart` 守「编辑正文必须触发保存调度」腿（此前无人守）；「真机编辑未落盘」分歧仍悬置待真机定性（见审计报告 P1-4）

**审计报告入库**

- `docs/audit_2026-10-05.md`：六代理并行复核（S+R / C+E / P+V / D+M / T / L）。台账 134 条：132 闭环属实、零假闭环；S-06 仍存（签名，外部决策）；D-15 降级部分闭环（白系捷径 7 处残留）。新发现 4 P1 / 5 P2 / 14 P3（含 3 存疑待裁决），无发版阻塞项

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
