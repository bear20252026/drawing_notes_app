import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import 'package:drawing_notes_app/features/editor_v2/application/viewport_state.dart';
import 'package:drawing_notes_app/features/editor_v2/application/infinite_canvas_notifier.dart';

/// 批次 F-6：无限画布测试（缩放/平移/重置/坐标转换/可见区域）。
void main() {
  late ProviderContainer container;
  late InfiniteCanvasNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(infiniteCanvasProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('初始状态：scale=1, offset=0', () {
    final state = container.read(infiniteCanvasProvider);
    expect(state.scale, 1.0);
    expect(state.offsetX, 0.0);
    expect(state.offsetY, 0.0);
  });

  test('pan：平移', () {
    notifier.pan(100, 200);
    final state = container.read(infiniteCanvasProvider);
    expect(state.offsetX, 100.0);
    expect(state.offsetY, 200.0);
  });

  test('zoom：缩放（focalPoint 为中心）', () {
    notifier.zoom(2.0, 500, 500);
    final state = container.read(infiniteCanvasProvider);
    expect(state.scale, 2.0);
    // focalPoint 为中心——偏移量应变化。
    expect(state.offsetX, isNot(0.0));
    expect(state.offsetY, isNot(0.0));
  });

  test('zoom：缩放范围限制（0.1 ~ 10.0）', () {
    notifier.zoom(0.01, 0, 0);
    expect(container.read(infiniteCanvasProvider).scale, 0.1);
    notifier.reset();
    notifier.zoom(100, 0, 0);
    expect(container.read(infiniteCanvasProvider).scale, 10.0);
  });

  test('reset：恢复初始状态', () {
    notifier.pan(100, 200);
    notifier.zoom(2.0, 500, 500);
    notifier.reset();
    final state = container.read(infiniteCanvasProvider);
    expect(state.scale, 1.0);
    expect(state.offsetX, 0.0);
    expect(state.offsetY, 0.0);
  });

  test('ViewportState：世界坐标 ↔ 屏幕坐标转换', () {
    const viewport = ViewportState(scale: 2.0, offsetX: 100, offsetY: 200);
    // 世界坐标 (10, 20) → 屏幕坐标 (10*2+100, 20*2+200) = (120, 240)
    final screen = viewport.worldToScreen(10, 20);
    expect(screen.dx, 120.0);
    expect(screen.dy, 240.0);
    // 屏幕坐标 (120, 240) → 世界坐标 ((120-100)/2, (240-200)/2) = (10, 20)
    final world = viewport.screenToWorld(120, 240);
    expect(world.dx, 10.0);
    expect(world.dy, 20.0);
  });

  test('ViewportState：可见世界区域', () {
    const viewport = ViewportState(scale: 2.0, offsetX: 100, offsetY: 200);
    final rect = viewport.visibleWorldRect(800, 600);
    // (0,0) → (-100/2, -200/2) = (-50, -100)
    expect(rect.left, -50.0);
    expect(rect.top, -100.0);
    // (800,600) → ((800-100)/2, (600-200)/2) = (350, 200)
    expect(rect.right, 350.0);
    expect(rect.bottom, 200.0);
  });
}
