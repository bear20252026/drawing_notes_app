import 'package:flutter/material.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

/// 液态玻璃顶栏（Apple HIG：toolbars 属于「浮层」，可用玻璃）。
///
/// 实现策略：**复用原生 [AppBar] 承担全部布局行为**（status bar 避让、
/// leading/title/actions 排版、bottom 插槽、滚动 elevation），本组件只在它
/// 背后垫一层 [GlassSurface]。这样替换 `AppBar` 时不会引入布局回归——
/// 玻璃是纯附加的背景层，不参与测量。
///
/// ## 必须配合 `extendBodyBehindAppBar`
///
/// 玻璃的观感来自模糊**背后的内容**。Scaffold 默认 `extendBodyBehindAppBar: false`，
/// body 从顶栏下方开始，顶栏背后是纯色 Scaffold 背景 —— 此时 BackdropFilter
/// 无内容可采样，玻璃退化成一块半透明色板。
///
/// 因此接入本组件时，所在 [Scaffold] 必须：
///
/// ```dart
/// Scaffold(
///   extendBodyBehindAppBar: true,   // 让内容延伸到顶栏之后
///   appBar: const GlassAppBar(title: Text('标题')),
///   body: Padding(
///     padding: EdgeInsets.only(top: kToolbarHeight + MediaQuery.paddingOf(context).top),
///     child: ...,
///   ),
/// )
/// ```
///
/// ## 红线：禁止玻璃叠玻璃
///
/// 本组件已是玻璃层，`bottom` 插槽里的东西**不得再自带 [GlassSurface]**，
/// 否则触发「玻璃叠玻璃」红线（`DESIGN_SYSTEM.md:218`，原文 legibility collapses）。
/// 迁移时请摘掉 bottom 内部原有的 GlassSurface，由本组件统一提供玻璃底。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions,
    this.bottom,
    this.saturation,
    this.surfaceOpacity,
    this.sigma,
  });

  final Widget? title;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<Widget>? actions;

  /// 底部插槽（如 TabBar）。**不得再包 GlassSurface**——见类注释红线。
  final PreferredSizeWidget? bottom;

  /// backdrop 饱和度倍率（默认取 [LiquidGlassRecipe.kDefaultSaturation]）。
  final double? saturation;

  /// 基底不透明度（默认取 [LiquidGlassRecipe.kRegularOpacity]）。
  final double? surfaceOpacity;

  /// 模糊标准差（默认取 [LiquidGlassRecipe.kDefaultSigma]）。
  final double? sigma;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  /// 配合 `extendBodyBehindAppBar: true` 时，body 顶部需要让出的高度。
  ///
  /// 内容延伸到顶栏之后才有东西可模糊，但也因此会被顶栏盖住，
  /// 所以 body 必须自行让位。集中在这里计算，避免每个页面手算出错。
  ///
  /// ```dart
  /// Padding(
  ///   padding: EdgeInsets.only(
  ///     top: GlassAppBar.bodyTopPadding(context, bottomHeight: 56),
  ///   ),
  ///   child: ...,
  /// )
  /// ```
  static double bodyTopPadding(
    BuildContext context, {
    double bottomHeight = 0,
  }) {
    return MediaQuery.paddingOf(context).top + kToolbarHeight + bottomHeight;
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      // 顶栏通栏，不套圆角（圆角只用于浮动面板）。
      borderRadius: BorderRadius.zero,
      saturation: saturation ?? LiquidGlassRecipe.kDefaultSaturation,
      surfaceOpacity: surfaceOpacity ?? LiquidGlassRecipe.kRegularOpacity,
      sigma: sigma ?? LiquidGlassRecipe.kDefaultSigma,
      child: AppBar(
        // 玻璃由外层 GlassSurface 提供，这里必须全透明，否则叠一层色板。
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: title,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions,
        bottom: bottom,
      ),
    );
  }
}
