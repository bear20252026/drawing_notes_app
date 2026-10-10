import 'package:flutter/widgets.dart';

import 'package:drawing_notes_app/core/theme/apple_motion.dart';

/// 列表错位入场（stagger）包装。
///
/// 消费 [AppleMotion.staggerItem]/[AppleMotion.staggerStep] 两个此前零
/// 消费的预留令牌（M-09 审计 2026-09-27 成对保留）：首屏前 [maxStaggered]
/// 项按序错位淡入 + 8px 上移（[AppleMotion.enterOffsetY]），其余项直出
/// ——长列表不为屏外行付动画。
///
/// - 入场 = opacity 0→1 + translateY(8→0)，[AppleMotion.easeOut]；
/// - `reduceMotion` 时只保留淡入（去位移——规范「更轻不是零」）；
/// - 只播一次：列表滚动/刷新不重播（无 didUpdateWidget 重触发）。
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.maxStaggered = 10,
  });

  /// 行序：决定错位延迟（index × staggerStep）。
  final int index;

  final Widget child;

  /// 参与错位的最大行数（其后直出）。默认 10。
  final int maxStaggered;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    final inRange = widget.index < widget.maxStaggered;
    if (!inRange) {
      _entered = true;
      return;
    }
    // 挂起一帧再入场：避免与列表首建同帧（jank），错位延迟从这一帧起算。
    final delay = AppleMotion.staggerStep * widget.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(delay, () {
        if (mounted) setState(() => _entered = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppleMotion.reduceMotionOf(context);
    final inRange = widget.index < widget.maxStaggered;
    if (!inRange) return widget.child;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _entered ? 1 : 0),
      duration: AppleMotion.staggerItem,
      curve: AppleMotion.easeOut,
      child: widget.child,
      builder: (context, t, child) {
        final dy = reduce ? 0.0 : AppleMotion.enterOffsetY * (1 - t);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
    );
  }
}
