import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/utils/domain_display_labels.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_focus.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';

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
/// - [onChanged]：**必须**由宿主传入。控制器只 `notifyListeners`（重绘 UI），
///   而笔记本页面模式的落盘完全靠宿主的 `onChanged`/自动保存调度
///   （`editor_page.dart:_notifyChanged`）。此前面板没有任何保存回调，
///   导致「新建/删除/显隐/合并/透明度」这些操作在笔记本页里从不置脏、
///   从不排保存——最后一次动作是图层操作就丢改动（真机集成测试实测抓到）。
class LayerPanel extends StatelessWidget {
  const LayerPanel({
    super.key,
    required this.controller,
    this.onChanged,
    this.width = 220,
  });

  final DrawingController controller;

  /// 图层内容变更后的宿主回调（置脏 + 排自动保存）。
  final VoidCallback? onChanged;
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
                      Text(
                        AppLocalizations.of(context)?.layersTitle ?? '图层',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip:
                            AppLocalizations.of(context)?.layerNew ?? '新建图层',
                        icon: const Icon(Icons.add_box_outlined, size: 20),
                        onPressed: () {
                          controller.addLayer();
                          onChanged?.call();
                        },
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
                        onChanged: onChanged,
                        layerIndex: internalIndex,
                        selected: selected,
                        opacity: layer.opacity,
                        visible: layer.visible,
                        name: DomainDisplayLabels.layerName(
                          AppLocalizations.of(context),
                          layer.name,
                        ),
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
    this.onChanged,
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

  /// 见 [LayerPanel.onChanged]：每次改到图层内容都要让宿主置脏并排保存。
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
        borderRadius: BorderRadius.circular(AppleRadius.sm),
        child: AppleFocusRing(borderRadius: AppleRadius.sm, child: InkWell(
          borderRadius: BorderRadius.circular(AppleRadius.sm),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 缩略图（当前图层渲染缓存位图）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppleRadius.xs),
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
                    // 显隐开关（眼睛）。触控目标 ≥44×44（HIG / 三输入
                    // 兼容铁律）：compact 密度下默认仅 ~40px，补 min 约束。
                    IconButton(
                      tooltip: visible
                          ? AppLocalizations.of(context)?.barHideLayers ??
                                '隐藏图层'
                          : AppLocalizations.of(context)?.barShowLayers ??
                                '显示图层',
                      icon: Icon(
                        visible ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: () {
                        controller.toggleLayerVisibility(layerIndex);
                        onChanged?.call();
                      },
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
                          // 只在拖拽结束时通知：拖动过程中每帧都置脏/排保存
                          // 是纯 IO 风暴（自动保存本身有防抖，但宿主的
                          // onChanged 回调没有）。
                          onChangeEnd: (_) => onChanged?.call(),
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
                      AppLocalizations.of(context)?.layerUp ?? '上移',
                      canMoveUp,
                      () {
                        controller.moveLayerUp(layerIndex);
                        onChanged?.call();
                      },
                    ),
                    _smallIcon(
                      Icons.arrow_downward,
                      AppLocalizations.of(context)?.layerDown ?? '下移',
                      canMoveDown,
                      () {
                        controller.moveLayerDown(layerIndex);
                        onChanged?.call();
                      },
                    ),
                    _smallIcon(
                      Icons.call_merge,
                      AppLocalizations.of(context)?.layerMergeDown ?? '向下合并',
                      canMerge,
                      () {
                        controller.mergeLayerDown(layerIndex);
                        onChanged?.call();
                      },
                    ),
                    _smallIcon(
                      Icons.delete_outline,
                      AppLocalizations.of(context)?.layerDelete ?? '删除图层',
                      controller.document.layers.length > 1,
                      () {
                        controller.removeLayer(layerIndex);
                        onChanged?.call();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }

  Widget _smallIcon(
    IconData icon,
    String tip,
    bool enabled,
    VoidCallback onTap,
  ) {
    // 触控目标 ≥44×44：compact + 16px 图标默认 ~40px，补 min 约束
    //（视觉不变，仅扩大命中区）。
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      disabledColor: AppleColor.inkSubtle,
      onPressed: enabled ? onTap : null,
    );
  }
}
