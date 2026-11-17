import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';

/// S5 验证：Riverpod 编译时安全 + 可测试性（ProviderContainer 独立构建）。
///
/// R5 裁决（业主批准 2026-11-17）：B2~B4 派生 provider 与三域 Notifier 示范
/// 测试随生产零消费的示范单元一并删除；保留 themeProvider/themeModeProvider
/// （生产在用）与 B1 容器本体测试（drawingControllerProvider 已生产接线）。
void main() {
  test('themeProvider 编译时安全：ProviderContainer 可独立读取', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final theme = container.read(themeProvider(false));
    expect(theme, isNotNull);
    expect(theme.brightness, Brightness.light);
  });

  test('themeProvider 按对比度档返回不同配色（平台域裁决 C2）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final normal = container.read(themeProvider(false));
    final high = container.read(themeProvider(true));

    // 常规档：卡片边框是 8% 发丝线；高对比度档：纯黑 100% 不透明。
    final normalShape = normal.cardTheme.shape! as RoundedRectangleBorder;
    final highShape = high.cardTheme.shape! as RoundedRectangleBorder;
    expect(normalShape.side.color.a, lessThan(0.2));
    expect(highShape.side.color, Colors.black);
  });

  test('provider override 可测试替换（依赖注入）', () {
    // Riverpod 3.x：overrideWithBuild 覆盖 build 返回值（closure 签名 (ref, notifier)）。
    // C-15：载体改测试内本地 provider（原借 darkModeProvider 死代码，已删）。
    final localProvider = NotifierProvider<_TestFlag, bool>(_TestFlag.new);
    final container = ProviderContainer(
      overrides: [localProvider.overrideWithBuild((ref, notifier) => true)],
    );
    addTearDown(container.dispose);

    expect(container.read(localProvider), isTrue, reason: 'override 生效');
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
}

/// override 测试的本地载体（C-15 后不再借用生产 provider）。
class _TestFlag extends Notifier<bool> {
  @override
  bool build() => false;
}
