import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 左侧垂直工具条（对齐 Excalidraw LayerUI 布局）。
///
/// 审计三-1（2026-09-06）：从贴边灰板改为**浮动玻璃岛**——GlassSurface
/// （sigma 12 / 0.62）+ AppleRadius.lg 胶囊，由宿主以浮层定位在画布之上
/// （工具条属 DESIGN_SYSTEM §5 的浮层，可用玻璃）。选中态 = Action Blue
/// 底 + 白图标（全 App 唯一强调色）。
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
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppleRadius.lg),
      sigma: 12,
      padding: const EdgeInsets.all(4),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 手型：画布导航与绘制模式显式分离，避免误触发笔画。
              _tool(
                Icons.pan_tool_alt_rounded,
                '平移画布 (H)',
                handActive,
                onHand,
              ),
              Divider(height: 12, color: scheme.outlineVariant),
              // 画笔
              _tool(
                Icons.edit_rounded,
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
                Icons.draw_rounded,
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
                Icons.highlight_rounded,
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
                Icons.auto_fix_high_rounded,
                '橡皮擦 (E)',
                isEraser,
                onEraser,
              ),
              // 吸管
              _tool(
                Icons.colorize_rounded,
                '吸管工具',
                eyedropperActive,
                onEyedropper,
              ),
              // 矩形选区
              _tool(
                Icons.crop_free_rounded,
                '矩形选区 (R)',
                controller.selectionTool == SelectionTool.rect,
                onRectSelect,
              ),
              // 框选（多元素）
              _tool(
                Icons.select_all_rounded,
                '框选多个元素',
                marqueeActive,
                onMarquee,
              ),
              // 文字
              _tool(
                Icons.text_fields_rounded,
                '文字 (T)',
                textToolActive,
                onText,
              ),
              // 形状弹出菜单
              _shapeMenu(context),
              // 连线
              _tool(Icons.call_merge_rounded, '节点连线', linkMode, onLink),
              Divider(height: 12, color: scheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shapeMenu(BuildContext context) {
    final selected = activeShape != null;
    final menu = PopupMenuButton<ShapeType>(
      tooltip: AppLocalizations.of(context)?.editorShapeTool ?? '形状工具',
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppleRadius.md)),
      ),
      icon: _toolIcon(
        selected ? _shapeIcon(activeShape!) : Icons.category_rounded,
        selected,
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
    );
    if (!selected) return menu;
    return Container(
      decoration: BoxDecoration(
        color: AppleColor.actionBlue,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
      ),
      child: menu,
    );
  }

  IconData _shapeIcon(ShapeType t) => switch (t) {
    ShapeType.rect => Icons.crop_square_rounded,
    ShapeType.ellipse => Icons.circle_outlined,
    ShapeType.diamond => Icons.diamond_outlined,
    ShapeType.arrow => Icons.arrow_forward_rounded,
    ShapeType.line => Icons.remove_rounded,
  };

  Widget _toolIcon(IconData icon, bool selected) => Icon(
    icon,
    size: 20,
    color: selected ? Colors.white : null,
  );

  Widget _tool(
    IconData icon,
    String tip,
    bool selected,
    VoidCallback onTap,
  ) {
    if (!selected) {
      return Tooltip(
        message: tip,
        child: IconButton(icon: _toolIcon(icon, false), onPressed: onTap),
      );
    }
    return Tooltip(
      message: tip,
      child: Container(
        decoration: BoxDecoration(
          color: AppleColor.actionBlue,
          borderRadius: BorderRadius.circular(AppleRadius.sm),
        ),
        child: IconButton(
          icon: _toolIcon(icon, true),
          onPressed: onTap,
        ),
      ),
    );
  }
}
