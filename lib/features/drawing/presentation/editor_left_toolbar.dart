import 'package:flutter/material.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 左侧垂直工具条（对齐 Excalidraw LayerUI 布局）。
///
/// 高频工具垂直排列、图标清晰展现，比底部横向挤压更易发现；
/// 样式类高级功能仍留在底部工具栏/右侧属性面板。
class EditorLeftToolbar extends StatelessWidget {
  const EditorLeftToolbar({
    super.key,
    required this.controller,
    required this.eyedropperActive,
    required this.textToolActive,
    required this.marqueeActive,
    required this.linkMode,
    required this.handActive,
    required this.onHand,
    required this.activeShape,
    required this.onBrush,
    required this.onPencil,
    required this.onHighlighter,
    required this.onLaser,
    required this.onEraser,
    required this.onEyedropper,
    required this.onRectSelect,
    required this.onMarquee,
    required this.onText,
    required this.onShape,
    required this.onLink,
  });

  final DrawingController controller;
  final bool eyedropperActive;
  final bool textToolActive;
  final bool marqueeActive;
  final bool linkMode;
  final bool handActive;
  final VoidCallback onHand;
  final ShapeType? activeShape;
  final VoidCallback onBrush;
  final VoidCallback onPencil;
  final VoidCallback onHighlighter;
  final VoidCallback onLaser;
  final VoidCallback onEraser;
  final VoidCallback onEyedropper;
  final VoidCallback onRectSelect;
  final VoidCallback onMarquee;
  final VoidCallback onText;
  final ValueChanged<ShapeType> onShape;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEraser = controller.tool == BrushType.eraser;
    return Container(
      width: 46,
      color: scheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 6),
              // 手型：画布导航与绘制模式显式分离，避免误触发笔画。
              _tool(
                context,
                Icons.pan_tool_alt_outlined,
                '平移画布 (H)',
                handActive,
                onHand,
              ),
              const Divider(height: 12),
              // 画笔
              _tool(
                context,
                Icons.edit,
                '画笔 (P)',
                controller.tool == BrushType.pen &&
                    controller.selectionTool == SelectionTool.none &&
                    !eyedropperActive &&
                    !textToolActive &&
                    !marqueeActive,
                onBrush,
              ),
              // 铅笔：与钢笔分离的独立预设，保留略深的石墨色与尺寸。
              _tool(
                context,
                Icons.draw_outlined,
                '铅笔 (N)',
                controller.tool == BrushType.pencil &&
                    controller.selectionTool == SelectionTool.none &&
                    !eyedropperActive &&
                    !textToolActive &&
                    !marqueeActive,
                onPencil,
              ),
              // 高亮笔：采用独立局部合成层，实际支持不叠色书写。
              _tool(
                context,
                Icons.highlight,
                '高亮笔 (M)',
                controller.tool == BrushType.marker &&
                    controller.selectionTool == SelectionTool.none &&
                    !eyedropperActive &&
                    !textToolActive &&
                    !marqueeActive,
                onHighlighter,
              ),

              // 激光指示器：独立的、不会写入文档的临时尾迹工具。
              _tool(
                context,
                Icons.gesture_rounded,
                '激光指示器（临时尾迹）',
                controller.tool == BrushType.laser &&
                    controller.selectionTool == SelectionTool.none &&
                    !eyedropperActive &&
                    !textToolActive &&
                    !marqueeActive,
                onLaser,
              ),

              // 橡皮擦
              _tool(
                context,
                Icons.auto_fix_off_outlined,
                '橡皮擦 (E)',
                isEraser,
                onEraser,
              ),
              // 吸管
              _tool(
                context,
                Icons.colorize,
                '吸管工具',
                eyedropperActive,
                onEyedropper,
              ),
              // 矩形选区
              _tool(
                context,
                Icons.crop_free,
                '矩形选区 (R)',
                controller.selectionTool == SelectionTool.rect,
                onRectSelect,
              ),
              // 框选（多元素）
              _tool(
                context,
                Icons.select_all,
                '框选多个元素',
                marqueeActive,
                onMarquee,
              ),
              // 文字
              _tool(
                context,
                Icons.text_fields,
                '文字 (T)',
                textToolActive,
                onText,
              ),
              // 形状弹出菜单
              PopupMenuButton<ShapeType>(
                tooltip: '形状工具',
                icon: Icon(
                  activeShape != null
                      ? _shapeIcon(activeShape!)
                      : Icons.category_outlined,
                  size: 20,
                ),
                onSelected: onShape,
                itemBuilder: (_) => [
                  for (final s in ShapeType.values)
                    PopupMenuItem(
                      value: s,
                      child: Text(switch (s) {
                        ShapeType.rect => '矩形',
                        ShapeType.ellipse => '椭圆',
                        ShapeType.diamond => '菱形',
                        ShapeType.arrow => '箭头',
                        ShapeType.line => '直线',
                      }),
                    ),
                ],
              ),
              // 连线
              _tool(context, Icons.call_merge, '节点连线', linkMode, onLink),
              const Divider(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  IconData _shapeIcon(ShapeType t) => switch (t) {
    ShapeType.rect => Icons.crop_square,
    ShapeType.ellipse => Icons.circle_outlined,
    ShapeType.diamond => Icons.diamond_outlined,
    ShapeType.arrow => Icons.arrow_forward,
    ShapeType.line => Icons.remove,
  };

  Widget _tool(
    BuildContext context,
    IconData icon,
    String tip,
    bool selected,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        isSelected: selected,
        color: selected ? scheme.primary : null,
        onPressed: onTap,
      ),
    );
  }
}
