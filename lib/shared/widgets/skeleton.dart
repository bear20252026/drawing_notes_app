// U4a 设计精修（2026-09-02）：首屏加载骨架屏。
//
// 替代列表页裸 CircularProgressIndicator：以真实布局形态（行/卡片网格）
// 的灰色占位 + 呼吸脉冲呈现，减少"白屏→内容跳变"。遵循系统
// 「减弱动态效果」设置（MediaQuery.disableAnimationsOf → 静态）。
//
// 性能优化：呼吸脉冲不再由每个骨架块各起一个 AnimationController..
// repeat（8 行 × 3 块 = 24 个 ticker），改为**骨架组件级共享单
// controller**——由 SkeletonList / SkeletonCardGrid 的 State 创建并传入，
// 全部块以 AnimatedBuilder 监听同一个；dispose 随父 State 收口
// （父组件即「最后一个使用者」，语义正确）。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';

/// 呼吸脉冲骨架块（脉冲动画由父组件的共享 controller 驱动）。
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.controller,
    required this.width,
    required this.height,
    required this.radius,
  });

  final AnimationController controller;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 禁用动画时保持静止全亮度。
        final opacity = disabled ? 1.0 : 0.5 + 0.5 * controller.value;
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// 列表首屏骨架（AllDocs 桌面/移动共用）：
/// 与 AllDocRow 同形态（36 图标块 + 标题/副标题两条）。
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 8});

  final int rows;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  /// 全部骨架块共享的呼吸脉冲（见文件头说明）。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: widget.rows,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, _) => Row(
        children: [
          _SkeletonBlock(controller: _pulse, width: 36, height: 36, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(
                  controller: _pulse,
                  width: MediaQuery.sizeOf(context).width * 0.4,
                  height: 13,
                  radius: AppleRadius.xs,
                ),
                const SizedBox(height: 8),
                _SkeletonBlock(
                  controller: _pulse,
                  width: 160,
                  height: 10,
                  radius: AppleRadius.xs,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _SkeletonBlock(controller: _pulse, width: 22, height: 22, radius: 11),
        ],
      ),
    );
  }
}

/// 卡片网格首屏骨架（HomePage 画布/分页画布 Tab）：
/// 与 _DrawingCard/_NotebookCard 同网格参数（maxCrossAxisExtent 256）。
class SkeletonCardGrid extends StatefulWidget {
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
  State<SkeletonCardGrid> createState() => _SkeletonCardGridState();
}

class _SkeletonCardGridState extends State<SkeletonCardGrid>
    with SingleTickerProviderStateMixin {
  /// 全部卡片块共享的呼吸脉冲（见文件头说明）。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: widget.maxCrossAxisExtent,
        childAspectRatio: widget.childAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: widget.count,
      itemBuilder: (_, _) => _SkeletonBlock(
        controller: _pulse,
        width: double.infinity,
        height: double.infinity,
        radius: AppleRadius.md,
      ),
    );
  }
}
