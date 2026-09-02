// U4a 设计精修（2026-09-02）：首屏加载骨架屏。
//
// 替代列表页裸 CircularProgressIndicator：以真实布局形态（行/卡片网格）
// 的灰色占位 + 呼吸脉冲呈现，减少"白屏→内容跳变"。遵循系统
// 「减弱动态效果」设置（MediaQuery.disableAnimationsOf → 静态）。

import 'package:flutter/material.dart';

/// 呼吸脉冲骨架块。
class _SkeletonBlock extends StatefulWidget {
  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<_SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<_SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 禁用动画时保持静止全亮度。
        final opacity = disabled ? 1.0 : 0.5 + 0.5 * _controller.value;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 列表首屏骨架（AllDocs 桌面/移动共用）：
/// 与 AllDocRow 同形态（36 图标块 + 标题/副标题两条）。
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 8});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, _) => Row(
        children: [
          const _SkeletonBlock(width: 36, height: 36, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(
                  width: MediaQuery.sizeOf(context).width * 0.4,
                  height: 13,
                  radius: 6,
                ),
                const SizedBox(height: 8),
                const _SkeletonBlock(width: 160, height: 10, radius: 5),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _SkeletonBlock(width: 22, height: 22, radius: 11),
        ],
      ),
    );
  }
}

/// 卡片网格首屏骨架（HomePage 画布/分页画布 Tab）：
/// 与 _DrawingCard/_NotebookCard 同网格参数（maxCrossAxisExtent 256）。
class SkeletonCardGrid extends StatelessWidget {
  const SkeletonCardGrid({
    super.key,
    this.count = 6,
    this.maxCrossAxisExtent = 256,
    this.childAspectRatio = 0.82,
  });

  final int count;
  final double maxCrossAxisExtent;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: count,
      itemBuilder: (_, _) => const _SkeletonBlock(
        width: double.infinity,
        height: double.infinity,
        radius: 12,
      ),
    );
  }
}
