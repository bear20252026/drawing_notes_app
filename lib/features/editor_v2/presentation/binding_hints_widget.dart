// editor_v2——BindingHintsWidget 节点连线提示（用户需求 #10——2026-08-24）。
//
// 用户需求：节点连线功能指示不明——应提供交互提示、空态引导与说明文案。
//
// Excalidraw 借鉴：上下文提示 + 空态引导 + 工具说明。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/text_scale_helper.dart';

/// 节点连线提示 Widget（用户需求 #10——交互提示/空态引导）。
///
/// 当用户选择箭头/连线工具时显示：
/// - 工具说明（如何使用箭头连接形状）
/// - 可绑定形状提示（矩形/椭圆/菱形可被连接）
/// - 操作建议（拖拽起点到形状，再拖拽到目标形状）
class BindingHintsWidget extends StatelessWidget {
  const BindingHintsWidget({
    super.key,
    required this.currentTool,
    this.hasShapes = false,
  });

  /// 当前工具名称。
  final String currentTool;

  /// 画布上是否有形状（用于空态引导）。
  final bool hasShapes;

  @override
  Widget build(BuildContext context) {
    // 只在箭头/连线工具时显示提示。
    if (currentTool != 'shape') return const SizedBox.shrink();

    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 工具说明。
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_forward,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getToolHint(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: TextScaleHelper.scaled(context, 13),
                    ),
                  ),
                ],
              ),

              // 可绑定形状提示。
              if (hasShapes) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.link,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '可连接：矩形、椭圆、菱形',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: TextScaleHelper.scaled(context, 12),
                      ),
                    ),
                  ],
                ),
              ],

              // 空态引导。
              if (!hasShapes) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '先创建形状，再用箭头连接',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getToolHint() {
    return '拖拽起点到形状，释放到目标形状完成连接';
  }
}
