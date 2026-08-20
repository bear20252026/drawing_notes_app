// editor_v2——ToolbarWidget（批次 E——2026-08-21）。
//
// 最小工具栏（画笔/直线/矩形/椭圆/箭头/文字/选择/橡皮擦）。
// 纯 UI——工具状态在 ViewModel。
library;

import 'package:flutter/material.dart';

/// V2 工具栏（最小 UI——CUJ-01/02/04）。
class EditorV2Toolbar extends StatelessWidget {
  const EditorV2Toolbar({
    super.key,
    required this.currentTool,
    required this.currentShapeType,
    required this.onToolChanged,
    required this.onShapeTypeChanged,
  });

  final String currentTool;
  final String currentShapeType;
  final ValueChanged<String> onToolChanged;
  final ValueChanged<String> onShapeTypeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey[200],
      child: Row(
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
            onTap: () => onToolChanged('erase'),
          ),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: label,
        child: IconButton(
          icon: Icon(icon, color: isActive ? Colors.blue : Colors.grey[700]),
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: isActive ? Colors.blue[50] : null,
          ),
        ),
      ),
    );
  }
}
