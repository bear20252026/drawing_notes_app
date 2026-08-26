/// VFS 存储 Schema 迁移模块。
///
/// 提供版本化存储格式迁移能力：
/// - [SchemaMigrator]：迁移管理器（版本检测、执行、回滚）
/// - [SchemaMigration]：单次迁移定义
/// - [MigrationContext]：迁移执行上下文
/// - [MigrationRunner]：应用启动时自动迁移
/// - [MigrationException]：迁移异常
library;

export 'migration_runner.dart';
export 'migrations.dart';
export 'schema_migrator.dart';
