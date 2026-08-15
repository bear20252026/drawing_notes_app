import 'package:flutter/material.dart' show Brightness, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/di/providers.dart';

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
}
