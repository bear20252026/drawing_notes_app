import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 苹果 HIG 2026 借鉴——AppleTheme 主题系统测试（纯逻辑——不搞崩）。
void main() {
  test('AppleColors：语义色（设计到角色）', () {
    expect(AppleColors.primary, '#007AFF');
    expect(AppleColors.label, '#000000');
    expect(AppleColors.background, '#FFFFFF');
    expect(AppleColors.success, '#34C759');
    expect(AppleColors.danger, '#FF3B30');
    expect(AppleColors.gray6, '#F2F2F7');
  });

  test('AppleColors.roleFor：暗色模式适配（背景/文本反色）', () {
    expect(AppleColors.roleFor(AppleColors.background, darkMode: true), '#000000');
    expect(AppleColors.roleFor(AppleColors.label, darkMode: true), '#FFFFFF');
    expect(AppleColors.roleFor(AppleColors.primary, darkMode: true), '#007AFF'); // 语义色不变。
    // 亮色模式——不变。
    expect(AppleColors.roleFor(AppleColors.background, darkMode: false), '#FFFFFF');
  });

  test('AppleTheme：Liquid Glass 毛玻璃参数', () {
    expect(AppleTheme.glassOpacity, 0.72);
    expect(AppleTheme.glassBlurRadius, 20.0);
    expect(AppleTheme.glassHighlightOpacity, 0.35);
    expect(AppleTheme.glassEdgeOpacity, 0.12);
    final glass = AppleTheme.glassCard();
    expect(glass.opacity, 0.72);
    expect(glass.blur, 20.0);
    expect(glass.radius, 12.0);
  });

  test('AppleTheme：圆角（Liquid Glass 形状）', () {
    expect(AppleTheme.cornerRadius, 12.0);
    expect(AppleTheme.cornerRadiusLarge, 20.0);
    expect(AppleTheme.cornerRadiusSmall, 8.0);
    expect(AppleTheme.controlCornerRadius, 10.0);
  });

  test('AppleTheme：排版（SF Pro——Dynamic Type）', () {
    expect(AppleTheme.largeTitleSize, 34.0);
    expect(AppleTheme.bodySize, 17.0);
    expect(AppleTheme.captionSize, 12.0);
    // 大标题 > 正文（层次——Depth）。
    expect(AppleTheme.largeTitleSize, greaterThan(AppleTheme.bodySize));
  });

  test('AppleTheme：布局（8pt 网格——44pt 点击目标——HIG 规则）', () {
    expect(AppleTheme.spacingUnit, 8.0);
    expect(AppleTheme.minTapTarget, 44.0); // HIG 规则。
    expect(AppleTheme.sidebarWidth, 260.0);
    expect(AppleTheme.toolbarHeight, 52.0);
  });

  test('AppleTheme：阴影（Depth 层次）', () {
    expect(AppleTheme.shadowOpacity, 0.1);
    expect(AppleTheme.shadowBlur, 16.0);
    expect(AppleTheme.floatingShadowOpacity, 0.2);
  });
}
