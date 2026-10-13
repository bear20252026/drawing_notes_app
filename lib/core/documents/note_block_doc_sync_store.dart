// 由 Claude 团队生成 | Drawing Notes App
// NoteBlockDoc ⇄ 同步字节适配器：把核心的 SyncDocumentStore 接到本地
// NoteBlockDocStore（本地优先的「本地半边」）。

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';

/// 把 [NoteBlockDocStore] 适配成同步器所需的字节级 [SyncDocumentStore]。
class NoteBlockDocSyncStore implements SyncDocumentStore {
  NoteBlockDocSyncStore(this._store);

  final NoteBlockDocStore _store;

  /// 编码复用缓存（性能优化）：同一轮同步里 [listDocuments]（算 size）与
  /// [readDocument]（取上传内容）会对同一文档各做一次 jsonEncode + UTF-8。
  /// 以 id + updatedAt 校验复用同一份字节（编码一次、取 length 复用）；
  /// LRU 容量 [_encodedCacheCapacity] 条防长期驻留。
  /// DN-206 起**每轮 [listDocuments] 开头整体作废**：只靠 updatedAt 校验挡不住
  /// 「同毫秒等长改写」，而那正是摘要要抓的对象——跨轮复用没有安全收益。
  final Map<String, _EncodedDocBytes> _encodedCache = {};

  /// 缓存容量：块文档 JSON 通常为 KB 级，8 条上限的驻留开销可忽略。
  static const int _encodedCacheCapacity = 8;

  /// 同一份编码的摘要（DN-206）：size 与 digest 必须同源于**这一次**编码，
  /// 「字节数相同而摘要不同」才是可信的内容差异证据。
  _EncodedDocBytes _encodedOf(NoteBlockDoc doc) {
    final updatedMs = doc.updatedAt.millisecondsSinceEpoch;
    final cached = _encodedCache[doc.id];
    if (cached != null && cached.updatedMs == updatedMs) {
      // LRU 提升：删后重插保持插入序为访问序。
      _encodedCache
        ..remove(doc.id)
        ..[doc.id] = cached;
      return cached;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc.toJson())));
    final entry = _EncodedDocBytes(updatedMs, bytes, _digestOf(bytes));
    _encodedCache
      ..remove(doc.id)
      ..[doc.id] = entry;
    while (_encodedCache.length > _encodedCacheCapacity) {
      _encodedCache.remove(_encodedCache.keys.first);
    }
    return entry;
  }

  /// 上传内容用的字节（与 [listDocuments] 报出的 size/digest 同源同一次编码）。
  Uint8List _encodedBytesOf(NoteBlockDoc doc) => _encodedOf(doc).bytes;

  /// 内容摘要 = 编码字节的 SHA-256 前 16 位十六进制（64 bit）。
  ///
  /// 截断是为了清单体积（1000 篇只多 16KB 而不是 64KB）；这里的用途是
  /// 「检测同一毫秒同字节数的不同内容」，不是抗第二原像，64 bit 足够。
  static String _digestOf(Uint8List bytes) =>
      crypto.sha256.convert(bytes).toString().substring(0, 16);

  /// DN-107（P0 数据安全）：如实区分「可读取」与「存在但锁定」。
  ///
  /// 此前受密未解锁的笔记被直接 `continue` 掉，同步侧看到「基线有、本次
  /// 清单无」就推导成用户删除，进而真的 `DELETE` 云端副本——关掉应用重开、
  /// 笔记尚未解锁就同步即可触发。**读取不到 ≠ 用户删除。**
  @override
  Future<SyncLocalInventory> listDocuments() async {
    // DN-206：**每轮开始时作废缓存**。这张缓存原本只用 id + updatedAt 校验，
    // 而本条要抓的正是「同一毫秒的等长改写」——updatedAt 没变、内容变了，
    // 于是旧缓存会把上一轮的字节与摘要原样报出去（测试第一次跑就把它逼了出来：
    // 等长标题替换后 size 与 digest 都和旧值一致）。缓存的意义只是省掉同一轮内
    // listDocuments→readDocument 的重复编码，跨轮复用从来没有安全收益。
    _encodedCache.clear();
    final ids = await _store.listIds();
    final metas = <SyncDocMeta>[];
    final unreadable = <String>{};
    for (final id in ids) {
      // N2：受密未解锁的笔记不解锁内容（fail-closed），但要如实上报为
      // 「存在但不可读取」，交给同步侧保留其云端记录。
      final NoteBlockDoc? doc;
      try {
        doc = await _store.loadDocument(id);
      } on BlockDocLockedException {
        unreadable.add(id);
        continue;
      }
      if (doc == null) continue;
      final encoded = _encodedOf(doc);
      metas.add(
        SyncDocMeta(
          id: id,
          updatedAt: doc.updatedAt.millisecondsSinceEpoch,
          size: encoded.bytes.length,
          // DN-206：与 size 同源于同一次编码的内容摘要。
          digest: encoded.digest,
        ),
      );
    }
    return SyncLocalInventory(readable: metas, unreadable: unreadable);
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
  _EncodedDocBytes(this.updatedMs, this.bytes, this.digest);

  final int updatedMs;
  final Uint8List bytes;

  /// DN-206：bytes 的 SHA-256 前 16 位十六进制（见 `_digestOf` 的取舍说明）。
  final String digest;
}
