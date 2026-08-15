import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

/// 形状 8 向缩放手柄（四角 + 四边中点，借鉴 Excalidraw）。
///
/// 巨型类 Widget 组合解耦（2026-08-15 阶段 1）：从 editor_page_drag_ops
/// 的 [_buildResizeHandles]/[_resizeHandle] 提取为独立 Widget（DEV
/// 2026-08 方案：只读渲染提取 Widget、交互经回调注入）。
/// - 纯渲染：手柄位置计算 + 外观 + 手势检测；
/// - 交互编排（修改 shape 状态/通知）经 [onResize] 回调注入由 State 承担。
class ResizeHandles extends StatelessWidget {
  const ResizeHandles({
    super.key,
    required this.shape,
    required this.width,
    required this.height,
    required this.screenToCanvasDelta,
    required this.onResize,
    required this.onChanged,
  });

  /// 目标形状（决定手柄所属元素；实际修改由回调完成）。
  final PageShapeItem shape;

  /// 元素外接框尺寸（画布坐标，经 viewScale 换算后为手柄位置）。
  final double width;
  final double height;

  /// 屏幕增量 → 画布增量（视口旋转/缩放换算，由宿主注入）。
  final Offset Function(Offset screenDelta) screenToCanvasDelta;

  /// 手柄拖拽回调：[pos] 为手柄位置（画布坐标），[delta] 为画布增量，
  /// [isCorner] 区分角/边手柄（角调宽高、边调单边）。
  final void Function(Offset pos, Offset delta, bool isCorner) onResize;

  /// 拖拽结束通知（宿主 State 通知变更/自动保存）。
  final VoidCallback onChanged;

  static const double _handleSize = 10.0;

  @override
  Widget build(BuildContext context) {
    const size = _handleSize;
    final corners = <Offset>[
      Offset(0, 0), // 左上
      Offset(width, 0), // 右上
      Offset(0, height), // 左下
      Offset(width, height), // 右下
    ];
    final edges = <({Offset pos, bool horizontal})>[
      (pos: Offset(width / 2, 0), horizontal: false), // 上
      (pos: Offset(width / 2, height), horizontal: false), // 下
      (pos: Offset(0, height / 2), horizontal: true), // 左
      (pos: Offset(width, height / 2), horizontal: true), // 右
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final c in corners)
          _handle(pos: c, size: size, isCorner: true),
        for (final e in edges)
          _handle(pos: e.pos, size: size, isCorner: false),
      ],
    );
  }

  Widget _handle({
    required Offset pos,
    required double size,
    required bool isCorner,
  }) {
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          final delta = screenToCanvasDelta(d.delta);
          onResize(pos, delta, isCorner);
          onChanged();
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF42A5F5),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
      ),
    );
  }
}
