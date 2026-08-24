// unified_storage.dart — 统一存储接口（2026-08-24）。
//
// 抽象层：统一 StorageService（应用配置）和 NotebookStorage（笔记本数据）
// 的访问模式，为未来替换底层实现（SQLite/云同步）提供无痛迁移路径。
//
// 设计原则：
// - 接口隔离：读写分离（ReadOnlyStorage / WritableStorage）
// - 类型安全：泛型 key-value + 类型化文档
// - 版本感知：所有写入携带 schemaVersion
// - 完整性校验：SHA-256 内嵌校验和

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 存储文档（带版本和校验和的包装层）。
class StorageEnvelope<T> {
  const StorageEnvelope({
    required this.key,
    required this.data,
    required this.schemaVersion,
    required this.checksum,
    required this.createdAt,
    required this.updatedAt,
  });

  final String key;
  final T data;
  final int schemaVersion;
  final String checksum; // SHA-256 hex
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 验证数据完整性。
  bool verifyIntegrity(String serializedData) {
    final computed = sha256.convert(utf8.encode(serializedData)).toString();
    return computed == checksum;
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) serializer) {
    return {
      'key': key,
      'data': serializer(data),
      'schemaVersion': schemaVersion,
      'checksum': checksum,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static StorageEnvelope<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) deserializer,
  ) {
    return StorageEnvelope<T>(
      key: json['key'] as String,
      data: deserializer(json['data'] as Map<String, dynamic>),
      schemaVersion: json['schemaVersion'] as int,
      checksum: json['checksum'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// 只读存储接口。
abstract class ReadOnlyStorage {
  /// 读取文档（不存在返回 null）。
  Future<StorageEnvelope<T>?> get<T>(
    String key,
    T Function(Map<String, dynamic>) deserializer,
  );

  /// 列出指定前缀的所有文档。
  Future<List<StorageEnvelope<T>>> list<T>(
    String prefix,
    T Function(Map<String, dynamic>) deserializer,
  );

  /// 检查文档是否存在。
  Future<bool> exists(String key);
}

/// 可写存储接口。
abstract class WritableStorage extends ReadOnlyStorage {
  /// 写入文档（自动计算校验和、设置时间戳）。
  Future<void> put<T>(
    String key,
    T data,
    int schemaVersion,
    Map<String, dynamic> Function(T) serializer,
  );

  /// 删除文档。
  Future<void> delete(String key);

  /// 原子批量写入。
  Future<void> putBatch<T>(
    Map<String, T> entries,
    int schemaVersion,
    Map<String, dynamic> Function(T) serializer,
  );
}

/// 统一存储接口（读写 + 迁移支持）。
abstract class UnifiedStorage extends WritableStorage {
  /// 当前 schema 版本。
  int get currentSchemaVersion;

  /// 执行数据迁移。
  Future<MigrationResult> migrate();

  /// 验证所有文档完整性。
  Future<IntegrityReport> verifyIntegrity();

  /// 导出所有数据（备份用）。
  Future<Uint8List> exportAll();

  /// 导入数据（恢复用）。
  Future<ImportResult> importAll(Uint8List backup);
}

/// 迁移结果。
class MigrationResult {
  const MigrationResult({
    required this.migratedCount,
    required this.skippedCount,
    required this.errorCount,
    required this.fromVersion,
    required this.toVersion,
    this.errors = const [],
  });

  final int migratedCount;
  final int skippedCount;
  final int errorCount;
  final int fromVersion;
  final int toVersion;
  final List<String> errors;

  bool get isSuccess => errorCount == 0;
}

/// 完整性报告。
class IntegrityReport {
  const IntegrityReport({
    required this.totalDocuments,
    required this.validCount,
    required this.corruptedCount,
    this.corruptedKeys = const [],
  });

  final int totalDocuments;
  final int validCount;
  final int corruptedCount;
  final List<String> corruptedKeys;

  bool get isAllValid => corruptedCount == 0;
}

/// 导入结果。
class ImportResult {
  const ImportResult({
    required this.importedCount,
    required this.skippedCount,
    required this.errorCount,
    this.errors = const [],
  });

  final int importedCount;
  final int skippedCount;
  final int errorCount;
  final List<String> errors;
}

/// 基于文件系统的统一存储实现。
class FileSystemUnifiedStorage implements UnifiedStorage {
  FileSystemUnifiedStorage({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  Directory? _dataDir;

  @override
  int get currentSchemaVersion => 1;

  Future<Directory> _ensureDataDir() async {
    if (_dataDir != null) return _dataDir!;
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}unified_data');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dataDir = dir;
    return dir;
  }

  String _filePathForKey(String key) {
    // 安全：key 转为文件名（替换路径分隔符）
    final safeKey = key.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    return '${_dataDir!.path}${Platform.pathSeparator}$safeKey.json';
  }

  @override
  Future<StorageEnvelope<T>?> get<T>(
    String key,
    T Function(Map<String, dynamic>) deserializer,
  ) async {
    await _ensureDataDir();
    final file = File(_filePathForKey(key));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return StorageEnvelope.fromJson(json, deserializer);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<StorageEnvelope<T>>> list<T>(
    String prefix,
    T Function(Map<String, dynamic>) deserializer,
  ) async {
    await _ensureDataDir();
    final results = <StorageEnvelope<T>>[];
    await for (final entity in _dataDir!.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (!entity.path.contains(prefix)) continue;
      try {
        final json = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        results.add(StorageEnvelope.fromJson(json, deserializer));
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  @override
  Future<bool> exists(String key) async {
    await _ensureDataDir();
    return File(_filePathForKey(key)).exists();
  }

  @override
  Future<void> put<T>(
    String key,
    T data,
    int schemaVersion,
    Map<String, dynamic> Function(T) serializer,
  ) async {
    await _ensureDataDir();
    final serialized = jsonEncode(serializer(data));
    final checksum = sha256.convert(utf8.encode(serialized)).toString();
    final now = DateTime.now();

    final envelope = StorageEnvelope<T>(
      key: key,
      data: data,
      schemaVersion: schemaVersion,
      checksum: checksum,
      createdAt: now,
      updatedAt: now,
    );

    final json = jsonEncode(envelope.toJson(serializer));
    final file = File(_filePathForKey(key));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete(String key) async {
    await _ensureDataDir();
    final file = File(_filePathForKey(key));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> putBatch<T>(
    Map<String, T> entries,
    int schemaVersion,
    Map<String, dynamic> Function(T) serializer,
  ) async {
    for (final entry in entries.entries) {
      await put(entry.key, entry.value, schemaVersion, serializer);
    }
  }

  @override
  Future<MigrationResult> migrate() async {
    // 当前版本无需迁移
    return MigrationResult(
      migratedCount: 0,
      skippedCount: 0,
      errorCount: 0,
      fromVersion: currentSchemaVersion,
      toVersion: currentSchemaVersion,
    );
  }

  @override
  Future<IntegrityReport> verifyIntegrity() async {
    await _ensureDataDir();
    var total = 0;
    var valid = 0;
    var corrupted = 0;
    final corruptedKeys = <String>[];

    await for (final entity in _dataDir!.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      total++;
      try {
        final content = await entity.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final storedChecksum = json['checksum'] as String?;
        if (storedChecksum == null) {
          corrupted++;
          corruptedKeys.add(entity.path);
          continue;
        }
        final dataJson = jsonEncode(json['data']);
        final computed = sha256.convert(utf8.encode(dataJson)).toString();
        if (computed == storedChecksum) {
          valid++;
        } else {
          corrupted++;
          corruptedKeys.add(entity.path);
        }
      } catch (_) {
        corrupted++;
        corruptedKeys.add(entity.path);
      }
    }

    return IntegrityReport(
      totalDocuments: total,
      validCount: valid,
      corruptedCount: corrupted,
      corruptedKeys: corruptedKeys,
    );
  }

  @override
  Future<Uint8List> exportAll() async {
    await _ensureDataDir();
    final archive = <String, dynamic>{};
    await for (final entity in _dataDir!.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      archive[name] = await entity.readAsString();
    }
    return utf8.encode(jsonEncode(archive));
  }

  @override
  Future<ImportResult> importAll(Uint8List backup) async {
    await _ensureDataDir();
    var imported = 0;
    var skipped = 0;
    var errors = 0;
    final errorList = <String>[];

    try {
      final archive = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
      for (final entry in archive.entries) {
        try {
          final file = File('${_dataDir!.path}${Platform.pathSeparator}${entry.key}');
          await file.writeAsString(entry.value as String, flush: true);
          imported++;
        } catch (e) {
          errors++;
          errorList.add('${entry.key}: $e');
        }
      }
    } catch (e) {
      errors++;
      errorList.add('Invalid backup format: $e');
    }

    return ImportResult(
      importedCount: imported,
      skippedCount: skipped,
      errorCount: errors,
      errors: errorList,
    );
  }
}
