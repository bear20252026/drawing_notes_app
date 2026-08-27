import 'package:material_ui/material_ui.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/application/history_notifier.dart';
import 'package:drawing_notes_app/features/drawing/application/selection_notifier.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/application/viewport_notifier.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';

/// S5 验证：Riverpod 编译时安全 + 可测试性（ProviderContainer 独立构建）。
void main() {
  test('themeProvider 编译时安全：ProviderContainer 可独立读取', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final theme = container.read(themeProvider);
    expect(theme, isNotNull);
    expect(theme.brightness, Brightness.light);
  });

  test('darkModeProvider 可读可写（单向状态流）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(darkModeProvider), isFalse);
    container.read(darkModeProvider.notifier).state = true;
    expect(container.read(darkModeProvider), isTrue);
  });

  test('provider override 可测试替换（依赖注入）', () {
    // Riverpod 3.x：overrideWithBuild 覆盖 build 返回值（closure 签名 (ref, notifier)）。
    final container = ProviderContainer(
      overrides: [darkModeProvider.overrideWithBuild((ref, notifier) => true)],
    );
    addTearDown(container.dispose);

    expect(container.read(darkModeProvider), isTrue, reason: 'override 生效');
  });

  test('themeModeProvider：Notifier 维护主题模式（替代 ChangeNotifier）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(themeModeProvider),
      ThemeMode.system,
      reason: '初始跟随系统',
    );
    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(
      container.read(themeModeProvider),
      ThemeMode.dark,
      reason: 'setMode 更新状态',
    );
  });

  test('themeModeProvider：cycle 循环切换（system→light→dark→system）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(themeModeProvider.notifier).setMode(ThemeMode.system);
    container.read(themeModeProvider.notifier).cycle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    container.read(themeModeProvider.notifier).cycle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    container.read(themeModeProvider.notifier).cycle();
    expect(container.read(themeModeProvider), ThemeMode.system);
  });
  test('B1: drawingControllerProvider 经 ProviderContainer 可独立单测', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final doc = DrawingDocument(id: 'b1', title: 'B1 迁移示范');
    final controller = container.read(drawingControllerProvider(doc));
    expect(controller.isDirty, isFalse);
    controller.touchDocument();
    expect(controller.isDirty, isTrue, reason: 'history 操作经 provider 可达');
  });
  test('B2: drawingDirtyProvider 派生未保存状态（select 收窄）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final doc = DrawingDocument(id: 'b2', title: 'B2 派生示范');
    expect(container.read(drawingDirtyProvider(doc)), isFalse);
    container.read(drawingControllerProvider(doc)).touchDocument();
    container.invalidate(drawingDirtyProvider(doc)); // 失效重建（Riverpod 标准）
    expect(
      container.read(drawingDirtyProvider(doc)),
      isTrue,
      reason: 'invalidate 后派生 provider 反映控制器脏标记',
    );
  });
  test('B3-B4: 核心状态派生 provider（undo/redo/图层）可独立单测', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final doc = DrawingDocument(id: 'b34', title: 'B3-B4 派生示范');
    final controller = container.read(drawingControllerProvider(doc));
    expect(container.read(drawingCanUndoProvider(doc)), isFalse);
    expect(container.read(drawingCanRedoProvider(doc)), isFalse);
    expect(container.read(drawingCurrentLayerProvider(doc)), 0);
    controller.touchDocument();
    container.invalidate(drawingCanUndoProvider(doc));
    container.invalidate(drawingCurrentLayerProvider(doc));
    expect(
      container.read(drawingCurrentLayerProvider(doc)),
      0,
      reason: 'touchDocument 不改图层索引，派生值稳定',
    );
  });
  test('视口域 Notifier：首个域迁移示范（不可变 state + 方法）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(viewportProvider).scale, 1.0);
    container.read(viewportProvider.notifier).setScale(2.0);
    expect(
      container.read(viewportProvider).scale,
      2.0,
      reason: 'setScale 更新不可变 state',
    );
    container.read(viewportProvider.notifier).pan(10, 20);
    expect(container.read(viewportProvider).offsetX, 10);
    expect(container.read(viewportProvider).offsetY, 20);
    container.read(viewportProvider.notifier).reset();
    expect(container.read(viewportProvider).scale, 1.0);
  });
  test('选区域 Notifier：第二个域迁移示范（begin/extend/end/clear）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sel = container.read(selectionProvider);
    expect(sel.isActive, isFalse);
    container
        .read(selectionProvider.notifier)
        .beginSelection(SelectionTool.rect, const Offset(10, 10));
    expect(container.read(selectionProvider).isActive, isTrue);
    container
        .read(selectionProvider.notifier)
        .extendSelection(const Offset(100, 100));
    expect(container.read(selectionProvider).draft.length, 2, reason: '矩形=2 点');
    container.read(selectionProvider.notifier).clearSelection();
    expect(container.read(selectionProvider).isActive, isFalse);
  });
  test('历史域 Notifier：第三个域迁移示范（canUndo/canRedo 可见状态）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final hist = container.read(historyProvider);
    expect(hist.canUndo, isFalse);
    expect(hist.canRedo, isFalse);
    container
        .read(historyProvider.notifier)
        .notifyChanged(canUndo: true, canRedo: false);
    expect(container.read(historyProvider).canUndo, isTrue);
    container
        .read(historyProvider.notifier)
        .afterUndo(canUndo: false, canRedo: true);
    expect(container.read(historyProvider).canRedo, isTrue);
    expect(container.read(historyProvider).canUndo, isFalse);
  });
}
