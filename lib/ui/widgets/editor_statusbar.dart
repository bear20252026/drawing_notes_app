import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../engine/drawing_controller.dart';
import '../../engine/stylus_input.dart';
import '../../models/stroke.dart';

/// 编辑器状态栏（架构重构 R3：从 editor_page 外移的纯展示组件）。
///
/// 显示：当前工具（画笔/橡皮擦）、笔宽、缩放百分比、鼠标画布坐标。
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 纯展示：只监听 [controller] 与 [hoverPos] 并渲染，不含业务逻辑；
/// - 不读写文件、不操作存储层。
class EditorStatusBar extends StatelessWidget {
  const EditorStatusBar({
    super.key,
    required this.controller,
    required this.hoverPos,
    required this.inkPressureSample,
  });

  final DrawingController controller;

  /// 鼠标悬停/移动时的画布坐标（状态栏显示）。
  final ValueListenable<Offset?> hoverPos;

  /// 最近一次墨迹输入的压力来源。为空表示尚未开始书写。
  final ValueListenable<InkPressureSample?> inkPressureSample;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final isEraser = controller.tool == BrushType.eraser;
          final activeSize = isEraser
              ? controller.eraserSize
              : controller.brushSize;
          return ValueListenableBuilder<Offset?>(
            valueListenable: hoverPos,
            builder: (context, pos, _) =>
                ValueListenableBuilder<InkPressureSample?>(
                  valueListenable: inkPressureSample,
                  builder: (context, pressure, _) {
                    final scalePercent = (controller.viewScale * 100).round();
                    final coord = pos != null
                        ? 'x:${pos.dx.round()} y:${pos.dy.round()}'
                        : 'x:- y:-';
                    final pressureLabel = pressure?.diagnostics;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEraser ? Icons.auto_fix_high : Icons.brush,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isEraser ? '橡皮擦' : '画笔',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${activeSize.round()}px',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$scalePercent%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (pressureLabel != null) ...[
                            const SizedBox(width: 12),
                            Tooltip(
                              message: pressure!.hasHardwarePressure
                                  ? '正在使用设备上报的真实压力范围'
                                  : '当前设备未报告可用压感，正在使用稳定的回退策略',
                              child: Text(
                                pressureLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: pressure.hasHardwarePressure
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            coord,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          );
        },
      ),
    );
  }
}
