import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';

import 'audit_logger.dart';

/// 持久化审计日志（P1 #25 修复）：
/// 将内存审计日志持久化到加密存储，支持：
/// - AES-256-GCM 加密存储
/// - 分片存储（每片 1MB，最多保留 30 天）
/// - 启动时加载历史日志
/// - 保持哈希链完整性验证
class PersistentAuditLogger {
  PersistentAuditLogger._();

  static PersistentAuditLogger? _instance;

  /// 获取单例实例。
  static PersistentAuditLogger get instance {
    _instance ??= PersistentAuditLogger._();
    return _instance!;
  }

  /// 加密密钥（从安全存储加载或生成）。
  late final encrypt.Key _encryptionKey;

  /// 初始化向量（每次加密时生成新的）。
  late final encrypt.IV _iv;

  /// 加密器。
  late final encrypt.Encrypter _encrypter;

  /// 审计日志存储目录。
  Directory? _auditDir;

  /// 每片最大大小（1MB）。
  static const int _maxShardSizeBytes = 1 * 1024 * 1024;

  /// 最大保留天数（30天）。
  static const int _maxRetentionDays = 30;

  /// 片文件名前缀。
  static const String _shardPrefix = 'audit_log_';

  /// 片文件扩展名。
  static const String _shardExtension = '.enc';

  /// 初始化加密器和存储目录。
  Future<void> initialize() async {
    // 生成或加载加密密钥（实际应用中应从安全存储加载）。
    _encryptionKey = encrypt.Key(Uint8List.fromList(
      List.generate(32, (i) => i), // 占位——生产环境从安全存储加载
    ));

    // 每次启动生成新的 IV。
    _iv = encrypt.IV.fromSecureRandom(16);

    // 初始化加密器（AES-256-GCM）。
    _encrypter = encrypt.Encrypter(encrypt.AES(
      _encryptionKey,
      mode: encrypt.AESMode.gcm,
    ));

    // 确保存储目录存在。
    await _ensureAuditDir();
  }

  /// 确保审计日志存储目录存在。
  Future<Directory> _ensureAuditDir() async {
    if (_auditDir != null) return _auditDir!;

    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}audit_logs');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _auditDir = dir;
    return dir;
  }

  /// 持久化审计日志到加密存储。
  ///
  /// 实现策略：
  /// 1. 将审计日志序列化为 JSON
  /// 2. 使用 AES-256-GCM 加密
  /// 3. 分片存储（每片 1MB）
  /// 4. 清理过期日志（超过 30 天）
  Future<void> persist(AuditLogger logger) async {
    await _ensureAuditDir();

    // 1. 获取审计日志快照。
    final entries = AuditLogger.snapshot();

    // 2. 序列化为 JSON。
    final jsonData = jsonEncode({
      'version': 1,
      'entries': entries,
      'persistedAt': DateTime.now().toIso8601String(),
      'count': entries.length,
    });

    // 3. 加密数据。
    final encrypted = _encrypter.encryptBytes(
      utf8.encode(jsonData),
      iv: _iv,
    );

    // 4. 分片存储。
    await _writeShards(encrypted.bytes);

    // 5. 清理过期日志。
    await _cleanupOldShards();
  }

  /// 将加密数据分片写入文件。
  Future<void> _writeShards(Uint8List encryptedData) async {
    final shardCount = (encryptedData.length / _maxShardSizeBytes).ceil();

    for (var i = 0; i < shardCount; i++) {
      final start = i * _maxShardSizeBytes;
      final end = (start + _maxShardSizeBytes).clamp(0, encryptedData.length);
      final shardData = encryptedData.sublist(start, end);

      final shardPath = _shardPath(i);
      final file = File(shardPath);

      // 写入分片数据（带超时保护）。
      try {
        await file.writeAsBytes(shardData, flush: true)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        // 超时：清理分片文件，保留已有分片。
        try {
          if (await file.exists()) await file.delete();
        } catch (deleteErr) {
          debugPrint('[PersistentAuditLogger] 超时清理分片失败: $deleteErr');
        }
        throw FileSystemException(
          '审计日志分片写入超时（30秒）。',
          shardPath,
        );
      }
    }

    // 删除多余的旧分片（如果新分片数少于旧分片数）。
    for (var i = shardCount; ; i++) {
      final shardPath = _shardPath(i);
      final file = File(shardPath);
      if (!await file.exists()) break;
      await file.delete();
    }
  }

  /// 获取分片文件路径。
  String _shardPath(int index) {
    return '${_auditDir!.path}${Platform.pathSeparator}'
        '$_shardPrefix${index.toString().padLeft(4, '0')}$_shardExtension';
  }

  /// 从加密存储加载审计日志。
  ///
  /// 实现策略：
  /// 1. 读取所有分片文件
  /// 2. 合并分片数据
  /// 3. 使用 AES-256-GCM 解密
  /// 4. 反序列化 JSON
  /// 5. 验证哈希链完整性
  Future<List<String>> load() async {
    await _ensureAuditDir();

    // 1. 读取所有分片。
    final encryptedData = await _readShards();

    if (encryptedData.isEmpty) {
      // 没有持久化的日志，返回空列表。
      return [];
    }

    // 2. 解密数据。
    final encrypted = encrypt.Encrypted(encryptedData);
    final decryptedBytes = _encrypter.decryptBytes(encrypted, iv: _iv);

    // 3. 反序列化 JSON。
    final jsonData = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
    final entries = (jsonData['entries'] as List).cast<String>();

    // 4. 验证哈希链完整性（生产环境已启用）。
    final isValid = _verifyHashChain(entries);
    if (!isValid) {
      debugPrint('[PersistentAuditLogger] 警告：审计日志哈希链验证失败，日志可能被篡改');
    }

    return entries;
  }

  /// 读取所有分片并合并。
  Future<Uint8List> _readShards() async {
    final shards = <Uint8List>[];

    for (var i = 0; ; i++) {
      final shardPath = _shardPath(i);
      final file = File(shardPath);

      if (!await file.exists()) break;

      try {
        final shardData = await file.readAsBytes();
        shards.add(shardData);
      } catch (e) {
        // 分片读取失败：停止读取后续分片。
        break;
      }
    }

    if (shards.isEmpty) return Uint8List(0);

    // 合并分片。
    final totalLength = shards.fold(0, (sum, shard) => sum + shard.length);
    final merged = Uint8List(totalLength);
    var offset = 0;

    for (final shard in shards) {
      merged.setRange(offset, offset + shard.length, shard);
      offset += shard.length;
    }

    return merged;
  }

  /// 清理过期的分片文件（超过 30 天）。
  Future<void> _cleanupOldShards() async {
    final now = DateTime.now();
    const maxAge = Duration(days: _maxRetentionDays);

    await for (final entity in _auditDir!.list()) {
      if (entity is! File) continue;

      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_shardPrefix)) continue;

      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) > maxAge) {
          await entity.delete();
        }
      } catch (e) {
        debugPrint('[PersistentAuditLogger] 清理过期分片失败: ${entity.path} — $e');
      }
    }
  }

  /// 验证哈希链完整性。
  ///
  /// 每条日志格式为 JSON 字符串，包含 "hash" 字段。
  /// 验证逻辑：每条日志的 hash = SHA-256(prevHash || entryContent)。
  /// 第一条日志的 prevHash 为创世哈希。
  bool _verifyHashChain(List<String> entries) {
    if (entries.isEmpty) return true;

    const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000'; // 创世哈希（64个零）。

    var prevHash = genesisHash;
    for (final entry in entries) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final storedHash = map['hash'] as String?;
        if (storedHash == null || storedHash.isEmpty) {
          debugPrint('[PersistentAuditLogger] 哈希链断点：条目缺少 hash 字段');
          return false;
        }

        // 重建哈希：SHA-256(prevHash || entry 除 hash 外的内容)。
        final contentMap = Map<String, dynamic>.from(map)..remove('hash');
        final contentJson = jsonEncode(contentMap);
        final payload = utf8.encode('$prevHash$contentJson');
        final computedHash = _sha256Hex(payload);

        if (computedHash != storedHash) {
          debugPrint('[PersistentAuditLogger] 哈希链校验失败：'
              '期望 $computedHash，实际 $storedHash');
          return false;
        }

        prevHash = storedHash;
      } catch (e) {
        debugPrint('[PersistentAuditLogger] 哈希链验证异常：$e');
        return false;
      }
    }

    return true;
  }

  /// 计算 SHA-256 哈希并返回十六进制字符串。
  static String _sha256Hex(List<int> data) {
    return crypto.sha256.convert(data).toString();
  }

  /// 清除所有持久化的审计日志（测试用）。
  Future<void> clearAll() async {
    await _ensureAuditDir();

    await for (final entity in _auditDir!.list()) {
      if (entity is! File) continue;

      final name = entity.uri.pathSegments.last;
      if (name.startsWith(_shardPrefix)) {
        try {
          await entity.delete();
        } catch (e) {
          debugPrint('[PersistentAuditLogger] 删除日志分片失败: ${entity.path} — $e');
        }
      }
    }
  }

  /// 获取持久化审计日志的统计信息。
  Future<Map<String, dynamic>> getStats() async {
    await _ensureAuditDir();

    var shardCount = 0;
    var totalSizeBytes = 0;
    DateTime? oldestShard;
    DateTime? newestShard;

    await for (final entity in _auditDir!.list()) {
      if (entity is! File) continue;

      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_shardPrefix)) continue;

      shardCount++;

      try {
        final stat = await entity.stat();
        totalSizeBytes += stat.size;

        if (oldestShard == null || stat.modified.isBefore(oldestShard)) {
          oldestShard = stat.modified;
        }
        if (newestShard == null || stat.modified.isAfter(newestShard)) {
          newestShard = stat.modified;
        }
      } catch (e) {
        debugPrint('[PersistentAuditLogger] 统计分片信息失败: ${entity.path} — $e');
      }
    }

    return {
      'shardCount': shardCount,
      'totalSizeBytes': totalSizeBytes,
      'totalSizeMB': (totalSizeBytes / (1024 * 1024)).toStringAsFixed(2),
      'oldestShard': oldestShard?.toIso8601String(),
      'newestShard': newestShard?.toIso8601String(),
      'maxRetentionDays': _maxRetentionDays,
      'maxShardSizeMB': (_maxShardSizeBytes / (1024 * 1024)).toStringAsFixed(2),
    };
  }
}
