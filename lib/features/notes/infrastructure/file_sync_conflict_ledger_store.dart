// 文件版 [SyncConflictLedgerStore]：与同步基线同目录（数据根**之外**）。
//
// 为什么和基线放一起而不是数据根内：与 `sync_push_waivers.dart` 头部同一条理由
// ——恢复一个旧数据根之后，台账里那些「当时按什么处理了」的事实与改判方向描述
// 的是上一个数据根里的文档，继承过来会让一次恢复悄悄沿用旧的长期裁决。
//
// 读用 `sidecar_read_guard.dart` 的三态（与 `favorite_store.dart` 同一条判据，
// 不抄第二份）：台账是**读-改-写**（record/setOverride 都要先读全表），一次半写
// 之后若把「读不出来」答成「空台账」，下一次记录就会把用户的全部冲突历史整体
// 覆盖掉——这正是审计 2026-10-16 点名的本仓头号复发形态。所以：分类、落审计、
// 覆盖前先抢救原件。
//
// 写用随机后缀 tmp + flush + rename 的原子纪律（A7 修复那条），失败只清理自己
// 建的临时文件，绝不把异常吞掉。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drawing_notes_app/core/storage/sidecar_read_guard.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict_ledger.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart'
    show defaultSyncBaselineDirectory;

class FileSyncConflictLedgerStore implements SyncConflictLedgerStore {
  FileSyncConflictLedgerStore({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  /// 与 `FileSyncBaselineStore.baselineFileName` 同一条纪律：文件名只有这一处
  /// 定义，测试与将来的诊断都从这里取。
  static const String fileName = 'sync_conflict_ledger.json';

  /// 侧车清单键（`readSidecarList` 用它取顶层那份 List）。
  static const String _listKey = 'entries';

  File? _file;

  bool _unreadableNoted = false;
  bool _corruptPreserved = false;

  /// 已被抢救出来的那份原件的保留件文件名（`.corrupt-*`；没抢救过为 null）。
  /// 与 `FavoriteStore.salvagedOriginalName` 同一形状：「台账看起来全空了」
  /// 必须被说成「旧内容保住了一份原件」。
  String? get salvagedOriginalName => _salvagedOriginalName;
  String? _salvagedOriginalName;

  /// 写链：record/setOverride 的读-改-写非原子，快速连点会丢更新。
  Future<void> _tail = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() fn) {
    final task = _tail.then((_) => fn());
    _tail = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<File> _fileRef() async {
    if (_file != null) return _file!;
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await defaultSyncBaselineDirectory();
    _file = File('${base.path}${Platform.pathSeparator}$fileName');
    return _file!;
  }

  @override
  Future<List<ConflictLedgerEntry>> load() async {
    final file = await resolveSidecarFile(_fileRef);
    if (file == null) return <ConflictLedgerEntry>[]; // 目录解析失败：不抛给 UI
    final read = readSidecarList(file, _listKey);
    if (read.state != SidecarRead.readable) {
      if (read.state == SidecarRead.unreadable) {
        noteUnreadableSidecar(
          'sync_conflict_ledger',
          alreadyNoted: _unreadableNoted,
        );
        _unreadableNoted = true;
      }
      return <ConflictLedgerEntry>[];
    }
    final entries = <ConflictLedgerEntry>[];
    for (final item in read.items) {
      final parsed = _decodeEntry(item);
      // 条目级 fail-closed：一条坏的不影响其余（坏的那条丢掉，后果是那条历史
      // 不可见，而不是整份台账被当成空的）。
      if (parsed != null) entries.add(parsed);
    }
    entries.sort((a, b) => b.lastDetectedAtMs.compareTo(a.lastDetectedAtMs));
    return List.unmodifiable(entries);
  }

  @override
  Future<void> record(List<SyncConflict> conflicts, {int? nowMs}) =>
      _enqueue(() async {
        if (conflicts.isEmpty) return;
        final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
        final existing = {for (final e in await load()) e.docId: e};
        for (final c in conflicts) {
          final prior = existing[c.docId];
          if (prior == null) {
            existing[c.docId] = ConflictLedgerEntry(
              docId: c.docId,
              firstDetectedAtMs: now,
              lastDetectedAtMs: now,
              count: 1,
              lastConflict: c,
            );
            continue;
          }
          // 只更新「最近一次」的三件事；改判原样保留（见契约）。
          existing[c.docId] = prior.copyWith(
            lastDetectedAtMs: now,
            count: prior.count + 1,
            lastConflict: c,
          );
        }
        await _write(existing.values);
      });

  @override
  Future<void> setOverride(
    String docId,
    ConflictResolution? resolution, {
    int? nowMs,
  }) => _enqueue(() async {
    final existing = {for (final e in await load()) e.docId: e};
    final prior = existing[docId];
    if (prior == null) return; // 见契约：不凭空造条目
    if (resolution == null) {
      existing[docId] = prior.copyWith(clearOverride: true);
    } else {
      existing[docId] = prior.copyWith(
        resolutionOverride: resolution,
        overriddenAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      );
    }
    await _write(existing.values);
  });

  /// 整份覆盖写（集合很小，不做增量）。随机 tmp + flush + rename。
  Future<void> _write(Iterable<ConflictLedgerEntry> entries) async {
    final file = await _fileRef();
    // 覆盖前抢救：盘上此刻仍读不出来时先复制一份 `.corrupt-*`。
    final preserved = await preserveUnreadableSidecar(
      file,
      listKey: _listKey,
      auditScope: 'sync_conflict_ledger',
      alreadyPreserved: _corruptPreserved,
    );
    if (preserved != null) {
      _corruptPreserved = true;
      _salvagedOriginalName ??= File(preserved).uri.pathSegments.last;
    }
    // 稳定序：按 docId 排，同一份台账两次写出逐字节一致（便于比对与测试）。
    final sorted = [...entries]..sort((a, b) => a.docId.compareTo(b.docId));
    final r = Random.secure();
    final suffix = hexEncode(List<int>.generate(8, (_) => r.nextInt(256)));
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    try {
      await tmp.writeAsString(
        jsonEncode({
          _listKey: [for (final e in sorted) _encodeEntry(e)],
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        /* 幂等清理：写入失败后删 tmp 尽力而为，失败不覆盖将 rethrow 的原始错误 */
      }
      rethrow;
    }
  }

  // ---- 编解码 ----

  /// 条目编码：把 [SyncConflict] 的字段平铺进同一层，避免嵌套对象在 JSON 里
  /// 多一层缩进（台账是人也要能读的文件）。
  static Map<String, Object?> _encodeEntry(ConflictLedgerEntry e) {
    final c = e.lastConflict;
    return {
      'docId': e.docId,
      'firstDetectedAtMs': e.firstDetectedAtMs,
      'lastDetectedAtMs': e.lastDetectedAtMs,
      'count': e.count,
      if (e.resolutionOverride != null)
        'resolutionOverride': e.resolutionOverride!.name,
      if (e.overriddenAtMs != null) 'overriddenAtMs': e.overriddenAtMs,
      'localUpdatedAt': c.localUpdatedAt,
      'localSize': c.localSize,
      'remoteUpdatedAt': c.remoteUpdatedAt,
      'remoteSize': c.remoteSize,
      'remoteTimestampUntrusted': c.remoteTimestampUntrusted,
      'localUnchangedSinceBaseline': c.localUnchangedSinceBaseline,
      'fingerprintTie': c.fingerprintTie,
      'contentUnverifiable': c.contentUnverifiable,
      if (c.resolvedResolution != null)
        'resolvedResolution': c.resolvedResolution!.name,
      if (c.localDigest != null) 'localDigest': c.localDigest,
      if (c.remoteDigest != null) 'remoteDigest': c.remoteDigest,
    };
  }

  /// 条目解码；任何一处形状不对都返回 null（调用方丢弃该条）。
  ///
  /// 数字字段一律走 `_asInt`：JSON 里的 int/double 都收，但**不接受 String**
  /// ——那是文件被别的手工改过的信号，猜着解析比丢掉更危险。
  static ConflictLedgerEntry? _decodeEntry(Object? item) {
    if (item is! Map) return null;
    final docId = item['docId'];
    if (docId is! String || docId.isEmpty) return null;
    final first = _asInt(item['firstDetectedAtMs']);
    final last = _asInt(item['lastDetectedAtMs']);
    final count = _asInt(item['count']);
    if (first == null || last == null || count == null || count < 1) {
      return null;
    }
    final conflict = _decodeConflict(item);
    if (conflict == null || conflict.docId != docId) {
      return null;
    }
    final resolutionOverride = _decodeResolution(item['resolutionOverride']);
    final overriddenAt = _asInt(item['overriddenAtMs']);
    if (item.containsKey('resolutionOverride') &&
        resolutionOverride == null) {
      return null;
    }
    if (item.containsKey('overriddenAtMs') && overriddenAt == null) {
      return null;
    }
    return ConflictLedgerEntry(
      docId: docId,
      firstDetectedAtMs: first,
      lastDetectedAtMs: last,
      count: count,
      lastConflict: conflict,
      resolutionOverride: resolutionOverride,
      overriddenAtMs: overriddenAt,
    );
  }

  /// 从**平铺**的条目 map 里取出 [SyncConflict]（字段名与 [_encodeEntry] 对应）。
  static SyncConflict? _decodeConflict(Map map) {
    final docId = map['docId'];
    final localUpdatedAt = _asInt(map['localUpdatedAt']);
    final localSize = _asInt(map['localSize']);
    final remoteUpdatedAt = _asInt(map['remoteUpdatedAt']);
    final remoteSize = _asInt(map['remoteSize']);
    if (docId is! String ||
        localUpdatedAt == null ||
        localSize == null ||
        remoteUpdatedAt == null ||
        remoteSize == null) {
      return null;
    }
    final localDigest = map['localDigest'];
    final remoteDigest = map['remoteDigest'];
    if (map.containsKey('localDigest') && localDigest is! String) return null;
    if (map.containsKey('remoteDigest') && remoteDigest is! String) return null;
    return SyncConflict(
      docId: docId,
      localUpdatedAt: localUpdatedAt,
      localSize: localSize,
      remoteUpdatedAt: remoteUpdatedAt,
      remoteSize: remoteSize,
      remoteTimestampUntrusted: map['remoteTimestampUntrusted'] == true,
      localUnchangedSinceBaseline: map['localUnchangedSinceBaseline'] == true,
      fingerprintTie: map['fingerprintTie'] == true,
      contentUnverifiable: map['contentUnverifiable'] == true,
      resolvedResolution: _decodeResolution(map['resolvedResolution']),
      localDigest: localDigest as String?,
      remoteDigest: remoteDigest as String?,
    );
  }

  static ConflictResolution? _decodeResolution(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) return null;
    for (final r in ConflictResolution.values) {
      if (r.name == raw) return r;
    }
    return null; // 未知枚举名 ⇒ 当作没写（不猜）
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is double && raw == raw.roundToDouble()) return raw.toInt();
    return null;
  }
}
