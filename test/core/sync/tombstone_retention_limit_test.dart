// M8（第三轮专家审计）：墓碑留存上限从 512 抬到 2048。
//
// 缺陷形状：清单每轮整份拉取，墓碑必须裁剪，但 512 这个上限在**极端删除
// 场景**下会被打穿——同一批设备各自离线数周、期间删掉超过 512 篇时，
// 最旧的那批墓碑被 [SyncManifest.pruneTombstones] 淘汰。墓碑上的因果锚
// （`baseRev` / `baseSize`）是「这条删除是对着哪一版做的」的唯一凭据；锚丢了，
// 那篇文档在别的设备上重新出现时只剩「本地独有 ⇒ 上传」一条判据，删除方向
// 可能被误判成复活。
//
// 本文件钉两件事：
//  ① 上限值本身是契约（写死 2048）——静默改回去会让这条审计失效；
//  ② 裁剪行为：2048 条以内一条不丢，超出时淘汰**最旧**的（按 deletedAt，
//     同刻按 id 字典序），且结果稳定（同一输入两次裁剪必须逐字节相同——
//     清单要参与 ETag 条件写）。
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_planner.dart';

SyncTombstone _tomb(String id, int deletedAt) => SyncTombstone(
  id: id,
  deletedAt: deletedAt,
  baseRev: deletedAt,
  baseSize: 100,
);

void main() {
  group('① 上限值是契约', () {
    test('maxTombstones == 2048（原值 512 在极端删除场景下会丢因果锚）', () {
      expect(SyncManifest.maxTombstones, 2048);
    });

    test('恰好 2048 条 ⇒ 一条不淘汰', () {
      final all = [
        for (var i = 0; i < 2048; i++) _tomb('doc_$i', 1000 + i),
      ];
      final kept = SyncManifest.pruneTombstones(all);
      expect(kept, hasLength(2048));
      for (final t in all) {
        expect(kept.containsKey(t.id), isTrue, reason: '${t.id} 不该被淘汰');
      }
    });

    test('2049 条 ⇒ 恰好淘汰最旧的那一条，其余全留', () {
      final all = [
        _tomb('oldest', 1), // 最旧
        for (var i = 0; i < 2048; i++) _tomb('doc_$i', 1000 + i),
      ];
      final kept = SyncManifest.pruneTombstones(all);
      expect(kept, hasLength(2048));
      expect(kept.containsKey('oldest'), isFalse, reason: '淘汰的必须是最旧那条');
      for (var i = 0; i < 2048; i++) {
        expect(kept.containsKey('doc_$i'), isTrue, reason: '较新的不许被牵连');
      }
    });
  });

  group('② 裁剪行为', () {
    test('超出上限 ⇒ 保留最新的一批（极端删除场景下不丢较新的因果锚）', () {
      final all = [
        for (var i = 0; i < 3000; i++) _tomb('doc_${i.toString().padLeft(4, '0')}', 1000 + i),
      ];
      final kept = SyncManifest.pruneTombstones(all);
      expect(kept, hasLength(2048));
      // 最新的 2048 条 = 下标 952..2999。
      for (var i = 952; i < 3000; i++) {
        expect(
          kept.containsKey('doc_${i.toString().padLeft(4, '0')}'),
          isTrue,
          reason: '第 $i 条属于最新 2048 条，必须留下',
        );
      }
      expect(kept.containsKey('doc_0000'), isFalse);
      expect(kept.containsKey('doc_0951'), isFalse);
      expect(kept.containsKey('doc_0952'), isTrue, reason: '边界：第一条留下的');
    });

    test('同一时间戳 ⇒ 按 id 字典序兜底淘汰（不留「看运气」的口径）', () {
      final all = [
        for (var i = 0; i < 10; i++) _tomb('doc_${String.fromCharCode(65 + i)}', 5000),
      ];
      final kept = SyncManifest.pruneTombstones(all, limit: 5);
      expect(kept.keys.toSet(), {'doc_F', 'doc_G', 'doc_H', 'doc_I', 'doc_J'});
    });

    test('结果稳定：同一输入两次裁剪逐条相同（清单要参与 ETag 条件写）', () {
      final all = [
        for (var i = 0; i < 2500; i++) _tomb('doc_$i', 1000 + (i * 7) % 997),
      ];
      final a = SyncManifest.pruneTombstones(all);
      final b = SyncManifest.pruneTombstones(all);
      expect(a.keys.toSet(), b.keys.toSet());
      for (final id in a.keys) {
        expect(a[id], equals(b[id]));
      }
    });

    test('未超上限 ⇒ 原样保留（顺序不同也不裁）', () {
      final all = [_tomb('b', 2000), _tomb('a', 1000)];
      final kept = SyncManifest.pruneTombstones(all);
      expect(kept, hasLength(2));
      expect(kept['a'], equals(all[1]));
      expect(kept['b'], equals(all[0]));
    });

    test('缺时间戳（旧清单）⇒ 按最旧处理，优先淘汰信息不全的那条', () {
      final all = [
        const SyncTombstone(id: 'no_ts'),
        _tomb('has_ts', 1000),
      ];
      final kept = SyncManifest.pruneTombstones(all, limit: 1);
      expect(kept.keys, {'has_ts'}, reason: '缺锚的那条先被淘汰，符合 retentionKey 口径');
    });

    test('空输入 ⇒ 空输出（不抛）', () {
      expect(SyncManifest.pruneTombstones(const []), isEmpty);
    });
  });
}
