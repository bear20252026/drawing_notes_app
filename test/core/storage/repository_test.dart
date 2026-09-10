// DocumentRepository 契约单测（实现 = StorageService，本地 JSON 文件版）：
// 保存 / 加载 / 删除 / 列表语义 + ID 路径遍历防护。
// 见 lib/core/storage/repository.dart 与 storage_service.dart。

import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('repository_test_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  DocumentRepository makeRepo() =>
      StorageService(directoryProvider: () async => tempDir);

  test('save 返回落盘路径：文件真实存在且以 <id>.json 命名', () async {
    final repo = makeRepo();

    final path = await repo.save(
      DrawingDocument(id: 'doc_round', title: '契约测试'),
    );

    expect(File(path).existsSync(), isTrue);
    expect(path, endsWith('doc_round.json'));
  });

  test('save→load 往返：标题/尺寸/默认图层完整恢复', () async {
    final repo = makeRepo();

    await repo.save(
      DrawingDocument(id: 'doc_round', title: '我的画', width: 320, height: 240),
    );
    final loaded = await repo.load('doc_round');

    expect(loaded, isNotNull);
    expect(loaded!.id, 'doc_round');
    expect(loaded.title, '我的画');
    expect(loaded.width, 320);
    expect(loaded.height, 240);
    expect(loaded.layers, hasLength(1), reason: '默认单图层完整保留');
  });

  test('load 不存在的文档返回 null（不抛错）', () async {
    final repo = makeRepo();

    expect(await repo.load('no_such_doc'), isNull);
  });

  test('listDocuments：返回全部元信息，按更新时间倒序', () async {
    final repo = makeRepo();
    await repo.save(
      DrawingDocument(
        id: 'older',
        title: '较早',
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await repo.save(
      DrawingDocument(
        id: 'newer',
        title: '较新',
        updatedAt: DateTime(2026, 9, 1),
      ),
    );

    final metas = await repo.listDocuments();

    expect(metas.map((m) => m.id).toList(), ['newer', 'older']);
    final meta = metas.firstWhere((m) => m.id == 'newer');
    expect(meta.title, '较新');
    expect(meta.layerCount, 1);
    expect(meta.strokeCount, 0);
    expect(meta.updatedAt, DateTime(2026, 9, 1));
  });

  test('listDocuments：空目录返回空列表', () async {
    expect(await makeRepo().listDocuments(), isEmpty);
  });

  test('delete 语义：删除成功返回 true，文档消失，重复删除返回 false', () async {
    final repo = makeRepo();
    await repo.save(DrawingDocument(id: 'doc_del', title: '待删除'));

    expect(await repo.delete('doc_del'), isTrue);
    expect(await repo.load('doc_del'), isNull);
    expect((await repo.listDocuments()), isEmpty);
    expect(await repo.delete('doc_del'), isFalse, reason: '不存在时删除返回 false');
  });

  test('delete 后回收站保留副本（M-06：移入回收站而非永久删除）', () async {
    final repo = makeRepo();
    await repo.save(DrawingDocument(id: 'doc_trash', title: '回收站测试'));

    await repo.delete('doc_trash');

    final trashDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}documents_trash',
    );
    final trashed = trashDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(trashed, hasLength(1));
    expect(trashed.single, startsWith('doc_trash_'));
  });

  test('路径遍历防护：非法 ID 在 save/load/delete 均抛 ArgumentError', () async {
    final repo = makeRepo();
    final evilId = '../escape';

    expect(
      () => repo.save(DrawingDocument(id: evilId, title: 'x')),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => repo.load(evilId), throwsA(isA<ArgumentError>()));
    expect(() => repo.delete(evilId), throwsA(isA<ArgumentError>()));
  });
}
