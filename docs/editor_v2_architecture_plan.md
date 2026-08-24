# Editor V2 架构方案（2026-08-21——基于全球调研 + 专家方案）

## 核心原则（专家方案 + 2026 最佳实践）

### 1. 分层架构（Headless Logic——无 UI 单元测试）
```
lib/features/editor_v2/
├── application/
│   ├── editor_v2_viewmodel.dart    # Riverpod Provider——不可变状态 + 命令分发
│   └── ui_intent.dart              # UI Intent（用户操作抽象——跨平台）
├── domain/
│   └── (复用 packages/editor_core) # DocumentV2/GeometryEngine/DocumentReducer
├── presentation/
│   ├── editor_v2_screen.dart       # Canvas Widget + 工具栏（最小 UI）
│   ├── canvas_painter.dart         # 直接 Canvas 绘画（CustomPainter + RepaintBoundary）
│   └── toolbar_widget.dart         # 工具栏（画笔/直线/矩形/椭圆/箭头/文字/选择）
└── adapters/
    ├── drawing_adapter.dart        # 将旧 V1 DrawingController 桥接到 V2（迁移期）
    └── platform_adapter.dart       # Android/Windows 事件抽象
```

### 2. 状态管理（Riverpod + 不可变 + 命令模式）
```dart
// editor_v2_viewmodel.dart
@riverpod
class EditorV2ViewModel extends _$EditorV2ViewModel {
  @override
  EditorV2State build() => const EditorV2State.initial();

  // 命令分发（通过 DocumentReducer）
  void execute(DocumentCommand command) {
    final reducer = DocumentReducer(state.document);
    final newDoc = reducer.execute(command);
    state = state.copyWith(document: newDoc, canUndo: true);
  }

  void undo() { ... }
  void redo() { ... }
}

@immutable
class EditorV2State {
  const EditorV2State({required this.document, this.canUndo = false, ...});
  final DocumentV2 document;
  final bool canUndo;
  // copyWith + == + hashCode（不可变）
}
```

### 3. 渲染层（2026 最佳实践）
- **直接 Canvas 绘画**（CustomPainter + RepaintBoundary——硬件加速）
- **Lazy Repainting**：只在状态变更时重绘（RepaintBoundary 隔离）
- **分层渲染**：背景层/内容层/交互层（独立 CustomPainter）
- **性能**：无每元素 Widget（直接 Canvas 操作——Sheetifye/industrial-drawing 模式）

### 4. 输入层（跨平台手势抽象）
- **InputEvent 抽象**（PointerEvent → InputEvent——Android/Windows 统一）
- **工具状态机**：draw/select/pan/measure/erase（当前工具决定输入解释）
- **手势处理器**：tap/drag/scale（复用 editor_input_arbiter 的算法）

### 5. 历史管理（DocumentReducer 已有 + 2026 增强）
- **stop 标记**（交互开始/结束的检查点——tldraw 模式）
- **squashToMark**（合并多个操作为单条历史——减少历史条目）
- **bail**（取消时回滚到标记——不推入历史）

## 最小主路径（批次 E——CUJ-01/02/04/05）

### CUJ-01：创建→画一笔→保存→重开
1. 用户点击"新建画作"→ 输入名称 → 创建 DocumentV2（空）
2. 画笔工具 → 手势拖拽 → AddStrokeCommand → 执行 → 重绘
3. 返回（自动保存——800ms 防抖）
4. 重开 → 加载 DocumentV2 → 重绘

### CUJ-02：直线/箭头/选择/移动/撤销
1. 直线工具 → 手势拖拽 → 直线几何（GeometryEngine.line）
2. 选择工具 → 点击元素 → 选中状态
3. 移动手势 → MoveItemCommand → 执行
4. 撤销 → undo()

### CUJ-04：橡皮擦
1. 橡皮擦工具 → 手势拖拽 → 距离判定（distanceTo/距离阈值）
2. 删除匹配元素 → RemoveStrokeCommand/RemoveShapeCommand

### CUJ-05：加密→锁定→再认证→重开
1. 加密笔记本 → NotebookSession.unlock(key)
2. 锁定 → SessionGuard.lock() → 密钥清除
3. 再认证 → 输入密码 → unlock()
4. 重开 → 验证（CUJ-01 流程 + 加密层）

## 技术决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 状态管理 | **Riverpod** | 2026 Flutter 标准——不可变 Provider——预测式状态流 |
| 渲染 | **CustomPainter + RepaintBoundary** | 直接 Canvas 绘画——无每元素 Widget——性能最优 |
| 历史 | **DocumentReducer（已有）+ stop/squash/bail** | 命令模式——2026 tldraw/Excalidraw 最佳实践 |
| 输入 | **InputEvent 抽象**（复用 editor_input_arbiter） | 跨平台手势统一 |
| 平台适配 | **infrastructure/platform/**（已有） | Android/Windows 事件 → InputEvent |

## 依赖关系（专家方案 R-02/R-03）

```
editor_v2/presentation/ → editor_v2/application/ → packages/editor_core + packages/notebook_domain
editor_v2/application/ → lib/infrastructure/（通过 ports——不直接依赖）
editor_v2/adapters/ → lib/infrastructure/（平台抽象）
lib/app/composition_root.dart → editor_v2/application/（依赖注入）
```

## 验收标准（批次 E——CUJ-01/02/04/05）

- [ ] CUJ-01 Android + Windows 通过
- [ ] CUJ-02 Android + Windows 通过
- [ ] CUJ-04 Android + Windows 通过
- [ ] CUJ-05 Android + Windows 通过
- [ ] flutter analyze 零问题
- [ ] 全量测试（403+）通过
- [ ] 边界检查通过
- [ ] 无 V2 → Legacy import（R-02）
- [ ] 无 UI → 文件/密钥/VFS 直接访问（R-03）
