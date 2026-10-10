import 'package:flutter/material.dart';

/// 选区操作条动作按钮（复制/粘贴/锁定/删除/清除等）。
///
/// 巨型类 Widget 组合解耦（2026-08-15 阶段 3）：从 editor_page_drag_ops
/// 的 [_selectionAction] 提取为独立 Widget（DEV 2026-08 方案：纯 UI
/// 渲染提取 Widget、交互经回调注入；selection_area 组件先例）。
/// 纯 UI：icon/tooltip/onTap 三参数，无状态逻辑。
class SelectionActionButton extends StatelessWidget {
  const SelectionActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        // P1-7：compact 密度命中区约 40px，低于 HIG/WCAG 2.5.5 的 44px
        // 触控下限——与状态栏/图层面板同款补最小约束（视觉不变）。
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: onTap,
      ),
    );
  }
}
