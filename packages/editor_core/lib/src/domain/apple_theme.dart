// editor_core——AppleTheme 苹果设计语言主题（HIG 2026 借鉴——2026-08-22）。
//
// 用户需求：使用苹果的设计语言——借鉴 Excalidraw/excalidraw-cn/Saber/AFFiNE
// 四个项目的功能与 UI 设计——毛玻璃/圆角/清爽配色。
//
// 苹果 HIG 2026 核心（调研）：
// - Liquid Glass（毛玻璃——半透明材料——反射/折射周围——iOS 26/macOS Tahoe）
// - Clarity/Deference/Depth（清晰/谦逊/层次——三个原则）
// - 语义色（systemBlue 等——设计到角色——非原始 hex——适配亮暗模式）
// - SF Pro（系统字体——body 17pt/大标题 34pt）
// - 44pt 最小点击目标（HIG 规则）
// - 8pt 网格（间距约定——4pt 细分）
//
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

/// 苹果语义色（HIG 2026——设计到角色——非原始 hex——适配亮暗模式）。
class AppleColors {
  const AppleColors._();

  /// 主色（systemBlue——社区测量 #007AFF——非苹果官方保证值）。
  static const primary = '#007AFF';
  static const label = '#000000';
  static const secondaryLabel = '#3C3C43';
  static const tertiaryLabel = '#8E8E93';
  static const background = '#FFFFFF';
  static const secondaryBackground = '#F2F2F7';
  static const success = '#34C759';
  static const danger = '#FF3B30';
  static const warning = '#FF9500';
  static const gray1 = '#8E8E93';
  static const gray2 = '#AEAEB2';
  static const gray3 = '#C7C7CC';
  static const gray4 = '#D1D1D6';
  static const gray5 = '#E5E5EA';
  static const gray6 = '#F2F2F7';

  /// 暗色模式适配（语义角色 → 暗色值——设计到角色）。
  static String roleFor(String hex, {required bool darkMode}) {
    if (!darkMode) return hex;
    switch (hex) {
      case background:
        return '#000000'; // 暗色背景。
      case secondaryBackground:
        return '#1C1C1E'; // 暗色次级背景。
      case label:
        return '#FFFFFF'; // 暗色主文本。
      case secondaryLabel:
        return '#EBEBF5'; // 暗色次级文本。
      case gray1:
        return '#8E8E93';
      case gray2:
        return '#636366';
      case gray3:
        return '#48484A';
      case gray4:
        return '#3A3A3C';
      case gray5:
        return '#2C2C2E';
      default:
        return hex; // 语义色（primary/success/danger 等）暗色不变。
    }
  }
}

/// 苹果设计语言主题（HIG 2026——积木式纯 Dart）。
///
/// 包含：Liquid Glass 毛玻璃参数 / 圆角 / 排版 / 布局规则——
/// 供 UI 层（Flutter Widget）使用——纯数据（可独立测试）。
class AppleTheme {
  const AppleTheme._();

  // ─────────────── Liquid Glass 毛玻璃参数（WWDC25） ───────────────

  /// 毛玻璃表面不透明度（半透明——浮在内容上）。
  static const double glassOpacity = 0.72;

  /// 毛玻璃模糊半径（像素——Liquid Glass 效果）。
  static const double glassBlurRadius = 20.0;

  /// 毛玻璃高光（顶部亮边——玻璃质感）。
  static const double glassHighlightOpacity = 0.35;

  /// 毛玻璃暗边（底部暗边——层次感）。
  static const double glassEdgeOpacity = 0.12;

  // ─────────────── 圆角（Liquid Glass 形状） ───────────────

  /// 标准圆角（卡片/面板——Liquid Glass 控件）。
  static const double cornerRadius = 12.0;

  /// 大圆角（弹窗/侧边栏——更圆润——Liquid Glass 控件）。
  static const double cornerRadiusLarge = 20.0;

  /// 小圆角（按钮/输入框）。
  static const double cornerRadiusSmall = 8.0;

  /// 控件圆角（硬件形状——按钮更圆润——HIG 2026 控件）。
  static const double controlCornerRadius = 10.0;

  // ─────────────── 排版（SF Pro——Dynamic Type） ───────────────

  /// 大标题（34pt——页面标题）。
  static const double largeTitleSize = 34.0;

  /// 标题 1（28pt）。
  static const double title1Size = 28.0;

  /// 标题 2（22pt）。
  static const double title2Size = 22.0;

  /// 标题 3（20pt）。
  static const double title3Size = 20.0;

  /// 正文（17pt——iOS Dynamic Type 默认）。
  static const double bodySize = 17.0;

  /// 注脚（13pt）。
  static const double footnoteSize = 13.0;

  /// 说明（12pt）。
  static const double captionSize = 12.0;

  // ─────────────── 布局（8pt 网格——44pt 点击目标） ───────────────

  /// 间距单位（8pt 网格——4pt 细分）。
  static const double spacingUnit = 8.0;

  /// 最小点击目标（44x44pt——HIG 规则）。
  static const double minTapTarget = 44.0;

  /// 侧边栏宽度（AFFiNE 借鉴——苹果设计语言风格）。
  static const double sidebarWidth = 260.0;

  /// 工具栏高度。
  static const double toolbarHeight = 52.0;

  // ─────────────── 阴影（Depth——层次原则） ───────────────

  /// 卡片阴影（浅——层级 1）。
  static const double shadowOpacity = 0.1;

  /// 卡片阴影模糊半径。
  static const double shadowBlur = 16.0;

  /// 悬浮元素阴影（深——层级 2——Liquid Glass 浮起）。
  static const double floatingShadowOpacity = 0.2;

  /// 获取毛玻璃参数（供 UI 层——Liquid Glass 卡片）。
  static ({double opacity, double blur, double radius}) glassCard() {
    return (
      opacity: glassOpacity,
      blur: glassBlurRadius,
      radius: cornerRadius,
    );
  }
}
