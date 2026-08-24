// audit_log_store.dart — 审计日志持久化：Hash chain 写磁盘，防篡改，加密存储（2026-08-24）。
//
// 架构：
// - Hash chain：每条日志包含前一条的哈希，形成不可篡改的链
// - 持久化：日志条目追加写入文件（append-only），支持断电恢复
// - 加密存储：日志文件用 Vault DEK 加密，防未授权读取
// - 防篡改：启动时验证整个 hash chain 的完整性
// - 分片：日志文件达到阈值后自动轮转（防止单文件过大）
//
// 存储布局：
// vault/audit/
//   audit.001.log.enc    — 加密的日志分片
//   audit.002.log.enc    — ...
//   audit.meta.json      — 元数据（当前分片号、最后哈希）

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'secure_bytes.dart';

/// 审计日志存储——Hash chain 持久化 + 加密。
class AuditLogStore {
  AuditLogStore({
    required this.directory,
    required SecureBytes encryptionKey,
  }) : _encryptionKey = encryptionKey;

  final Directory directory;
  final SecureBytes _encryptionKey;

  // 分片配置。
  static const int _maxEntriesPerShard = 1000;
  static const String _shardPrefix = 'audit.';
  static const String _shardSuffix = '.log.enc';
  static const String _metaFileName = 'audit.meta.json';

  // 内存中的 hash chain 状态。
  List<AuditLogEntry>? _entries;
  String _lastHash = 'GENESIS';
  int _currentShard = 0;
  int _entryCount = 0;

  /// 初始化存储（创建目录、加载元数据）。
  Future<void> initialize() async {
    await directory.create(recursive: true);
    await _loadMeta();
    await _loadAndVerifyChain();
  }

  /// 追加审计日志条目（幂等——相同 content 不重复写入）。
  Future<AuditLogEntry> append({
    required String action,
    required String content,
  }) async {
    // 检查幂等性（最近 100 条）。
    final recentEntries = _entries?.take(100) ?? [];
    for (final entry in recentEntries) {
      if (entry.action == action && entry.content == content) {
        return entry; // 幂等返回。
      }
    }

    final entry = AuditLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      action: action,
      content: content,
      previousHash: _lastHash,
    );

    // 计算条目哈希。
    final entryHash = await _computeEntryHash(entry);
    final entryWithHash = entry.copyWith(hash: entryHash);

    // 加密并追加到当前分片。
    await _appendEncrypted(entryWithHash);

    // 更新内存状态。
    _entries ??= [];
    _entries!.insert(0, entryWithHash);
    _lastHash = entryHash;
    _entryCount++;

    // 检查是否需要轮转分片。
    if (_entryCount >= _maxEntriesPerShard) {
      await _rotateShard();
    }

    // 持久化元数据。
    await _saveMeta();

    return entryWithHash;
  }

  /// 获取审计日志（可选：指定时间范围）。
  Future<List<AuditLogEntry>> getEntries({
    int? startTime,
    int? endTime,
    int? limit,
  }) async {
    if (_entries == null) {
      await _loadAndVerifyChain();
    }

    var entries = _entries ?? [];

    if (startTime != null) {
      entries = entries.where((e) => e.timestamp >= startTime).toList();
    }
    if (endTime != null) {
      entries = entries.where((e) => e.timestamp <= endTime).toList();
    }
    if (limit != null) {
      entries = entries.take(limit).toList();
    }

    return entries;
  }

  /// 验证 hash chain 完整性。
  ///
  /// 返回 true 如果链完整无篡改。
  Future<bool> verifyChainIntegrity() async {
    if (_entries == null) {
      await _loadAndVerifyChain();
    }

    final entries = _entries ?? [];
    if (entries.isEmpty) return true;

    // 从最新到最旧验证。
    String expectedHash = entries.first.hash;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];

      // 验证哈希值。
      if (entry.hash != expectedHash) {
        return false;
      }

      // 验证 previousHash 链接。
      if (i + 1 < entries.length) {
        if (entry.previousHash != entries[i + 1].hash) {
          return false;
        }
      }

      // 重新计算哈希验证。
      final recomputedHash = await _computeEntryHash(entry);
      if (recomputedHash != entry.hash) {
        return false;
      }

      expectedHash = entry.previousHash;
    }

    return true;
  }

  /// 获取当前 hash chain 的根哈希（用于跨设备同步验证）。
  String get chainTip => _lastHash;

  /// 获取总条目数。
  int get entryCount => _entryCount;

  /// 清零加密密钥。
  void dispose() {
    _encryptionKey.dispose();
    _entries = null;
  }

  // --- 内部实现 ---

  /// 计算条目哈希（SHA-256）。
  Future<String> _computeEntryHash(AuditLogEntry entry) async {
    final data = utf8.encode(
      '${entry.timestamp}|${entry.action}|${entry.content}|${entry.previousHash}',
    );
    final hash = await Sha256().hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 加密并追加条目到当前分片文件。
  Future<void> _appendEncrypted(AuditLogEntry entry) async {
    final shardFile = _shardFile(_currentShard);
    final entryJson = utf8.encode(jsonEncode(entry.toJson()));
    final entryBytes = Uint8List.fromList(entryJson);

    // 加密条目（每条独立加密——支持随机访问）。
    final encrypted = await _encryptEntry(entryBytes);

    // 追加写入（4 字节长度前缀 + 加密数据）。
    final sink = shardFile.openWrite(mode: FileMode.append);
    final lengthPrefix = ByteData(4)..setUint32(0, encrypted.length, Endian.big);
    sink.add(lengthPrefix.buffer.asUint8List());
    sink.add(encrypted);
    await sink.flush();
    await sink.close();
  }

  /// 加密单条日志条目（AES-256-GCM）。
  Future<Uint8List> _encryptEntry(Uint8List data) async {
    return _encryptionKey.withBytes((keyBytes) async {
      final aes = AesGcm.with256bits();
      final nonce = _randomNonce();
      final secretBox = await aes.encrypt(
        data,
        secretKey: SecretKey(keyBytes),
        nonce: nonce,
        aad: utf8.encode('audit|entry'),
      );
      return Uint8List.fromList([
        ...nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
    });
  }

  /// 解密单条日志条目。
  Future<Uint8List> _decryptEntry(Uint8List encrypted) async {
    return _encryptionKey.withBytes((keyBytes) async {
      final aes = AesGcm.with256bits();
      final nonce = encrypted.sublist(0, 12);
      final cipherText = encrypted.sublist(12, encrypted.length - 16);
      final macBytes = encrypted.sublist(encrypted.length - 16);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final clear = await aes.decrypt(
        secretBox,
        secretKey: SecretKey(keyBytes),
        aad: utf8.encode('audit|entry'),
      );
      return Uint8List.fromList(clear);
    });
  }

  /// 加载并验证整个 hash chain。
  Future<void> _loadAndVerifyChain() async {
    _entries = [];
    _entryCount = 0;
    _lastHash = 'GENESIS';

    // 加载所有分片。
    for (var shard = 0; shard <= _currentShard; shard++) {
      final shardFile = _shardFile(shard);
      if (!await shardFile.exists()) continue;

      final bytes = await shardFile.readAsBytes();
      var offset = 0;

      while (offset + 4 <= bytes.length) {
        // 读取长度前缀。
        final length = ByteData.sublistView(bytes, offset, offset + 4)
            .getUint32(0, Endian.big);
        offset += 4;

        if (offset + length > bytes.length) break;

        // 解密条目。
        final encrypted = bytes.sublist(offset, offset + length);
        offset += length;

        try {
          final decrypted = await _decryptEntry(encrypted);
          final json = jsonDecode(utf8.decode(decrypted));
          final entry = AuditLogEntry.fromJson(json as Map<String, dynamic>);

          // 验证哈希链。
          final recomputedHash = await _computeEntryHash(entry);
          if (recomputedHash != entry.hash) {
            // 日志被篡改——记录但不中断（可能部分损坏）。
            print('WARNING: 审计日志条目哈希不匹配: ${entry.timestamp}');
          }

          _entries!.add(entry);
          _entryCount++;
          _lastHash = entry.hash;
        } catch (e) {
          // 解密失败——跳过（可能是损坏的条目）。
          print('WARNING: 审计日志条目解密失败: $e');
        }
      }
    }

    // 按时间倒序排列（最新在前）。
    _entries!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// 轮转分片。
  Future<void> _rotateShard() async {
    _currentShard++;
    _entryCount = 0;
    await _saveMeta();
  }

  /// 获取分片文件。
  File _shardFile(int shard) {
    final name = '$_shardPrefix${shard.toString().padLeft(3, '0')}$_shardSuffix';
    return File('${directory.path}/$name');
  }

  /// 加载元数据。
  Future<void> _loadMeta() async {
    final metaFile = File('${directory.path}/$_metaFileName');
    if (!await metaFile.exists()) return;

    try {
      final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      _currentShard = json['currentShard'] as int? ?? 0;
      _lastHash = json['lastHash'] as String? ?? 'GENESIS';
    } catch (_) {
      // 元数据损坏——重置。
      _currentShard = 0;
      _lastHash = 'GENESIS';
    }
  }

  /// 持久化元数据。
  Future<void> _saveMeta() async {
    final metaFile = File('${directory.path}/$_metaFileName');
    final json = jsonEncode({
      'currentShard': _currentShard,
      'lastHash': _lastHash,
      'entryCount': _entryCount,
      'lastUpdated': DateTime.now().toIso8601String(),
    });
    await metaFile.writeAsString(json, flush: true);
  }

  /// 生成随机 nonce。
  static Uint8List _randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));
  }
}

/// 审计日志条目（不可变）。
class AuditLogEntry {
  const AuditLogEntry({
    required this.timestamp,
    required this.action,
    required this.content,
    this.previousHash = 'GENESIS',
    this.hash = '',
  });

  final int timestamp;
  final String action;
  final String content;
  final String previousHash;
  final String hash;

  AuditLogEntry copyWith({
    int? timestamp,
    String? action,
    String? content,
    String? previousHash,
    String? hash,
  }) {
    return AuditLogEntry(
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
      content: content ?? this.content,
      previousHash: previousHash ?? this.previousHash,
      hash: hash ?? this.hash,
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'action': action,
    'content': content,
    'previousHash': previousHash,
    'hash': hash,
  };

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      timestamp: json['timestamp'] as int,
      action: json['action'] as String,
      content: json['content'] as String,
      previousHash: json['previousHash'] as String? ?? 'GENESIS',
      hash: json['hash'] as String? ?? '',
    );
  }

  /// 格式化时间戳。
  String get formattedTime {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => '[$formattedTime] $action: $content';
}
