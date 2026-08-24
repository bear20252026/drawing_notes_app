// editor_v2——LayerPanel 层管理面板（AFFiNE 借鉴——2026-08-21）。
//
// AFFiNE 图层管理（可见性/透明度/重排）本地化——积木式独立 Widget。
// 不修改现有功能——保证现有功能正常——不搞崩。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/text_scale_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';
import '../application/editor_v2_viewmodel.dart';

/// AFFiNE 层管理面板（积木式独立 Widget——不大幅变动）。
///
/// 功能：
/// - 图层列表（LayerV2——名称/可见性/透明度）
/// - 可见性切换（visible 字段）
/// - 透明度调整（opacity 滑块 0~1）
/// - 重排（上下移动——AFFiNE 图层排序）
///
/// 设计：积木式——独立 Widget——不耦合其他组件——可插拔。
class LayerPanel extends ConsumerWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorV2NotifierProvider);
    final doc = state.document;
    final layers = doc.layers;

    if (layers.isEmpty) {
      return const Center(
        child: Text('无图层', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: layers.length,
      itemBuilder: (context, index) {
        final layer = layers[index];
        return _LayerTile(
          layer: layer,
          index: index,
          totalLayers: layers.length,
        );
      },
    );
  }
}

/// 单个图层条目（积木式——不耦合）。
class _LayerTile extends ConsumerWidget {
  const _LayerTile({
    required this.layer,
    required this.index,
    required this.totalLayers,
  });

  final LayerV2 layer;
  final int index;
  final int totalLayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // 可见性切换（眼睛图标）。
            Semantics(
              label: layer.visible ? '隐藏图层 ${layer.name}' : '显示图层 ${layer.name}',
              button: true,
              child: IconButton(
                icon: Icon(
                  layer.visible ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: layer.visible
                      ? Colors.blue
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  final notifier = ref.read(editorV2NotifierProvider.notifier);
                  final currentDoc = ref.read(editorV2NotifierProvider).document;
                  final updatedLayers = List<LayerV2>.from(currentDoc.layers);
                  updatedLayers[index] = layer.copyWith(visible: !layer.visible);
                  notifier.execute(UpdateDocumentCommand(layers: updatedLayers));
                },
                padding: EdgeInsets.zero,
                // 无障碍：触摸目标提升至 48dp（原 32dp）。
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ),
            // 图层名称。
            Expanded(
              child: Text(
                layer.name,
                style: TextStyle(
                  fontSize: TextScaleHelper.scaled(context, 13),
                  // 无障碍：不可见层用 onSurfaceVariant 替换 Colors.grey（对比达标）。
                  color: layer.visible
                      ? Colors.black87
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 透明度调整（滑块）。
            SizedBox(
              width: 80,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.blue.withValues(alpha: layer.opacity),
                  inactiveTrackColor: Colors.grey.shade300,
                  thumbColor: Colors.blue,
                ),
                child: Semantics(
                  label: '图层 ${layer.name} 不透明度',
                  child: Slider(
                    value: layer.opacity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (value) {
                      final notifier = ref.read(editorV2NotifierProvider.notifier);
                      final currentDoc = ref.read(editorV2NotifierProvider).document;
                      final updatedLayers = List<LayerV2>.from(currentDoc.layers);
                      updatedLayers[index] = layer.copyWith(opacity: value);
                      notifier.execute(UpdateDocumentCommand(layers: updatedLayers));
                    },
                  ),
                ),
              ),
            ),
            // 重排按钮（上移/下移——AFFiNE 图层排序）。
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: '上移图层 ${layer.name}',
                  button: true,
                  child: IconButton(
                    icon: Icon(Icons.keyboard_arrow_up, size: 18,
                        color: index > 0
                            ? Colors.black87
                            : Theme.of(context).colorScheme.outlineVariant),
                    onPressed: index > 0 ? () {
                      final notifier = ref.read(editorV2NotifierProvider.notifier);
                      final currentDoc = ref.read(editorV2NotifierProvider).document;
                      final updatedLayers = List<LayerV2>.from(currentDoc.layers);
                      final temp = updatedLayers[index - 1];
                      updatedLayers[index - 1] = updatedLayers[index];
                      updatedLayers[index] = temp;
                      notifier.execute(UpdateDocumentCommand(layers: updatedLayers));
                    } : null,
                    padding: EdgeInsets.zero,
                    // 无障碍：触摸目标提升至 48dp（原 24dp）。
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ),
                Semantics(
                  label: '下移图层 ${layer.name}',
                  button: true,
                  child: IconButton(
                    icon: Icon(Icons.keyboard_arrow_down, size: 18,
                        color: index < totalLayers - 1
                            ? Colors.black87
                            : Theme.of(context).colorScheme.outlineVariant),
                    onPressed: index < totalLayers - 1 ? () {
                      final notifier = ref.read(editorV2NotifierProvider.notifier);
                      final currentDoc = ref.read(editorV2NotifierProvider).document;
                      final updatedLayers = List<LayerV2>.from(currentDoc.layers);
                      final temp = updatedLayers[index + 1];
                      updatedLayers[index + 1] = updatedLayers[index];
                      updatedLayers[index] = temp;
                      notifier.execute(UpdateDocumentCommand(layers: updatedLayers));
                    } : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
