// shared/widgets——统一图层面板（V1/V2 合并——2026-08-24）。
//
// 从 V1/V2 重复代码中统一的图层面板：
// - 支持图层列表显示
// - 支持图层选择/重命名/删除
// - 支持图层可见性/锁定切换
// - 支持图层顺序调整
//
// 设计原则：
// - 纯 UI 组件，不含业务逻辑
// - 所有状态通过参数传入
// - 所有操作通过回调返回
// - 可被 V1/V2 共同使用
library;

import 'package:flutter/material.dart';

/// 统一图层面板（V1/V2 合并——2026-08-24）。
///
/// 显示图层列表，支持：
/// - 图层选择
/// - 图层可见性切换
/// - 图层锁定切换
/// - 图层重命名
/// - 图层删除
/// - 图层顺序调整
class UnifiedLayerPanel extends StatelessWidget {
  const UnifiedLayerPanel({
    super.key,
    required this.layers,
    required this.selectedLayerId,
    required this.onLayerSelected,
    this.onLayerVisibilityChanged,
    this.onLayerLockChanged,
    this.onLayerRenamed,
    this.onLayerDeleted,
    this.onLayerReorder,
    this.width = 200,
  });

  /// 图层列表。
  final List<LayerInfo> layers;

  /// 当前选中的图层 ID。
  final String? selectedLayerId;

  /// 图层选择回调。
  final ValueChanged<String> onLayerSelected;

  /// 图层可见性变更回调。
  final ValueChanged<String>? onLayerVisibilityChanged;

  /// 图层锁定变更回调。
  final ValueChanged<String>? onLayerLockChanged;

  /// 图层重命名回调。
  final void Function(String id, String newName)? onLayerRenamed;

  /// 图层删除回调。
  final ValueChanged<String>? onLayerDeleted;

  /// 图层顺序调整回调。
  final void Function(String id, int newIndex)? onLayerReorder;

  /// 面板宽度。
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: scheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.layers, size: 16),
                SizedBox(width: 8),
                Text(
                  '图层',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                Text(
                  '${layers.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 图层列表
          Expanded(
            child: ReorderableListView.builder(
              itemCount: layers.length,
              onReorder: (oldIndex, newIndex) {
                if (onLayerReorder != null) {
                  final layer = layers[oldIndex];
                  onLayerReorder!(layer.id, newIndex);
                }
              },
              itemBuilder: (context, index) {
                final layer = layers[index];
                final isSelected = layer.id == selectedLayerId;

                return _LayerTile(
                  key: ValueKey(layer.id),
                  layer: layer,
                  isSelected: isSelected,
                  onTap: () => onLayerSelected(layer.id),
                  onVisibilityChanged: onLayerVisibilityChanged != null
                      ? () => onLayerVisibilityChanged!(layer.id)
                      : null,
                  onLockChanged: onLayerLockChanged != null
                      ? () => onLayerLockChanged!(layer.id)
                      : null,
                  onRenamed: onLayerRenamed != null
                      ? (newName) => onLayerRenamed!(layer.id, newName)
                      : null,
                  onDeleted: onLayerDeleted != null
                      ? () => onLayerDeleted!(layer.id)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    super.key,
    required this.layer,
    required this.isSelected,
    required this.onTap,
    this.onVisibilityChanged,
    this.onLockChanged,
    this.onRenamed,
    this.onDeleted,
  });

  final LayerInfo layer;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onVisibilityChanged;
  final VoidCallback? onLockChanged;
  final ValueChanged<String>? onRenamed;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? scheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // 拖拽手柄
              Icon(Icons.drag_indicator, size: 16, color: scheme.outline),

              SizedBox(width: 8),

              // 图层名称
              Expanded(
                child: _buildLayerName(context),
              ),

              // 可见性切换
              if (onVisibilityChanged != null)
                GestureDetector(
                  onTap: onVisibilityChanged,
                  child: Icon(
                    layer.isVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    size: 16,
                    color: layer.isVisible
                        ? scheme.onSurface
                        : scheme.outline,
                  ),
                ),

              SizedBox(width: 4),

              // 锁定切换
              if (onLockChanged != null)
                GestureDetector(
                  onTap: onLockChanged,
                  child: Icon(
                    layer.isLocked ? Icons.lock : Icons.lock_open,
                    size: 16,
                    color: layer.isLocked
                        ? scheme.error
                        : scheme.outline,
                  ),
                ),

              SizedBox(width: 4),

              // 删除按钮
              if (onDeleted != null)
                GestureDetector(
                  onTap: onDeleted,
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: scheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayerName(BuildContext context) {
    if (onRenamed == null) {
      return Text(
        layer.name,
        style: TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      );
    }

    return GestureDetector(
      onDoubleTap: () {
        // 双击重命名
        showDialog(
          context: context,
          builder: (context) {
            final controller = TextEditingController(text: layer.name);
            return AlertDialog(
              title: Text('重命名图层'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '输入图层名称',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    onRenamed!(controller.text);
                    Navigator.pop(context);
                  },
                  child: Text('确定'),
                ),
              ],
            );
          },
        );
      },
      child: Text(
        layer.name,
        style: TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 图层信息（公共数据模型）。
class LayerInfo {
  const LayerInfo({
    required this.id,
    required this.name,
    this.isVisible = true,
    this.isLocked = false,
    this.itemCount = 0,
  });

  /// 图层 ID。
  final String id;

  /// 图层名称。
  final String name;

  /// 是否可见。
  final bool isVisible;

  /// 是否锁定。
  final bool isLocked;

  /// 图层中的元素数量。
  final int itemCount;
}
