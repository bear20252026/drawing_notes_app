# V1/V2 编辑器统一迁移计划

> 产出者：返修-笔记模式（2026-08-24）
> 状态：分析阶段完成
> 工作区：D:\write\1\build_latest\worktrees\wp3-note-mode

---

## 1. 现状概览

| 维度 | V1 Drawing | V2 Editor |
|------|-----------|-----------|
| 文件数 | 68 个 | 23 个 |
| 代码量 | 577 KB | 143 KB |
| 状态管理 | ChangeNotifier (DrawingController) | Riverpod Notifier (EditorV2State) |
| 数据模型 | DrawingDocument (mutable) | DocumentV2 (immutable) |
| 画布 | Canvas + Viewport + Cache | InfiniteCanvas + PageV2 |
| 工具栏 | 757 行（单文件 EditorToolbar） | 141 行（toolbar_widget.dart） |
| 属性面板 | 280 行（properties_panel.dart） | 242 行（property_panel.dart） |
| 图层面板 | layer_panel.dart | layer_panel.dart |
| 存储 | StorageService (SQLite/Hive) | NotebookStorage (JSON) |

## 2. 功能差异矩阵

### 2.1 V1 独有功能（V2 缺失）

| 功能 | V1 位置 | 优先级 |
|------|---------|--------|
| 多图层管理（新建/删除/显隐/锁定/合并） | DrawingController + layer_panel.dart | **P0** |
| 形状识别（矩形/圆/三角形自动修正） | shape_recognizer.dart | P1 |
| 图片插入/变换（缩放/旋转/裁剪） | images_notifier.dart + image_transform_service.dart | **P0** |
| SVG 导入/导出 | editor_exporter.dart | P1 |
| 橡皮擦模式（点/线/形状三种模式） | eraser_mode.dart + eraser_mode_store.dart | P1 |
| 笔刷预设商店 | brush_preset_store.dart | P2 |
| 剪贴板（复制/粘贴/剪切） | editor_page_editing.dart | **P0** |
| 搜索（笔记内搜索） | search_service.dart | P2 |
| 插件系统 | plugin_registry.dart | P3 |
| 手写笔输入（压感/倾斜） | stylus_input.dart | P2 |
| 图层离屏位图缓存（性能） | drawing_controller_render.dart | P1 |
| 视口变换/缩放/平移 | viewport_notifier.dart | **P0** |
| 编辑器导出（PNG/PDF） | editor_exporter.dart | P1 |
| 右键菜单/上下文菜单 | editor_context_bar.dart | P2 |
| 工具栏状态映射 | toolbar_state_mapper.dart | P1 |
| 键盘快捷键 | editor_page_shortcuts.dart | P1 |
| 左侧工具栏 | editor_left_toolbar.dart | P2 |

### 2.2 V2 独有功能（V1 缺失）

| 功能 | V2 位置 | 优先级 |
|------|---------|--------|
| 笔记模式（Word 式文字编辑） | note_editor_widget.dart | **P0**（已完成 #13/#18） |
| 块编辑器（BlockSuite 模式） | block_editor_widget.dart | P1 |
| 表格视图 | table_view_widget.dart | P2 |
| 幻灯片模式 | slide_presenter.dart | P2 |
| NotebookStorage 落盘 | note_document_bridge.dart | **P0**（已完成 #13） |
| / 命令菜单 | SlashCommandService | P2 |
| 无限画布（InfiniteCanvas） | infinite_canvas_widget.dart | P1 |
| 历史面板 | history_panel.dart | P2 |
| 侧边栏 | sidebar_widget.dart | P2 |
| 缩放控件 | zoom_controls.dart | P1 |
| 导出面板 | export_panel.dart | P2 |
| NoteBlock 模型（10+ 种块类型） | note_block.dart (editor_core) | P1 |

### 2.3 共有功能（需统一）

| 功能 | V1 文件 | V2 文件 | 统一方案 |
|------|---------|---------|----------|
| 工具栏 | editor_toolbar.dart (757 行) | toolbar_widget.dart (141 行) | → UnifiedToolbar |
| 属性面板 | properties_panel.dart (280 行) | property_panel.dart (242 行) | → UnifiedPropertyPanel |
| 图层面板 | layer_panel.dart | layer_panel.dart | → UnifiedLayerPanel |
| Canvas 渲染 | canvas_painter.dart | canvas_painter.dart | 合并为单一实现 |
| 形状绘制 | editor_page_tools.dart | (缺失) | 需迁入 V2 |

## 3. 架构差异分析

### 3.1 状态管理

```
V1: DrawingController (ChangeNotifier)
    ├── Mutable state
    ├── Direct mutation methods
    └── notifyListeners()

V2: EditorV2Notifier (Riverpod AsyncNotifier)
    ├── Immutable state (EditorV2State)
    ├── copyWith pattern
    └── StateProvider + ConsumerWidget
```

**迁移策略**：V2 已采用 Riverpod，不可回退。统一后全部使用 Riverpod。

### 3.2 数据模型

```
V1: DrawingDocument (mutable)
    ├── layers: List<Layer>
    │   ├── strokes: List<Stroke>
    │   ├── shapes: List<ShapeItem>
    │   ├── texts: List<TextItem>
    │   └── images: List<DocumentImageItem>
    └── 直接修改属性

V2: DocumentV2 (immutable)
    ├── pages: List<PageV2>
    │   ├── notes: List<NoteParagraph>
    │   └── index: int
    └── copyWith pattern
```

**迁移策略**：保留 V2 DocumentV2 结构，扩展为支持 layers。

### 3.3 渲染管线

```
V1: DrawingController → LayerRenderCache (位图缓存) → CanvasPainter
    └── 离屏渲染 → 性能高

V2: EditorV2State → CanvasPainterV2 → CustomPaint
    └── 直接绘制 → 性能依赖文档复杂度
```

**迁移策略**：引入 V1 的 LayerRenderCache 到 V2。

## 4. 公共组件层（shared/widgets/）

已完成的公共组件（见 `lib/shared/widgets/`）：

| 组件 | 文件 | 状态 |
|------|------|------|
| ColorPickerGrid | editor_components.dart | ✅ 完成 |
| StrokeWidthSlider | editor_components.dart | ✅ 完成 |
| OpacitySlider | editor_components.dart | ✅ 完成 |
| LineStyleSelector | editor_components.dart | ✅ 完成 |
| ToolButton | editor_components.dart | ✅ 完成 |
| ColorPickerDot | editor_components.dart | ✅ 完成 |
| UnifiedToolbar | unified_toolbar.dart | ✅ 完成 |
| UnifiedPropertyPanel | unified_property_panel.dart | ✅ 完成 |
| UnifiedLayerPanel | unified_layer_panel.dart | ✅ 完成 |

## 5. 迁移计划

### Phase 1：数据模型统一（Week 1）

1. 扩展 DocumentV2 支持图层：
   ```dart
   class DocumentV2 {
     final List<PageV2> pages;
     final List<LayerV2> layers; // 新增
   }
   
   class LayerV2 {
     final String id;
     final String name;
     final bool isVisible;
     final bool isLocked;
     final double opacity;
     final List<StrokeV2> strokes;
     final List<ShapeV2> shapes;
     final List<TextV2> texts;
     final List<ImageV2> images;
   }
   ```

2. 创建 V1 → V2 数据迁移器（DrawingDocument → DocumentV2）

3. 统一 ID 生成策略（LocalIdGenerator → UUID）

### Phase 2：绘图引擎统一（Week 2）

1. 将 DrawingController 的核心逻辑拆分为：
   - StrokeRenderer（笔画渲染）
   - ShapeRenderer（形状渲染）
   - ImageRenderer（图片渲染）
   - LayerCompositor（图层合成）
   - HistoryManager（历史管理）

2. 将以上模块封装为 Riverpod Provider

3. 引入 V1 的 LayerRenderCache 优化渲染性能

### Phase 3：UI 组件统一（Week 3）

1. 用 UnifiedToolbar 替换 V1 的 EditorToolbar 和 V2 的 toolbar_widget
2. 用 UnifiedPropertyPanel 替换 V1/V2 属性面板
3. 用 UnifiedLayerPanel 替换 V1/V2 图层面板
4. 合并 canvas_painter.dart（V1/V2 各一个）
5. 迁入 V1 独有 UI：
   - editor_context_bar.dart → context_menu.dart
   - editor_statusbar.dart → status_bar.dart
   - selection_bar.dart → selection_toolbar.dart
   - selection_action_button.dart → selection_actions.dart

### Phase 4：功能迁移（Week 4）

1. P0 功能迁入 V2：
   - 图片插入/变换 → image_block.dart
   - 剪贴板 → clipboard_service.dart
   - 视口变换 → viewport_provider.dart
   - 多图层管理 → layer_provider.dart

2. P1 功能迁入 V2：
   - 形状识别 → shape_recognizer.dart
   - SVG 导入/导出
   - 橡皮擦模式
   - 键盘快捷键
   - 导出（PNG/PDF）

### Phase 5：V1 冻结 + 清理（Week 5）

1. 将 V1 drawing/ 标记为 @Deprecated
2. 确保所有入口点（NotebookViewPage, EditorV2Screen）都使用 V2
3. 删除 V1 引用（如果不再有调用方）
4. 清理 material_ui 依赖（如果 V2 不需要）

## 6. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| V1 DrawingController 状态过重（25 个 part 文件） | 迁移周期长 | 分阶段迁移，每阶段独立可测 |
| V1 material_ui 依赖深度耦合 | 可能影响 V2 | V2 已解耦，共享组件不依赖 material_ui |
| 图层缓存机制复杂 | 性能风险 | 先用 V2 直接渲染，后优化引入缓存 |
| 数据迁移兼容性 | 旧数据可能丢失 | 写迁移测试，双读策略 |

## 7. 测试计划

- [ ] V1 → V2 数据迁移测试
- [ ] UnifiedToolbar 组件测试
- [ ] UnifiedPropertyPanel 组件测试
- [ ] UnifiedLayerPanel 组件测试
- [ ] 绘图引擎核心测试（笔画/形状/图片）
- [ ] 渲染性能基准测试（V1 缓存 vs V2 直接绘制）
- [ ] 端到端测试（创建→编辑→保存→重开）

## 8. 时间线

| 阶段 | 周期 | 交付物 |
|------|------|--------|
| Phase 1 数据模型统一 | Week 1 | DocumentV2 + LayerV2 + 迁移器 |
| Phase 2 绘图引擎统一 | Week 2 | Riverpod Provider 化的渲染模块 |
| Phase 3 UI 组件统一 | Week 3 | 统一 UI（工具栏/属性/图层/画布） |
| Phase 4 功能迁移 | Week 4 | V1 独有功能全部迁入 V2 |
| Phase 5 V1 冻结 | Week 5 | V1 标记废弃 + 清理 |
