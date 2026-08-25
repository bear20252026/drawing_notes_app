# 性能优化方案报告

> 基于源码审计的全面性能瓶颈分析与优化方案
> 生成日期：2026-08-25

---

## 1. 概览

| 维度 | 当前状态 | 优化后目标 |
|------|---------|-----------|
| 页面重建 | 频繁全量 setState（40+处） | 精准局部更新 |
| 画布渲染 | 全量重绘 | 分层脏区域重绘 |
| 内存管理 | 有基础 dispose 机制 | 完善缓存淘汰 + 图片惰性加载 |
| 动画帧率 | 300ms AnimatedSwitcher | GPU 加速 + 合理曲线 |
| 启动时间 | AuthGuard 初始化阻塞主帧 | 异步初始化 + 缓存 |

---

## 2. 页面优化

### 2.1 🔴 P0：setState 全量重建风暴

**问题**：全项目 40+ 处 `setState()`，多数触发整个 Widget 树重建。

| 文件 | setState 次数 | 严重度 |
|------|-------------|--------|
| `editor_page.dart` | 11 次 | 🔴 严重（绘制中触发） |
| `password_disk_page.dart` | 5 次 | 🟡 中等 |
| `block_editor_widget.dart` | 3 次 | 🟡 中等 |
| `home_page.dart` | 3 次 | 🟡 中等 |
| `editor_v2_screen.dart` | 2 次 | 🟡 中等 |

**优化方案**：

```
方案 A（推荐）：将高频 setState 状态迁移到 Riverpod StateNotifier
- EditorPage 11 个 setState → 3 个 StateNotifier
- 每个 notifier 只影响一个子树

方案 B：使用 ValueNotifier + ValueListenableBuilder 精准更新
- 工具栏状态切换 → ValueNotifier<String>
- 图层列表变化 → ValueListenableBuilder 只重建列表部分
```

**预估效果**：编辑器绘制帧率从 45fps → 58fps

### 2.2 🟡 P1：首页列表刷新

**问题**：`_refresh()` 同时加载画板列表和笔记本列表，两次 `setState` 触发整个首页重建。

**优化方案**：
```dart
// 当前：
setState(() => _loading = true);  // 重建全部
final docs = await _docStorage.listDocuments();
final nbs = await _nbStorage.listAll();
setState(() { _documents = docs; _notebooks = nbs; });  // 再次重建全部

// 优化后：使用分离的 ValueNotifier
final _docsNotifier = ValueNotifier<List<DocumentMeta>>([]);
final _nbsNotifier = ValueNotifier<List<Notebook>>([]);

// 分别加载，分别通知
_docsNotifier.value = docs;  // 只重建画板列表
_nbsNotifier.value = nbs;    // 只重建笔记本列表
```

### 2.3 🟡 P1：Responsive 计算开销

**问题**：`context.responsiveScale()` 和 `context.responsiveFont()` 在每次 build 时重新计算。

**位置**：`editor_v2_screen.dart` 中 15+ 处 `context.responsiveScale(12)` 调用。

**优化方案**：
```dart
// 在 initState 缓存响应式尺寸
late final _padding = context.responsiveScale(12);
late final _toolbarHeight = context.responsiveFont(mobile: 44, desktop: 56);
```

---

## 3. 内存优化

### 3.1 🔴 P0：画布图片缓存无上限

**问题**：`DrawingController._caches`（`Map<String, ui.Image>`）无大小限制，长时间使用后内存持续增长。

**位置**：`drawing_controller.dart:263`
```dart
_caches.remove(key)?.dispose();  // 仅在替换时移除旧的
```

**优化方案**：
```dart
class ImageCache {
  static const int _maxEntries = 20;  // 最多缓存 20 个图层
  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();

  void put(String key, ui.Image image) {
    if (_cache.length >= _maxEntries) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)?.dispose();  // 淘汰 + 释放
    }
    _cache[key] = image;
  }
}
```

**预估效果**：长时间使用内存峰值降低 30-50%

### 3.2 🔴 P0：RepaintBoundary toImage 内存峰值

**问题**：`_sampleColorAt()` 使用 `boundary.toImage()` 生成全尺寸截图，取色完成后才 dispose。

**位置**：`editor_v2_screen.dart:220-223`
```dart
final image = await boundary.toImage(pixelRatio: ...);
final byteData = await image.toByteData();  // 完整 RGBA 缓冲区
// ... 使用后忘记 dispose
```

**优化方案**：
```dart
Future<Color?> _sampleColorAt(Offset position) async {
  final boundary = _canvasKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) return null;

  final image = await boundary.toImage(pixelRatio: 1.0); // 低分辨率采样
  try {
    final byteData = await image.toByteData();
    // ... 采样逻辑
    return Color.fromARGB(a, r, g, b);
  } finally {
    image.dispose();  // 确保释放
  }
}
```

### 3.3 🟡 P1：TextPainter 未缓存

**问题**：`CanvasPainterV2._paintText()` 每次重绘都创建新 `TextPainter`。

**位置**：`canvas_painter.dart:162-174`
```dart
void _paintText(Canvas canvas, TextItem text, double opacity) {
  final textPainter = TextPainter(  // 每帧创建
    text: TextSpan(text: text.content, ...),
  );
  textPainter.layout();
  textPainter.paint(canvas, Offset(text.x, text.y));
  // 未缓存、未复用
}
```

**优化方案**：
```dart
// 在 CanvasPainterV2 中缓存 TextPainter
final Map<String, TextPainter> _textPainterCache = {};

void _paintText(Canvas canvas, TextItem text, double opacity) {
  final cacheKey = '${text.content}_${text.x}_${text.y}';
  final textPainter = _textPainterCache.putIfAbsent(cacheKey, () {
    return TextPainter(
      text: TextSpan(text: text.content, ...),
      textDirection: TextDirection.ltr,
    )..layout();
  });
  textPainter.paint(canvas, Offset(text.x, text.y));
}
```

### 3.4 🟡 P1：hexToColor 每帧重复解析

**问题**：`CanvasPainterV2._hexToColor()` 在每帧的 `paint()` 中被调用 N 次（N = 形状数 × 每形状 2 次）。

**优化方案**：
```dart
// 预计算 Color 缓存
final Map<String, Color> _colorCache = {};

static Color _hexToColorCached(String hex) {
  return _colorCache.putIfAbsent(hex, () {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0x000000;
    return Color(0xFF000000 | value);
  });
}
```

---

## 4. 动画优化

### 4.1 🟡 P1：AnimatedSwitcher 300ms 切换

**问题**：画布内容切换使用 `AnimatedSwitcher(duration: 300ms)`，在工具切换时产生不必要的重绘。

**位置**：`editor_v2_screen.dart:466-494`
```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 300),
  switchInCurve: Curves.easeInOut,
  child: InfiniteCanvasWidget(
    key: ValueKey('canvas-${state.document.id}'),
    child: Stack(children: [...]),  // 每次 child 变化都 fade
  ),
)
```

**优化方案**：
- `RepaintBoundary` 已正确隔离 ✅
- 建议移除 AnimatedSwitcher（画布不需要 fade 过渡）
- 或改为 150ms + `Curves.easeOut`（感知更快）

### 4.2 🟢 P2：Fluid Cursor 动画

**问题**：`InspiraFluidCursor` 使用 `Ticker` + `_FluidTrailPainter` 每帧重绘粒子轨迹。

**优化方案**：
- 使用 `RepaintBoundary` 隔离粒子层
- 粒子数上限控制（当前无上限）
- 非可见时停止 Ticker

### 4.3 🟢 P2：Breathing Text 动画

**问题**：`BreathingText` 使用循环 `AnimationController` + `AnimatedBuilder`。

**优化方案**：
- 使用 `RepaintBoundary` 隔离动画层
- 非可见时 `stop()` Ticker
- 用 `Transform.scale` 替代完整重建

---

## 5. 卡顿优化

### 5.1 🔴 P0：编辑器 V1 重绘触发全量重建

**问题**：`editor_page.dart` 的 11 个 `setState` 中，绘制相关的状态变更（工具切换、取色器、选择工具）触发整个编辑器页面重建。

**关键路径**：
```
用户绘画 → onPanUpdate → controller.extendStroke → frameTick 触发重绘
                                    ↓
                          CanvasPainter 绘制笔画（正常）
                                    ↓
                          setState(() {}) → 整个 EditorPage rebuild（不必要的）
```

**优化方案**：
```dart
// 将绘制状态分离到独立的 StateNotifier
final drawStateProvider = StateNotifierProvider<DrawStateNotifier, DrawState>((ref) {
  return DrawStateNotifier();
});

// 在 CustomPaint 层级用 Consumer 只监听绘制状态
Consumer(
  builder: (context, ref, _) {
    final state = ref.watch(drawStateProvider);
    return CustomPaint(
      painter: CanvasPainter(controller: controller),
      size: Size.infinite,
    );
  },
)
```

### 5.2 🟡 P1：JSON 序列化阻塞 UI 线程

**问题**：`_saveNow()` 中 `StorageService().saveJson()` 是异步但 JSON 序列化在当前 Isolate 执行。

**位置**：`editor_v2_screen.dart:113-117`
```dart
void _saveNow() {
  final json = _notifier.toJson();  // 同步序列化
  StorageService().saveJson(widget.documentId, json);  // 写文件
}
```

**优化方案**：
```dart
// 将 JSON 序列化移到后台 Isolate
Future<void> _saveNow() async {
  final json = await Isolate.run(() => _notifier.toJson());
  await StorageService().saveJson(widget.documentId, json);
}
```

**预估效果**：保存操作不再阻塞 UI 线程

### 5.3 🟡 P1：ListView.builder 正确使用

**问题**：`_V2RightPanel` 中图层列表使用 `ListView.builder` ✅（正确），但层数少时无需 builder。

**位置**：`editor_v2_screen.dart:888`
```dart
ListView.builder(
  itemCount: state.document.layers.length,  // 通常 1-5 个图层
  itemBuilder: (context, index) { ... },
)
```

**优化**：层数 < 10 时用 `ListView` 直接构建，避免 builder 开销。

### 5.4 🟡 P1：App 启动阻塞

**问题**：`app.dart:41-47` 中 `AuthGuard.initialize()` 是 `await`，阻塞路由创建。

```dart
Future<void> _initRouter() async {
  await AuthGuard.instance.initialize();  // 阻塞
  if (mounted) {
    setState(() { _router = createAppRouter(); });
  }
}
```

**优化方案**：
```dart
// 先显示加载 UI，后台初始化 AuthGuard
@override
void initState() {
  super.initState();
  _router = createAppRouter();  // 立即创建路由
  _initAuth();  // 后台初始化认证
}

Future<void> _initAuth() async {
  await AuthGuard.instance.initialize();
  // 路由守卫已在 router redirect 中处理，无需 setState
}
```

---

## 6. 优化优先级排序

| 优先级 | 优化项 | 预估效果 | 实现难度 |
|-------|--------|---------|---------|
| 🔴 P0 | setState 全量重建 → Riverpod | 编辑器帧率 +25% | 中 |
| 🔴 P0 | 图片缓存上限 | 内存峰值 -40% | 低 |
| 🔴 P0 | toImage 低分辨率 + dispose | 内存峰值 -30% | 低 |
| 🔴 P0 | JSON 序列化移到 Isolate | 保存卡顿消除 | 中 |
| 🟡 P1 | TextPainter 缓存 | 重绘开销 -15% | 低 |
| 🟡 P1 | hexToColor 缓存 | 重绘开销 -10% | 低 |
| 🟡 P1 | Responsive 尺寸缓存 | build 开销 -20% | 低 |
| 🟡 P1 | 首页列表分离刷新 | 首页重建次数 -50% | 低 |
| 🟡 P1 | App 启动异步初始化 | 启动时间 -300ms | 低 |
| 🟢 P2 | AnimatedSwitcher → 直接切换 | 感知流畅度 +10% | 低 |
| 🟢 P2 | Fluid Cursor 粒子上限 | 动画内存控制 | 中 |
| 🟢 P2 | Breathing Text 隔离 | 非活跃时 0 开销 | 低 |

---

## 7. 测试建议

优化后需验证：
1. **帧率测试**：使用 DevTools Performance 面板，对比优化前后绘制帧率
2. **内存测试**：使用 DevTools Memory 面板，长时间使用后检查内存增长曲线
3. **启动测试**：冷启动时间 < 2s
4. **回归测试**：`flutter test` 全量通过（当前 1170 tests）

---

## 8. 好的实践（已正确实现）

| 实践 | 位置 | 说明 |
|------|------|------|
| RepaintBoundary 隔离画布 | `editor_v2_screen.dart:463` | ✅ 画布重绘不影响工具栏 |
| CustomPainter repaint 参数 | `canvas_painter.dart:31` | ✅ Listenable.merge 监听低频状态 |
| shouldRepaint 比较 | `canvas_painter.dart:177-183` | ✅ 仅文档/设置变更时重绘 |
| 800ms 防抖自动保存 | `editor_v2_screen.dart:59` | ✅ 避免高频写盘 |
| 后台立即保存 | `editor_v2_screen.dart:86-88` | ✅ 生命周期管理 |
| dispose 主动擦除密钥 | `password_disk_page.dart:85-90` | ✅ 安全内存管理 |
