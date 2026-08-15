import 'package:material_ui/material_ui.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
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
    final container = ProviderContainer(
      overrides: [darkModeProvider.overrideWith((ref) => true)],
    );
    addTearDown(container.dispose);

    expect(container.read(darkModeProvider), isTrue, reason: 'override 生效');
  });

  test('themeModeProvider：Notifier 维护主题模式（替代 ChangeNotifier）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system,
        reason: '初始跟随系统');
    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark,
        reason: 'setMode 更新状态');
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
    expect(container.read(drawingDirtyProvider(doc)), isTrue,
        reason: 'invalidate 后派生 provider 反映控制器脏标记');
  });
}
