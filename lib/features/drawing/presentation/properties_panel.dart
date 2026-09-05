import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import '../../../core/theme/apple_design.dart';

/// 右侧属性面板（对齐 Excalidraw 右侧属性栏体验）。
///
/// 位于图层面板下方，集中显示当前工具/选中元素的属性编辑：
/// - 画笔：颜色 + 粗细滑块；
/// - 选中形状：线宽 / 透明度 / 填充 / 虚线；
/// - 选中文字：字号 / 颜色 / 粗斜体。
/// 纯展示组件：状态经参数传入，操作经回调返回（架构分层铁律）。
class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({
    super.key,
    required this.controller,
    required this.selectedShape,
    required this.selectedText,
    required this.selectedImage,
    required this.onPickColor,
    required this.onBrushSizeChanged,
    required this.onShapeStrokeWidth,
    required this.onShapeOpacity,
    required this.onShapeFill,
    required this.onShapeDash,
    required this.onShapeRough,
    required this.onTextColor,
    required this.onTextFontSize,
    required this.onCycleFont,
    required this.onCropImage,
  });

  final DrawingController controller;
  final PageShapeItem? selectedShape;
  final PageTextItem? selectedText;
  final PageImageItem? selectedImage;
  final VoidCallback onPickColor;
  final ValueChanged<double> onBrushSizeChanged;
  final ValueChanged<double> onShapeStrokeWidth;
  final ValueChanged<double> onShapeOpacity;
  final VoidCallback onShapeFill;
  final VoidCallback onShapeDash;

  /// 手绘风格开关（平滑↔手绘，借鉴 Excalidraw/rough.js，保持自身风格）。
  final VoidCallback onShapeRough;

  final VoidCallback onTextColor;
  final ValueChanged<double> onTextFontSize;

  /// 循环切换字体族（默认/衬线/等宽/手写，借鉴 Excalidraw FontPicker）。
  final VoidCallback onCycleFont;

  /// 裁剪选中的图片（对齐 Excalidraw 图片裁剪）。
  final VoidCallback onCropImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(10),
      color: scheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final isEraser = controller.tool == BrushType.eraser;
          return ListView(
            children: [
              // ---- 画笔属性 ----
              const Text('画笔', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  // 当前颜色圆点（点击弹色板）
                  Tooltip(
                    message: '画笔颜色',
                    // 热区 44×44（审计二-1：HIG 最小触控尺寸），视觉圆点保持 28。
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppleRadius.md),
                          onTap: onPickColor,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: controller.color,
                              shape: BoxShape.circle,
                              // v1.10.8 色板同款：outlineVariant 发丝线替代
                              // Colors.black26 硬描边（审计三-3 补漏）。
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 粗细滑块
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          value:
                              (isEraser
                                      ? controller.eraserSize
                                      : controller.brushSize)
                                  .clamp(1, 100),
                          min: 1,
                          max: 100,
                          onChanged: onBrushSizeChanged,
                        ),
                        Text(
                          '${(isEraser ? controller.eraserSize : controller.brushSize).round()}px',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              // ---- 选中图片属性（对齐 Excalidraw 图片裁剪）----
              if (selectedImage != null) ...[
                const Text('图片', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.crop, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onCropImage,
                        icon: const Icon(Icons.crop, size: 16),
                        label: const Text('裁剪图片'),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
              ],

              // ---- 选中形状属性 ----
              if (selectedShape != null) ...[
                const Text('形状', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.line_weight, size: 16),
                    Expanded(
                      child: Slider(
                        value: selectedShape!.strokeWidth.clamp(1, 20),
                        min: 1,
                        max: 20,
                        onChanged: onShapeStrokeWidth,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.opacity, size: 16),
                    Expanded(
                      child: Slider(
                        value: selectedShape!.fillColor != null ? 1.0 : 0.0,
                        min: 0,
                        max: 1,
                        onChanged: onShapeOpacity,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: '填充色',
                      icon: Icon(
                        selectedShape!.fillColor != null
                            ? Icons.format_color_fill
                            : Icons.format_color_reset,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: onShapeFill,
                    ),
                    IconButton(
                      tooltip: '实线/虚线',
                      icon: Icon(
                        selectedShape!.dash ? Icons.more_horiz : Icons.remove,
                        size: 18,
                      ),
                      isSelected: selectedShape!.dash,
                      onPressed: onShapeDash,
                    ),
                    IconButton(
                      tooltip: '手绘风格（rough）',
                      icon: Icon(
                        selectedShape!.rough
                            ? Icons.gesture
                            : Icons.linear_scale,
                        size: 18,
                      ),
                      isSelected: selectedShape!.rough,
                      onPressed: onShapeRough,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '线宽 ${selectedShape!.strokeWidth.round()}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const Divider(height: 16),
              ],

              // ---- 选中文字属性 ----
              if (selectedText != null) ...[
                const Text('文字', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.format_size, size: 16),
                    Expanded(
                      child: Slider(
                        value: selectedText!.fontSize.clamp(8, 200),
                        min: 8,
                        max: 200,
                        onChanged: onTextFontSize,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Tooltip(
                      message: '文字颜色',
                      // 热区 44×44（审计二-1），视觉圆点保持 22。
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppleRadius.md),
                            onTap: onTextColor,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Color(selectedText!.color),
                                shape: BoxShape.circle,
                                // v1.10.8 色板同款发丝线（审计三-3 补漏）。
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${selectedText!.fontSize.round()}px',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 字体族循环切换（借鉴 Excalidraw FontPicker）。
                Row(
                  children: [
                    const Icon(Icons.font_download_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onCycleFont,
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: Text(switch (selectedText!.fontFamily) {
                          'serif' => '衬线字体',
                          'monospace' => '等宽字体',
                          'handwriting' => '手写字体',
                          _ => '默认字体',
                        }, style: Theme.of(context).textTheme.labelMedium),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
