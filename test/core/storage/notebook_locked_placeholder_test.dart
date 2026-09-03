/// listAll 锁定占位（fail-closed 可见性，与 N2 块文档列表占位同口径）。
///
/// 覆盖：保险库锁定时 DNV 密文分页画布以占位条目出现在 listAll（不再
/// 静默跳过）；解锁后恢复真实条目；搜索索引跳过占位；buildAllDocs 将
/// 占位映射为单行 locked 条目。
///
/// 注：DNV 信封直接用主密钥加密（无 KDF），用例快速；仍放宽超时防
/// 全量套件高并发抖动。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nb_locked_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  File nbFile(String id) => File(
    '${tempDir.path}${Platform.pathSeparator}notebooks'
    '${Platform.pathSeparator}$id.json',
  );

  Notebook nbWithPage(String id, String title) => Notebook(
    id: id,
    title: title,
    pages: [
      NotebookPage(
        id: '${id}_pg1',
        title: '$title页1',
        document: DrawingDocument(id: '${id}_doc1', title: '$title页1'),
      ),
    ],
  );

  /// 以 DNV 主密钥信封写入分页画布文件（模拟保险库解锁期写入）。
  Future<void> writeDnvEncrypted(Notebook nb, Uint8List key) async {
    final data = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(nb.toJson()),
    );
    final sealed = await VaultFileCodec.encrypt(
      Uint8List.fromList(data),
      key,
      aadContext: 'nb:${nb.id}',
    );
    await nbFile(nb.id).parent.create(recursive: true);
    await nbFile(nb.id).writeAsBytes(sealed, flush: true);
  }

  NotebookStorage storageWith({Uint8List? key}) => NotebookStorage(
    directoryProvider: () async => tempDir,
    keyProvider: key == null ? () async => null : () async => key,
  );

  test('保险库锁定 → listAll 返回占位条目（不静默跳过；内容 fail-closed）', () async {
    final key = VaultKeyService.randomBytes(32);
    final nb = nbWithPage('nb_locked_1', '机密画布');
    await writeDnvEncrypted(nb, key);

    final list = await storageWith().listAll();
    expect(list, hasLength(1));
    final placeholder = list.single;
    expect(placeholder.id, 'nb_locked_1');
    expect(placeholder.title, '加密分页画布');
    expect(placeholder.encrypted, isTrue);
    expect(placeholder.pages, isEmpty);
    expect(placeholder.encryptedPayload, isNull);
    expect(placeholder.isLockedPlaceholder, isTrue);
  });

  test('保险库解锁 → listAll 返回真实条目（占位消失、页面展开）', () async {
    final key = VaultKeyService.randomBytes(32);
    final nb = nbWithPage('nb_locked_2', '真实画布');
    await writeDnvEncrypted(nb, key);

    final list = await storageWith(key: key).listAll();
    expect(list, hasLength(1));
    final real = list.single;
    expect(real.title, '真实画布');
    expect(real.pages, hasLength(1));
    expect(real.pages.single.title, '真实画布页1');
    expect(real.isLockedPlaceholder, isFalse);
  });

  test('混合：锁定 DNV 条目占位 + 明文壳受密条目正常列出（互不干扰）', () async {
    final key = VaultKeyService.randomBytes(32);
    await writeDnvEncrypted(nbWithPage('nb_locked_3', 'DNV机密'), key);

    // 明文壳受密分页画布（JSON 可读，pages 由文件密码信封保护）。
    final pwNb = Notebook(
      id: 'nb_locked_4',
      title: '文件密码画布',
      encrypted: true,
      encryptedPayload: '{"v":5,"c":"x"}',
    );
    await nbFile('nb_locked_4').parent.create(recursive: true);
    await nbFile('nb_locked_4').writeAsString(
      const JsonEncoder.withIndent('  ').convert(pwNb.toJson()),
      flush: true,
    );

    final list = await storageWith().listAll();
    expect(list, hasLength(2));
    final locked = list.singleWhere((n) => n.id == 'nb_locked_3');
    expect(locked.isLockedPlaceholder, isTrue);
    final pw = list.singleWhere((n) => n.id == 'nb_locked_4');
    expect(pw.title, '文件密码画布');
    expect(pw.encryptedPayload, isNotNull);
    expect(pw.isLockedPlaceholder, isFalse);
  });

  test('listSearchDocuments 跳过锁定占位（锁定内容不进搜索索引）', () async {
    final key = VaultKeyService.randomBytes(32);
    await writeDnvEncrypted(nbWithPage('nb_locked_5', '搜索不可见'), key);

    final docs = await storageWith().listSearchDocuments();
    expect(docs, isEmpty);
  });

  test('buildAllDocs：占位 → 单行 locked note 条目；真实条目按页展开', () async {
    final placeholder = Notebook(
      id: 'nb_locked_6',
      title: '加密分页画布',
      encrypted: true,
    );
    final real = nbWithPage('nb_locked_7', '真实画布');

    final result = buildAllDocs(
      docs: const [],
      notebooks: [placeholder, real],
      blockDocs: const [],
      now: DateTime.now(),
    );

    final lockedRows = result.docs
        .where((d) => d.id == 'nb_locked_6')
        .toList(growable: false);
    expect(lockedRows, hasLength(1));
    expect(lockedRows.single.kind, AllDocKind.note);
    expect(lockedRows.single.locked, isTrue);
    expect(lockedRows.single.notebookId, 'nb_locked_6');
    expect(lockedRows.single.title, '加密分页画布');

    final realRows = result.docs
        .where((d) => d.notebookId == 'nb_locked_7')
        .toList(growable: false);
    expect(realRows, hasLength(1));
    expect(realRows.single.locked, isFalse);
    expect(realRows.single.pageId, 'nb_locked_7_pg1');
  });
}
