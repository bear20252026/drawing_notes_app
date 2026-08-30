import 'package:drawing_notes_app/core/canvas_model/fractional_index.dart';

/// 图层排序计算所需的最小不可变对象信息。
class EditorLayerOrderEntry {
  const EditorLayerOrderEntry({
    required this.id,
    required this.fractionalIndex,
    required this.zOrder,
  });

  final String id;
  final String? fractionalIndex;
  final int zOrder;
}

/// 混排画布对象的图层排序结果计算器。
///
/// 该协作者不读取页面、控制器或 Widget，也不直接修改领域对象。它只根据
/// 对象 id、fractionalIndex、zOrder、选择集合和动作模式返回需要写回的键；
/// 页面组合根继续负责状态写回、通知、撤销/重做和持久化时序。
class EditorLayerOrderMutation {
  const EditorLayerOrderMutation._();

  /// 计算排序动作需要写回的对象键。
  ///
  /// [mode] 约定为 0=置顶、1=置底、2=上移、其他值=下移，保持既有命令契约。
  /// 旧文档缺少 fractionalIndex 时仅使用 zOrder 生成比较占位键，不写入模型。
  static Map<String, String?> reorder({
    required Iterable<EditorLayerOrderEntry> entries,
    required Set<String> selectedIds,
    required int mode,
  }) {
    final zOrdered =
        [
          for (final entry in entries)
            _SortableEntry(
              entry: entry,
              comparisonKey: entry.fractionalIndex ?? _zToKey(entry.zOrder),
            ),
        ]..sort((a, b) {
          final comparison = a.comparisonKey.compareTo(b.comparisonKey);
          return comparison != 0
              ? comparison
              : a.entry.zOrder.compareTo(b.entry.zOrder);
        });

    final selected = zOrdered
        .where((entry) => selectedIds.contains(entry.entry.id))
        .toList();
    if (selected.isEmpty) return const <String, String?>{};

    final assignments = <String, String?>{};
    String keyOf(String id) {
      for (final entry in zOrdered) {
        if (entry.entry.id == id) return entry.comparisonKey;
      }
      return 'a0';
    }

    void assign(String id, String? key) {
      assignments[id] = key;
    }

    switch (mode) {
      case 0:
        final maxKey = zOrdered
            .map((entry) => keyOf(entry.entry.id))
            .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
        for (final entry in selected) {
          assign(entry.entry.id, generateKeyBetween(maxKey, null));
        }
      case 1:
        final minKey = zOrdered
            .map((entry) => keyOf(entry.entry.id))
            .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
        for (final entry in selected) {
          assign(entry.entry.id, generateKeyBetween(null, minKey));
        }
      case 2:
        for (final entry in selected) {
          final index = zOrdered.indexWhere(
            (candidate) => candidate.entry.id == entry.entry.id,
          );
          if (index <= 0) continue;
          final previous = zOrdered[index - 1];
          if (selected.any((item) => item.entry.id == previous.entry.id)) {
            continue;
          }
          final currentKey = keyOf(entry.entry.id);
          assign(previous.entry.id, currentKey);
          assign(entry.entry.id, keyOf(previous.entry.id));
        }
      default:
        for (final entry in selected.reversed) {
          final index = zOrdered.indexWhere(
            (candidate) => candidate.entry.id == entry.entry.id,
          );
          if (index < 0 || index >= zOrdered.length - 1) continue;
          final next = zOrdered[index + 1];
          if (selected.any((item) => item.entry.id == next.entry.id)) {
            continue;
          }
          final currentKey = keyOf(entry.entry.id);
          assign(next.entry.id, currentKey);
          assign(entry.entry.id, keyOf(next.entry.id));
        }
    }
    return Map<String, String?>.unmodifiable(assignments);
  }

  static String _zToKey(int z) => 'a0.${z + 0x10000000}';
}

class _SortableEntry {
  const _SortableEntry({required this.entry, required this.comparisonKey});

  final EditorLayerOrderEntry entry;
  final String comparisonKey;
}
