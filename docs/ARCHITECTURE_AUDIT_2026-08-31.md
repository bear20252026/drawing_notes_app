# 架构专项审计报告（2026-08-31）

> 重点：架构合理性 / 耦合 / 可维护性 / 重构方案。方法：硬指标采集（跨 feature 依赖矩阵、  
> core 纯度、单例扫描、文件规模）+ 双并行代理深挖 + 人工复核。**本次审计发现并已修复 1 个  
> P0 级生产 bug**（见 Q1）。

## 总体评价

架构基本面优秀：core 对 features 零依赖、单一 UI 方言、feature 内四层  
（domain/application/infrastructure/presentation）执行到位、唯一单例（VaultService）合理。  
**主要债务集中在「notes 模块职责混杂」与「doc_editor 巨类」两点**，均为可控的重构项，  
无一处循环依赖。

模块规模：drawing 91 文件/18.7k 行 · notes 55 文件/13.2k 行 · doc 21 文件/6.4k 行 ·  
all_docs 10 文件/2k 行 · schedule 5 文件/1.1k 行。doc_editor.dart 2119 行为全库最大文件。

---

## Q0 · 审计中发现的 P0 生产 bug（已修复，f260ac6）

`app_shell.dart:98 _bumpDataVersion()` 方法体被 P1 批次的"全局替换  
`_dataVersion.value++` → `_bumpDataVersion()`"误伤为自递归——**任何文档页退出即栈溢出  
崩溃**，v1.4.0/v1.4.1 安装包均受影响。测试未抓到的原因：smoke 用例只验证"打开"，未验证  
"操作→返回"完整生命周期。已修复并补回归用例（`test/app_shell_smoke_test.dart`）。  
**教训已入档：全局标识符替换必须排除定义处自身；回归测试必须覆盖完整生命周期。**

---

## 高优先级（架构结构性，建议本迭代内做）

### Q1. notes 模块三类职责混杂（耦合度：高；工作量：中）

- **证据**：notes 55 文件实际混装三类互不相干的子系统：
  1. **块编辑领域模型**：`domain/note_block*.dart`（NoteBlock/NoteBlockDoc/NoteBlockEditor/  
     text_span_editor/note_block_history 等，doc 模块 20+ 文件全部依赖它们）、  
     `infrastructure/note_block_doc_store.dart`（doc 模块的存储，却在 notes）；
  2. **edgeless 无限画布页**：`domain/edgeless_doc.dart`（930 行）+ edgeless_page*/  
     edgeless_controller（约 2.5k 行）；
  3. **笔记本旧体系**：`infrastructure/notebook_storage.dart`（564 行）+ NotebookPage 系。
- **影响**：领域模型归属错位——块编辑（doc 模块）是 NoteBlock 系的唯一重度消费者，但其  
  模型/存储/历史/转换器全挂在 notes 名下；notes 自己的 edgeless/笔记本体系反而依赖这些  
  块模型，形成「消费方与所有方倒挂」。
- **重构方案**（依赖方向单向、无循环，可安全拆分）：
  1. `git mv` 块编辑域模型 9 文件 → `lib/features/doc/domain/`；store → `doc/infrastructure/`；  
     转换器（markdown/history/text_span_editor）随行。约 40 处 import 重写（脚本化，参照  
     core/canvas_model 迁移先例）。
  2. edgeless 系（约 8 文件）→ `lib/features/edgeless/`（若后续嵌入笔记画布，可再评估  
     并入 drawing）。
  3. notebook_storage/NotebookPage 维持在 notes（旧体系收敛后可整体退役）。
- **收益**：notes 收敛为「笔记本旧体系」单职责；doc 自持领域闭环；"doc 寄生 notes"清零。

### Q2. app_shell.dart 职责膨胀（耦合度：中高；工作量：小）

- **证据**：13 个方法 + 6 个字段，承担：底部导航装配、三目的数据源装配（\_loadAllDocs/  
  \_loadAllBlockDocs + 缓存）、数据版本通知（\_dataVersion/\_bumpDataVersion）、5 个 store  
  实例管理、回收站路由、反向链接点击路由、标签注入、收藏联动。
- **方案**：抽 `AppServices` facade（core 层不可行——含 UI 路由，放 `lib/app/`）：
  ```dart
  class AppServices {
    // store 实例、bumpDataVersion()、loadAllDocs()、loadAllBlockDocs()、
    // openDocById()、openTrash() —— shell 只剩导航与装配。
  }
  ```
  通过构造参数注入 DocPage/HomePage 等页面，替代当前逐参数传递（tagStore/blockDocStore/  
  allDocsLoader/onOpenDocById 四参数已开始在 DocPage 间扩散）。
- **收益**：新增功能不再往 shell 堆方法；页面装配参数收敛为单个 services。

### Q3. 编辑器退出/脏状态双实现（耦合度：中；工作量：小）

- **证据**：`doc_page.dart` PopScope（canPop: !\_pendingChanges + saveNow flush）与  
  `doc_editor.dart:1097` chrome 模式 PopScope（\_showExitDialog 确认框）两套并存，脏判定  
  分别是 `_pendingChanges`（shell 保存链）与 `_isDirty`（editor 内部）。
- **方案**：统一为 editor 单一脏事实源 + 可插拔退出策略（`onWillPop: saveAndExit |
  confirmDialog`），DocPage 与 chrome 各传策略。
- **收益**：消除两处脏判定漂移的风险（P0-H2 的 flush 逻辑 chrome 模式就没有）。

---

## 中优先级（可维护性，建议排期）

### M1. doc_editor.dart 2119 行巨类（工作量：中）

- 结构：State 内混装 块渲染/键盘处理/slash 菜单/选区工具条/撤销/资源管理/工具栏 7 组职责。
- 方案：按 all_docs_page 先例拆 4 个 part——`editor_blocks.dart`（渲染+资源）、  
  `editor_keys.dart`（键盘+IME）、`editor_history.dart`（撤销+合帧）、  
  `editor_overlays.dart`（slash+选区工具条）。逻辑零改动，仅物理切分。

### M2. 文档实体命名族谱混乱（工作量：大，收益在长期）

- 「文档」概念现存 5 种命名：NotebookPage（旧笔记本）、NoteBlockDoc（打字笔记）、  
  EdgelessDoc（无限画布）、DrawingDocument（画板）、SyncDocument（同步载荷），另有  
  NoteBlockDocHeader/SearchIndex/SyncStore 派生族。
- 方案：不批量改名（回归风险大）；**冻结增量**——新实体一律语义化命名并写入  
  ARCHITECTURE.md 命名表；旧名随 Q1 拆分顺路迁移（NoteBlockDoc 系随 doc/domain 自然  
  更名 BlockDoc 的机会窗口）。

### M3. 「全量加载所有文档」loader 三处重复（工作量：小）

- `app_shell._loadAllBlockDocs`、`doc_page._effectiveAllDocsFuture`、  
  `search_page` 内联——同一 `listIds+loadDocument` 循环写三遍。
- 方案：抽 `NoteBlockDocStore.loadAll()`（放 store 自身），三处调用之；  
  配合 P1 的头信息缓存，反向链接索引改用 `listDocHeaders`+按需加载全文。

### M4. AlertDialog 样板 33 处/20 文件（工作量：小）

- 取消/确认双钮 + 尺寸 360 的信息对话框模式重复。
- 方案：抽 `AppleDialog.confirm(context, title, content, {confirmText})` 到  
  apple_design，逐处替换（可渐进）。

### M5. 死代码（工作量：小）

- `doc_link_index.dart` 的 `outgoingLinksOf`/`buildBacklinkIndex` 生产零调用（仅测试）。
- 方案：标注 `@visibleForTesting`，出链面板功能落地时转正；或直接删除。

---

## 低优先级 / 正面结论

- **正面**：core 纯度零违规；Store 构造模式统一（directoryProvider 注入 + 默认目录）；  
  中文注释覆盖率 100%；风格整体一致；Apple* 组件使用无需强规则（稀疏但合理）。
- **无需整改**：drawing 的 editor_page 系 5 文件实为 part 拆分（单一 State），结构合理；  
  schedule 模块自洽零跨依赖；document_object_editing_session.dart 职责单一。
- HomePage 的 loadDocs fallback 路径建议标注 `@visibleForTesting`（遗留小项）。

---

## 重构路线图（按优先级与依赖排序）

| 批次         | 内容                                                    | 工作量   | 前置                |
| ---------- | ----------------------------------------------------- | ----- | ----------------- |
| **R1（立即）** | Q0 递归修复 ✅ 已完成（f260ac6）                                | —     | —                 |
| **R2**     | Q2 抽 AppServices facade + Q3 退出策略统一 + M3 loadAll() 收敛 | 各小    | 无                 |
| **R3**     | Q1 块编辑域模型迁 doc/domain（脚本化 import 重写 + edgeless 独立模块）  | 中（半天） | R2（减少迁移后再改 shell） |
| **R4**     | M1 doc_editor 四 part 拆分 + M4 对话框组件 + M5 死代码           | 各小    | R3（拆分后行数减半再做）     |
| **R5（长期）** | M2 命名冻结与渐进迁移                                          | 持续    | R3                |

R3 是唯一中等工作量项，其余均为小步快跑。每批次保持"1324+ 测试全绿 + analyze 0 问题"  
的提交纪律。

