// A2（第三轮协同方案 §9）：操作日志的磁盘侧车。
//
// 与 `OperationLog`（内存有界影子流）的关系：内存侧记的是「这个会话发生过哪些
// 语义操作」，本文件负责把它**成对落到数据根内**，让重启后仍可回放、并给将来的
// 增量同步一个可读的来源。落点选在数据根内的 `oplog/`，理由只有一条但很强：
// 备份包打包的就是数据根 ⇒ 恢复旧备份时日志**跟着一起回退**。落在根外（像
// `sync_state.json` 那样）就会造出「恢复出来的旧库 + 新日志」这种第二套真相,
// 而那正是 DN-204 两条提交刚堵掉的病。
//
// 三条不变量（都在 test/core/operation/operation_log_store_test.dart 里钉着）：
//  ① **文档是权威**：读回时丢掉 `baseRev` 超前于盘上文档 revision 的记录。
//     「文档写了、日志没写」只是少几条可再生的记录；「日志写了、文档没写」会让
//     回放造出不存在的内容 —— 后者不可接受，所以一律以前者为准。
//  ② **幂等**：`append` 按 `seq` 去重，同一批记录投两次结果不变（崩溃后重放、
//     队列重复消费都不会把日志拉长）。
//  ③ **加密降级不留第二条通道**：建过库却拿不到密钥（保险库锁定）时**什么都不写**，
//     绝不落一份明文侧车；没建库时明文落盘与文档写路径同口径。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:drawing_notes_app/core/operation/document_operation.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

/// 一条已落盘的操作：信封（`seq` + `baseRev`）+ 原样的操作 JSON。
///
/// 信封字段**只活在日志里**，不进工程文件 ⇒ 加它不改文档格式、不 bump 版本号。
class OperationLogRecord {
  const OperationLogRecord({
    required this.seq,
    required this.baseRev,
    required this.operation,
  });

  /// 每文档单调递增的序号，同时是幂等去重的键。
  final int seq;

  /// 该操作所基于的文档 revision（本仓口径：文档 `updatedAt` 毫秒 + 内容摘要
  /// 折算的稳定整数）。读回时以盘上文档 revision 为界。
  final int baseRev;

  final DocumentOperation operation;

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'baseRev': baseRev,
    'op': operation.toJson(),
  };

  factory OperationLogRecord.fromJson(Map<String, dynamic> json) {
    final seq = json['seq'];
    final baseRev = json['baseRev'];
    final op = json['op'];
    if (seq is! int || baseRev is! int || op is! Map) {
      // 记录面不容「猜它大概是什么」：一条看不懂就整份日志不可信，
      // 与 `OperationLog.fromJsonl` 同一口径（回放路径不做静默丢弃）。
      throw const FormatException('操作日志记录格式损坏');
    }
    return OperationLogRecord(
      seq: seq,
      baseRev: baseRev,
      operation: DocumentOperation.fromJson(
        Map<String, dynamic>.from(op),
      ),
    );
  }

  // 刻意不覆写 ==/hashCode：幂等去重用的是 `seq`（见 OperationLogStore.append），
  // 按 payload 判等要么退化成「按类型判等」（会把两条不同操作混为一谈），
  // 要么得深比较——两者都不该出现在这条记录面上。
}

/// 单个文档侧车的上限（保守值，且必须有——内存侧已有 2000 条纪律，磁盘侧不能没有）。
class OperationLogLimits {
  const OperationLogLimits({this.maxRecords = 256, this.maxBytes = 64 * 1024});

  final int maxRecords;
  final int maxBytes;

  /// 全仓统一的一份默认值（不在调用点各写一份数字）。
  static const OperationLogLimits standard = OperationLogLimits();
}

/// 操作日志侧车存储。
class OperationLogStore {
  OperationLogStore({
    required this.directoryProvider,
    this.keyProvider,
    this.limits = OperationLogLimits.standard,
  });

  /// 数据根目录（侧车落在其下的 `oplog/`，因此在备份包内）。
  final Future<Directory> Function() directoryProvider;

  /// 主密钥提供者：null ⇒ 未启用加密（明文落盘，与文档写路径同口径）；
  /// 已接密钥提供者但取不到密钥 ⇒ 视为「已建库但锁定」，本次什么都不写。
  final Future<Uint8List?> Function()? keyProvider;

  final OperationLogLimits limits;

  /// 测试专用时序屏障：在「临时文件写完」与「改名替换正式文件」之间 await。
  /// 生产恒 null。用意与 `StorageWritePipeline.rewriteBarrierForTest` 相同——
  /// 崩溃窗口不能靠调度碰运气，要能确定地停在「tmp 已写、尚未改名」那一格。
  @visibleForTesting
  Future<void> Function(String docId)? writeBarrierForTest;

  /// id 消毒沿用文档存储的白名单：侧文件名由外部可控的 id 拼出来，
  /// 不给 `../` 之类留口。非法 id 直接抛，不静默落到别的文件上。
  static void _requireValidDocId(String docId) {
    if (!StorageDirectories.validIdPattern.hasMatch(docId)) {
      throw ArgumentError.value(docId, 'docId', '文档 ID 不合法');
    }
  }

  Future<File> _fileFor(String docId) async {
    _requireValidDocId(docId);
    final root = await directoryProvider();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}oplog',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$docId.jsonl');
  }

  /// 读回侧车。[docRevision] 给定时，丢掉 `baseRev` 超前于它的那段尾巴
  /// （不变量①）。文件不存在 ⇒ 空列表（新文档/未落过盘都是这个）。
  Future<List<OperationLogRecord>> load(
    String docId, {
    int? docRevision,
  }) async {
    final file = await _fileFor(docId);
    if (!file.existsSync()) return const [];
    final raw = await file.readAsBytes();
    final clear = await _open(raw, docId);
    final records = <OperationLogRecord>[];
    for (final line in const LineSplitter().convert(utf8.decode(clear))) {
      if (line.trim().isEmpty) continue;
      records.add(
        OperationLogRecord.fromJson(
          Map<String, dynamic>.from(jsonDecode(line) as Map),
        ),
      );
    }
    if (docRevision == null) return records;
    // 文档 revision 是权威：比它新的记录说明「日志写了、文档没写」——截掉。
    return [
      for (final r in records)
        if (r.baseRev <= docRevision) r,
    ];
  }

  /// 追加并原子重写整份侧车。返回**实际新增**的记录数（幂等去重后）。
  ///
  /// 为什么是「重写整份」而不是 `appendAsBytes`：一是这样崩溃后不需要处理半行；
  /// 二是上限截断（丢最旧）本来就是全量重写；三是它让写路径只有一种契约
  /// （tmp + 改名），不给日志留第二条降级通道（批次 C 的同一主题）。
  Future<int> append(String docId, List<OperationLogRecord> records) async {
    if (records.isEmpty) return 0;
    // 参数校验必须在下面的读兜底**之前**：否则非法 id 抛出的 ArgumentError
    // 会被「读不懂现有侧车就放弃写入」的 catch 一起吞成静默 no-op——
    // 那是调用方的编程错误，必须响，不该伪装成「这次没写成」。
    _requireValidDocId(docId);
    final List<OperationLogRecord> existing;
    try {
      existing = await load(docId);
    } on Object {
      // 读不懂现有侧车（锁定 / 格式损坏 / 来路不明）⇒ **放弃本次写入**。
      // 覆盖一份看不懂的日志，等于用「我以为的开头」把别人的记录抹掉；
      // 而侧车是可再生的记录面，少一次追加不伤文档本体。
      return 0;
    }
    var lastSeq = existing.isEmpty ? 0 : existing.last.seq;
    final fresh = <OperationLogRecord>[];
    for (final r in records) {
      if (r.seq <= lastSeq) continue; // 不变量②：同 seq 重放不重复入册
      fresh.add(r);
      lastSeq = r.seq;
    }
    if (fresh.isEmpty) return 0;
    var merged = [...existing, ...fresh];
    // 上限截断：丢掉「已经体现在盘上快照里」的最旧记录（可再生，且文档才是权威）。
    if (merged.length > limits.maxRecords) {
      merged = merged.sublist(merged.length - limits.maxRecords);
    }
    var file = _encodeLines(merged);
    if (file.length > limits.maxBytes) {
      // 字节也顶到上限时按行二分裁到装得下为止——比「直接放弃写入」好：
      // 完全没写过的日志会让回放从零开始。
      var keep = merged.length;
      while (keep > 1 && file.length > limits.maxBytes) {
        keep = (keep / 2).ceil();
        file = _encodeLines(merged.sublist(merged.length - keep));
      }
      merged = merged.sublist(merged.length - keep);
    }
    final written = await _writeAtomic(docId, file);
    // 返回契约是「实际新增的记录数」，不是「打算新增」：锁定态下什么都没落，
    // 必须返回 0，否则调用方会把一份不存在的日志当成已持久化。
    return written ? fresh.length : 0;
  }

  Uint8List _encodeLines(List<OperationLogRecord> records) =>
      Uint8List.fromList(
        utf8.encode(
          '${[for (final r in records) jsonEncode(r.toJson())].join('\n')}\n',
        ),
      );

  /// 密封（DNV 信封，AAD 绑 `oplog:<docId>` ⇒ 侧车不能改名换身份）。
  /// 返回 null = 本次不该落盘（建过库但拿不到密钥）。
  Future<Uint8List?> _seal(String docId, Uint8List clear) async {
    final provider = keyProvider;
    if (provider == null) return clear; // 未启用加密：明文兼容是产品设计
    final key = await provider();
    if (key == null) return null; // 锁定：宁可不写，也不落一份明文侧车
    return VaultFileCodec.encrypt(clear, key, aadContext: 'oplog:$docId');
  }

  Future<Uint8List> _open(Uint8List raw, String docId) async {
    if (!VaultFileCodec.isEncrypted(raw)) {
      final provider = keyProvider;
      final key = provider == null ? null : await provider();
      if (key == null) return raw; // 未加密落盘（无 keyProvider 或未建库）
      // 已建库却读到明文：说明这份侧车来路不明（外部写入/降级遗留）——
      // 按 fail-closed 拒绝，不当成可信记录回放。
      throw const VaultFileLockException();
    }
    final key = await keyProvider?.call();
    if (key == null) throw const VaultFileLockException();
    return VaultFileCodec.decrypt(raw, key, aadContext: 'oplog:$docId');
  }

  /// 落盘。返回 false = 本次确实没写（保险库锁定）；改名失败等真错误直接抛。
  Future<bool> _writeAtomic(String docId, Uint8List clear) async {
    final file = await _fileFor(docId);
    final sealed = await _seal(docId, clear);
    if (sealed == null) return false; // 锁定：不写、不抛（保存链不该被侧车挡住）
    final tmp = File('${file.path}.${LocalIdGenerator.next('oplog')}.tmp');
    try {
      await tmp.writeAsBytes(sealed, flush: true);
      await writeBarrierForTest?.call(docId);
      // 改名失败时**只清临时文件、绝不删正式文件**：侧车是可再生的记录面，
      // 留着上一份总比两边都没有好（「先删再 rename」在 Windows 共享冲突下
      // 正是 DN-108/205 那条契约要防的三副本同时消失）。
      await tmp.rename(file.path);
      return true;
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始异常。
      }
      rethrow;
    }
  }
}
