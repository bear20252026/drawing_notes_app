# editor_v2 与 drawing 模块合并评估报告

## 当前状态

两个模块**都已符合** Clean Architecture 标准：

### editor_v2 模块结构
```
features/editor_v2/
├── domain/           # editor_repository.dart（零 Flutter 依赖）
├── application/      # editor_v2_viewmodel.dart + 多个 Notifier
├── infrastructure/   # editor_storage_repository.dart + drawing_adapter.dart
└── presentation/     # editor_v2_screen.dart + 多个 Widget
```

### drawing 模块结构
```
features/drawing/
├── domain/           # stroke.dart + shape_item.dart + layer.dart + document.dart
├── application/      # drawing_controller.dart（God Object）+ 多个 Notifier
├── infrastructure/   # document_repository_impl.dart + stroke_repository_impl.dart
└── presentation/     # 多个 Widget
```

## 重复分析

| 功能 | editor_v2 | drawing | 重复度 |
|------|-----------|---------|--------|
| Canvas 渲染 | canvas_painter.dart | canvas_painter.dart | 🔴 高 |
| 图层管理 | layer_panel.dart | layer.dart | 🔴 高 |
| 笔画/笔刷 | stroke_style_notifier.dart | stroke.dart | 🔴 高 |
| 历史/撤销 | history_panel.dart | 无 | 🟢 独有 |
| 无限画布 | infinite_canvas_widget.dart | 无 | 🟢 独有 |
| 笔记编辑 | note_editor_widget.dart | 无 | 🟢 独有 |
| 表格视图 | table_view_widget.dart | 无 | 🟢 独有 |
| PDF 导入 | pdf_import_service.dart | 无 | 🟢 独有 |

## 合并建议

### 结论：建议合并 ✅

**理由：**
1. Canvas 渲染逻辑高度重复（两个 `canvas_painter.dart`）
2. 图层管理概念重叠（`layer_panel.dart` vs `layer.dart`）
3. 笔画/笔刷管理重复
4. 统一维护成本更低

### 目标结构
```
features/editor/
├── domain/                  # 统一领域模型
│   ├── entities/
│   │   ├── stroke.dart      # 来自 drawing
│   │   ├── layer.dart       # 合并两个模块
│   │   ├── canvas_block.dart # 来自 editor_v2
│   │   └── document.dart    # 统一文档模型
│   ├── repositories/
│   │   ├── document_repository.dart
│   │   └── stroke_repository.dart
│   └── value_objects/
│       ├── color.dart
│       └── brush_type.dart
├── application/             # 统一用例
│   ├── document_use_cases.dart
│   ├── stroke_use_cases.dart
│   ├── canvas_use_cases.dart
│   └── export_use_cases.dart
├── infrastructure/          # 统一实现
│   ├── document_repository_impl.dart
│   ├── stroke_repository_impl.dart
│   └── services/
│       ├── document_codec.dart
│       └── sync_service.dart
└── presentation/            # 统一 UI
    ├── pages/
    │   └── editor_page.dart
    └── widgets/
        ├── canvas_painter.dart  # 合并后的统一渲染
        ├── layer_panel.dart
        ├── toolbar_widget.dart
        └── note_editor_widget.dart
```

### 迁移步骤
1. 创建 `features/editor/` 目录结构
2. 合并 domain 层实体（去重）
3. 合并 application 层用例
4. 合并 infrastructure 层实现
5. 合并 presentation 层 Widget
6. 更新路由配置
7. 删除旧模块

### 风险评估
- **风险等级**：中
- **主要风险**：editor_v2 的高级功能（无限画布、笔记编辑、表格视图）需要保持兼容
- **缓解措施**：分阶段迁移，先合并基础功能，再迁移高级功能
