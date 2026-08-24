# #16 架构统一核查报告

> 核查人：返修-CI质量 | 基线：c91c7d2 | 日期：2026-08-24

## 一、ToolEngine 统一性

| 检查项 | 结论 | 证据 |
|--------|------|------|
| ToolEngine 唯一定义 | ✅ 已统一 | `packages/editor_core/lib/src/domain/tool_engine.dart`（全文46处引用） |
| editor_v2 使用 ToolEngine | ✅ 是 | `editor_v2_viewmodel.dart` 导入并使用 `ToolEngine` |
| drawing 使用 ToolEngine | ⚠️ 独立体系 | `drawing_controller.dart` 有自研 `DrawingController`，不依赖 ToolEngine |
| 重复 ToolEngine 实现 | ✅ 无 | 全库 grep 仅 `tool_engine.dart` 一处定义 |

**结论**：ToolEngine 在 editor_core/editor_v2 层已真正统一。drawing feature 有独立控制器体系（DrawingController），属于架构分层设计而非重复实现。

## 二、同一功能多套实现排查

### 2.1 StrokePoint — ⚠️ 发现双套实现

| 位置 | API 风格 | 功能 |
|------|----------|------|
| `editor_core/lib/src/domain/brush_styles.dart:33` | 命名参数 `{required x, required y, pressure}` + copyWith/==/hashCode | Saber 画笔风格系统 |
| `drawing/domain/stroke.dart:21` | 位置参数 `(x, y, pressure)` + toJson/fromJson | 原始画布笔画系统 |

**风险**：两套 StrokePoint 互不兼容，跨模块传递需转换。editor_core 版本更成熟（有值语义），drawing 版本有序列化支持。

### 2.2 BrushType — ⚠️ 发现双套枚举

| 位置 | 枚举值 |
|------|--------|
| `editor_core/lib/src/domain/brush_styles.dart` | pen, ballpoint, highlighter, pencil |
| `drawing/domain/stroke.dart` | pen, pencil, marker, laser, eraser |

**分析**：editor_core 版本面向 Saber 画笔风格（压力感应/纹理），drawing 版本面向画布运行时工具（激光/橡皮擦）。两套各有用途，但 `pen`/`pencil` 存在语义重叠。

### 2.3 其他领域模型 — ✅ 无重复

| 模型 | 唯一位置 |
|------|----------|
| ToolEngine | `editor_core/lib/src/domain/tool_engine.dart` |
| ToolType | `editor_core/lib/src/domain/tool_engine.dart` |
| DocumentV2 | `editor_core/lib/src/domain/document_v2.dart` |
| Frame | `editor_core/lib/src/domain/frame.dart` |
| CanvasTransform | `editor_core/lib/src/domain/canvas_transform.dart` |
| HoneypotKey | `editor_core/lib/src/domain/honeypot_key.dart` |

## 三、lib/v2 唯一活跃层 & Legacy 冻结

| 检查项 | 结论 | 说明 |
|--------|------|------|
| lib/features/editor (v1) | ✅ 不存在 | 无 `lib/features/editor/` 目录 |
| lib/features/editor_v2 | ✅ 唯一活跃 | 完整 DDD 分层（adapters/application/presentation） |
| lib/infrastructure/storage/v2 | ✅ 存在 | v2 存储层活跃 |
| lib/infrastructure/storage (v1) | ⚠️ 需确认 | 存在 `lib/infrastructure/storage/` 目录（可能为 v1 残留） |
| @Deprecated 标注 | ✅ 4处 | 全部为工具函数/常量级弃用，非架构级 Legacy |

## 四、packages 结构

| 包 | 职责 | 状态 |
|----|------|------|
| `editor_core` | 编辑器领域模型（ToolEngine/BrushStyles/Frame/...） | ✅ 活跃，100+ 文件 |
| `notebook_domain` | 笔记本安全域（Session/KeyHandle/LockPolicy） | ✅ 活跃 |

## 五、遗留风险清单（建议后续处理，本次不做大重构）

1. **StrokePoint 双套实现**：建议将 drawing 版本迁移至 editor_core 版本，或建立适配层。
2. **BrushType 枚举重叠**：pen/pencil 语义重叠，建议统一或明确文档说明分工。
3. **storage v1 残留**：确认 `lib/infrastructure/storage/` 是否为 v1 残留，若是则标记冻结。
4. **4处 @Deprecated**：均为小工具函数，可后续清理。
