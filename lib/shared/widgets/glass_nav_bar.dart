// 液态玻璃底部导航条（v1.10.5，导航类控件玻璃化）。
//
// 设计来源：
// - Apple HIG / iOS 26 liquid glass tab bar：悬浮胶囊 tab bar（玻璃材质 +
//   底部留边）；liquid-glass-react 配方沉淀见 shaders/liquid_glass.frag 头注释。
// - M3 交互行为保留：NavigationBar 的 indicator（选中交互态，非条体材质）、
//   目的地切换动画、tooltip 全部原生不变——玻璃只替换材质。
//
// 红线对照（DESIGN_SYSTEM.md）：底部导航条是常驻浮层，属玻璃合法域；
// 条内无嵌套玻璃（indicator 非材质层），非玻璃叠玻璃。
//
// 让位机制（与 settings_page 顶栏注释同原则——可滚动让位优先）：
// - 配合 Scaffold `extendBody: true` 使用：Scaffold 会把本条总高
//   （[kHeight] + [kBottomMargin]）注入 body 的 MediaQuery.padding.bottom，
//   页面按各自结构消费（见 app_shell 接入注释）。
// - 系统手势区/3 键导航：由本组件内部 [SafeArea] 消费 viewPadding.bottom，
//   胶囊永远悬浮在系统栏上方；再向内清零注入，防止 NavigationBar
//   的内部 SafeArea 二次膨胀。
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 玻璃底部导航条：[NavigationBar] 的材质替换壳。
///
/// ```dart
/// bottomNavigationBar: GlassNavigationBar(
///   selectedIndex: _index,
///   onDestinationSelected: _onSelect,
///   destinations: _barDestinations(),
/// ),
/// ```
class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;

  /// 浮层配方：与玻璃弹窗同家族（sigma 16 / 基底 0.72）。
  static const double kSigma = 16;
  static const double kSurfaceOpacity = 0.72;

  /// 胶囊条本体高度（M3 NavigationBar 默认 80，悬浮形态收窄到 64）。
  static const double kHeight = 64;

  /// 胶囊左右留边（悬浮于内容之上，iOS 26 tab bar 语义）。
  static const double kInsetH = 12;

  /// 胶囊底部留边（同时为系统手势区留出呼吸空间）。
  static const double kBottomMargin = 12;

  /// 条总高（= extendBody 注入 body 的 MediaQuery.padding.bottom 增量）。
  static double get totalHeight => kHeight + kBottomMargin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kInsetH, 0, kInsetH, kBottomMargin),
      // 消费系统 viewPadding（手势条 / 3 键导航），胶囊悬浮于系统栏上方。
      child: SafeArea(
        top: false,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(kHeight / 2),
          sigma: kSigma,
          surfaceOpacity: kSurfaceOpacity,
          child: SizedBox(
            height: kHeight,
            child: Builder(
              builder: (innerContext) {
                final mq = MediaQuery.of(innerContext);
                return MediaQuery(
                  // 胶囊内不再吃任何底部注入：外层 SafeArea 已完成系统栏
                  // 让位，Scaffold 的 extendBody 注入只应被 body 页面消费，
                  // 不应把胶囊自身撑高。
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(bottom: 0),
                    viewPadding: mq.viewPadding.copyWith(bottom: 0),
                  ),
                  child: NavigationBar(
                    height: kHeight,
                    // 材质全透明：玻璃壳提供基底；indicator 保留（选中态）。
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    destinations: destinations,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
