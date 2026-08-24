// Inspira UI——列表项入场动画（stagger 交错效果）。
//
// 用途：搜索结果、文件列表等场景的入场动画。
// - [StaggerEntrance]：单项包装器，淡入 + 上滑，按 index 交错延迟
// - [StaggeredListView]：ListView.builder 的 drop-in 替代
//
// 性能与可访问性约定：
// - 动画只在首次构建播放（滚动复用不重播）
// - 尊重系统"减少动态效果"→ 直接显示
// - 交错延迟封顶，长列表不会越排越慢
import 'package:flutter/material.dart';

/// 入场方向：上/下/左/右滑入。
enum StaggerDirection { up, down, left, right }

/// 默认单项时长 / 交错步长 / 最大总延迟。
const Duration kStaggerItemDuration = Duration(milliseconds: 360);
const Duration kStaggerStep = Duration(milliseconds: 40);
const int kStaggerMaxSteps = 12; // 第 13 项起与第 12 项同时入场

/// 单项入场动画包装器：透明度 0→1 + 沿 [direction] 反向位移归位。
///
/// [index] 决定交错延迟；[enabled]=false 时直接显示
/// （由宿主根据 MediaQuery.disableAnimations 决定）。
class StaggerEntrance extends StatefulWidget {
  const StaggerEntrance({
    super.key,
    required this.child,
    required this.index,
    this.direction = StaggerDirection.up,
    this.distance = 24,
    this.itemDuration = kStaggerItemDuration,
    this.step = kStaggerStep,
    this.enabled = true,
  });

  final Widget child;
  final int index;

  /// 入场方向：元素从该方向的反侧滑入（[StaggerDirection.up] = 自下而上）。
  final StaggerDirection direction;

  /// 起始位移距离（逻辑像素）。
  final double distance;
  final Duration itemDuration;
  final Duration step;
  final bool enabled;

  @override
  State<StaggerEntrance> createState() => _StaggerEntranceState();
}

class _StaggerEntranceState extends State<StaggerEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.itemDuration);
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    final stepIndex = widget.index.clamp(0, kStaggerMaxSteps);
    final delay = widget.step * stepIndex;
    Future<void>.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        final d = widget.distance * (1 - t);
        // up=自下而上；down=自上而下；left=自右向左；right=自左向右。
        final offset = switch (widget.direction) {
          StaggerDirection.up => Offset(0, d),
          StaggerDirection.down => Offset(0, -d),
          StaggerDirection.left => Offset(d, 0),
          StaggerDirection.right => Offset(-d, 0),
        };
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: offset,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// [ListView.builder] 的带入场动画版本。
///
/// 其余参数透传给 ListView.builder；
/// [itemBuilder] 返回的内容会被自动包上 [StaggerEntrance]。
class StaggeredListView extends StatelessWidget {
  const StaggeredListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.disableAnimations = false,
    this.direction = StaggerDirection.up,
    this.distance = 24,
    this.itemDuration = kStaggerItemDuration,
    this.step = kStaggerStep,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final bool disableAnimations;

  /// 入场方向与距离、单项目时长与交错步长，透传给 [StaggerEntrance]。
  final StaggerDirection direction;
  final double distance;
  final Duration itemDuration;
  final Duration step;

  @override
  Widget build(BuildContext context) {
    final reduced =
        disableAnimations || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return ListView.builder(
      itemCount: itemCount,
      controller: controller,
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: padding,
      itemBuilder: (context, index) => reduced
          ? itemBuilder(context, index)
          : StaggerEntrance(
              index: index,
              direction: direction,
              distance: distance,
              itemDuration: itemDuration,
              step: step,
              child: KeyedSubtree(
                key: ValueKey('stagger-$index'),
                child: itemBuilder(context, index),
              ),
            ),
    );
  }
}
