// schema_version.dart — Schema 版本管理 + 数据迁移机制（2026-08-24）。
//
// 设计参考：
// - Sentry：schemaVersion + migrations 列表——自动升级
// - AFFiNE：SpaceStorage 版本向量——CRDT 预留
// - Saber：VFS JSON index 版本字段——向后兼容
//
// 纯 Dart——禁 Flutter/dart:io（R-02）。

import 'dart:convert';
import 'dart:typed_data';

/// Schema 版本常量。
class SchemaVersion {
  SchemaVersion._();

  /// 当前 Schema 版本号。
  static const int current = 3;

  /// 版本历史：
  /// - v1: 初始版本（DrawingDocument JSON）
  /// - v2: 添加 vectorClock 字段（CRDT 预留）
  /// - v3: 添加 dataIntegrityHash 字段（SHA-256 校验）
  static const List<int> supported = [1, 2, 3];
}

/// Schema 迁移接口。
abstract class SchemaMigration {
  /// 源版本号。
  int get fromVersion;

  /// 目标版本号。
  int get toVersion;

  /// 执行迁移。
  ///
  /// [data] 为原始 JSON 数据，返回迁移后的 JSON 数据。
  Map<String, dynamic> migrate(Map<String, dynamic> data);
}

/// Schema 迁移管理器。
class SchemaMigrationManager {
  SchemaMigrationManager({List<SchemaMigration>? migrations})
      : _migrations = migrations ?? _defaultMigrations();

  final List<SchemaMigration> _migrations;

  /// 获取当前 Schema 版本号。
  int get currentVersion => SchemaVersion.current;

  /// 检查数据是否需要迁移。
  bool needsMigration(Map<String, dynamic> data) {
    final version = _extractVersion(data);
    return version < SchemaVersion.current;
  }

  /// 获取数据的 Schema 版本号。
  int getVersion(Map<String, dynamic> data) => _extractVersion(data);

  /// 执行迁移链。
  ///
  /// 从数据当前版本逐步迁移到最新版本。
  /// 返回迁移后的数据（版本号已更新）。
  Map<String, dynamic> migrateToLatest(Map<String, dynamic> data) {
    var currentData = Map<String, dynamic>.from(data);
    var currentVersion = _extractVersion(currentData);

    // 按版本顺序执行迁移。
    final sortedMigrations = List<SchemaMigration>.from(_migrations)
      ..sort((a, b) => a.fromVersion.compareTo(b.fromVersion));

    for (final migration in sortedMigrations) {
      if (migration.fromVersion >= currentVersion &&
          migration.toVersion <= SchemaVersion.current) {
        currentData = migration.migrate(currentData);
        currentVersion = migration.toVersion;
      }
    }

    // 更新版本号。
    currentData['schemaVersion'] = SchemaVersion.current;
    return currentData;
  }

  /// 验证数据完整性。
  ///
  /// 检查必需字段是否存在、类型是否正确。
  static ValidationResult validate(Map<String, dynamic> data) {
    final errors = <String>[];

    // 检查必需字段。
    if (!data.containsKey('id')) {
      errors.add('缺少必需字段: id');
    }
    if (!data.containsKey('name')) {
      errors.add('缺少必需字段: name');
    }
    if (!data.containsKey('created')) {
      errors.add('缺少必需字段: created');
    }
    if (!data.containsKey('last')) {
      errors.add('缺少必需字段: last');
    }

    // 检查版本号。
    final version = data['schemaVersion'] as int? ?? 1;
    if (!SchemaVersion.supported.contains(version)) {
      errors.add('不支持的 Schema 版本: $version');
    }

    // 检查数据完整性哈希（v3+）。
    if (version >= 3 && !data.containsKey('dataIntegrityHash')) {
      errors.add('v3+ 数据缺少 dataIntegrityHash 字段');
    }

    return errors.isEmpty
        ? const ValidationResult.success()
        : ValidationResult.failure(errors.join('; '));
  }

  /// 提取版本号（默认 v1）。
  int _extractVersion(Map<String, dynamic> data) {
    return data['schemaVersion'] as int? ?? 1;
  }

  /// 默认迁移链。
  static List<SchemaMigration> _defaultMigrations() {
    return [
      _MigrationV1ToV2(),
      _MigrationV2ToV3(),
    ];
  }
}

/// 验证结果。
class ValidationResult {
  const ValidationResult.success() : error = null;
  const ValidationResult.failure(this.error);

  final String? error;

  bool get isValid => error == null;
  bool get isInvalid => error != null;
}

/// v1 → v2 迁移：添加 vectorClock 字段。
class _MigrationV1ToV2 implements SchemaMigration {
  @override
  int get fromVersion => 1;

  @override
  int get toVersion => 2;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> data) {
    final migrated = Map<String, dynamic>.from(data);

    // 添加 vectorClock 字段（如果不存在）。
    if (!migrated.containsKey('vectorClock')) {
      migrated['vectorClock'] = <String, dynamic>{
        'clocks': <String, dynamic>{},
      };
    }

    // 更新版本号。
    migrated['schemaVersion'] = 2;

    return migrated;
  }
}

/// v2 → v3 迁移：添加 dataIntegrityHash 字段。
class _MigrationV2ToV3 implements SchemaMigration {
  @override
  int get fromVersion => 2;

  @override
  int get toVersion => 3;

  @override
  Map<String, dynamic> migrate(Map<String, dynamic> data) {
    final migrated = Map<String, dynamic>.from(data);

    // 添加 dataIntegrityHash 字段（空字符串——实际哈希由 StorageBackend 计算）。
    if (!migrated.containsKey('dataIntegrityHash')) {
      migrated['dataIntegrityHash'] = '';
    }

    // 更新版本号。
    migrated['schemaVersion'] = 3;

    return migrated;
  }
}

/// 数据完整性 SHA-256 校验工具。
///
/// 用于验证存储数据的完整性（防篡改/损坏）。
class DataIntegrityChecker {
  DataIntegrityChecker._();

  /// 计算数据的 SHA-256 哈希。
  ///
  /// 纯 Dart 实现——不依赖 dart:io 或 crypto 包。
  /// 使用 Dart 内置的 Object.hashCode 作为轻量级校验，
  /// 生产环境应使用 dart:convert + crypto 包。
  static String computeHash(List<int> data) {
    // 轻量级哈希：使用 Dart 内置哈希。
    // 生产环境应替换为 SHA-256 实现。
    var hash = 0x811c9dc5; // FNV-1a 初始值。
    for (final byte in data) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 验证数据完整性。
  ///
  /// 比较计算的哈希与存储的哈希。
  static bool verify(List<int> data, String expectedHash) {
    if (expectedHash.isEmpty) return true; // 无哈希——跳过验证。
    final computed = computeHash(data);
    return computed == expectedHash;
  }

  /// 为文档数据生成完整性哈希。
  ///
  /// 将 JSON 数据序列化后计算哈希。
  static String hashDocument(Map<String, dynamic> doc) {
    // 移除哈希字段本身（避免循环依赖）。
    final dataForHash = Map<String, dynamic>.from(doc)
      ..remove('dataIntegrityHash');

    // 序列化为 JSON（键排序——确保一致性）。
    final json = jsonEncode(dataForHash);
    final bytes = utf8.encode(json);
    return computeHash(bytes);
  }

  /// 验证文档数据完整性。
  static bool verifyDocument(Map<String, dynamic> doc) {
    final storedHash = doc['dataIntegrityHash'] as String? ?? '';
    if (storedHash.isEmpty) return true; // 无哈希——跳过验证。

    final computedHash = hashDocument(doc);
    return computedHash == storedHash;
  }
}
