// shared/widgets——公共绘图工具组件（V1/V2 统一—�?026-08-24）�?//
// �?V1/V2 重复代码中提取的公共组件�?// - ColorPickerGrid：颜色选择网格
// - StrokeWidthSlider：线宽滑�?// - OpacitySlider：透明度滑�?// - LineStyleSelector：线条样式选择�?// - ToolButton：工具栏按钮
//
// 设计原则�?// - �?UI 组件，不含业务逻辑
// - 所有状态通过参数传入
// - 所有操作通过回调返回
// - 可被 V1/V2 共同使用
library;

import 'package:flutter/material.dart';

import '../../../core/theme/text_scale_helper.dart';

/// 颜色选择网格（V1/V2 公共组件）�?///
/// 12 色预设方块，选中高亮边框�?/// 常用于画笔颜色选择、形状填充色选择等�?class ColorPickerGrid extends StatelessWidget {
  const ColorPickerGrid({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
    this.colors = _defaultColors,
    this.size = 28,
  });

  /// 当前选中的颜色（十六进制字符串，�?'#FF0000'）�?  final String selectedColor;

  /// 颜色选择回调�?  final ValueChanged<String> onColorSelected;

  /// 颜色预设列表（默�?12 色）�?  final List<String> colors;

  /// 方块大小�?  final double size;

  static const List<String> _defaultColors = [
    '#000000', '#FFFFFF', '#FF0000', '#FF6600',
    '#FFCC00', '#33CC33', '#0099FF', '#6633CC',
    '#FF3399', '#999999', '#CCCCCC', '#666666',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: colors.map((color) {
        final isSelected = selectedColor == color;
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _hexToColor(color),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade400,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check, size: size * 0.57, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  static Color _hexToColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }
}

/// 线宽滑块（V1/V2 公共组件）�?///
/// 常用于画笔粗细、形状线宽等�?class StrokeWidthSlider extends StatelessWidget {
  const StrokeWidthSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 32,
    this.label = '线宽',
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12), color: Colors.grey)),
            Text('${value.round()}px',
                style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12), fontWeight: FontWeight.w500)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.grey.shade300,
            thumbColor: Colors.blue,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 透明度滑块（V1/V2 公共组件）�?///
/// 常用于画笔透明度、形状填充透明度等�?class OpacitySlider extends StatelessWidget {
  const OpacitySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '透明�?,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12), color: Colors.grey)),
            Text('${(value * 100).round()}%',
                style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12), fontWeight: FontWeight.w500)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.grey.shade300,
            thumbColor: Colors.blue,
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 线条样式选择器（V1/V2 公共组件）�?///
/// 支持实线/虚线/点线三种样式�?class LineStyleSelector extends StatelessWidget {
  const LineStyleSelector({
    super.key,
    required this.selectedStyle,
    required this.onStyleChanged,
  });

  final LineStyle selectedStyle;
  final ValueChanged<LineStyle> onStyleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('线条样式', style: TextStyle(fontSize: TextScaleHelper.scaled(context, 12), color: Colors.grey)),
        SizedBox(height: 6),
        Row(
          children: LineStyle.values.map((style) {
            final isSelected = selectedStyle == style;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton(
                  onPressed: () => onStyleChanged(style),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: isSelected
                        ? Colors.blue.withValues(alpha: 0.1)
                        : null,
                    side: BorderSide(
                      color: isSelected ? Colors.blue : Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    style.label,
                    style: TextStyle(
                      fontSize: TextScaleHelper.scaled(context, 11),
                      color: isSelected ? Colors.blue : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// 线条样式枚举�?enum LineStyle {
  solid,
  dashed,
  dotted;

  String get label {
    switch (this) {
      case LineStyle.solid:
        return '实线';
      case LineStyle.dashed:
        return '虚线';
      case LineStyle.dotted:
        return '点线';
    }
  }
}

/// 工具栏按钮（V1/V2 公共组件）�?///
/// 支持选中状态、图标、提示文字�?class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
    this.size = 20,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : Colors.grey[700],
            size: size,
          ),
        ),
      ),
    );
  }
}

/// 颜色选择圆点（V1/V2 公共组件）�?///
/// 显示当前颜色，点击弹出颜色选择器�?class ColorPickerDot extends StatelessWidget {
  const ColorPickerDot({
    super.key,
    required this.color,
    required this.onTap,
    this.size = 28,
    this.tooltip = '选择颜色',
  });

  final Color color;
  final VoidCallback onTap;
  final double size;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
      ),
    );
  }
}
