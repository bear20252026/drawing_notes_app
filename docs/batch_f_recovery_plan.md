# 批次 F 高级功能恢复方案（2026-08-21——基于全球调研 + 专家方案）

## 核心原则（专家方案 + 2026 最佳实践）

### 专家方案要求
> "每次只恢复一个能力（分页、图片、橡皮擦语义、PDF 导入、导出、无限画布、图表、演示），每项都必须先写领域命令、再写平台集成和两端测试。连续两个版本没有 V2 核心回归后，删除相应旧 editor_page_* 与 drawing_controller_* 路径。"

### 2026 年调研整合

| 功能 | 2026 最佳实践 | 参考实现 |
|------|--------------|---------|
| **分页画布** | O(1) 矢量缓存 + PictureRecorder 回放 + 连续/离散滚动模式 | scribe_canvas（2026） |
| **图片/媒体** | 媒体仓库隔离（notebookId-scoped）+ VFS 加密对象 + 懒加载缩略图 | MediaRepositoryV2（已实现接口） |
| **橡皮擦** | 对象擦除（Smart Stroke Eraser——距离判定+整体移除）+ 像素擦除（BlendMode.clear + saveLayer） | scribe_canvas + CustomPainter erase 模式 |
| **PDF 导入** | pdf_render/pdfx 渲染 + 多页扫描 + 自动裁剪 | document_scanner + pdfx |
| **PDF 导出** | pdf 包生成 + 多页 + 背景/页眉页脚 | scribe_canvas.exportToPdf |
| **无限画布** | Transform（Matrix4）+ 世界空间裁剪（world-space culling）+ 边界约束 + 交互/编程模式 | canvas_kit（2025-2026） |
| **图表/演示** | 稳定版本后恢复——Chart.js 模式（数据→渲染分离） | 待连续两个稳定版本后 |

## 批次 F 执行顺序（按专家"按价值恢复"）

### F-1：分页画布（Multi-Page Canvas）—— P0

**目标**：多个画布页面在滚动视图中连续/离散切换。

**实现**：
```dart
// domain
class PageV2 {
  final String id;
  final DocumentV2 document;  // 每页独立 DocumentV2
  final int index;
}

// application
class PagedCanvasViewModel extends Notifier<List<PageV2>> {
  void addPage();
  void insertPage(int index);
  void deletePage(int index);
  void reorderPage(int oldIndex, int newIndex);
}

// presentation
class PagedCanvasWidget extends ConsumerWidget {
  // ListView.builder + PageView 或 CustomScrollView
  // 每页独立 CustomPainter（RepaintBoundary 隔离）
}
```

**验收**：
- [ ] 新建/插入/删除/重排页面
- [ ] 连续滚动 + 离散翻页模式切换
- [ ] 每页独立撤销/重做栈
- [ ] Android + Windows CUJ-03（canvas_and_paged_text_editing）

### F-2：图片/媒体插入（Media Repository）—— P0

**目标**：插入图片到画布，按 notebookId 隔离存储。

**实现**：
```dart
// 已有接口：MediaRepositoryPort（packages/notebook_domain）
// 实现：MediaRepositoryV2（infrastructure/storage/v2/）
class MediaRepositoryV2 implements MediaRepositoryPort {
  // store：加密存储到 VFS（AAD 绑定 notebookId）
  // read：授权读取（NotebookSession 验证）
  // thumbnail：懒加载缩略图缓存
}

// 命令
class InsertImageCommand extends DocumentCommand {
  final String layerId;
  final String mediaId;
  final double x, y, width, height;
}
```

**验收**：
- [ ] 插入图片到画布（拖拽/选择器）
- [ ] 图片按 notebookId 隔离（K_note 加密）
- [ ] 缩略图懒加载（大图不阻塞 UI）
- [ ] 移动/缩放/删除图片
- [ ] Android + Windows

### F-3：橡皮擦语义（Eraser Mode）—— P0

**目标**：对象擦除（整体移除）+ 像素擦除（BlendMode.clear）。

**实现**：
```dart
// domain
enum EraserMode { object, pixel }

// 对象擦除（GeometryEngine 距离判定）
class EraseByDistanceCommand extends DocumentCommand {
  final double eraserX, eraserY, radius;
  // 距离 < radius 的 stroke/shape/text 整体移除
}

// 像素擦除（CustomPainter 层——BlendMode.clear）
// canvas.saveLayer() → 绘制带 BlendMode.clear 的 Path → canvas.restore()
```

**验收**：
- [ ] 对象擦除：触碰笔画任意位置 → 整体移除（live 高亮）
- [ ] 像素擦除：擦除区域精确像素清除
- [ ] 撤销/重做支持
- [ ] Android + Windows CUJ-04（object_and_pixel_eraser）

### F-4：PDF 导入（PDF Import）—— P1

**目标**：导入 PDF 为多页画布背景。

**实现**：
- 使用 `pdfx` 或 `pdf_render` 包渲染 PDF 页面
- 每页渲染为图片 → 作为 PageV2 的背景
- SVG 预检（已有 SvgPreflight）+ PDF 配额检查（页数/大小）

**验收**：
- [ ] 选择 PDF → 渲染为多页背景
- [ ] 每页可独立绘制
- [ ] Android + Windows

### F-5：PDF/PNG 导出（Export）—— P1

**目标**：导出画布为 PDF/PNG 文件。

**实现**：
- PDF：使用 `pdf` 包生成多页 PDF（含背景/绘制内容/页眉页脚）
- PNG：`toImage()` → `toByteData(format: png)` → 文件写入
- 导出读取不可变文档快照和已解锁会话（不读取 Widget 状态）

**验收**：
- [ ] 导出完整 PDF（多页 + 绘制内容）
- [ ] 导出 PNG（当前页面）
- [ ] Android + Windows

### F-6：无限画布（Infinite Canvas）—— P1

**目标**：平移/缩放画布（Transform）+ 世界空间裁剪。

**实现**：
```dart
// application
class ViewportState {
  final double scale;
  final Offset translation;
  final Size viewportSize;
  
  // 世界坐标 ↔ 屏幕坐标转换
  Offset worldToScreen(Offset worldPos);
  Offset screenToWorld(Offset screenPos);
  
  // 可见区域（世界坐标）
  Rect get visibleWorldRect;
}

// presentation
class InfiniteCanvasWidget extends ConsumerWidget {
  // GestureDetector（onScaleUpdate → 更新 ViewportState）
  // CustomPainter（canvas.transform(matrix4) → 绘制可见元素）
  // 世界空间裁剪（只绘制 visibleWorldRect 内的元素）
}
```

**验收**：
- [ ] 双指缩放 + 拖拽平移
- [ ] 性能：世界空间裁剪（只绘制可见区域）
- [ ] 边界约束（可选：画布边界不超出）
- [ ] Android + Windows

### F-7：图表/演示模式 —— P2（连续两个稳定版本后）

**目标**：数据图表 + 幻灯片演示。

**条件**：连续两个稳定版本没有 V2 核心回归后才恢复。

## 执行时间规划

| 功能 | 优先级 | 周期 | 前置依赖 |
|------|--------|------|----------|
| F-1 分页画布 | P0 | 1 周 | 批次 E（已完成） |
| F-2 图片/媒体 | P0 | 1 周 | F-1（分页）+ MediaRepositoryV2 |
| F-3 橡皮擦 | P0 | 1 周 | GeometryEngine（已完成） |
| F-4 PDF 导入 | P1 | 1 周 | F-1（分页） |
| F-5 PDF/PNG 导出 | P1 | 1 周 | F-1（分页） |
| F-6 无限画布 | P1 | 1 周 | ViewportState |
| F-7 图表/演示 | P2 | 后续 | 连续两个稳定版本 |

## 非回归验证

每项功能恢复后必须通过：
- [ ] 全量测试（408+ 测试不回归）
- [ ] flutter analyze 零问题
- [ ] 边界检查通过
- [ ] Android + Windows 双平台证据（受影响功能）
- [ ] 加密/会话/存储测试不回归（S-001~S-005）
