# 测试覆盖率报告 — P2 #32

**日期**：2026-08-24
**分支**：master
**命令**：`flutter test --coverage`

---

## 概览

| 指标 | 值 |
|------|----|
| 总行数（LF） | 8,546 |
| 覆盖行数（LH） | 3,952 |
| **行覆盖率** | **46.2%** |
| 覆盖文件数 | 63 |

---

## 各文件覆盖率

### 零覆盖（0%）—— 优先补测试

| 文件 | 行数 |
|------|------|
| `lib/engine/svg_exporter.dart` | 34 |
| `lib/engine/gesture_math.dart` | 18 |
| `lib/engine/plugin_registry.dart` | 10 |
| `lib/engine/shape_library.dart` | 63 |
| `lib/ui/widgets/layer_panel.dart` | 99 |
| `lib/ui/widgets/properties_panel.dart` | 100 |
| `lib/ui/pages/presentation_page.dart` | 66 |

### 低覆盖（<20%）

| 文件 | 覆盖率 | 行数 |
|------|--------|------|
| `lib/ui/widgets/color_picker_dialog.dart` | 0.7% | 135 |
| `lib/ui/widgets/editor_toolbar.dart` | 0.8% | 243 |
| `lib/engine/shape_renderer.dart` | 4.4% | 136 |
| `lib/engine/editor_exporter.dart` | 6.4% | 188 |
| `lib/ui/widgets/editor_components.dart` | 9.0% | 365 |
| `lib/models/selection.dart` | 9.1% | 11 |
| `lib/ui/pages/editor_page.dart` | 14.3% | 2551 |
| `lib/ui/widgets/editor_viewmodel.dart` | 19.1% | 94 |

### 满覆盖（100%）

| 文件 | 行数 |
|------|------|
| `lib/models/document_image_item.dart` | 44 |
| `lib/models/layer.dart` | 16 |
| `lib/engine/stroke_geometry_cache.dart` | 29 |
| `lib/models/shape_endpoint_binding.dart` | 16 |
| `lib/engine/command_registry.dart` | 28 |
| `lib/engine/eraser_mode_store.dart` | 10 |
| `lib/engine/shape_creation_geometry.dart` | 26 |
| `lib/storage/repository.dart` | 1 |
| `lib/ui/widgets/glass_surface.dart` | 20 |
| `lib/ui/widgets/ambient_background.dart` | 7 |

---

## 测试结果

| 状态 | 数量 |
|------|------|
| 通过 | 7 |
| 失败 | 3 |
| 错误 | 0 |

### 失败用例

1. **app_design_test**: 期望 Size(44,44) 实际 Size(48,48) — UI 尺寸微调
2. **v2_dependency_boundaries V-005**: `storage_adapter.dart` import legacy `document.dart`
3. **v2_dependency_boundaries V-006**: `property_panel.dart` UTF-8 解码失败

> 注意：大量测试因 `drawing_controller.dart` / `drawing_controller_render.dart` 编译错误
> （未定义成员 `_grid`, `_selectedStrokeIndices` 等）而无法运行。修复这些编译错误
> 后覆盖率预计会显著提升。
