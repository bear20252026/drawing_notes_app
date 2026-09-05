// 液态玻璃 FAB（v1.10.5，导航类控件玻璃化）。
//
// 设计来源：
// - Apple HIG / liquid-glass-react（tmp_design_refs 配方已沉淀，
//   见 shaders/liquid_glass.frag 头注释）：浮层玻璃 = blur + saturate + 基底色。
// - M3 交互行为保留：ink state layer、尺寸（圆形 56 / extended 高 56）、
//   hero 语义不变——玻璃只替换材质，不替换交互。
//
// 红线对照（DESIGN_SYSTEM.md）：FAB 是浮层（悬浮于内容之上），属玻璃合法域；
// 与底部玻璃导航条同屏共存（不嵌套，非玻璃叠玻璃）。
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 玻璃 FAB：[FloatingActionButton] 的材质替换壳。
///
/// 用法与原生 FAB 参数对齐（onPressed / child / heroTag），调用点零迁移成本：
/// ```dart
/// floatingActionButton: GlassFab.extended(
///   onPressed: _createCanvas,
///   icon: const Icon(Icons.add),
///   label: const Text('新建画布'),
/// )
/// ```
class GlassFab extends StatelessWidget {
  /// 圆形玻璃 FAB（M3 默认 56dp）。
  const GlassFab({super.key, required this.onPressed, this.child, this.heroTag})
    : _extendedIcon = null,
      _extendedLabel = null;

  /// 胶囊玻璃 FAB（M3 extended，高 56dp）。
  const GlassFab.extended({
    super.key,
    required this.onPressed,
    required Widget icon,
    required Widget label,
    this.heroTag,
  }) : child = null,
       _extendedIcon = icon,
       _extendedLabel = label;

  final VoidCallback? onPressed;
  final Widget? child;
  final Object? heroTag;
  final Widget? _extendedIcon;
  final Widget? _extendedLabel;

  /// 浮层配方：与玻璃弹窗同家族（sigma 16 / 基底 0.72）。
  static const double kSigma = 16;
  static const double kSurfaceOpacity = 0.72;

  /// M3 FAB 直径 / extended 高度 → 玻璃圆角（胶囊全圆）。
  static const double kRadius = 28;

  @override
  Widget build(BuildContext context) {
    final isExtended = _extendedIcon != null;
    final Widget fab = isExtended
        ? FloatingActionButton.extended(
            heroTag: heroTag,
            onPressed: onPressed,
            // 材质全透明：玻璃壳提供基底；state layer（ink）保留交互反馈。
            backgroundColor: Colors.transparent,
            elevation: 0,
            highlightElevation: 0,
            hoverElevation: 0,
            focusElevation: 0,
            icon: _extendedIcon,
            label: _extendedLabel!,
          )
        : FloatingActionButton(
            heroTag: heroTag,
            onPressed: onPressed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            highlightElevation: 0,
            hoverElevation: 0,
            focusElevation: 0,
            child: child,
          );
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(kRadius)),
      sigma: kSigma,
      surfaceOpacity: kSurfaceOpacity,
      child: fab,
    );
  }
}
