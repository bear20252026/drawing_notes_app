import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/presentation/editor_selection_geometry.dart';
import '../../../core/theme/apple_design.dart';

/// 形状 8 向缩放手柄（四角 + 四边中点，借鉴 Excalidraw）。
///
/// 巨型类 Widget 组合解耦（2026-08-15 阶段 1）：从 editor_page_drag_ops
/// 的 [_buildResizeHandles]/[_resizeHandle] 提取为独立 Widget（DEV
/// 2026-08 方案：只读渲染提取 Widget、交互经回调注入）。
/// - 纯渲染：手柄位置计算 + 外观 + 手势检测；
/// - 交互编排（几何计算、状态修改和通知）经命名 [onResize] 回调由宿主承担。
class ResizeHandles extends StatelessWidget {
  const ResizeHandles({
    super.key,
    required this.width,
    required this.height,
    required this.screenToCanvasDelta,
    required this.onResize,
    required this.onChanged,
  });

  /// 元素外接框尺寸（经 viewScale 换算后的展示坐标，决定手柄位置）。
  final double width;
  final double height;

  /// 屏幕增量 → 画布增量（视口旋转/缩放换算，由宿主注入）。
  final Offset Function(Offset screenDelta) screenToCanvasDelta;

  /// 手柄拖拽回调：传递明确的八向 [EditorShapeResizeHandle] 语义和
  /// 画布增量；宿主决定如何计算及写入领域状态。
  final void Function(EditorShapeResizeHandle handle, Offset canvasDelta)
  onResize;

  /// 每次拖拽更新后的通知（宿主 State 通知变更/自动保存）。
  final VoidCallback onChanged;

  /// 视觉手柄尺寸：保持 10px 的小巧观感，不遮挡画布内容。
  static const double _handleSize = 10.0;

  /// 触控热区尺寸：视觉手柄外的隐形命中区。
  ///
  /// 依据 Apple HIG / WCAG 2.5.5 / Material 最小触控尺寸取 44px——
  /// 原实现命中区等于视觉 10px，触屏主用设备上几乎点不中
  /// （2026-09-04 第三轮审计「高」级项，本轮修复）。
  static const double _hitSize = 44.0;

  @override
  Widget build(BuildContext context) {
    const size = _handleSize;
    final handles = <({EditorShapeResizeHandle handle, Offset position})>[
      (handle: EditorShapeResizeHandle.topLeft, position: Offset.zero),
      (handle: EditorShapeResizeHandle.top, position: Offset(width / 2, 0)),
      (handle: EditorShapeResizeHandle.topRight, position: Offset(width, 0)),
      (handle: EditorShapeResizeHandle.left, position: Offset(0, height / 2)),
      (
        handle: EditorShapeResizeHandle.right,
        position: Offset(width, height / 2),
      ),
      (handle: EditorShapeResizeHandle.bottomLeft, position: Offset(0, height)),
      (
        handle: EditorShapeResizeHandle.bottom,
        position: Offset(width / 2, height),
      ),
      (
        handle: EditorShapeResizeHandle.bottomRight,
        position: Offset(width, height),
      ),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final entry in handles)
          _handle(handle: entry.handle, position: entry.position, size: size),
      ],
    );
  }

  Widget _handle({
    required EditorShapeResizeHandle handle,
    required Offset position,
    required double size,
  }) {
    // 命中区 44×44、视觉手柄 10×10 居中：热区中心与视觉中心保持同一点，
    // 桌面鼠标观感零变化；外层 Stack 为 Clip.none，热区不会被裁掉。
    // 注意：极小元素上相邻手柄热区会重叠，后声明的手柄优先命中
    // （列表顺序 TL→BR）。如需更精细，可按元素尺寸缩放 _hitSize。
    return Positioned(
      left: position.dx - _hitSize / 2,
      top: position.dy - _hitSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          onResize(handle, screenToCanvasDelta(details.delta));
          onChanged();
        },
        child: SizedBox(
          width: _hitSize,
          height: _hitSize,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                // 四-2 统一（审计第 4 轮遗留）：手柄蓝从 Material #42A5F5
                // 归位品牌 Action Blue，与 canvas_painter 选框族一致。
                color: AppleColor.actionBlue,
                borderRadius: BorderRadius.circular(AppleRadius.xs),
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
