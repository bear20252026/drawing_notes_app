# 三开源项目源码精读与本地化适配报告（2026-08-15）

> 精读对象：完全匹配三项目源码（本地 `D:\write\1\research\`）。
> 原则：成熟度优先、桌面（Windows）+ 移动（Android）双端兼容、许可合规
> （flutter-quill Apache-2.0 / scribe_canvas MIT / iwb_canvas_engine MIT）。
> 方法：逐文件精读核心机制（数据模型/渲染缓存/事务写入/序列化），
> 对照本项目（engine 自研、249 测试基线）确定适配点。

---

## 一、flutter-quill（Apache-2.0，2.9k star，最成熟）—— 富文本升级参考

### 1.1 源码精读结论
| 模块 | 机制 | 精读要点 |
| --- | --- | --- |
| **Delta 模型** | 抽离为独立包 `dart_quill_delta`（本仓库仅 export） | 操作序列：insert/delete/retain + attributes；本项目 `TextRun` 片段可视为 Delta 子集 |
| **Document** | `Delta` + 文档树 `Root` + `changes` 广播流 + `History` | 单文档模型：`insert(index, data)` 应用启发式规则后广播 `DocChange`；`cachedPlainText` 明文缓存 |
| **序列化** | `Document.fromJson(List)` / `toDelta()` | Delta JSON（ops 数组）+ `Style.fromJson(attributes)` 属性反序列化 |
| **QuillController** | 持有 `Document` + 配置透传 | 变更经 `changes` 流驱动编辑器刷新 |

### 1.2 本地化适配方案（成熟度优先 → 首选落地）
```
本项目 PageTextItem.runs（TextRun 片段）→ 增加 Delta 兼容层：
① 新增 runs → Delta ops 转换（insert text + attributes：bold/italic/underline/strike/color/align/font）
② 新增 Delta ops → runs 回读（双向兼容，旧文档 runs 读取不受影响）
③ 序列化：doc JSON 增加 delta 字段（version 字段区分），旧 runs 保留读取
```
- 成熟度：✅ 2.9k star / 2585 commits，最成熟
- 双端兼容：✅ 全平台（含 Windows/Android）
- 许可：✅ Apache-2.0
- 风险：低（纯数据模型层转换，不引入编辑器 UI 依赖）

---

## 二、scribe_canvas（MIT，O(1) 向量缓存）—— 画布性能参考

### 2.1 源码精读结论
| 模块 | 机制 | 精读要点 |
| --- | --- | --- |
| **O(1) 渲染缓存** | `ScribePainter.cachedPicture`（预渲染 `ui.Picture`） | "Pre-rendered picture of all committed strokes. Built once per stroke"；`paint()` 直接 `canvas.drawPicture(cachedPicture!)`；`shouldRepaint` 用 `!identical(old.cachedPicture, new.cachedPicture)` **引用比较**（O(1) 判定，无路径重建） |
| **压感/变宽** | `Stroke.points + widths`（逐点宽度数组） | 每点独立宽度；`StrokeRendererUtil`：滤波（filteredPts/filteredWts）→ 平滑（smoothPoints）→ **锥形包络**（generateEnvelope，taperFraction=0.20） |
| **控制器** | `ScribeCanvasController`（标准 Flutter 控制器模式） | 类似 TextEditingController；`exportToPdf` 内置 |

### 2.2 本地化适配方案（缓存思想进本项目）
```
本项目 stroke_renderer 现有 Expando 双质量 Path 缓存 → 增加 Picture 缓存层：
① 提交 stroke 时用 PictureRecorder 一次性预渲染 → 缓存 ui.Picture
② 重绘时 canvas.drawPicture 代替逐 Path draw（重绘 O(1)）
③ 变更判定用引用比较（identical）而非重算几何
```
- 成熟度：✅ 0.6.3 稳定（3 个月前更新）
- 双端兼容：✅ Android/iOS/macOS/Windows
- 许可：✅ MIT
- 风险：中（渲染层改动，需保留回退开关，先并行验证再切换）

---

## 三、iwb_canvas_engine（MIT，事务写入 + JSON 校验）—— 数据可靠性参考

### 3.1 源码精读结论
| 模块 | 机制 | 精读要点 |
| --- | --- | --- |
| **事务写入** | store 层**稀疏提交**：`CommittedDocument`（不可变快照）+ `DocumentStoreKernel.installSparseCommit(PreparedSparseStoreCommit)` + `SparseTransactionWorkEvent` | 批量变更打包为稀疏提交原子安装，快照不可变 → 崩溃安全/可审计 |
| **JSON 严格校验** | codec 层 `schema_v1_validation.dart` | `schemaVersion must be 1.` 强校验 + 路径定位（`$.schemaVersion`）——与本项目 `document_codec` 版本降级思路同源 |
| **分层** | api/contracts/codec/store/runtime 清晰分层 | 渲染与存储解耦（与本项目 engine/ 分层一致） |

### 3.2 本地化适配方案（事务思想进本项目）
```
本项目 drawing_controller 命令栈 → 增加批量事务提交：
① 新增 DocumentTransaction：把多个 DocCommand 打包为原子提交（全部成功或全部回滚）
② 提交记录写入快照（类似 CommittedDocument 不可变语义）
③ 序列化时 schemaVersion 校验已有 → 对齐 iwb 的路径级报错
```
- 成熟度：✅ 5.0.1 稳定（5 个月前更新，多版本迭代）
- 双端兼容：✅ 全平台
- 许可：✅ MIT
- 风险：低-中（命令栈已存在，事务封装不破坏既有单命令路径）

---

## 四、适配优先级与总体建议

| 优先级 | 适配项 | 来源 | 风险 | 价值 |
| --- | --- | --- | --- | --- |
| P0 | runs ↔ Delta 双向转换层 | flutter-quill | 低 | 高（富文本生产级基础） |
| P1 | 批量命令事务（DocumentTransaction） | iwb_canvas_engine | 低-中 | 高（原子性/审计） |
| P1 | Picture 缓存层（重绘 O(1)） | scribe_canvas | 中 | 高（千笔级 60fps） |

**共同原则**：
1. 成熟度优先：flutter-quill（2.9k）→ iwb（5.0.1）→ scribe（0.6.3）
2. 双端兼容：三项目均含 Windows/Android，无平台排除
3. 许可合规：MIT/Apache-2.0，无 GPL 风险
4. 渐进落地：每项 1 周试用 + 人工抽检 + 回退开关，不破坏 249 测试基线

> 本报告为精读结论与适配蓝图；落地顺序按 P0→P1，每步独立验证、独立提交。
