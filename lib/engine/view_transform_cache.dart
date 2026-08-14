import 'dart:collection';
import 'dart:ui';

/// 视图变换按文件 LRU 缓存：重新打开同一文档/笔记页时恢复上次的
/// 缩放与平移位置（借鉴 Saber 的 CanvasTransformCache，独立实现）。
///
/// 只缓存最近打开过的少数文档（[_maxEntries] 条），避免长期驻留；
/// 命中或写入都会把条目刷新为最近使用，淘汰最久未用的条目。
class ViewTransformCache {
  ViewTransformCache._();

  /// 最多保留的文档数。
  static const int _maxEntries = 8;

  static final LinkedHashMap<String, ViewTransformEntry> _entries =
      LinkedHashMap();

  /// 记录某文档的最新视图变换。
  ///
  /// 已存在的条目先移除再插入，从而刷新为最近使用；超出容量时
  /// 淘汰最久未使用的条目（LinkedHashMap 保持插入顺序）。
  static void save(String key, double scale, Offset offset) {
    _entries.remove(key);
    _entries[key] = ViewTransformEntry(scale, offset);
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 读取某文档的缓存视图（命中时刷新为最近使用）；无缓存返回 null。
  static ViewTransformEntry? restore(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry; // 刷新 LRU 位置
    return entry;
  }

  /// 当前缓存的文档数（供测试与诊断）。
  static int get length => _entries.length;

  /// 清空全部缓存（测试/退出登录时使用）。
  static void clear() => _entries.clear();
}

/// 一份文档的缓存视图变换。
class ViewTransformEntry {
  const ViewTransformEntry(this.scale, this.offset);

  final double scale;
  final Offset offset;
}
