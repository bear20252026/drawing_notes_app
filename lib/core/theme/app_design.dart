import 'package:flutter/material.dart';

import 'app_theme_spec.dart';
import 'apple_contrast.dart';
import 'apple_design.dart';
import 'material_theme_adapter.dart';

// `ThemeMode` 的落盘 wire 名适配（CTL-03 ②）——做成 part 而不是独立库，
// 是为了让 `core/di/providers.dart` 不必为它新增一条 import 边
// （那会把 Martin instability 从 0.33 推到 0.50，撞上路 3b 的 0.4 基线）。
part 'theme_mode_wire.dart';

/// 应用统一设计语言。
///
/// 目标不是模仿任何平台的专有控件，而是以内容优先、低噪声表面层级、
/// 稳定间距和可访问触控尺寸构建克制而有质感的创作工作区。
///
/// 颜色策略（用户@要求保留深蓝色系）：
///   - 明亮模式 = Apple（苹果）配色：Action Blue `#0066CC`、米白底 `#F5F5F7`、墨色 `#1D1D1F`。
///   - 黑暗模式 = 既有深蓝（navy）配色：`#4568A9` / `#101521` / `#181F2E` / `#222B3D`。
///   - 结构风格（圆角 / 间距 / 字重 / 动效 / 胶囊 / 过渡）= 统一为 Apple 风格，两种模式一致。
abstract final class AppDesign {
  // ---- 深蓝（黑暗模式）核心色板：保留 ----
  // 双令牌源收编（审计四-1）：与 AppleColor 同值的常量一律改别名引用，
  // 单一事实来源——改令牌对全部消费文件同步生效，杜绝配色静默分叉。
  // （2026-11-12 清理：navyInk `#172033` / navyAccent `#4568A9` 两个常量
  // 零消费者已删——深蓝配色本身由 `_navyScheme()` 的 ColorScheme 承担，
  // 未随之改动；`#4568A9` 仍是该 scheme 的 inversePrimary。）
  static const Color darkCanvas = AppleColor.canvansDark;
  static const Color darkSurface = AppleColor.surfaceDark;
  static const Color darkSubtleSurface = AppleColor.subtleSurfaceDark;

  // ---- Apple（明亮模式）核心色板 ----
  static const Color ink = AppleColor.ink; // Apple 主体墨色
  static const Color accent = AppleColor.actionBlue; // Action Blue
  static const Color lightCanvas = AppleColor.parchment; // 米白底 (parchment)
  static const Color lightSurface = AppleColor.surfaceWhite;
  // 注意：与 AppleColor.subtleSurface（0xFFEBEBED）是**两个不同的灰阶**
  //（本处为 systemGray6），刻意不合并——合并即改视觉，需实机对比另行裁决。
  static const Color lightSubtleSurface = Color(0xFFF2F2F7);

  // ---- Apple 结构风格（两种模式一致）----
  // 主题适配层（2026-11-16）：pagePadding 权威已收编进 AppThemeSpec
  //（斩断适配器→本文件的循环边）；此处保留别名，80+ 消费文件零改动。
  static const double pagePadding = AppThemeSpec.pagePadding;
  static const double compactPagePadding = 12;

  /// 卡片圆角 = `AppleRadius.lg`（DESIGN.md:425「Store utility cards」18px）。
  static const double cardRadius = AppleRadius.lg;

  /// 控件圆角 = `AppleRadius.md`（DESIGN.md:424「White Pearl Button
  /// capsules」11px）。此前写死 12——属于 DESIGN.md:511 明令禁止的
  ///「mixing radii grammars」。
  static const double controlRadius = AppleRadius.md;
  // M-01（审计 2026-09-27）：影子时长令牌 quickMotion(140ms)/
  // standardMotion(200ms) 已删除——时长令牌唯一权威是 AppleMotion
  // （press 120 / dropdown 200 等七档），影子令牌会让 140ms 这样的
  // 离档值绕过动效域门禁。消费点 home_page_widgets 已改 AppleMotion.press。

  /// 明亮模式主题；[contrast] 为 [AppleContrast.high] 时走 Windows
  /// 高对比度配色（平台域裁决 C2）。
  static ThemeData lightTheme({
    AppleContrast contrast = AppleContrast.normal,
  }) => _theme(Brightness.light, contrast);

  /// 深蓝（黑暗）模式主题；[contrast] 同上。
  static ThemeData darkTheme({AppleContrast contrast = AppleContrast.normal}) =>
      _theme(Brightness.dark, contrast);

  /// 便捷工厂：用布尔直接取明亮模式主题。
  ///
  /// 存在的唯一理由是**依赖方向**：DI 装配层（`core/di/providers.dart`）
  /// 的 Martin instability 基线是 0.4，若它为了拿 [AppleContrast] 枚举
  /// 而多一条出向 import，I 值会从 0.33 涨到 0.50 撞上
  /// `test/architecture_test.dart` 规则 3b。用布尔传参即可不引入该依赖。
  static ThemeData lightThemeFor(bool highContrast) => lightTheme(
    contrast: highContrast ? AppleContrast.high : AppleContrast.normal,
  );

  /// 主题装配薄委托（主题适配层 2026-11-16）：决策在 [AppThemeSpec]
  /// （零 Material 依赖的内部模型），Material 装配语法在
  /// [MaterialThemeAdapter]（唯一转换点）。本方法只做枚举→布尔映射。
  /// 产出与重构前逐字段等价（黄金基线回归钉死，四档全覆盖）。
  static ThemeData _theme(Brightness brightness, AppleContrast contrast) =>
      MaterialThemeAdapter.themeOf(
        AppThemeSpec.resolve(
          brightness: brightness,
          highContrast: contrast == AppleContrast.high,
        ),
      );

  /// Apple 明亮模式 ColorScheme。
  static ColorScheme _appleLightScheme() =>
      MaterialThemeAdapter.colorSchemeOf(AppThemeSpec.appleLightColors);

  /// 明亮模式 ColorScheme 的公开只读入口（**本次新增，不改动现有私有名**）。
  ///
  /// 注：本类**不做**「梯子外的值一律禁止」的裁决——DESIGN.md 的排版梯子
  /// 覆盖的是营销/正文档，短交互文案（对话框正文）另有一档，已具名为
  /// [AppleType.dialogBody]。此处提供的是该档的**颜色**来源。
  ///
  /// 存在的理由：`lib/main.dart` 的构建失败兜底 `_BuildErrorFallback`
  /// 刻意不取 `Theme.of(context)`（出错上下文可能已损坏，见该处注释），
  /// 但它仍需要一个「与 ColorScheme 语义一致」的前景色——此前是自造
  /// `Color(0xFFEBEDF3)` / `Colors.black87` 常量对。改为引用本入口后，
  /// 兜底前景色与主题的 `onSurface` / `onSurfaceVariant` 恒等，
  /// 且不需要新增对 `BuildContext` 的依赖。
  ///
  /// 与私有名并存是刻意的：现有测试与调用点仍走 `lightTheme()` /
  /// `darkTheme()`，本次只做「新增一个只读视图」，不改任何既有签名。
  static ColorScheme appleLightScheme() => _appleLightScheme();

  /// 深蓝（navy）黑暗模式 ColorScheme 的公开只读入口（同上）。
  static ColorScheme navyScheme() => _navyScheme();

  /// 深蓝（navy）黑暗模式 ColorScheme —— 保留既有应用身份。
  ///
  /// H1（UI/UX 规范修复，2026-10-17）：`primary` / `surfaceTint` 由
  /// `#B5CCFF` 改为 [AppleColor.actionBlueOnDark] `#2997FF`——DESIGN.md:299
  /// 称 `#0066CC` 为「唯一品牌级交互色」，深色档的同族高亮版即
  /// `actionBlueOnDark`（`apple_focus.dart` 已用同一档做深底焦点环）。
  /// `onPrimary` 保持 `#102244`：对 `#2997FF` 约 5.6:1，稳过 AA。
  static ColorScheme _navyScheme() =>
      MaterialThemeAdapter.colorSchemeOf(AppThemeSpec.navyColors);

  // Windows 高对比度两档色板（亮：纯白底/纯黑字；暗：纯黑底/纯白字，
  // 边框 100% 不透明，正文 ≥7:1）已收编进 AppThemeSpec.highContrast*
  // Colors（含设计依据注释）；原私有 _highContrast*Scheme 委托在
  // _theme 改经 AppThemeSpec.resolve 后零引用，已删（2026-11-16）。
  // 高对比主题入口不变：lightTheme/darkTheme(contrast: AppleContrast.high)。
}
