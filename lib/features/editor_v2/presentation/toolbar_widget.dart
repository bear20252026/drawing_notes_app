// editor_v2——ToolbarWidget（批次 E——2026-08-21）。
//
// 最小工具栏（画笔/直线/矩形/椭圆/箭头/文字/选择/橡皮擦）。
// 纯 UI——工具状态在 ViewModel。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/text_scale_helper.dart';

/// V2 工具栏（阶段2——笔刷类型/粗细/颜色——2026-08-24）。
class EditorV2Toolbar extends StatelessWidget {
  const EditorV2Toolbar({
    super.key,
    required this.currentTool,
    required this.brushType,
    required this.currentShapeType,
    required this.brushSize,
    required this.strokeColorHex,
    required this.onToolChanged,
    required this.onShapeTypeChanged,
    required this.onBrushTypeChanged,
    required this.onBrushSizeChanged,
    required this.onColorChanged,
    this.onImportPdf,
  });

  final String currentTool;
  final String brushType;
  final String currentShapeType;
  final double brushSize;
  final String strokeColorHex;
  final ValueChanged<String> onToolChanged;
  final ValueChanged<String> onShapeTypeChanged;
  final ValueChanged<String> onBrushTypeChanged;
  final ValueChanged<double> onBrushSizeChanged;
  final ValueChanged<String> onColorChanged;
  final VoidCallback? onImportPdf;

  @override
  Widget build(BuildContext context) {
    final showBrushOptions = currentTool == 'draw';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey[200],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：工具按钮。
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolButton(
                icon: Icons.edit,
                label: 'Draw',
                isActive: currentTool == 'draw',
                onTap: () => onToolChanged('draw'),
              ),
              _ToolButton(
                icon: Icons.select_all,
                label: 'Select',
                isActive: currentTool == 'select',
                onTap: () => onToolChanged('select'),
              ),
              _ToolButton(
                icon: Icons.rectangle_outlined,
                label: 'Rect',
                isActive: currentTool == 'shape' && currentShapeType == 'rect',
                onTap: () {
                  onToolChanged('shape');
                  onShapeTypeChanged('rect');
                },
              ),
              _ToolButton(
                icon: Icons.circle_outlined,
                label: 'Ellipse',
                isActive: currentTool == 'shape' && currentShapeType == 'ellipse',
                onTap: () {
                  onToolChanged('shape');
                  onShapeTypeChanged('ellipse');
                },
              ),
              _ToolButton(
                icon: Icons.remove,
                label: 'Line',
                isActive: currentTool == 'shape' && currentShapeType == 'line',
                onTap: () {
                  onToolChanged('shape');
                  onShapeTypeChanged('line');
                },
              ),
              _ToolButton(
                icon: Icons.arrow_forward,
                label: 'Arrow',
                isActive: currentTool == 'shape' && currentShapeType == 'arrow',
                onTap: () {
                  onToolChanged('shape');
                  onShapeTypeChanged('arrow');
                },
              ),
              _ToolButton(
                icon: Icons.text_fields,
                label: 'Text',
                isActive: currentTool == 'text',
                onTap: () => onToolChanged('text'),
              ),
              _ToolButton(
                icon: Icons.delete,
                label: 'Erase',
                isActive: currentTool == 'erase',
                onTap: () {
                  onToolChanged('erase');
                  onBrushTypeChanged('eraser');
                },
              ),
              _ToolButton(
                icon: Icons.colorize,
                label: 'Eyedropper',
                isActive: currentTool == 'eyedropper',
                onTap: () => onToolChanged('eyedropper'),
              ),
              _ToolButton(
                icon: Icons.picture_as_pdf,
                label: 'Import PDF',
                isActive: false,
                onTap: onImportPdf ?? () {},
              ),
            ],
          ),
          // 第二行：绘图模式下的笔刷选项（V1/V2 迁移阶段2）。
          if (showBrushOptions) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 笔刷类型。
                _BrushChip(
                  icon: Icons.edit,
                  label: '钢笔',
                  isActive: brushType == 'pen',
                  onTap: () => onBrushTypeChanged('pen'),
                ),
                _BrushChip(
                  icon: Icons.brush,
                  label: '铅笔',
                  isActive: brushType == 'pencil',
                  onTap: () => onBrushTypeChanged('pencil'),
                ),
                _BrushChip(
                  icon: Icons.highlight,
                  label: '荧光笔',
                  isActive: brushType == 'marker',
                  onTap: () => onBrushTypeChanged('marker'),
                ),
                _BrushChip(
                  icon: Icons.lens_blur,
                  label: '激光',
                  isActive: brushType == 'laser',
                  onTap: () => onBrushTypeChanged('laser'),
                ),
                const SizedBox(width: 8),
                // 粗细滑块。
                SizedBox(
                  width: 80,
                  child: Slider(
                    value: brushSize,
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: brushSize.round().toString(),
                    onChanged: onBrushSizeChanged,
                  ),
                ),
                Text(
                  '${brushSize.round()}',
                  style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12)),
                ),
                const SizedBox(width: 8),
                // 颜色预览圆。
                GestureDetector(
                  onTap: () {
                    // TODO: 打开颜色选择器。
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _hexToColor(strokeColorHex),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Color _hexToColor(String hex) {
    if (hex.startsWith('#') && hex.length == 7) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return Colors.black;
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  )]
                : null,
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.white : Colors.grey[700],
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// 笔刷类型选择芯片（V1/V2 迁移阶段2——2026-08-24）。
class _BrushChip extends StatelessWidget {
  const _BrushChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        avatar: Icon(
          icon,
          size: 14,
          color: isActive ? Colors.white : Colors.grey[700],
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: TextScaleHelper.scaled(context, 11),
            color: isActive ? Colors.white : Colors.grey[700],
          ),
        ),
        selected: isActive,
        selectedColor: Colors.blue,
        backgroundColor: Colors.transparent,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
