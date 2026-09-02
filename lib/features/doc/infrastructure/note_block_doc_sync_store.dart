// 由 Claude 团队生成 | Drawing Notes App
// NoteBlockDoc ⇄ 同步字节适配器：把核心的 SyncDocumentStore 接到本地
// NoteBlockDocStore（本地优先的「本地半边」）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';

/// 把 [NoteBlockDocStore] 适配成同步器所需的字节级 [SyncDocumentStore]。
class NoteBlockDocSyncStore implements SyncDocumentStore {
  NoteBlockDocSyncStore(this._store);

  final NoteBlockDocStore _store;

  @override
  Future<List<SyncDocMeta>> listDocuments() async {
    final ids = await _store.listIds();
    final metas = <SyncDocMeta>[];
    for (final id in ids) {
      // N2：受密未解锁的笔记跳过（fail-closed——同步不解锁受密内容）。
      final NoteBlockDoc? doc;
      try {
        doc = await _store.loadDocument(id);
      } on BlockDocLockedException {
        continue;
      }
      if (doc == null) continue;
      metas.add(
        SyncDocMeta(
          id: id,
          updatedAt: doc.updatedAt.millisecondsSinceEpoch,
          size: utf8.encode(jsonEncode(doc.toJson())).length,
        ),
      );
    }
    return metas;
  }

  @override
  Future<Uint8List?> readDocument(String id) async {
    // N2：受密未解锁 → null（同步器按缺失处理，不解锁受密内容）。
    final NoteBlockDoc? doc;
    try {
      doc = await _store.loadDocument(id);
    } on BlockDocLockedException {
      return null;
    }
    if (doc == null) return null;
    return Uint8List.fromList(utf8.encode(jsonEncode(doc.toJson())));
  }

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    // 远端字节损坏/不可解析 → 抛出，由同步器中止并避免把损坏内容算作已同步。
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final doc = NoteBlockDoc.fromJson(map);
    await _store.saveDocument(doc.id == id ? doc : doc.copyWith(id: id));
  }

  @override
  Future<void> deleteDocument(String id) async {
    await _store.deleteDocument(id);
  }
}
