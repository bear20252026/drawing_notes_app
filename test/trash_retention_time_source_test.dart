/// P0 回归锁：画布回收站的「过期」必须以**文件名里的删除时刻**为准，
/// 列表热路径的惰性清理必须节流。
///
/// 缺陷原貌（本次修复）：`purgeTrash` 用 `entity.statSync().modified` 判过期，
/// 而删除是 `rename` 进回收站（不改 mtime）⇒ mtime 实为「最后一次保存时间」；
/// 同时 `listDocuments` 每次无节流调用 `purgeTrash` ⇒ 删一个 30 天没编辑过的
/// 画布，回一次首页就被物理删除（连带其受管图片回收），30 天反悔窗口归零。
/// 同口径备案见块文档域 `note_block_doc_store_trash.dart` 的 `_deletedAtOf`
/// （「30 天清理因此误判」）与 `note_block_doc_store.dart` 的 P1-H4 一小时节流。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('trash_time_source_');
    storage = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  String trashDirPath() =>
      '${tempDir.path}${Platform.pathSeparator}documents_trash';

  /// 直接在回收站落一个条目（不经过 delete——要精确控制文件名与 mtime）。
  File seedTrash(String name, {DateTime? mtime}) {
    final dir = Directory(trashDirPath())..createSync(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}$name',
    )..writeAsBytesSync(utf8.encode(jsonEncode({'seed': name})));
    if (mtime != null) file.setLastModifiedSync(mtime);
    return file;
  }

  test('文件名=今天 + mtime=60 天前（刚删除的旧画布）→ 不得清理', () async {
    final now = DateTime.now();
    final file = seedTrash(
      'doc_keep_${now.millisecondsSinceEpoch}.json',
      mtime: now.subtract(const Duration(days: 60)),
    );

    expect(await storage.purgeTrash(), 0, reason: 'mtime 不再参与过期判定');
    expect(file.existsSync(), isTrue, reason: '30 天反悔窗口必须保留');
    // 列表展示同样以文件名时间为准（不是 mtime）。
    final trash = await storage.listTrash();
    expect(trash, hasLength(1));
    expect(
      trash.single.$3.isAfter(now.subtract(const Duration(minutes: 5))),
      isTrue,
      reason: '展示用删除时刻取自文件名，不是 60 天前的 mtime',
    );
  });

  test('文件名=60 天前 → 超保留期被清理（mtime 很新也不救）', () async {
    final now = DateTime.now();
    final oldMillis =
        now.subtract(const Duration(days: 60)).millisecondsSinceEpoch;
    final file = seedTrash('doc_old_$oldMillis.json', mtime: now);

    expect(await storage.purgeTrash(), 1);
    expect(file.existsSync(), isFalse);
  });

  test('真实链路：删除 30 天未编辑的画布后，回首页（listDocuments）不物理删除', () async {
    const id = 'doc_e2e';
    await storage.save(DrawingDocument(id: id, title: '旧画布'));
    // 模拟「最后一次保存在 60 天前」——重命名不改 mtime，删除后仍是旧值。
    final live = File(
      '${tempDir.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}$id.json',
    )..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 60)));
    expect(live.existsSync(), isTrue);

    expect(await storage.delete(id), isTrue);
    // 首页刷新：listDocuments 触发惰性清理（节流后的入口）。
    await storage.listDocuments();

    final trash = await storage.listTrash();
    expect(trash, hasLength(1), reason: '刚删除的文档不得被过期清理误删');
    expect(await storage.restoreTrash(trash.single.$1), id);
    expect(await storage.load(id), isNotNull);
  });

  test('惰性清理节流：短时间内二次列表不重复扫盘（显式 purgeTrash 仍生效）', () async {
    final oldMillis = DateTime.now()
        .subtract(const Duration(days: 60))
        .millisecondsSinceEpoch;
    var file = seedTrash('doc_throttle_$oldMillis.json', mtime: null);

    await storage.listDocuments();
    expect(file.existsSync(), isFalse, reason: '首次列表应完成过期清理');

    // 再造一条已过期的：仍在 1 小时节流窗口内 → 本次列表不扫盘。
    file = seedTrash('doc_throttle2_$oldMillis.json', mtime: null);
    await storage.listDocuments();
    expect(file.existsSync(), isTrue, reason: '节流窗口内不得重复全盘扫描清理');

    // 显式调用 purgeTrash（回收站 UI/测试语义）不受节流影响。
    expect(await storage.purgeTrash(), 1);
    expect(file.existsSync(), isFalse);
  });

  test('生成式 ID（含下划线）：listTrash 给出完整原 ID，restore 移回正确文件名', () async {
    // 旧实现 `split('_').first` 对 LocalIdGenerator 的 `doc_<ts>_<seq>_<rand>`
    // 只截出前缀 'doc'——恢复会把不同文档写成同一个 documents/doc.json。
    final id = StorageService.newId();
    await storage.save(DrawingDocument(id: id, title: '生成 ID'));
    expect(await storage.delete(id), isTrue);

    final trash = await storage.listTrash();
    expect(trash.single.$2, id);
    expect(await storage.restoreTrash(trash.single.$1), id);
    expect(await storage.load(id), isNotNull);
    expect(await storage.listTrash(), isEmpty);
  });
}
