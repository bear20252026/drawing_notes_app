// editor_v2——PropertyPanel 属性面板（AFFiNE 借鉴——2026-08-21）。
//
// AFFiNE 右侧属性面板本地化——选中元素属性编辑（颜色/线宽/透明度/边框）。
// 积木式独立 Widget——不耦合其他组件——可插拔——不搞崩。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';
import '../application/stroke_style_notifier.dart';

/// AFFiNE 属性面板（积木式独立 Widget——选中元素属性编辑）。
///
/// 功能：
/// - 颜色预设（12色方块——选中高亮——AFFiNE 调色板风格）
/// - 线宽滑块（1~32——StrokeStyle 范围）
/// - 透明度滑块（0~1）
/// - 线条样式（solid/dashed/dotted）
/// - 背景色选择（形状填充色）
///
/// 设计：积木式——独立 Widget——不耦合其他组件——可插拔。
class PropertyPanel extends ConsumerWidget {
  const PropertyPanel({super.key});

  // AFFiNE/Excalidraw 常用颜色预设（12色——不含透明）。
  static const List<String> _colorPresets = [
    '#000000', '#FFFFFF', '#FF0000', '#FF6600',
    '#FFCC00', '#33CC33', '#0099FF', '#6633CC',
    '#FF3399', '#999999', '#CCCCCC', '#666666',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 画笔样式（积木式独立 Notifier——不耦合 EditorV2Notifier）。
    final strokeStyle = ref.watch(strokeStyleProvider);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题（AFFiNE 风格）。
            Text('属性', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            // 颜色选择器（预设方块）。
            _buildColorSection(ref, strokeStyle),
            const SizedBox(height: 12),
            // 线宽滑块。
            _buildStrokeWidthSection(ref, strokeStyle),
            const SizedBox(height: 12),
            // 透明度滑块。
            _buildOpacitySection(ref, strokeStyle),
            const SizedBox(height: 12),
            // 线条样式（solid/dashed/dotted）。
            _buildLineStyleSection(ref, strokeStyle),
          ],
        ),
      ),
    );
  }

  /// 颜色选择区（12色预设方块——选中高亮边框）。
  Widget _buildColorSection(WidgetRef ref, StrokeStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('颜色', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _colorPresets.map((color) {
            final isSelected = style.strokeColor == color;
            return GestureDetector(
              onTap: () {
                ref.read(strokeStyleProvider.notifier)
                    .updateColor(color);
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _hexToColor(color),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.grey.shade400,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 线宽滑块区（1~32）。
  Widget _buildStrokeWidthSection(WidgetRef ref, StrokeStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('线宽', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text('${style.strokeWidth.round()}px',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.grey.shade300,
            thumbColor: Colors.blue,
          ),
          child: Slider(
            value: style.strokeWidth,
            min: StrokeStyle.minWidth,
            max: StrokeStyle.maxWidth,
            onChanged: (value) {
              ref.read(strokeStyleProvider.notifier)
                  .updateStrokeWidth(value);
            },
          ),
        ),
      ],
    );
  }

  /// 透明度滑块区（0~1）。
  Widget _buildOpacitySection(WidgetRef ref, StrokeStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('透明度', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text('${(style.opacity * 100).round()}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.grey.shade300,
            thumbColor: Colors.blue,
          ),
          child: Slider(
            value: style.opacity,
            min: 0.0,
            max: 1.0,
            onChanged: (value) {
              ref.read(strokeStyleProvider.notifier)
                  .updateOpacity(value);
            },
          ),
        ),
      ],
    );
  }

  /// 线条样式区（solid/dashed/dotted）。
  Widget _buildLineStyleSection(WidgetRef ref, StrokeStyle style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('线条样式', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Row(
          children: StrokeLineType.values.map((type) {
            final isSelected = style.strokeStyle == type;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(strokeStyleProvider.notifier)
                        .updateLineStyle(type);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
                    side: BorderSide(
                      color: isSelected ? Colors.blue : Colors.grey.shade400,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _lineTypeName(type),
                    style: TextStyle(
                      fontSize: 11,
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

  String _lineTypeName(StrokeLineType type) {
    switch (type) {
      case StrokeLineType.solid:
        return '实线';
      case StrokeLineType.dashed:
        return '虚线';
      case StrokeLineType.dotted:
        return '点线';
    }
  }

  /// 十六进制颜色字符串转 Color。
  static Color _hexToColor(String hex) {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }
}
