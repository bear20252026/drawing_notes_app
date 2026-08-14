import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/drawing_controller.dart';

/// 图层面板（Phase 3 验收核心）。
///
/// 提供能力：
/// - 图层列表（缩略图 + 名称 + 眼睛显隐开关）
/// - 新建 / 删除图层
/// - 图层透明度滑块（0~100%）
/// - 图层上移 / 下移（调整顺序）
/// - 图层向下合并
///
/// 说明：
/// - 列表按"最上层在最上方"显示（与主流绘图软件一致，
///   与内部存储顺序 [DrawingDocument.layers] 相反）；
/// - 所有操作直接调用 [DrawingController] 的方法，
///   撤销历史由控制器统一记录。
class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key, required this.controller, this.width = 220});

  final DrawingController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: width,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final layers = controller.document.layers;
            // 显示顺序：最上层（索引最大）在列表顶部。
            final displayOrder = layers.reversed.toList();
            final currentIndex = controller.currentLayerIndex;

            return Column(
              children: [
                // 面板标题 + 新建图层按钮
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Row(
                    children: [
                      Text('图层', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      IconButton(
                        tooltip: '新建图层',
                        icon: const Icon(Icons.add_box_outlined, size: 20),
                        onPressed: controller.addLayer,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 图层列表
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(4),
                    itemCount: displayOrder.length,
                    itemBuilder: (context, i) {
                      // 把"显示序号"换算回内部索引。
                      final internalIndex = displayOrder.length - 1 - i;
                      final layer = displayOrder[i];
                      final selected = internalIndex == currentIndex;
                      return _LayerItem(
                        controller: controller,
                        layerIndex: internalIndex,
                        selected: selected,
                        opacity: layer.opacity,
                        visible: layer.visible,
                        name: layer.name,
                        thumbnail: controller.paintViews[internalIndex].image,
                        canMoveUp: internalIndex < layers.length - 1,
                        canMoveDown: internalIndex > 0,
                        canMerge: internalIndex > 0,
                        onSelect: () =>
                            controller.currentLayerIndex = internalIndex,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 单个图层条目。
class _LayerItem extends StatelessWidget {
  const _LayerItem({
    required this.controller,
    required this.layerIndex,
    required this.selected,
    required this.opacity,
    required this.visible,
    required this.name,
    required this.thumbnail,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canMerge,
    required this.onSelect,
  });

  final DrawingController controller;
  final int layerIndex;
  final bool selected;
  final double opacity;
  final bool visible;
  final String name;
  final Object? thumbnail; // ui.Image?，用动态类型避免 UI 层直接依赖 dart:ui
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canMerge;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 缩略图（当前图层渲染缓存位图）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: thumbnail is ui.Image
                          ? RawImage(
                              image: thumbnail as ui.Image,
                              width: 40,
                              height: 40,
                              fit: BoxFit.contain,
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              color: scheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_outlined, size: 18),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 显隐开关（眼睛）
                    IconButton(
                      tooltip: visible ? '隐藏图层' : '显示图层',
                      icon: Icon(
                        visible ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          controller.toggleLayerVisibility(layerIndex),
                    ),
                  ],
                ),
                // 透明度滑块
                Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10,
                          ),
                        ),
                        child: Slider(
                          value: opacity.clamp(0.0, 1.0),
                          onChanged: (v) =>
                              controller.setLayerOpacity(layerIndex, v),
                        ),
                      ),
                    ),
                    Text(
                      '${(opacity * 100).round()}%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                // 操作按钮行：上移/下移/合并/删除
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _smallIcon(
                      Icons.arrow_upward,
                      '上移',
                      canMoveUp,
                      () => controller.moveLayerUp(layerIndex),
                    ),
                    _smallIcon(
                      Icons.arrow_downward,
                      '下移',
                      canMoveDown,
                      () => controller.moveLayerDown(layerIndex),
                    ),
                    _smallIcon(
                      Icons.call_merge,
                      '向下合并',
                      canMerge,
                      () => controller.mergeLayerDown(layerIndex),
                    ),
                    _smallIcon(
                      Icons.delete_outline,
                      '删除图层',
                      controller.document.layers.length > 1,
                      () => controller.removeLayer(layerIndex),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallIcon(
    IconData icon,
    String tip,
    bool enabled,
    VoidCallback onTap,
  ) {
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      disabledColor: Colors.grey,
      onPressed: enabled ? onTap : null,
    );
  }
}
