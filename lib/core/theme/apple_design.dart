import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/apple_pressable.dart';

/// Apple (HIG) 设计语言 token 与可复用部件。
///
/// 参照 DESIGN.md（getdesign@apple）给出的苹果官方规范抽取：
/// - 单一强调色 Action Blue，克制使用；
/// - 低噪声表面层级（米白画布 / 白色表面 / 细描边胶囊），
/// - 胶囊按钮与圆角卡片（18px），
/// - SF 风格排版（标题 w600 + 负字距，正文 17px / 控制文本 13px）。
///
/// 颜色策略（用户@要求保留深蓝色系）：
/// - 明亮模式的「浅色 token」= Apple：米白画布 / 白表面 / 墨色文本。
/// - 黑暗模式的「深色 token」= 既有深蓝（navy）：`#101521` / `#181F2E` / `#222B3D`，
///   以便深色模式保留应用原有深蓝身份；结构风格（圆角/间距/字重/胶囊）两种模式均 Apple。
/// 本类提供可直接复用的部件，供各页面统一采用；页面背景/表面应优先用
/// `Theme.of(context).colorScheme` 自适应，深色模式自动落到深蓝色板。
abstract final class AppleColor {
  /// Action Blue：主强调色。
  static const Color actionBlue = Color(0xFF0066CC);

  /// 深色模式下的高亮蓝（按钮/链接）。
  static const Color actionBlueOnDark = Color(0xFF2997FF);

  /// 焦点蓝（Focus Blue）：键盘焦点环专用，比强调蓝略亮。
  /// DESIGN.md:8 `primary-focus: "#0071e3"`、:300「reserved for the keyboard
  /// focus ring on buttons (`outline: 2px solid`)」、:440 button-primary-focus。
  static const Color focusBlue = Color(0xFF0071E3);

  /// 主墨色（近黑）。
  static const Color ink = Color(0xFF1D1D1F);

  /// 次要墨色。
  static const Color inkMuted = Color(0xFF6E6E73);

  /// 淡墨（辅助说明）。
  static const Color inkSubtle = Color(0xFF98989F);

  /// 米白画布。
  static const Color parchment = Color(0xFFF5F5F7);

  /// 白色表面。
  static const Color surfaceWhite = Color(0xFFFFFFFF);

  /// 输入/芯片浅底。
  static const Color subtleSurface = Color(0xFFEBEBED);

  /// 细描边。
  static const Color hairline = Color(0xFFE0E0E0);

  /// 深色画布（深蓝 navy —— 保留原应用身份）。
  static const Color canvansDark = Color(0xFF101521);

  /// 深色表面（深蓝 navy）。
  static const Color surfaceDark = Color(0xFF181F2E);

  /// 深色芯片底（深蓝 navy）。
  static const Color subtleSurfaceDark = Color(0xFF222B3D);

  /// 环境背景渐变（深色）：内容工作区的低对比底色，
  /// 由 `ambient_background.dart` 的页面字面量收编（令牌层允许定义字面量）。
  static const List<Color> ambientDarkGradient = [
    canvansDark,
    Color(0xFF162034),
    Color(0xFF0F1420),
  ];

  /// 环境背景渐变（浅色）。
  static const List<Color> ambientLightGradient = [
    Color(0xFFF8F9FC),
    Color(0xFFF1F4FA),
    Color(0xFFF7F8FB),
  ];

  /// 星标橙（Apple 系统橙）。
  static const Color favourite = Color(0xFFFF9F0A);

  /// 系统绿（笔记类）。
  static const Color noteGreen = Color(0xFF30D158);

  /// 系统紫（块文档类）。
  static const Color blockPurple = Color(0xFFBF5AF2);

  /// 错误红（Apple 系统红）。
  static const Color errorRed = Color(0xFFFF3B30);

  /// 错误**文本**专用档（P1-3，审计 2026-10-09）。
  ///
  /// #FF3B30 对白底仅 3.55:1，做正文颜色不过 AA（4.5:1）——它只适合
  /// 填充底/图标（3:1 档）。正文级错误提示（保存失败/加载失败/校验
  /// 信息）一律用本档：浅底深红 #B3261E（6.96:1）、深底提亮
  /// #FFB4AB（对 #181F2E ≈ 9:1）。
  static Color errorTextOf(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFFB4AB)
      : const Color(0xFFB3261E);

  // ---------------------------------------------------------------------------
  // 次级信息两级配色
  //
  // **历史债（2026-09-04 清理）**：同一个「次要信息」语义在全库被写成
  // 0.4 / 0.45 / 0.5 / 0.55 / 0.6 **五种 alpha、共 20 处**，深浅模式下观感
  // 各不相同；更糟的是对本身已带 alpha 的语义色再叠乘会造成**二次衰减**
  // （如 dividerColor 8% 再乘 0.08 → 0.64%，分隔线实际不可见）。
  // 现收敛为两级，调用点一律走这两个入口，不再手写 alpha。
  // ---------------------------------------------------------------------------

  /// 次级**文字**色：元信息、描述、分组标题、输入框 hint、空态副文本。
  ///
  /// 走 M3 语义色 `onSurfaceVariant`（浅色 #6E6E73，白底对比度约 5.3:1），
  /// 由主题按明暗档自动适配，**不手工叠 alpha**。
  static Color mutedOf(ColorScheme scheme) => scheme.onSurfaceVariant;

  /// 次级**图标 / 装饰**色：锁标、展开箭头、文件密码标、已完成（勾选）态。
  ///
  /// WCAG 对非文本只要求 3:1，55% onSurface 约 4.0:1，安全且仍读作「次要」。
  static Color subtleOf(ColorScheme scheme) =>
      scheme.onSurface.withValues(alpha: 0.55);

  // ---------------------------------------------------------------------------
  // 画布内容层（domain）色——审计 D-03/D-02 的具名收编点
  //
  // **域边界（docs/AUDIT_2026-09-16.md §六「方法备注」）**：
  // 画布内容层（纸型网格、用户笔迹色、PDF 导出白底、画布底色）按
  // domain 豁免，**不进 UI 铬/组件主题的计违规范围**。但豁免的是「可以
  // 有自己的一套色」，不是「可以留裸字面量」——原写法是散落在
  // canvas_painter / editor_painters 里的 `Color(0xFF...)` 内联字面量，
  // 每次审计扫描都会误报，也无法一处改全局生效。
  // 现按 D-03（具名收编）收进本层：数值逐字不变，语义具名，颜色来源
  // 仍是令牌层而非调用点字面量。**只新增，不删除/不改任何现有令牌。**
  // ---------------------------------------------------------------------------

  /// 无限画布底色（浅色纸面）。
  ///
  /// 原 `CanvasPainter.canvasPaperBackground` 的画布域同值。导出产物
  /// 呈现的底色属内容层，故刻意**不等于** `parchment`（#F5F5F7）——
  /// 合并即改视觉，两个灰阶并存。
  static const Color canvasPaperBackground = Color(0xFFF4F5F7);

  /// 多选锁定态选框琥珀（Excalidraw 同款锁定警示色）。
  ///
  /// 原 `CanvasPainter.lockedSelectionAmber`。属内容层警示反馈，
  /// 与系统橙 [favourite]（#FF9F0A）不同值，不合并。
  static const Color lockedSelectionAmber = Color(0xFFF59E0B);

  /// 缩放提示角标描边（画布域半透明灰）。
  ///
  /// 原 `CanvasPainter.zoomBadgeOutline`；同时用于像素橡皮擦实时圆环。
  static const Color zoomBadgeOutline = Color(0xB0636B78);

  /// 对齐参考线红（Excalidraw 同款对齐可视化）。
  ///
  /// 原 `SnapGuidePainter` 的局部 `alignmentGuideRed`。内容层数据色。
  static const Color alignmentGuideRed = Color(0xFFFF5252);

  /// 次级**面板**底色：分组列头、附件卡、数据库块、反向链接面板、
  /// 画板浮层面板（左侧工具条 / 图层 / 属性 / 选中条 / 状态栏）。
  ///
  /// 此前这类面板写的是 `surfaceContainerHighest.withValues(alpha: 0.35)`，
  /// 散落 5 处、深色模式下几乎不可见；改用 M3 的 `surfaceContainerLow`
  /// 语义档（由 surfaceTint #0066CC 推得，明暗自适应），并与画板既有
  /// 5 处用法统一。
  static Color panelOf(ColorScheme scheme) => scheme.surfaceContainerLow;

  /// **填充式底色**：填充输入框、行内代码高亮等需要「明确有块底」的场景。
  ///
  /// M3 规范：filled TextField 与 code highlight 都用 `surfaceContainerHighest`
  /// 满底。此前是 `surfaceContainerHighest.withValues(alpha: 0.5 / 0.6)` 的
  /// 二次衰减写法，深浅档观感不一致。
  static Color fillOf(ColorScheme scheme) => scheme.surfaceContainerHighest;
}

/// Apple 间距刻度（base=8）。
abstract final class AppleSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// 触控与指针命中区尺寸（**不是**间距刻度，故不入 [AppleSpacing]）。
///
/// AGENTS.md §3 硬要求「触控目标 ≥ 44×44」，DESIGN.md 同口径；此前这条要求在
/// 代码里以 22 个调用点（37 个字面量）的裸 `44` 散落存在（`SizedBox(width: 44,
/// height: 44)` 热区、三个按钮主题的 `Size(44, 44)`），改小了不会有任何门禁报警，
/// 也无法 grep 审计。收敛成具名常量后，§3 的最小目标变成一处可验证的事实。
abstract final class AppleTouch {
  /// 可点击目标的最小边长（触屏主用设备，含图标按钮的热区，不只是图标本体）。
  static const double minTarget = 44;
}

/// Apple 圆角刻度。
///
/// 数值严格对齐 DESIGN.md:127-135（`rounded:` 段），**不得自创中间值**：
/// `none 0 / xs 5 / sm 8 / md 11 / lg 18 / pill 9999 / full 9999`。
/// 本项目未使用 none（需要直角时直接不设 borderRadius）。
abstract final class AppleRadius {
  static const double xs = 5;
  static const double sm = 8;
  static const double md = 11;
  static const double lg = 18;

  /// 胶囊（按钮 / 搜索框 / 芯片）—— Apple 的标志性形状。
  static const double pill = 9999;

  /// 圆形（浮动圆形控件），与 pill 同值但语义不同。
  static const double full = 9999;
}

/// Apple 排版助记（SF 风格：标题 w600 + 负字距，正文 17，控制 13）。
abstract final class AppleType {
  static const double body = 17;
  static const double title = 17;
  static const double control = 13;
  static const double caption = 11.5;
  static const double headline = 22;

  /// 对话框正文（短交互文案）字号：15px / 400 / 行高 1.47。
  ///
  /// **为什么梯子外还有一档**：DESIGN.md 的 15 项排版梯子从 17px 起
  ///（:379「Body copy at 17px, not 16px」是**营销长文**档）；而对话框
  /// 是短交互文案，17px 会把确认弹窗撑成半屏。1.47 的行高规矩照办
  /// （:506 明令行高不得低于 1.47），只把字号收到 UI 尺度。
  ///
  /// 此前 `app_design.dart` 的 dialogTheme 写的是
  /// `AppleType.bodyStyle(...).copyWith(fontSize: 15)`——**裸数字 15**，
  /// 既绕过梯子也没有具名来源。本次收编为令牌（数值逐字未变，故
  /// `apple_dialog_test` 的 `fontSize == 15` 断言照旧通过）。
  static const double dialogBody = 15;

  /// 正文行高。DESIGN.md:346「Body uses 1.47」、:506「Don't tighten
  /// line-height below 1.47 for body copy — the editorial leading is part of
  /// the brand」。此前本项目完全缺失，走的是 Flutter 默认行高。
  static const double bodyLineHeight = 1.47;

  /// Bold 700——DESIGN.md 字梯合法档（300 / 400 / 600 / 700）中最重的一档。
  /// 用于「比 Semibold 高一档」的强调（面板节标题、文档大标题等）；
  /// 裸 FontWeight.w700 不允许散落调用点，统一引用此常量（审计 #11）。
  static const FontWeight bold = FontWeight.w700;

  /// Semibold 600——字梯标准强调档（标题/按钮/标签默认字重）。
  /// 裸 FontWeight.w600 同样收编到此常量（审计 #11/#35）。
  static const FontWeight semibold = FontWeight.w600;

  static TextStyle headlineStyle(Color color) => TextStyle(
    fontSize: headline,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    color: color,
  );

  static TextStyle titleStyle(Color color) => TextStyle(
    fontSize: title,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.35,
    color: color,
  );

  /// 正文。委托给 [AppleTypeScale.body]，保证与 DESIGN.md 的梯子单一来源
  /// （此前字距写的是 -0.1，表上是 -0.374）。
  static TextStyle bodyStyle(Color color) =>
      AppleTypeScale.of(AppleTypeScale.body, color);

  static TextStyle controlStyle(
    Color color, {
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(
    fontSize: control,
    fontWeight: weight,
    letterSpacing: -0.1,
    color: color,
  );

  static TextStyle captionStyle(Color color) => TextStyle(
    fontSize: caption,
    // DESIGN.md:504「Don't set body copy at weight 500 — Apple's ladder is
    // 300 / 400 / 600 / 700, with 500 deliberately absent. Body is always
    // 400」。caption 属正文族，此前误用 500。需要强调的调用点自行
    // copyWith(w600)（量标注、空态主文案即如此）。
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: color,
  );
}

/// 排版梯子中的一格（字号 / 字重 / 行高 / 字距四元组）。
///
/// 四者绑定成一个整体，是为了杜绝「只抄字号、不抄行高」的半吊子落地——
/// 这正是本项目此前的问题：`AppleType.bodyStyle` 有字号和行高，字距却是
/// 自己拍的 -0.1（表上是 -0.374）。
class AppleTypeSpec {
  const AppleTypeSpec(this.size, this.weight, this.height, this.tracking);

  /// 字号（px）。
  final double size;

  final FontWeight weight;

  /// 行高倍数。
  final double height;

  /// 字距（px）。DESIGN.md 用的是 px 而非 em，Flutter 的 letterSpacing
  /// 同样是逻辑像素，可直接对应。
  final double tracking;
}

/// DESIGN.md:336-350 的完整排版梯子（15 项）。
///
/// **权威**：DESIGN.md 的 `typography.*` 表，数值**逐格照抄**，不自行取舍
/// 或四舍五入。`test/core/theme/apple_type_scale_test.dart` 逐格断言与原表
/// 一致，改任何一个数都必须同步改测试与注释。
///
/// 两条配套原则（DESIGN.md:362-372）：
/// - **行高按角色区分**：展示类 1.07–1.19（紧），正文 1.47，页脚密集链接
///   栈例外地放到 2.41（:362 明确「不是 bug」）。
/// - **标题用 600 而非 700**（:369）；17px 及以上带负字距 -0.12~-0.374（:366）。
abstract final class AppleTypeScale {
  const AppleTypeScale._();

  /// 40px / 600 / 1.10 / 0 —— 产品磁贴顶部大标题。
  static const AppleTypeSpec displayLg = AppleTypeSpec(
    40,
    FontWeight.w600,
    1.10,
    0,
  );

  /// 34px / 600 / 1.47 / -0.374 —— 区块标题（SF Pro Text 的展示比例）。
  static const AppleTypeSpec displayMd = AppleTypeSpec(
    34,
    FontWeight.w600,
    1.47,
    -0.374,
  );

  /// 28px / 400 / 1.14 / 0.196 —— 产品磁贴副文案。
  static const AppleTypeSpec lead = AppleTypeSpec(
    28,
    FontWeight.w400,
    1.14,
    0.196,
  );

  /// 24px / 300 / 1.5 / 0 —— 环境页导语段落（罕见的 300 字重）。
  static const AppleTypeSpec leadAiry = AppleTypeSpec(
    24,
    FontWeight.w300,
    1.5,
    0,
  );

  /// 21px / 600 / 1.19 / 0.231 —— 磁贴副标语、子导航分类名。
  static const AppleTypeSpec tagline = AppleTypeSpec(
    21,
    FontWeight.w600,
    1.19,
    0.231,
  );

  /// 17px / 600 / 1.24 / -0.374 —— 行内强调。
  static const AppleTypeSpec bodyStrong = AppleTypeSpec(
    17,
    FontWeight.w600,
    1.24,
    -0.374,
  );

  /// 17px / 400 / 1.47 / -0.374 —— **默认段落**。
  ///
  /// DESIGN.md:379「Body copy at 17px, not 16px. Apple breaks the SaaS
  /// convention」——本项目笔记正文此前用的是 16px。
  static const AppleTypeSpec body = AppleTypeSpec(
    17,
    FontWeight.w400,
    1.47,
    -0.374,
  );

  /// 17px / 400 / 2.41 / 0 —— 页脚 / 商店的密集链接栈。
  static const AppleTypeSpec denseLink = AppleTypeSpec(
    17,
    FontWeight.w400,
    2.41,
    0,
  );

  /// 14px / 400 / 1.43 / -0.224 —— 次级说明、按钮文字。
  static const AppleTypeSpec caption = AppleTypeSpec(
    14,
    FontWeight.w400,
    1.43,
    -0.224,
  );

  /// 14px / 600 / 1.29 / -0.224 —— 强调型说明。
  static const AppleTypeSpec captionStrong = AppleTypeSpec(
    14,
    FontWeight.w600,
    1.29,
    -0.224,
  );

  /// 18px / 300 / 1.0 / 0 —— 商店主 CTA（罕见的 300 字重）。
  static const AppleTypeSpec buttonLarge = AppleTypeSpec(
    18,
    FontWeight.w300,
    1.0,
    0,
  );

  /// 14px / 400 / 1.29 / -0.224 —— 工具 / 导航按钮标签。
  static const AppleTypeSpec buttonUtility = AppleTypeSpec(
    14,
    FontWeight.w400,
    1.29,
    -0.224,
  );

  /// 12px / 400 / 1.0 / -0.12 —— 细则、页脚正文。
  static const AppleTypeSpec finePrint = AppleTypeSpec(
    12,
    FontWeight.w400,
    1.0,
    -0.12,
  );

  /// 10px / 400 / 1.3 / -0.08 —— 微型法律声明。
  static const AppleTypeSpec microLegal = AppleTypeSpec(
    10,
    FontWeight.w400,
    1.3,
    -0.08,
  );

  /// 12px / 400 / 1.0 / -0.12 —— 全局导航菜单项。
  static const AppleTypeSpec navLink = AppleTypeSpec(
    12,
    FontWeight.w400,
    1.0,
    -0.12,
  );

  // ---------------------------------------------------------------------------
  // 梯子外具名档（M2，UI/UX 规范修复 2026-10-17）
  //
  // 上面 15 格是 DESIGN.md:336-350 的**营销/正文档**，逐格照抄、不得增删。
  // 但本项目有三类场景天然落在梯子外，此前是裸 `copyWith(fontSize: N)`
  // 散落调用点——字号无具名来源、审计无法收敛。现收编为**具名档**：
  //
  // - UI 尺度（15/16）：DESIGN.md 的 17px 是营销长文档；列表条目、对话框、
  //   代码块等短交互/等宽场景用 UI 尺度（与 `AppleType.dialogBody` 同口径）。
  // - 锁屏/大号读数（19/26/33）：锁屏与密码盘是**功能读数**而非正文，
  //   字号由可读性与命中区决定，不属排版梯子管辖。
  //
  // 这些档**不进 DESIGN.md 表**（表是营销梯子的逐格照抄），但**进令牌层**
  // —— 调用点一律引用具名常量，不再写裸数字。
  // ---------------------------------------------------------------------------

  /// 15px / 400 / 1.47 / -0.374 —— UI 尺度正文（列表标题、嵌入链接）。
  ///
  /// 与 [AppleType.dialogBody] 同值：DESIGN.md 的 17px 是营销长文档，
  /// 列表条目等短交互文案用 UI 尺度。行高与字距承接正文梯子。
  static const AppleTypeSpec uiBody = AppleTypeSpec(
    15,
    FontWeight.w400,
    1.47,
    -0.374,
  );

  /// 16px / 400 / 1.47 / -0.374 —— 序号标记（列表项前的「1.」「2.」）。
  ///
  /// 落在 14（caption）与 17（body）之间：17 会与正文同大抢主体，
  /// 14 又小于正文导致层级倒挂。16 只作导航提示，不作正文。
  static const AppleTypeSpec ordinal = AppleTypeSpec(
    16,
    FontWeight.w400,
    1.47,
    -0.374,
  );

  /// 19px / 600 / 1.24 / -0.374 —— 锁屏标题（「尝试次数过多」）。
  ///
  /// 锁屏是功能读数场景：标题须压过倒计时数字与说明文字，但小于密码盘
  /// 数字（33px）——19 是两者之间的层级档。
  static const AppleTypeSpec lockTitle = AppleTypeSpec(
    19,
    FontWeight.w600,
    1.24,
    -0.374,
  );

  /// 26px / 700 / 1.19 / -0.35 —— 文档大标题输入框。
  ///
  /// AFFiNE 式正文大标题：比正文（17）大一档、比 display-md（34）小一档。
  /// 字重取 700（[AppleType.bold]）——这是**用户内容**的标题，不是 UI 文案，
  /// DESIGN.md:369「标题用 600」管的是 UI 组件文案，不管用户文档内容。
  static const AppleTypeSpec docTitle = AppleTypeSpec(
    26,
    FontWeight.w700,
    1.19,
    -0.35,
  );

  /// 33px / 400 / 1.0 / 0 —— 密码盘数字键。
  ///
  /// iOS 锁屏同款大号触控读数：字号由命中区（44pt）与可读性决定，
  /// 不属排版梯子管辖。字距归 0（数字不需要负字距）。
  static const AppleTypeSpec pinKey = AppleTypeSpec(
    33,
    FontWeight.w400,
    1.0,
    0,
  );

  /// 按梯子生成 [TextStyle]。
  ///
  /// [fontFamily] / [fontStyle] / [decoration] / [backgroundColor] 是笔记
  /// 编辑器按块类型叠加的变体（等宽、斜体、删除线、块底色），不改变梯子
  /// 本身的四元组。
  static TextStyle of(
    AppleTypeSpec spec,
    Color? color, {
    String? fontFamily,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    Color? backgroundColor,
  }) => TextStyle(
    fontSize: spec.size,
    fontWeight: spec.weight,
    height: spec.height,
    letterSpacing: spec.tracking,
    color: color,
    fontFamily: fontFamily,
    fontStyle: fontStyle,
    decoration: decoration,
    backgroundColor: backgroundColor,
  );
}

/// 交互状态层（平台域裁决 C8，2026-09-04）。
///
/// **权威**：`android/skills`（Google 官方）+ Material 3 状态层规范。
/// `DESIGN.md` 对 hover / pressed 态没有任何规定，属**平台域**——
/// 按 `docs/DESIGN_SYSTEM.md` 第 2 节的分权模型，该域由平台官方规范说了算。
///
/// **不违反「单一强调色」铁律**（DESIGN.md:491）：状态层一律叠
/// `onSurface` 的中性半透明，不引入第二种强调色。描边状的键盘焦点环
/// 另由 `focusBlue` 负责（那是边框，这是底色，两者叠加不冲突）。
abstract final class AppleStateLayer {
  /// 鼠标悬停。
  static const double hover = 0.08;

  /// 键盘焦点（底色；与 2px focusBlue 描边共存）。
  static const double focus = 0.12;

  /// 按压中。
  static const double pressed = 0.12;

  /// 拖拽中。
  static const double dragged = 0.16;

  /// 禁用态前景压低（不是叠层，是 alpha）。
  static const double disabled = 0.38;

  /// 生成按钮 / 可点组件的 `overlayColor`。
  ///
  /// [onSurface] 传主题的 `colorScheme.onSurface`。
  /// 返回 `null` 表示该状态不叠色，保留组件默认行为。
  ///
  /// 判定顺序自「最强状态」往下：拖拽 > 按压 > 焦点 > 悬停。
  /// 禁用态返回 null——禁用由主题统一压低前景，不叠状态色。
  static WidgetStateProperty<Color?> overlay(Color onSurface) {
    return WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return null;
      if (states.contains(WidgetState.dragged)) {
        return onSurface.withValues(alpha: dragged);
      }
      if (states.contains(WidgetState.pressed)) {
        return onSurface.withValues(alpha: pressed);
      }
      if (states.contains(WidgetState.focused)) {
        return onSurface.withValues(alpha: focus);
      }
      if (states.contains(WidgetState.hovered)) {
        return onSurface.withValues(alpha: hover);
      }
      return null;
    });
  }
}

/// 可复用的 Apple 主操作胶囊按钮。
///
/// 示例：`ApplePrimaryButton(label: '新建文档', onPressed: ...)`
class ApplePrimaryButton extends StatelessWidget {
  const ApplePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // ApplePressable 走「纯视觉」模式（onTap 为 null）：按压缩放交给它，
    // 点击行为仍由内部 FilledButton 处理，避免重复触发。
    return ApplePressable(
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.primary),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          padding: WidgetStatePropertyAll(
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppleRadius.pill),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            AppleType.controlStyle(Colors.white),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// 可复用的 Apple 分区标题（分组/工具条分区）。
class AppleSectionHeader extends StatelessWidget {
  const AppleSectionHeader({super.key, required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = AppleColor.mutedOf(scheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppleSpacing.md,
        12,
        AppleSpacing.xs,
        6,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppleType.captionStyle(muted))),
          ?action,
        ],
      ),
    );
  }
}

/// 弹窗「材质外壳」构建器：把已排好顺序的 [actions] 套进某种表面。
///
/// 抽这一层是为了让 `core/` 不必反向依赖 `shared/widgets/` 的玻璃组件——
/// 依赖方向恒为 shared → core：排布与平台按钮顺序留在 core（单一事实来源），
/// 材质（静态视觉域之外的**材质域**）由外层注入。
///
/// 实现约定：外壳必须自己负责与屏幕边缘的间距（inset），因为玻璃层需要
/// 贴合内容边界；内部 [AlertDialog] 的 `insetPadding` 应交由外壳置零。
typedef AppleDialogSurface = Widget Function({
  required Widget? title,
  required Widget? content,
  required List<Widget> actions,
});

/// 可复用的 Apple 确认对话框（R2-M4，架构审计 2026-08-31）。
///
/// 统一「取消 / 确认」双钮模式——全库 AlertDialog 样板 33 处的收敛入口。
/// 示例：`await AppleDialog.confirm(context, title: '彻底删除', content: '…')`
/// 确认返回 true，取消/ dismissing 返回 false；[confirmText] 传错误色文案
/// 时自动使用 error 色（危险操作语义）。
///
/// **平台域裁决 C1（2026-09-04）**：按钮顺序按平台走，不强制一种——
/// - Windows / Linux：主按钮在**左**（Fluent 与 GNOME 的既有习惯）；
/// - macOS / iOS / Android：主按钮在**右**（Apple HIG 与 M3 的习惯）。
/// 依据是 `docs/DESIGN_SYSTEM.md` 的分权模型：按钮顺序属**平台行为域**，
/// `DESIGN.md` 对该域表决权为零（它只管色/字/间距/圆角）。
///
/// **表面注入（2026-09-05）**：[confirm] 只负责排版与平台按钮顺序，
/// 材质外壳由可选的 [AppleDialogSurface] 注入。这样 core 不必反向依赖
/// `shared/widgets/` 的玻璃组件（依赖方向恒为 shared → core），
/// 同时保证「排布逻辑」仍是全库单一事实来源。
class AppleDialog {
  AppleDialog._();

  /// Windows / Linux 把主按钮放在左边。
  static bool get _primaryFirst {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// 给尚未收敛到 [confirm] 的裸 `AlertDialog` 用的平台感知按钮行。
  ///
  /// 调用方**恒定按「次要 → 主要」顺序传入**（与现全库 36 处
  /// `actions: [取消, 确定]` 的写法一致），本方法负责按平台重排：
  /// Windows / Linux 返回倒序（主按钮在左），其余平台原样返回。
  ///
  /// 这样迁移成本 = 把 `actions: [...]` 包一层，不必逐个审查语义。
  static List<Widget> actions(List<Widget> secondaryToPrimary) =>
      _primaryFirst ? secondaryToPrimary.reversed.toList() : secondaryToPrimary;

  /// Esc 取消基建（审计 2026-09-26 #12）：Flutter 的 `showDialog` 不处理
  /// Esc（SDK 源码已核），Windows 对话框惯例的取消键全库缺失。把 [child]
  /// 包上 `Esc → DismissIntent` 映射，[DismissAction] 经 `Navigator.maybePop`
  /// 关闭——与系统返回键同一条路由 pop 通道，因此 `PopScope(canPop: false)`
  /// 的进度类模态天然免疫 Esc（v1.17.24 基建）。
  ///
  /// [confirm] 与 `GlassDialog.show` 共用本方法（单一事实来源）。Esc 关闭
  /// 返回 null，调用方既有的 `?? false` 兜底即取消语义。
  static Widget escClosable(Widget child) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{DismissIntent: _EscDismissAction()},
        child: child,
      ),
    );
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String content,

    /// i18n（E1 批 1）：默认参数无法引用 l10n，改为可空 + 此处运行时
    /// 解析——全库 15+ 依赖默认值的调用点一处收敛。
    String? confirmText,
    String? cancelText,
    bool dangerous = false,

    /// 材质外壳注入点；省略时用裸 `AlertDialog`（既有行为不变）。
    AppleDialogSurface? surface,
  }) async {
    final l10n = AppLocalizations.of(context);
    final cancelButton = TextButton(
      // 三输入可达性：危险操作时初始焦点落在安全的「取消」上
      //（确认按钮是破坏性一侧，不应被回车误触）。
      autofocus: dangerous,
      onPressed: () => Navigator.of(context).pop(false),
      child: Text(cancelText ?? l10n?.cancel ?? '取消'),
    );
    final confirmButton = FilledButton(
      autofocus: !dangerous,
      style: dangerous
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      onPressed: () => Navigator.of(context).pop(true),
      child: Text(confirmText ?? l10n?.commonConfirm ?? '确定'),
    );
    final build = surface ?? _plainSurface;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => escClosable(
        build(
          title: Text(title),
          content: Text(content),
          // 代码里恒定写成「次要 → 主要」，由平台决定谁在左。
          actions: _primaryFirst
              ? <Widget>[confirmButton, cancelButton]
              : <Widget>[cancelButton, confirmButton],
        ),
      ),
    );
    return ok ?? false;
  }

  /// 默认外壳：裸 `AlertDialog`（未注入 [surface] 时的既有外观）。
  static Widget _plainSurface({
    required Widget? title,
    required Widget? content,
    required List<Widget> actions,
  }) {
    return AlertDialog(title: title, content: content, actions: actions);
  }
}

/// Esc 取消动作（审计 2026-09-26 #12）：内置 `DismissAction` 在本 Flutter
/// 版本为抽象类，且需携带 BuildContext 取 Navigator——走 `maybePop` 与
/// 系统返回键同一条路由 pop 通道，`PopScope(canPop: false)` 的模态天然免疫。
class _EscDismissAction extends ContextAction<DismissIntent> {
  _EscDismissAction();

  @override
  Object? invoke(DismissIntent intent, [BuildContext? context]) {
    Navigator.of(context!).maybePop();
    return null;
  }
}
