// 渲染引擎单元测试——视图变换缓存（ViewTransformCache）。
//
// 验证静态 LRU 缓存的行为与命中率：
// - save/restore 往返正确
// - 未命中返回 null（cache miss）
// - LRU 容量上限淘汰最旧条目
// - restore/save 均刷新最近使用位置
// - clear 清空
//
// 注意：ViewTransformCache 是全局静态缓存，测试之间必须 clear()
// 避免用例相互污染。
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/view_transform_cache.dart';

void main() {
  setUp(ViewTransformCache.clear);

  tearDown(ViewTransformCache.clear);

  group('save / restore 往返', () {
    test('保存后恢复得到相同 scale 与 offset', () {
      ViewTransformCache.save('page-1', 2.5, const Offset(120, 80));

      final entry = ViewTransformCache.restore('page-1');
      expect(entry, isNotNull);
      expect(entry!.scale, 2.5);
      expect(entry.offset, const Offset(120, 80));
    });

    test('不同 key 互不干扰', () {
      ViewTransformCache.save('a', 1.0, const Offset(0, 0));
      ViewTransformCache.save('b', 3.0, const Offset(50, 60));

      expect(ViewTransformCache.restore('a')!.scale, 1.0);
      expect(ViewTransformCache.restore('b')!.scale, 3.0);
    });

    test('覆盖写入同 key 更新值', () {
      ViewTransformCache.save('k', 1.0, const Offset(0, 0));
      ViewTransformCache.save('k', 4.0, const Offset(9, 9));

      final entry = ViewTransformCache.restore('k');
      expect(entry!.scale, 4.0);
      expect(entry.offset, const Offset(9, 9));
    });
  });

  group('未命中', () {
    test('restore 不存在的 key 返回 null 且不产生条目', () {
      expect(ViewTransformCache.restore('missing'), isNull);
      expect(ViewTransformCache.length, 0);
    });

    test('clear 之后全部 miss', () {
      ViewTransformCache.save('x', 2.0, const Offset(1, 1));
      ViewTransformCache.clear();

      expect(ViewTransformCache.restore('x'), isNull);
    });
  });

  group('LRU 淘汰策略（缓存命中率核心）', () {
    test('容量上限为 8，超出后淘汰最早使用的条目', () {
      for (var i = 0; i < 8; i++) {
        ViewTransformCache.save('key-$i', i.toDouble(), Offset.zero);
      }
      // 全部命中
      for (var i = 0; i < 8; i++) {
        expect(ViewTransformCache.restore('key-$i'), isNotNull,
            reason: 'key-$i 应在容量内');
      }

      // 第 9 个插入 → 最旧的 key-0 被淘汰
      ViewTransformCache.save('key-8', 8.0, Offset.zero);
      expect(ViewTransformCache.length, 8, reason: '容量应稳定在 8');
      expect(ViewTransformCache.restore('key-0'), isNull,
          reason: 'key-0 应被 LRU 淘汰');
      expect(ViewTransformCache.restore('key-8'), isNotNull);
    });

    test('restore 刷新使用顺序：被读过的条目不会被先淘汰', () {
      for (var i = 0; i < 8; i++) {
        ViewTransformCache.save('key-$i', i.toDouble(), Offset.zero);
      }
      // 读 key-0 使它变成"最近使用"
      ViewTransformCache.restore('key-0');

      // 插入第 9 个 → 此时应淘汰的是 key-1（而非刚读过的 key-0）
      ViewTransformCache.save('key-8', 8.0, Offset.zero);

      expect(ViewTransformCache.restore('key-0'), isNotNull,
          reason: 'restore 后 key-0 已刷新，不应被淘汰');
      expect(ViewTransformCache.restore('key-1'), isNull,
          reason: 'key-1 成为最旧条目，应被淘汰');
    });

    test('重复 save 同 key 刷新使用顺序且不增加长度', () {
      for (var i = 0; i < 8; i++) {
        ViewTransformCache.save('key-$i', i.toDouble(), Offset.zero);
      }
      // 重写 key-0（刷新位置）
      ViewTransformCache.save('key-0', 100.0, const Offset(7, 7));

      ViewTransformCache.save('key-8', 8.0, Offset.zero);

      expect(ViewTransformCache.restore('key-0'), isNotNull);
      expect(ViewTransformCache.restore('key-1'), isNull,
          reason: '重写 key-0 后 key-1 变为最旧，应被淘汰');
    });
  });

  group('缓存命中统计口径', () {
    test('典型工作流：往返缩放场景命中率验证', () {
      // 模拟用户在两个页面间反复切换的访问序列
      var hits = 0;
      var misses = 0;

      void access(String key) {
        if (ViewTransformCache.restore(key) != null) {
          hits++;
        } else {
          misses++;
        }
        ViewTransformCache.save(key, 1.5, const Offset(10, 10));
      }

      // 首次访问 10 个页面：全部 miss
      for (var i = 0; i < 10; i++) {
        access('page-$i');
      }
      expect(misses, 10);
      expect(hits, 0);

      // 容量 8：page-0/page-1 已被淘汰，再访问 page-2..9 应全部命中
      for (var i = 2; i < 10; i++) {
        access('page-$i');
      }
      expect(hits, 8);
      // page-2..9 的再次访问把 page-0/page-1 挤出后，
      // 最后两次访问（page-8、page-9）时它们仍在缓存中：
      // 精确统计：misses 保持 10（无新增 miss）
      expect(misses, 10);
    });
  });
}
