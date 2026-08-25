// schema_version.dart — Schema 版本管理（2026-08-24）。
//
// 职责：
// - 定义各存储模块的 schema 版本号
// - 提供版本比较和兼容性检查
// - 注册迁移路径（from → to）

/// Schema 版本信息。
class SchemaVersion {
  const SchemaVersion({
    required this.module,
    required this.version,
    required this.description,
    this.createdAt,
  });

  /// 模块标识（如 'notebook', 'document', 'media'）。
  final String module;

  /// 版本号（单调递增整数）。
  final int version;

  /// 版本描述。
  final String description;

  /// 创建时间。
  final DateTime? createdAt;

  @override
  String toString() => '$module@v$version';

  Map<String, dynamic> toJson() => {
    'module': module,
    'version': version,
    'description': description,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory SchemaVersion.fromJson(Map<String, dynamic> json) => SchemaVersion(
    module: json['module'] as String,
    version: json['version'] as int,
    description: json['description'] as String,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
  );
}

/// 迁移步骤定义。
class MigrationStep {
  const MigrationStep({
    required this.fromVersion,
    required this.toVersion,
    required this.module,
    required this.migrate,
    this.description = '',
  });

  final int fromVersion;
  final int toVersion;
  final String module;
  final String description;

  /// 迁移函数：接收旧数据 Map，返回新数据 Map。
  final Map<String, dynamic> Function(Map<String, dynamic> oldData) migrate;
}

/// Schema 版本注册表。
///
/// 使用方式：
/// ```dart
/// final registry = SchemaRegistry();
/// registry.register(SchemaVersion(module: 'notebook', version: 1, description: '初始版本'));
/// registry.register(SchemaVersion(module: 'notebook', version: 2, description: '添加加密字段'));
/// registry.addMigration(MigrationStep(
///   fromVersion: 1,
///   toVersion: 2,
///   module: 'notebook',
///   migrate: (data) => {...data, 'encrypted': false},
/// ));
/// ```
class SchemaRegistry {
  static final SchemaRegistry _instance = SchemaRegistry._();
  factory SchemaRegistry() => _instance;
  SchemaRegistry._();

  final Map<String, List<SchemaVersion>> _versions = {};
  final Map<String, List<MigrationStep>> _migrations = {};

  /// 注册 schema 版本。
  void register(SchemaVersion version) {
    _versions.putIfAbsent(version.module, () => []);
    final list = _versions[version.module]!;
    if (list.any((v) => v.version == version.version)) {
      throw StateError('Duplicate schema version: ${version.module}@v${version.version}');
    }
    list.add(version);
    list.sort((a, b) => a.version.compareTo(b.version));
  }

  /// 注册迁移步骤。
  void addMigration(MigrationStep step) {
    _migrations.putIfAbsent(step.module, () => []);
    final list = _migrations[step.module]!;
    if (list.any((m) => m.fromVersion == step.fromVersion && m.toVersion == step.toVersion)) {
      throw StateError(
        'Duplicate migration: ${step.module} v${step.fromVersion}→v${step.toVersion}',
      );
    }
    list.add(step);
    list.sort((a, b) => a.fromVersion.compareTo(b.fromVersion));
  }

  /// 获取模块最新版本。
  int latestVersion(String module) {
    final list = _versions[module];
    if (list == null || list.isEmpty) return 0;
    return list.last.version;
  }

  /// 获取模块所有版本。
  List<SchemaVersion> getVersions(String module) =>
      List.unmodifiable(_versions[module] ?? []);

  /// 获取迁移路径（from → to，可能多步）。
  List<MigrationStep> getMigrationPath(String module, int from, int to) {
    if (from >= to) return [];
    final steps = <MigrationStep>[];
    var current = from;
    final available = _migrations[module] ?? [];

    while (current < to) {
      final step = available.where((m) => m.fromVersion == current).firstOrNull;
      if (step == null) {
        throw StateError('No migration path for $module v$current→v${current + 1}');
      }
      steps.add(step);
      current = step.toVersion;
    }
    return steps;
  }

  /// 执行迁移链。
  Map<String, dynamic> migrate(
    String module,
    Map<String, dynamic> data,
    int fromVersion,
    int toVersion,
  ) {
    final steps = getMigrationPath(module, fromVersion, toVersion);
    var current = data;
    for (final step in steps) {
      current = step.migrate(current);
    }
    return current;
  }

  /// 检查是否需要迁移。
  bool needsMigration(String module, int currentVersion) {
    return currentVersion < latestVersion(module);
  }
}

/// 全局 schema 版本常量。
class SchemaVersions {
  SchemaVersions._();

  // ─── Notebook 模块 ───
  static const String notebook = 'notebook';
  static const int notebookV1 = 1; // 初始版本
  static const int notebookV2 = 2; // 添加 encrypted、encryptionMode 字段
  static const int notebookV3 = 3; // 添加 recoveryEnvelope、searchSummary
  static const int notebookV4 = 4; // 添加 schemaVersion 字段（内嵌版本追踪）
  static const int notebookCurrent = notebookV4;

  // ─── Document 模块 ───
  static const String document = 'document';
  static const int documentV1 = 1; // 初始版本
  static const int documentV2 = 2; // DocumentCodecV2（DNV2 魔数）
  static const int documentCurrent = documentV2;

  // ─── Media 模块 ───
  static const String media = 'media';
  static const int mediaV1 = 1; // 明文存储
  static const int mediaV2 = 2; // DAN 加密（MediaCryptoService）
  static const int mediaCurrent = mediaV2;

  // ─── Unified Storage 模块 ───
  static const String unified = 'unified';
  static const int unifiedV1 = 1; // 初始版本（带校验和）
  static const int unifiedCurrent = unifiedV1;
}

/// 注册所有已知 schema 版本和迁移路径。
void registerAllSchemas(SchemaRegistry registry) {
  // Notebook 模块
  registry.register(const SchemaVersion(
    module: SchemaVersions.notebook,
    version: SchemaVersions.notebookV1,
    description: '初始版本',
  ));
  registry.register(const SchemaVersion(
    module: SchemaVersions.notebook,
    version: SchemaVersions.notebookV2,
    description: '添加 encrypted、encryptionMode 字段',
  ));
  registry.register(const SchemaVersion(
    module: SchemaVersions.notebook,
    version: SchemaVersions.notebookV3,
    description: '添加 recoveryEnvelope、searchSummary',
  ));
  registry.register(const SchemaVersion(
    module: SchemaVersions.notebook,
    version: SchemaVersions.notebookV4,
    description: '添加 schemaVersion 字段（内嵌版本追踪）',
  ));

  // Notebook 迁移路径
  registry.addMigration(MigrationStep(
    fromVersion: 1,
    toVersion: 2,
    module: SchemaVersions.notebook,
    description: '添加 encrypted=false、encryptionMode=none',
    migrate: (data) => {
      ...data,
      'encrypted': data['encrypted'] ?? false,
      'encryptionMode': data['encryptionMode'] ?? 'none',
    },
  ));
  registry.addMigration(MigrationStep(
    fromVersion: 2,
    toVersion: 3,
    module: SchemaVersions.notebook,
    description: '添加 recoveryEnvelope=null、searchSummary=null',
    migrate: (data) => {
      ...data,
      'recoveryEnvelope': data['recoveryEnvelope'],
      'searchSummary': data['searchSummary'],
    },
  ));
  registry.addMigration(MigrationStep(
    fromVersion: 3,
    toVersion: 4,
    module: SchemaVersions.notebook,
    description: '添加 schemaVersion=4',
    migrate: (data) => {
      ...data,
      'schemaVersion': 4,
    },
  ));

  // Document 模块
  registry.register(const SchemaVersion(
    module: SchemaVersions.document,
    version: SchemaVersions.documentV1,
    description: '初始版本',
  ));
  registry.register(const SchemaVersion(
    module: SchemaVersions.document,
    version: SchemaVersions.documentV2,
    description: 'DocumentCodecV2（DNV2 魔数）',
  ));

  // Media 模块
  registry.register(const SchemaVersion(
    module: SchemaVersions.media,
    version: SchemaVersions.mediaV1,
    description: '明文存储',
  ));
  registry.register(const SchemaVersion(
    module: SchemaVersions.media,
    version: SchemaVersions.mediaV2,
    description: 'DAN 加密（MediaCryptoService）',
  ));
}
