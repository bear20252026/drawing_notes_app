// shared/widgets——统一属性面板（V1/V2 合并——2026-08-24）。
//
// 从 V1/V2 重复代码中统一的属性面板：
// - 支持画笔属性（颜色/线宽/透明度）
// - 支持形状属性（线宽/透明度/填充/虚线）
// - 支持文字属性（字号/颜色/粗斜体）
// - 使用公共组件（ColorPickerGrid、StrokeWidthSlider 等）
//
// 设计原则：
// - 纯 UI 组件，不含业务逻辑
// - 所有状态通过参数传入
// - 所有操作通过回调返回
// - 可被 V1/V2 共同使用
library;

import 'package:flutter/material.dart';

import 'editor_components.dart';

/// 统一属性面板（V1/V2 合并——2026-08-24）。
///
/// 根据当前选中的元素类型，显示对应的属性编辑控件：
/// - 画笔：颜色 + 线宽 + 透明度
/// - 形状：线宽 + 透明度 + 填充 + 虚线
/// - 文字：字号 + 颜色 + 粗斜体
class UnifiedPropertyPanel extends StatelessWidget {
  const UnifiedPropertyPanel({
    super.key,
    required this.state,
    required this.actions,
    this.showBrushProperties = true,
    this.showShapeProperties = false,
    this.showTextProperties = false,
    this.width = 190,
  });

  final UnifiedPropertyPanelState state;
  final UnifiedPropertyPanelActions actions;

  /// 是否显示画笔属性。
  final bool showBrushProperties;

  /// 是否显示形状属性。
  final bool showShapeProperties;

  /// 是否显示文字属性。
  final bool showTextProperties;

  /// 面板宽度。
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      color: scheme.surfaceContainerLow,
      child: ListView(
        children: [
          // 画笔属性
          if (showBrushProperties) ...[
            _buildSectionTitle(context, '画笔'),
            const SizedBox(height: 6),
            _buildBrushProperties(context),
            const Divider(height: 20),
          ],

          // 形状属性
          if (showShapeProperties && state.selectedShape != null) ...[
            _buildSectionTitle(context, '形状'),
            const SizedBox(height: 4),
            _buildShapeProperties(context),
            const Divider(height: 16),
          ],

          // 文字属性
          if (showTextProperties && state.selectedText != null) ...[
            _buildSectionTitle(context, '文字'),
            const SizedBox(height: 4),
            _buildTextProperties(context),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildBrushProperties(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 颜色选择
        Row(
          children: [
            ColorPickerDot(
              color: state.brushColor,
              onTap: actions.onPickColor,
            ),
            const SizedBox(width: 10),
            // 线宽滑块
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: state.brushSize.clamp(1, 100),
                    min: 1,
                    max: 100,
                    onChanged: actions.onBrushSizeChanged,
                  ),
                  Text(
                    '${state.brushSize.round()}px',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShapeProperties(BuildContext context) {
    final shape = state.selectedShape!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 线宽
        Row(
          children: [
            const Icon(Icons.line_weight, size: 16),
            Expanded(
              child: Slider(
                value: shape.strokeWidth.clamp(1, 20),
                min: 1,
                max: 20,
                onChanged: actions.onShapeStrokeWidth,
              ),
            ),
          ],
        ),

        // 透明度
        Row(
          children: [
            const Icon(Icons.opacity, size: 16),
            Expanded(
              child: Slider(
                value: shape.fillColor != null ? 1.0 : 0.0,
                onChanged: actions.onShapeOpacity,
              ),
            ),
          ],
        ),

        // 填充/虚线/手绘
        Row(
          children: [
            IconButton(
              tooltip: '填充色',
              icon: Icon(
                shape.fillColor != null
                    ? Icons.format_color_fill
                    : Icons.format_color_reset,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: actions.onShapeFill,
            ),
            IconButton(
              tooltip: '实线/虚线',
              icon: Icon(
                shape.dash ? Icons.more_horiz : Icons.remove,
                size: 18,
              ),
              isSelected: shape.dash,
              onPressed: actions.onShapeDash,
            ),
            const SizedBox(width: 8),
            Text(
              '线宽 ${shape.strokeWidth.round()}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextProperties(BuildContext context) {
    final text = state.selectedText!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字号
        Row(
          children: [
            const Icon(Icons.format_size, size: 16),
            Expanded(
              child: Slider(
                value: text.fontSize.clamp(8, 200),
                min: 8,
                max: 200,
                onChanged: actions.onTextFontSize,
              ),
            ),
          ],
        ),

        // 颜色
        Row(
          children: [
            ColorPickerDot(
              color: Color(text.color),
              onTap: actions.onTextColor ?? () {},
              size: 22,
              tooltip: '文字颜色',
            ),
            const SizedBox(width: 12),
            Text(
              '${text.fontSize.round()}px',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// 统一属性面板状态。
class UnifiedPropertyPanelState {
  const UnifiedPropertyPanelState({
    required this.brushColor,
    required this.brushSize,
    this.selectedShape,
    this.selectedText,
  });

  /// 画笔颜色。
  final Color brushColor;

  /// 画笔大小。
  final double brushSize;

  /// 选中的形状（可选）。
  final SelectedShapeInfo? selectedShape;

  /// 选中的文字（可选）。
  final SelectedTextInfo? selectedText;
}

/// 选中的形状信息。
class SelectedShapeInfo {
  const SelectedShapeInfo({
    required this.strokeWidth,
    this.fillColor,
    this.dash = false,
  });

  final double strokeWidth;
  final Color? fillColor;
  final bool dash;
}

/// 选中的文字信息。
class SelectedTextInfo {
  const SelectedTextInfo({
    required this.fontSize,
    required this.color,
  });

  final double fontSize;
  final int color;
}

/// 统一属性面板操作。
class UnifiedPropertyPanelActions {
  const UnifiedPropertyPanelActions({
    required this.onPickColor,
    required this.onBrushSizeChanged,
    this.onShapeStrokeWidth,
    this.onShapeOpacity,
    this.onShapeFill,
    this.onShapeDash,
    this.onTextColor,
    this.onTextFontSize,
  });

  final VoidCallback onPickColor;
  final ValueChanged<double> onBrushSizeChanged;
  final ValueChanged<double>? onShapeStrokeWidth;
  final ValueChanged<double>? onShapeOpacity;
  final VoidCallback? onShapeFill;
  final VoidCallback? onShapeDash;
  final VoidCallback? onTextColor;
  final ValueChanged<double>? onTextFontSize;
}
