# 专家级代码审查报告（2026-08-15）

> 范围：commit `17dd5e1`（11 大问题修复 + 11 大发现落地，17 文件 +687/-227）及关键模块。
> 方法：code_review 工具因工作目录限制不可用，改用**人工深度审查**（git diff 逐文件核验 + 高风险点精读 + 一致性交叉验证），对标中国政府验收标准（严谨、可审计、无回归）。

---

## 一、审查结论总览

| 等级 | 数量 | 说明 |
| --- | --- | --- |
| 🔴 P1 真实缺陷 | 2 | 已定位根因并当场修复，补回归测试 |
| 🟡 P2 观察项 | 1 | 功能可用，建议后续接入 UI |
| 🟢 审查通过项 | 8 | 虚线框选/版本降级/模型提取/画布文字等 |

## 二、P1 缺陷（已修复 + 回归验证）

### 2.1 形状工具预览与落定方向不一致

**文件**：`lib/ui/pages/editor_page.dart` `_shapeDraft`

**根因**：落定形状走 `ShapeCreationGeometry.fromDrag`（已保存 `lineStart/lineEnd` 真实端点，上一轮修复方向问题），但**绘制中预览** `_shapeDraft` 仍只靠 `flipX/flipY` 对角线表达，未传真实端点。用户拖直线/箭头时会看到"预览方向与实际落定方向跳动"。

**修复**：`_shapeDraft` 同样计算并传入 `lineStart/lineEnd`（相对外接框左上角），预览与落定完全一致。

### 2.2 橡皮擦命中线性形状的坐标基准偏移

**文件**：`lib/engine/drawing_controller.dart` `_eraserHitsShape`

**根因**：先 `rawBounds(shape).inflate(radius)` 得到 `bounds`，再以 `bounds.topLeft` 作为线段绝对坐标基准。`bounds.topLeft` 已向左上偏移 `radius`，导致线段整体偏移，命中判定偏差（**漏擦/误擦标准直线**，直接影响上一轮问题3的修复质量）。

**修复**：绝对基准改用形状原始外接框左上角 `Offset(shape.x, shape.y)`，线段距离判定准确。

## 三、P2 观察项

- `DrawingController.dominantStrokeColor`（选区主色加权提取，对齐 Saber Select）已实现但**尚无 UI 调用方**——建议在"批量改色/吸管"入口接入后开放。

## 四、审查通过项（核验无问题）

| 模块 | 核验结论 |
| --- | --- |
| `MarqueePainter` 虚线绘制 | PathMetrics 手工分段 12-8 虚线，无新依赖，正确 |
| `document_codec` 版本只读降级 | `fileVersion > _version` 明确抛 FormatException 提示升级，防静默丢数据 |
| `PageTextItem` 提取 text_item.dart | notebook.dart 导入导出一致，循环依赖消除，旧序列化兼容 |
| `DrawingDocument.textItems` | toJson/fromJson 向后兼容（旧文档空列表），document_codec 无破坏 |
| 画布模式文字（_addCanvasTextItem/_commitTextEditing） | 写入/提交/渲染三路径一致，无重复添加 |
| 激光内芯颜色 | 内芯=所选颜色，外层模糊光晕，醒目 |
| 深色阅读标准 RGB 反相矩阵 | 白色→黑色、黑字→白字，绿幕消除 |
| 无限画布切换 | 主菜单入口 + `_toggleInfiniteCanvas`，tickFrame 刷新，无受保护成员误用 |

## 五、后续大工程项前置检查（为任务 3-9 铺路）

- **Quill 混排**：本项目文字块为 Widget overlay，引入 flutter_quill 需评估依赖与现有 overlay 架构兼容性。
- **BSON 压缩**：`PointExtensions` 类似物不存在，需新增点列编解码 + 格式版本协商（当前 v2 向前兼容约束）。
- **WebDAV 同步**：项目无网络同步层，需新增同步服务抽象（对齐 Saber abstract_sync 三件套）。
- **elbow 箭头/吸附体系**：`ShapeBindingGeometry` 已支持端点绑定，可增量扩展。

---

## 六、回归验证

- `flutter analyze`：零问题
- 相关测试：shape_recognizer / shape_creation_geometry / laser_pointer / phase4_selection / reading_inversion 全过
- 全量门禁：243 项测试全过（审查前基线）
