import 'package:drawing_notes_app/engine/view_transform_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ViewTransformCache.clear);

  test('保存后可按键恢复视图变换', () {
    ViewTransformCache.save('doc:a', 1.5, const Offset(10, 20));

    final entry = ViewTransformCache.restore('doc:a');
    expect(entry, isNotNull);
    expect(entry!.scale, 1.5);
    expect(entry.offset, const Offset(10, 20));
  });

  test('未缓存的键返回 null，且不产生条目', () {
    expect(ViewTransformCache.restore('doc:missing'), isNull);
    expect(ViewTransformCache.length, 0);
  });

  test('超过容量时淘汰最久未使用（LRU）', () {
    for (var i = 0; i < 9; i++) {
      ViewTransformCache.save('doc:$i', 1.0, Offset.zero);
    }
    expect(ViewTransformCache.length, 8);

    // doc:0 是最早写入的，应被淘汰；doc:8 是最新的，仍在。
    expect(ViewTransformCache.restore('doc:0'), isNull);
    expect(ViewTransformCache.restore('doc:8'), isNotNull);
  });

  test('命中会刷新为最近使用，不被优先淘汰', () {
    ViewTransformCache.save('doc:a', 1.0, Offset.zero);
    for (var i = 0; i < 7; i++) {
      ViewTransformCache.save('doc:$i', 1.0, Offset.zero);
    }
    // 刷新 doc:a 为最近使用。
    ViewTransformCache.restore('doc:a');

    // 再写入一条，触发淘汰最久未使用的 doc:0（a 刚被刷新，不应被淘汰）。
    ViewTransformCache.save('doc:new', 1.0, Offset.zero);
    expect(ViewTransformCache.restore('doc:0'), isNull);
    expect(ViewTransformCache.restore('doc:a'), isNotNull);
  });
}
