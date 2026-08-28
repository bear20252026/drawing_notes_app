# 容量预算（P4） · 2026-08-28

> 目标：测出数据模型/持久化的容量边界，判断哪些维度会被**硬性限制**、哪些会
> **无界增长**，并给出证据与优先建议。方法：直接读领域模型与持久化代码，核对
> 上限常量与触发路径，不作臆测。

## 一、结论（先给判断）

**容量健康度：优。** 应用对"单条成本高"的维度（笔画点数、页面历史、图片文件、
检索摘要、自动保存频率）均已设上限；真正无界的维度（笔记本页数、书写过程原始
采样点）属于低频/瞬时且影响可接受的范畴。**无需为容量做侵入式重构。**

## 二、已设上限（成本可控）

| 维度 | 上限 | 机制 | 位置 |
|---|---|---|---|
| 持久化笔画点数 | 按几何长度上界 ≈ 长度 / 0.35 | 收笔时按 `finalSpacing=0.35` + `pressureTolerance=0.015` 抽稀 | `lib/core/rendering/stroke_geometry_cache.dart` |
| 实时预览点数 | 稀疏（`previewSpacing=1.5`），末点跟随笔尖 | 同文件 `append()` | 同文件 |
| 页面历史版本数 | 每页 **8** 份快照 | `NotebookPage.maxHistoryVersions = 8` | `lib/features/notes/domain/notebook_page_content.dart` |
| 检索摘要长度 | 200 字符 | `Notebook.searchSummaryMaxChars` | `lib/features/notes/domain/notebook_entity.dart` |
| 图片存储 | **存文件非内联 base64**；JSON 只记路径 | JPEG/PNG 写 `notebook_images/`、`document_images/` | `notebook_storage.dart` / `storage_service.dart` |
| 孤儿图片文件 | 删除文档时按"被其他文档引用"清理 → 不堆积 | `_deleteUnreferencedManagedImages()` + `_managedImagePathOrNull()` 防路径穿越 | `lib/core/storage/storage_service.dart:479-523` |
| 自动保存频率 | 防抖 800ms + 串行合并 + 失败退避 | `SaveScheduler` | `lib/features/drawing/application/save_scheduler.dart` |
| 写入原子性 | 临时文件写 + flush + 替换 / 删除 | `encrypted_write_transaction.dart`、`notebook_storage.dart` | 基础设施层 |

**关键点**：笔画点数是最容易失控的维度（高采样触控笔一帧产生大量近重 PointerMove），
但它被"收笔抽稀"*持久化到有界*、被"预览抽稀"*渲染到有界*——这是在源头就做对了的容量控制。

## 三、未设上限（无界，但可接受）

| 维度 | 风险 | 判定 |
|---|---|---|
| 笔记本页数 | `List<NotebookPage> pages` 无上限 | 低频；历史按页独立 capped=8，非全局复制；常规使用远达不到性能拐点 → **无需硬上限** |
| 书写过程原始采样点 | 收笔前 `_rawPoints` 随每个 PointerMove 增长 | **瞬时**内存，不落盘（落盘已抽稀）；受单笔时长/面积自然约束 → 可接受 |
| 一次整本加密保存 | `encryptedPayload`≈整本 base64（比原始大 33%） | 触发为离散动作（非逐笔），再经 SaveScheduler 串行化 → 频率可控，`O(n)` 单次可接受 |

## 四、估算（粗算，量级参考）

- `StrokePoint`：3 个 double ≈ 24B 内存；JSON 每点多约 30–40B。
- 一条 700 逻辑单位笔画的持久化点列 ≈ 700/0.35 ≈ **2000 点** ≈ 80KB JSON。
- 单页 8 份历史快照：若该页 50 笔画 / 500 点 ≈ 50KB，则 8 份 ≈ **400KB/页**。
- base64 载荷按 33% 膨胀：一个 1MB（原始）笔记本 → 约 1.33MB 加密载荷。

## 五、建议（按价值/成本排序）

1. **P4-R1（低，可做可不做）**：为"单条超长笔画"的原始采样设一个软上限（如超过
   阈值改用更大 preview 间距），防止超长连续书写时瞬时内存异常。收益有限，属防御性。
2. **P4-R2（不建议）**：硬性限制笔记本页数——与"用户自由创作"的产品预期冲突，且
   实际风险低，属于为假想场景增加复杂度。
3. **P4-R3（已达标）**：页面历史 8 版上限已覆盖"回溯/撤销"需求，无需调整。
4. **P4-R4（已验证）**：图片孤儿清理与路径防御已存在，无需新增。

**P4 结论**：无需代码改动；容量边界已由既有设计覆盖。剩余验证项仅剩 P5（真机/模拟器
上的实机容量与性能表现，需构建后人工跑测）。
