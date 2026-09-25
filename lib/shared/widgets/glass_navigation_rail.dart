// 液态玻璃侧边导航栏（v1.17.20，导航类控件玻璃化收尾）。
//
// 与 [GlassNavigationBar]（v1.10.5 底部导航条）同一配方家族：
// - Apple HIG / iOS 26 liquid glass 侧栏语义：玻璃材质替换 [NavigationRail]
//   的默认不透明表面；
// - M3 交互行为保留：NavigationRail 的 indicator（选中态）、labelType、
//   目的地切换动画、tooltip 全部原生不变——玻璃只替换材质；
// - [NavigationRail] 构造参数本就默认透明三件套由外层 Theme 控制，这里
//   直接显式置透明（与底部条同口径：材质全透明 + elevation 0）。
//
// 红线对照（DESIGN_SYSTEM.md）：侧边导航栏是常驻浮层，属玻璃合法域；
// 栏内无嵌套玻璃（indicator 非材质层），非玻璃叠玻璃。
//
// 布局边界（app_shell 宽屏分支）：Row 布局下内容不在栏后延伸——玻璃基底
// 模糊的是 Scaffold 背景（视觉为半透明面板 + 边缘亮线，桌面无滚动内容
// 从属），不做 extendBody 式左让位（内容左缘贴栏是桌面列表的可读性前提，
// 与窄屏底条的 extendBody 语义不同源，见 app_shell 接入注释）。
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 玻璃侧边导航栏：[NavigationRail] 的材质替换壳。
///
/// ```dart
/// NavigationRail(
///   ...,
/// ) // 替换为 ↓
/// GlassNavigationRail(
///   selectedIndex: _index,
///   onDestinationSelected: _onSelect,
///   destinations: _railDestinations(),
/// )
/// ```
class GlassNavigationRail extends StatelessWidget {
  const GlassNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.leading,
    this.trailing,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationRailDestination> destinations;
  final Widget? leading;
  final Widget? trailing;

  /// 浮层配方：与玻璃弹窗/底部导航条同家族（sigma 16 / 基底 0.72）。
  static const double kSigma = 16;
  static const double kSurfaceOpacity = 0.72;

  /// 玻璃面板外边距（悬浮面板语义，与底条 kInsetH 同源）。
  static const double kInset = 8;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(kInset),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppleRadius.lg),
        sigma: kSigma,
        surfaceOpacity: kSurfaceOpacity,
        child: NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          leading: leading,
          trailing: trailing,
          // 材质全透明：玻璃壳提供基底；indicator 保留（选中态）。
          // elevation 不置 0——SDK 断言要求 null 或 >0，交由默认值。
          backgroundColor: Colors.transparent,
          indicatorColor: null, // 保留 M3 默认 indicator（选中交互态）。
          destinations: destinations,
        ),
      ),
    );
  }
}
