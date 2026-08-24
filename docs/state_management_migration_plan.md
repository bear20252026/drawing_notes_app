# P2 #22 状态管理统一迁移计划

**审计日期**：2026-08-24  
**审计人**：Aion CLI（存储方案审计员）

---

## 一、现状总结

### 1.1 依赖情况

| 依赖 | 版本 | 状态 |
|------|------|------|
| `flutter_riverpod` | ^3.0.0 | ✅ 主力框架 |
| `riverpod` | ^3.2.1 | ✅ 核心包 |
| `provider` | ❌ 未引入 | — |
| `flutter_bloc` | ❌ 未引入 | — |
| `get_it` | ❌ 未引入 | — |

**结论**：项目**没有** Bloc/Cubit/Provider(get_it) 依赖，仅使用 Riverpod 3.x。

### 1.2 已迁移至 Riverpod Notifier 的模块

以下模块**已完成迁移**，使用 `NotifierProvider` + `ConsumerWidget`：

| 模块 | Notifier 类 | Provider | 文件 |
|------|-------------|----------|------|
| 深色模式 | `DarkModeNotifier` | `darkModeProvider` | `core/di/providers.dart` |
| 主题模式 | `AppThemeNotifier` | `themeModeProvider` | `core/di/providers.dart` |
| 视口状态 | `DrawingViewportNotifier` | `viewportProvider` | `drawing/application/viewport_notifier.dart` |
| 选区状态 | `DrawingSelectionNotifier` | `selectionProvider` | `drawing/application/selection_notifier.dart` |
| 历史状态 | `DrawingHistoryNotifier` | `historyProvider` | `drawing/application/history_notifier.dart` |
| 图片元素 | `DrawingImagesNotifier` | `imagesProvider` | `drawing/application/images_notifier.dart` |
| 形状元素 | `DrawingShapesNotifier` | `shapesProvider` | `drawing/application/shapes_notifier.dart` |
| Editor V2 | `EditorV2Notifier` | `editorV2NotifierProvider` | `editor_v2/application/editor_v2_viewmodel.dart` |
| 多页画布 | `PagedCanvasNotifier` | `pagedCanvasNotifierProvider` | `editor_v2/application/paged_canvas_viewmodel.dart` |
| 画笔样式 | `StrokeStyleNotifier` | `strokeStyleProvider` | `editor_v2/application/stroke_style_notifier.dart` |
| 无限画布 | `InfiniteCanvasNotifier` | `infiniteCanvasProvider` | `editor_v2/application/infinite_canvas_notifier.dart` |

### 1.3 仍使用 ChangeNotifier 的模块

| 类名 | 职责 | 行数 | 复杂度 | 文件 |
|------|------|------|--------|------|
| `AppThemeController` | 主题模式（旧版） | 77 | 低 | `core/theme/app_theme_controller.dart` |
| `DrawingController` | 绘图引擎核心 | 971+8 part | **极高** | `drawing/application/drawing_controller.dart` |
| `EditorViewModel` | 编辑器工具状态 | 205 | 中 | `drawing/presentation/editor_viewmodel.dart` |

---

## 二、迁移计划

### Phase 1：清理冗余（1 天）

#### 2.1 删除 `AppThemeController`

**原因**：已有 `AppThemeNotifier`（Riverpod Notifier）完全替代。

- 检查 `AppThemeController` 是否还有引用
- 如无引用，直接删除 `core/theme/app_theme_controller.dart`
- 如有引用，替换为 `ref.watch(themeModeProvider)`

**风险**：低  
**验证**：`flutter analyze` 无错误

#### 2.2 确认 `Consumer` 使用点

`app.dart:95` 使用了 `Consumer` widget：
```dart
builder: (context, _) => Consumer(
```
这是 Riverpod 的标准 widget，不是 `provider` 包的 Consumer。无需迁移。

### Phase 2：EditorViewModel 迁移（2 天）

#### 2.3 将 `EditorViewModel` 迁移为 Riverpod Notifier

**当前状态**：`EditorViewModel extends ChangeNotifier`（205 行）

**迁移方案**：
```dart
// 新文件：features/drawing/application/editor_notifier.dart

@immutable
class EditorState {
  const EditorState({
    this.eyedropperActive = false,
    this.textToolActive = false,
    this.linkMode = false,
    this.linkSourceId,
    this.selectionDone = false,
    this.selectedItemId,
    this.editingItemId,
    this.pendingTextItem,
  });

  final bool eyedropperActive;
  final bool textToolActive;
  final bool linkMode;
  final String? linkSourceId;
  final bool selectionDone;
  final String? selectedItemId;
  final String? editingItemId;
  final PageTextItem? pendingTextItem;

  EditorState copyWith({...}) => ...
}

class EditorNotifier extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  // 所有 EditorViewModel 的方法迁移为 state = state.copyWith(...)
  // 自动保存逻辑保留为 Timer 管理
}

final editorProvider = NotifierProvider<EditorNotifier, EditorState>(
  EditorNotifier.new,
);
```

**迁移步骤**：
1. 创建 `EditorState` 不可变状态类
2. 创建 `EditorNotifier extends Notifier<EditorState>`
3. 将 `EditorViewModel` 的所有 setter 方法迁移为 `state = state.copyWith(...)`
4. 将自动保存 Timer 逻辑保留在 Notifier 中
5. 更新 `editor_page.dart` 中的引用
6. 删除 `EditorViewModel`

**风险**：中（需要更新 editor_page.dart 的所有 Consumer 监听点）

### Phase 3：DrawingController 分域拆解（3-5 天）⚠️ 最复杂

#### 2.4 DrawingController 现状分析

`DrawingController` 是 971 行 + 8 个 part 文件的巨型 ChangeNotifier，职责包括：

| 域 | Part 文件 | 行数 | 已有 Riverpod Notifier |
|---|---|---|---|
| 视口变换 | `drawing_controller_viewport.dart` | ~80 | ✅ `DrawingViewportNotifier` |
| 选区工具 | `drawing_controller_selection.dart` | ~120 | ✅ `DrawingSelectionNotifier` |
| 撤销/重做 | `drawing_controller_history.dart` | ~100 | ✅ `DrawingHistoryNotifier` |
| 图片元素 | `drawing_controller_images.dart` | ~150 | ✅ `DrawingImagesNotifier` |
| 形状元素 | `drawing_controller_shapes.dart` | ~120 | ✅ `DrawingShapesNotifier` |
| 图层管理 | `drawing_controller_layers.dart` | ~80 | ❌ 未迁移 |
| 笔画绘制 | `drawing_controller_stroke.dart` | ~150 | ❌ 未迁移 |
| 文字元素 | `drawing_controller_text.dart` | ~100 | ❌ 未迁移 |

**策略**：**渐进式双写**（Strangler Fig Pattern）

```
┌─────────────────────────────────────────────────┐
│  阶段 A：新 Notifier 读取 DrawingController 状态  │
│  （已有：viewport/selection/history/images/shapes）│
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  阶段 B：新 Notifier 接管写入操作                  │
│  （待迁移：layers/stroke/text）                    │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  阶段 C：DrawingController 退化为纯引擎            │
│  （仅保留绘图算法，状态全部由 Riverpod 管理）       │
└─────────────────────────────────────────────────┘
```

#### 2.5 未迁移域详细计划

**LayerNotifier**（图层管理）：
- 状态：`currentLayerIndex`, `layerVisibility`, `layerOpacity`
- 操作：`addLayer`, `removeLayer`, `reorderLayers`, `toggleVisibility`
- 预计：~80 行

**StrokeNotifier**（笔画绘制）：
- 状态：`currentStroke`, `brushType`, `strokeWidth`, `color`
- 操作：`startStroke`, `addPoint`, `endStroke`
- 预计：~150 行

**TextNotifier**（文字元素）：
- 状态：`textItems`, `editingTextId`
- 操作：`addText`, `updateText`, `deleteText`
- 预计：~100 行

---

## 三、执行顺序

| 优先级 | 任务 | 预计工期 | 风险 |
|--------|------|----------|------|
| P0 | 删除 `AppThemeController` | 0.5 天 | 低 |
| P1 | `EditorViewModel` → Riverpod Notifier | 2 天 | 中 |
| P2 | `LayerNotifier` 拆分 | 1 天 | 中 |
| P2 | `StrokeNotifier` 拆分 | 1.5 天 | 高 |
| P2 | `TextNotifier` 拆分 | 1 天 | 中 |
| P3 | `DrawingController` 退化为纯引擎 | 2 天 | 高 |

**总工期**：约 8 天

---

## 四、验证标准

每个阶段完成后必须满足：

1. `flutter analyze` 零错误零警告
2. 所有现有测试通过
3. 手动测试：创建笔记 → 绘图 → 撤销/重做 → 保存 → 加载
4. 无内存泄漏（`ref.onDispose` 正确清理）
5. 每个迁移模块单独 commit

---

## 五、风险缓解

| 风险 | 缓解措施 |
|------|----------|
| DrawingController 双状态源不一致 | 阶段 A 先做只读桥接，阶段 B 再切换写入 |
| UI 刷新异常 | 每个 Notifier 迁移后立即手动测试 |
| 自动保存丢失 | EditorViewModel 的 Timer 逻辑必须完整迁移 |
| 性能退化 | Riverpod 的 select() 可做细粒度订阅 |

---

*计划完成。等待 Leader 确认后开始执行。*
