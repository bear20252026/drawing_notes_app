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

  /// 编码复用缓存（性能优化）：同一轮同步里 [listDocuments]（算 size）与
  /// [readDocument]（取上传内容）会对同一文档各做一次 jsonEncode + UTF-8。
  /// 以 id + updatedAt 校验复用同一份字节（编码一次、取 length 复用）；
  /// LRU 容量 [_encodedCacheCapacity] 条防长期驻留。
  final Map<String, _EncodedDocBytes> _encodedCache = {};

  /// 缓存容量：块文档 JSON 通常为 KB 级，8 条上限的驻留开销可忽略。
  static const int _encodedCacheCapacity = 8;

  Uint8List _encodedBytesOf(NoteBlockDoc doc) {
    final updatedMs = doc.updatedAt.millisecondsSinceEpoch;
    final cached = _encodedCache[doc.id];
    if (cached != null && cached.updatedMs == updatedMs) {
      // LRU 提升：删后重插保持插入序为访问序。
      _encodedCache
        ..remove(doc.id)
        ..[doc.id] = cached;
      return cached.bytes;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc.toJson())));
    _encodedCache
      ..remove(doc.id)
      ..[doc.id] = _EncodedDocBytes(updatedMs, bytes);
    while (_encodedCache.length > _encodedCacheCapacity) {
      _encodedCache.remove(_encodedCache.keys.first);
    }
    return bytes;
  }

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
          size: _encodedBytesOf(doc).length,
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
    // 同一轮同步内 listDocuments 已编码过且未再变化（updatedAt 校验）时
    // 直接复用那份字节，避免重复编码。
    return _encodedBytesOf(doc);
  }

  @override
  Future<void> writeDocument(String id, Uint8List bytes) async {
    // 远端字节损坏/不可解析 → 抛出，由同步器中止并避免把损坏内容算作已同步。
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final doc = NoteBlockDoc.fromJson(map);
    await _store.saveDocument(doc.id == id ? doc : doc.copyWith(id: id));
    // 内容刚被远端覆盖：丢弃对应编码缓存，后续一律按新内容重编。
    _encodedCache.remove(id);
  }

  @override
  Future<void> deleteDocument(String id) async {
    _encodedCache.remove(id);
    await _store.deleteDocument(id);
  }
}

/// 编码复用缓存条目：记录编码时文档的 updatedAt（毫秒），与当前不一致
/// 即视为已变化、重新编码。
class _EncodedDocBytes {
  _EncodedDocBytes(this.updatedMs, this.bytes);

  final int updatedMs;
  final Uint8List bytes;
}
