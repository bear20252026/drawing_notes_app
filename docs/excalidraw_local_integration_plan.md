# Excalidraw 本地化集成方案（2026-08-21）

## 一、Excalidraw 核心模式提取（可本地化）

| 模式 | Excalidraw 实现 | Flutter 适配 |
|------|----------------|-------------|
| **无限画布** | `canvas.transform(matrix4)` + 世界空间裁剪 | `Matrix4` + `InteractiveViewer`/`GestureDetector` + `CustomPainter` |
| **多画布** | 多 Scene 文件（`.excalidraw` JSON） | PageV2 + PagedCanvasViewModel（**已完成**） |
| **图片支持** | `ImageItem` + base64 嵌入 `.excalidraw` | ImageItem + MediaRepositoryV2（**已完成**） |
| **橡皮擦** | 对象擦除（距离判定）+ 像素擦除（`BlendMode.clear`） | EraseByDistanceCommand + RestoreErasedCommand（**已完成**） |
| **撤销/重做** | History 双栈 + `commitToHistory` 标记 | DocumentReducer（**已完成**） |
| **导出** | PNG/SVG/JSON 格式 | F-5 方案已就绪（`pdf` 包 + `toImage()`） |
| **手绘风格** | `Rough.js`（Canvas 粗糙线条） | Flutter CustomPainter（可选——先功能后风格） |

## 二、安全约束（不搞崩）

| 约束 | 实施 |
|------|------|
| **测试后合入** | 先在 `feat/batch-f-infinite-canvas` 分支测试——验证不崩——再合 master |
| **渐进集成** | 每次小步骤（ViewportState → Transform → 裁剪 → 手势）——验证通过再下一步 |
| **回滚准备** | git commit 每步——可回滚 |
| **不改现有功能** | 无限画布是新增层——不修改现有 CanvasPainterV2/PagedCanvasViewModel |

## 三、批次 F-6 实施计划（无限画布——Excalidraw 模式）

### 步骤 1：ViewportState（视口状态）

```dart
// lib/features/editor_v2/application/viewport_state.dart
@immutable
class ViewportState {
  const ViewportState({this.scale = 1.0, this.offsetX = 0.0, this.offsetY = 0.0});
  final double scale;
  final double offsetX;
  final double offsetY;
  
  // 世界坐标 ↔ 屏幕坐标转换
  Offset worldToScreen(Offset world) => Offset(
    world.dx * scale + offsetX,
    world.dy * scale + offsetY,
  );
  Offset screenToWorld(Offset screen) => Offset(
    (screen.dx - offsetX) / scale,
    (screen.dy - offsetY) / scale,
  );
  
  // 可见世界区域（用于裁剪）
  Rect visibleWorldRect(Size viewportSize) => Rect.fromLTWH(
    -offsetX / scale,
    -offsetY / scale,
    viewportSize.width / scale,
    viewportSize.height / scale,
  );
  
  ViewportState copyWith({double? scale, double? offsetX, double? offsetY}) =>
    ViewportState(
      scale: scale ?? this.scale,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
    );
}
```

### 步骤 2：InfiniteCanvasNotifier（Riverpod Notifier）

```dart
// lib/features/editor_v2/application/infinite_canvas_notifier.dart
@riverpod
class InfiniteCanvasNotifier extends _$InfiniteCanvasNotifier {
  @override
  ViewportState build() => const ViewportState();

  void pan(double dx, double dy) {
    state = state.copyWith(
      offsetX: state.offsetX + dx,
      offsetY: state.offsetY + dy,
    );
  }

  void zoom(double scale, Offset focalPoint) {
    final newScale = (state.scale * scale).clamp(0.1, 10.0);
    final dx = focalPoint.dx - (focalPoint.dx - state.offsetX) * newScale / state.scale;
    final dy = focalPoint.dy - (focalPoint.dy - state.offsetY) * newScale / state.scale;
    state = ViewportState(scale: newScale, offsetX: dx, offsetY: dy);
  }

  void reset() => state = const ViewportState();
}
```

### 步骤 3：InfiniteCanvasWidget（InteractiveViewer + CustomPainter）

```dart
// lib/features/editor_v2/presentation/infinite_canvas_widget.dart
class InfiniteCanvasWidget extends ConsumerWidget {
  final Widget child; // CanvasPainterV2
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(infiniteCanvasProvider);
    return GestureDetector(
      onScaleUpdate: (details) {
        if (details.pointerCount == 1) {
          ref.read(infiniteCanvasProvider.notifier).pan(
            details.focalPointDelta.dx,
            details.focalPointDelta.dy,
          );
        } else if (details.pointerCount >= 2) {
          ref.read(infiniteCanvasProvider.notifier).zoom(
            details.scale,
            details.localFocalPoint,
          );
        }
      },
      child: Transform(
        transform: Matrix4.identity()
          ..translate(viewport.offsetX, viewport.offsetY)
          ..scale(viewport.scale),
        child: child,
      ),
    );
  }
}
```

### 步骤 4：集成到 EditorV2Screen

```dart
// 替换现有 CanvasPainterV2 包装
InfiniteCanvasWidget(
  child: CustomPaint(
    painter: CanvasPainterV2(document: state.document),
    size: Size.infinite,
  ),
)
```

## 四、验收标准（F-6）

- [ ] 双指缩放（0.1x ~ 10x）
- [ ] 拖拽平移
- [ ] 性能：世界空间裁剪（只绘制可见区域）
- [ ] 边界约束（可选：画布边界不超出）
- [ ] 不影响现有功能（F-1 分页/F-2 图片/F-3 橡皮擦/CUJ-01~07）
- [ ] flutter analyze 零问题
- [ ] 全量测试（408+）不回归

## 五、参考文档

- [Excalidraw 源码](https://github.com/excalidraw/excalidraw)（130k 星标/4075 提交）
- [excalidraw-cn](https://github.com/korbinjoe/excalidraw-cn)（中文手写+多画布+ReveZone）
- [canvas_kit](https://pub.dev/packages/canvas_kit)（composable infinite pan/zoom canvas）
- [scribe_canvas](https://pub.dev/packages/scribe_canvas)（多页画布/手写/PDF 导出）
- 专家方案批次 F（`docs/batch_f_recovery_plan.md`）
- 专家目标架构（`docs/editor_v2_architecture_plan.md`）
