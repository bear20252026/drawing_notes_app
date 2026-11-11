// M5（第三轮专家审计）：列表不再对「损坏 / 超大 / 非法 ID / 锁定不可读」的
// 文件静默 `continue`。
//
// 缺陷形状很窄但后果很重：盘上有 5 篇、首页只有 3 篇，而用户没有任何地方能
// 知道少了哪两篇——只会以为笔记被删了。跳过本身是对的（一个坏文件不该让首页
// 整个打不开），但「跳过了」必须可观测：
//   ① [StorageService.lastListDamagedFiles] 给出**当前状态**（文件名集合，
//      UI 据此提示「有笔记读不出来」）；
//   ② 审计落一条 `storage.list.damaged_skipped`（按轮次聚合，不是逐文件一条
//      ——审计环只有 1000 条，而列表是 UI 每次重建都走的热路径）。
//
// 本文件钉四类跳过路径 + 两条反向锁（不该报的别报、修好了就消失）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late StorageService repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('list_damaged_');
    repo = StorageService(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  Directory docsDir() => Directory(
    '${tempDir.path}${Platform.pathSeparator}documents',
  );

  String pathOf(String fileName) =>
      '${docsDir().path}${Platform.pathSeparator}$fileName';

  /// 直接落一个「盘上文件」，绕开 save（要造的就是 save 产不出的形态）。
  void putRaw(String fileName, List<int> bytes) {
    docsDir().createSync(recursive: true);
    File(pathOf(fileName)).writeAsBytesSync(bytes);
  }

  /// 造一篇合法明文文档的原始字节。
  Uint8List plainDoc(String id, {String? innerId}) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'document': {
            'id': innerId ?? id,
            'title': '标题-$id',
            'width': 400,
            'height': 300,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
            'layers': <Object>[],
          },
        }),
      ),
    );
  }

  /// 本轮列表（[auditMark] 之后）落下的 `storage.list.damaged_skipped` 行。
  ///
  /// 必须按 mark 切，不能直接数全量：审计链是**进程级**的，同一份文件里
  /// 前面的用例已经落过同名条目（实测第一条断言前链里已有 8 条）。
  int auditMark = 0;

  List<String> damagedLinesSinceMark() => AuditLogger.snapshot()
      .skip(auditMark)
      .where((line) => line.contains('storage.list.damaged_skipped'))
      .toList();

  bool damagedReported() => damagedLinesSinceMark().isNotEmpty;

  group('① 四类「进不了列表」的路径都要登记', () {
    test('内容损坏（截断到不成 JSON）⇒ 记文件名，列表其余篇不受影响', () async {
      await repo.save(DrawingDocument(id: 'm5_ok', title: '好的'));
      putRaw('m5_broken.json', utf8.encode('{"document": {"id": "m5_broken"'));

      auditMark = AuditLogger.snapshot().length;
      final metas = await repo.listDocuments();

      expect(metas.map((m) => m.id), ['m5_ok'], reason: '坏文件不该拖垮整份列表');
      expect(repo.lastListDamagedFiles, {'m5_broken.json'});
      expect(damagedReported(), isTrue, reason: '静默跳过 = 用户看到「少了一篇」');
    });

    test('主密钥密钥存在但文件损坏 ⇒ 解密抛 VaultFileException 也走登记', () async {
      // 明文文档 + 有 keyProvider ⇒ 不属加密分支；要专门造「密文信封但解不开」
      // 的形态。密文头被截断后 isEncrypted 仍成立（>4 字节），decrypt 抛
      // VaultFileException ⇒ 落进 catch-all。
      final vaultRepo = StorageService(
        directoryProvider: () async => tempDir,
        vaultConfigured: () async => true,
        keyProvider: () async => Uint8List.fromList(List.filled(32, 7)),
      );
      final truncated = Uint8List.fromList([
        0x44, 0x4E, 0x56, // "DNV"
        0x01, // 版本 1
        ...List.filled(8, 0), // 载荷长度不够 ⇒ 解密必失败
      ]);
      putRaw('m5_torn.json', truncated);

      auditMark = AuditLogger.snapshot().length;
      final metas = await vaultRepo.listDocuments();

      expect(metas, isEmpty);
      expect(vaultRepo.lastListDamagedFiles, {'m5_torn.json'});
      expect(damagedReported(), isTrue);
    });

    test('非法 ID（正文里的 id 含路径分隔符）⇒ 登记，且不当成一篇', () async {
      await repo.save(DrawingDocument(id: 'm5_ok2', title: '好的'));
      putRaw('m5_badid.json', plainDoc('m5_badid', innerId: '../escape'));

      auditMark = AuditLogger.snapshot().length;
      final metas = await repo.listDocuments();

      expect(metas.map((m) => m.id), ['m5_ok2']);
      expect(repo.lastListDamagedFiles, {'m5_badid.json'});
    });

    test('无密钥可解的加密文档（保险库锁定）⇒ 登记，不静默消失', () async {
      // 先在有密钥时落一篇密文，再把同一份字节留在原地、用一个「取不到密钥」
      // 的实例去列表 ⇒ 走 key == null 那一支。
      final withKey = StorageService(
        directoryProvider: () async => tempDir,
        vaultConfigured: () async => true,
        keyProvider: () async => Uint8List.fromList(List.filled(32, 7)),
      );
      await withKey.save(DrawingDocument(id: 'm5_locked', title: '锁住的'));
      final raw = File(pathOf('m5_locked.json')).readAsBytesSync();
      expect(VaultFileCodec.isEncrypted(raw), isTrue, reason: '前提：落的是密文');

      final locked = StorageService(
        directoryProvider: () async => tempDir,
        vaultConfigured: () async => true,
        keyProvider: () async => null, // 保险库锁定：取不到主密钥
      );
      auditMark = AuditLogger.snapshot().length;
      final metas = await locked.listDocuments();

      expect(metas, isEmpty, reason: '锁定态不暴露内容，但也不能什么都不说');
      expect(locked.lastListDamagedFiles, {'m5_locked.json'});
    });

    test('超大文件（超单文件预算）⇒ 登记，且不做 readAsBytes', () async {
      // 100MB 真造出来太慢；用 sparse 手法：建文件后 setLength 撑到预算之上。
      // 列表的预检在 readAsBytes **之前**，所以这条断言同时也是「不会 OOM」的
      // 低成本替身（真读 100MB 进内存的用例由 document_budget 侧钉）。
      await repo.save(DrawingDocument(id: 'm5_small', title: '小的'));
      docsDir().createSync(recursive: true);
      final huge = File(pathOf('m5_huge.json'));
      huge.writeAsBytesSync(plainDoc('m5_huge'));
      // File 没有 setLengthSync：走 RandomAccessFile.setLength（同样造出稀疏文件）。
      final raf = huge.openSync(mode: FileMode.append);
      raf.setPositionSync(100 * 1024 * 1024);
      raf.truncateSync(100 * 1024 * 1024 + 1);
      raf.closeSync();

      auditMark = AuditLogger.snapshot().length;
      final metas = await repo.listDocuments();

      expect(metas.map((m) => m.id), ['m5_small']);
      expect(repo.lastListDamagedFiles, {'m5_huge.json'});
    });
  });

  group('② 反向锁：不该报的别报，修好了就消失', () {
    test('全是好文件 ⇒ 集合为空、审计一条不落', () async {
      await repo.save(DrawingDocument(id: 'm5_a', title: 'A'));
      await repo.save(DrawingDocument(id: 'm5_b', title: 'B'));

      auditMark = AuditLogger.snapshot().length;
      final metas = await repo.listDocuments();

      expect(metas, hasLength(2));
      expect(repo.lastListDamagedFiles, isEmpty);
      expect(
        damagedLinesSinceMark(),
        isEmpty,
        reason: '没有跳过就不该产生审计条目——否则热路径每次都污染审计环',
      );
    });

    test('坏文件被挪走后，下一轮列表不再报它（状态是当前快照，不是历史）', () async {
      putRaw('m5_gone.json', utf8.encode('not json at all'));
      expect((await repo.listDocuments()), isEmpty);
      expect(repo.lastListDamagedFiles, {'m5_gone.json'});

      File(pathOf('m5_gone.json')).deleteSync();
      await repo.listDocuments();
      expect(repo.lastListDamagedFiles, isEmpty);
    });
  });

  group('③ 登记口径', () {
    test('只记文件名（不含目录），同一文件只记一次', () async {
      putRaw('m5_dup.json', utf8.encode('broken-1'));
      await repo.listDocuments();
      expect(repo.lastListDamagedFiles, {'m5_dup.json'});
      expect(
        repo.lastListDamagedFiles.any((n) => n.contains(Platform.pathSeparator)),
        isFalse,
        reason: '带目录会让 UI 提示与审计 detail 各自拼路径，容易拼出两种写法',
      );

      // 坏文件原样还在，再列一次：集合语义 ⇒ 不会变成两条。
      await repo.listDocuments();
      expect(repo.lastListDamagedFiles, {'m5_dup.json'});
    });

    test('多个坏文件 ⇒ 审计仍只落一条（按轮次聚合，不是逐文件）', () async {
      putRaw('m5_m1.json', utf8.encode('x'));
      putRaw('m5_m2.json', utf8.encode('y'));
      putRaw('m5_m3.json', utf8.encode('z'));

      auditMark = AuditLogger.snapshot().length;
      await repo.listDocuments();

      expect(repo.lastListDamagedFiles, hasLength(3));
      final hits = damagedLinesSinceMark();
      expect(hits, hasLength(1), reason: '逐文件落审计会让列表热路径吃掉审计环');
      expect(hits.single, contains('count=3'));
    });

    test('返回的集合不可改（调用方改不动内部状态）', () async {
      putRaw('m5_ro.json', utf8.encode('x'));
      await repo.listDocuments();

      expect(
        () => repo.lastListDamagedFiles.add('hacked.json'),
        throwsUnsupportedError,
      );
    });
  });
}
