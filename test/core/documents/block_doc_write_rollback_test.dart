// 批次 D（2026-10-14 实测发现）：换入失败必须把上一版放回去。
//
// 缺陷是写故障注入用例时撞出来的，不是先想到再补的。形状如下：
// Windows 那条兜底是「rename 被拒 ⇒ 删掉正式文件 ⇒ 再 rename」。第二次 rename
// 仍可能失败（句柄删除挂起期 ACCESS_DENIED，退避 5 次用尽），那时正式文件已经没了，
// 盘上只剩 `.bak`。读路径确实能回退到 `.bak`，**但列表只认 `.json`**——于是：
//   首页与搜索里这篇笔记消失；
//   同步侧的形状是「基线有、本次清单无」⇒ 推导成用户删除 ⇒ 真的 `DELETE` 云端副本
//   （`note_block_doc_sync_store` 里 DN-107 注释写的正是这条推导）。
// ⇒ 一次失败的保存 = 云端数据丢失。本文件的三条用例就是这个出口的锁。
//
// 用明文装配（不给 keyProvider）：本文件验的是**文件面**的回滚与可见性，
// 掺进真 KDF 只会让它被拖进 kdf 分片，与本条主张无关。
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late NoteBlockDocStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('blockdoc_rollback_');
    AuditLogger.clear();
    store = NoteBlockDocStore(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    store.renameBarrierForTest = null;
    store.renameFaultForTest = null;
    await deleteTempDirWithRetry(tempDir);
  });

  String docPath(String id) =>
      '${tempDir.path}${Platform.pathSeparator}blockdocs'
      '${Platform.pathSeparator}$id.json';

  NoteBlockDoc doc(String id, String title) {
    final t = DateTime.fromMillisecondsSinceEpoch(0);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('${id}_b1', text: '内容 $title')],
      createdAt: t,
      updatedAt: t,
    );
  }

  /// 制造「换入这一步真失败」这一等价类：tmp 已完整、rename 前被移走
  /// （Linux 与 Windows 同判抛错）。真实共享冲突那一格由
  /// `storage_encryption_test.dart:225` 的 Windows 用例覆盖，两条不互相顶替。
  void breakRenameOnEntry() {
    store.renameBarrierForTest = (id, tmpPath) async {
      File(tmpPath).deleteSync();
    };
  }

  test('换入失败 ⇒ 正式文件被放回上一版、.bak 仍在、审计留痕、列表仍看得见这篇', () async {
    await store.saveDocument(doc('rb_a', '第一版'));
    await store.saveDocument(doc('rb_a', '第二版'));
    final path = docPath('rb_a');
    final v2 = File(path).readAsBytesSync();
    AuditLogger.clear();

    breakRenameOnEntry();
    await expectLater(
      store.saveDocument(doc('rb_a', '第三版')),
      throwsA(isA<FileSystemException>()),
    );
    store.renameBarrierForTest = null;

    expect(
      File(path).readAsBytesSync(),
      equals(v2),
      reason: '兜底已经删过正式文件；不回滚就等于让这篇从列表里消失',
    );
    expect(File('$path.bak').existsSync(), isTrue);
    expect(File('$path.bak').readAsBytesSync(), equals(v2));
    expect(
      AuditLogger.snapshot().any((l) => l.contains('write_rolled_back_from_backup')),
      isTrue,
      reason: '回滚是异常处置，必须可诊断——静默回滚等于下次没人知道这里着过火',
    );
    // 列表可见性才是这条链的终点：同步侧的删除墓碑就是从「清单里没有」推出来的。
    final headers = await store.listDocHeaders();
    expect(headers.map((h) => h.id), contains('rb_a'));
  });

  test('首写就撞上换入失败 ⇒ 不凭空造出正式文件，也没有 .bak（无上一版可回滚）', () async {
    breakRenameOnEntry();
    await expectLater(
      store.saveDocument(doc('rb_b', '唯一一版')),
      throwsA(isA<FileSystemException>()),
    );
    store.renameBarrierForTest = null;

    expect(File(docPath('rb_b')).existsSync(), isFalse);
    expect(File('${docPath('rb_b')}.bak').existsSync(), isFalse);
    expect(
      Directory('${tempDir.path}${Platform.pathSeparator}blockdocs')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('反向锁：成功写入绝不触发回滚（审计里没有回滚条目）', () async {
    await store.saveDocument(doc('rb_c', '第一版'));
    await store.saveDocument(doc('rb_c', '第二版'));
    AuditLogger.clear();

    await store.saveDocument(doc('rb_c', '第三版'));

    expect(
      AuditLogger.snapshot().any((l) => l.contains('write_rolled_back_from_backup')),
      isFalse,
      reason: '回滚只属于失败出口；成功路径一次都不该走它',
    );
    final loaded = await store.loadDocument('rb_c');
    expect(loaded?.title, '第三版');
  });

  test('兜底腿的成功分支：改名被拒 ⇒ 删目标再换入要真落地，且不触发回滚', () async {
    // 与上一条「反向锁」不重复：那条走的是 rename 一次成功的常规路径，本条走的是
    // **被拒之后**的兜底路径。这条腿只能注入——判据与实测记录见
    // `NoteBlockDocStore.renameFaultForTest`（本仓跑在 Linux CI 上永远到不了，
    // 真机上又只在「持句柄者刚好放手」的窗口里才成立）。
    await store.saveDocument(doc('rf_a', '第一版'));
    await store.saveDocument(doc('rf_a', '第二版'));
    final path = docPath('rf_a');
    final v2 = File(path).readAsBytesSync();
    AuditLogger.clear();

    var refused = 0;
    store.renameFaultForTest = (tmpPath, destinationPath) {
      if (refused > 0) return false; // 第二次换入走真实 rename
      // 注入的形状必须等于真实拒绝：两份都原地不动。
      expect(
        File(tmpPath).existsSync(),
        isTrue,
        reason: '兜底腿要用同一个 tmp 再换入一次：此刻它必须已经完整存在',
      );
      expect(
        File(destinationPath).existsSync(),
        isTrue,
        reason: '被拒的那一刻正式文件没被动过——它还在，才会需要「先删再换」',
      );
      refused++;
      return true;
    };

    await store.saveDocument(doc('rf_a', '第三版'));

    expect(refused, 1, reason: '钩子一次都没被调到 = 这条用例什么都没验');
    final text = utf8.decode(File(path).readAsBytesSync());
    expect(text, contains('第三版'), reason: '兜底腿的全部意义：这次写入要落地');
    expect(text, isNot(contains('第二版')));
    expect(
      File('$path.bak').readAsBytesSync(),
      equals(v2),
      reason: '换入成功也不该顺手吃掉上一版',
    );
    expect(
      Directory('${tempDir.path}${Platform.pathSeparator}blockdocs')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    expect(
      AuditLogger.snapshot().any((l) => l.contains('write_rolled_back_from_backup')),
      isFalse,
      reason: '回滚只属于失败出口：换入已成功还去跑它，说明这次写被当成失败'
          '（第三版没被第二版盖回去只是靠 existsSync 那道守卫）',
    );
    expect((await store.loadDocument('rf_a'))?.title, '第三版');
    expect((await store.listDocHeaders()).map((h) => h.id), contains('rf_a'));
  });
}
