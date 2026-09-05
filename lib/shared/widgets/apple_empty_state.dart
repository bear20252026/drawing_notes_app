// 空态统一组件（审计二-4：空态两极分化——部分页面有插画引导，部分
// 只有一行灰字）。单一事实来源：icon + 标题 + 引导语 + 可选行动按钮，
// 尺寸/颜色对齐「记下第一笔」规范形态（all_docs 首次使用空态）。
//
// 适用全页/整卡空态；空间受限的嵌入场景（侧栏窄条、大纲 rail、
// 卡片内嵌提示）保持紧凑一行字，刻意不套用本组件。
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';

class AppleEmptyState extends StatelessWidget {
  const AppleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.tip,
    this.actions = const [],
  });

  /// 主图标（56，muted 弱化色）。
  final IconData icon;

  /// 空态标题（一句话说清「这里是什么、为什么空」）。
  final String title;

  /// 引导语（12.5，告诉用户下一步做什么；null 则不显示）。
  final String? tip;

  /// 主行动按钮（可选；Wrap 居中排布）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtle = AppleColor.mutedOf(scheme);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: subtle),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          if (tip != null) ...[
            const SizedBox(height: 4),
            Text(
              tip!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: subtle),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
