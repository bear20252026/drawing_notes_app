// 文件版同步基线存储（file_sync_baseline_store.dart）单测：
// save/load 往返 / 损坏 JSON 容错（按空基线处理不抛错）/ 原子写（无 .tmp 残留）。

import 'dart:io';

import 'package:drawing_notes_app/core/sync/sync_planner.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File stateFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_baseline_test_');
    stateFile = File('${tempDir.path}${Platform.pathSeparator}sync_state.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  FileSyncBaselineStore makeStore() =>
      FileSyncBaselineStore(directoryProvider: () async => tempDir);

  SyncManifest sampleManifest({
    Map<String, SyncSnapshot> entries = const {},
    Set<String> deletedIds = const {},
  }) => SyncManifest(entries: entries, deletedIds: deletedIds);

  test('基线文件不存在时 load 返回 null（首次同步）', () async {
    expect(await makeStore().load(), isNull);
  });

  test('save→load 往返：条目与墓碑完整恢复', () async {
    final store = makeStore();
    final manifest = sampleManifest(
      entries: {
        'doc_a': const SyncSnapshot(id: 'doc_a', updatedAt: 1725000000000, size: 1024),
        'doc_b': const SyncSnapshot(id: 'doc_b', updatedAt: 1725000001000, size: 2048),
      },
      deletedIds: {'doc_dead'},
    );

    await store.save(manifest);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.entries.keys, containsAll(['doc_a', 'doc_b']));
    expect(
      loaded.entries['doc_a'],
      const SyncSnapshot(id: 'doc_a', updatedAt: 1725000000000, size: 1024),
    );
    expect(loaded.deletedIds, {'doc_dead'});
  });

  test('损坏的基线 JSON：load 返回空基线（null），不抛错', () async {
    await stateFile.writeAsString('{这不是合法 JSON');
    expect(await makeStore().load(), isNull);
  });

  test('合法 JSON 但条目结构损坏：同样按空基线处理（fail-open 到全量同步）', () async {
    // B10 修复路径：畸形清单条目应抛 FormatException，被 load 吞掉后
    // 返回 null（下次全量重新同步），而不是按残缺清单行动。
    await stateFile.writeAsString('{"entries": {"doc_a": 123}}');
    expect(await makeStore().load(), isNull);
  });

  test('save 原子落盘：目录内无 .tmp 残留，仅一份正式文件', () async {
    final store = makeStore();

    await store.save(sampleManifest(
      entries: {'a': const SyncSnapshot(id: 'a', updatedAt: 1, size: 1)},
    ));

    final leftovers = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(leftovers, ['sync_state.json'], reason: 'tmp 应已 rename 为正式文件');
  });

  test('重复 save 覆盖旧基线：最新清单生效，仍无 tmp 残留', () async {
    final store = makeStore();
    await store.save(sampleManifest(
      entries: {'old': const SyncSnapshot(id: 'old', updatedAt: 1, size: 1)},
    ));
    await store.save(sampleManifest(
      entries: {'new': const SyncSnapshot(id: 'new', updatedAt: 2, size: 2)},
      deletedIds: {'old'},
    ));

    final loaded = await makeStore().load();
    expect(loaded!.entries.keys, ['new']);
    expect(loaded.deletedIds, {'old'});
    expect(
      tempDir.listSync().whereType<File>().where((f) => f.path.contains('.tmp')),
      isEmpty,
    );
  });

  test('空清单基线可往返（无条目/无墓碑）', () async {
    final store = makeStore();
    await store.save(sampleManifest());

    final loaded = await makeStore().load();
    expect(loaded, isNotNull);
    expect(loaded!.entries, isEmpty);
    expect(loaded.deletedIds, isEmpty);
  });
}
