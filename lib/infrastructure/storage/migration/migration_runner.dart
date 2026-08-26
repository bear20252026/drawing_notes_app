/// Schema 迁移运行器 —— 在应用启动时自动检测并执行迁移。
///
/// 集成方式：
/// ```dart
/// // 在 main() 或 AppInitService 中调用
/// await MigrationRunner.run(appDir);
/// ```
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'migrations.dart';
import 'schema_migrator.dart';

/// 迁移运行器。
class MigrationRunner {
  MigrationRunner._();

  static bool _executed = false;

  /// 运行所有待执行的迁移。
  ///
  /// [appDir] 应用数据目录。
  /// [vaultDir] VFS 保险库目录（可选，默认为 appDir/vault）。
  static Future<int> run(Directory appDir, {Directory? vaultDir}) async {
    if (_executed) {
      debugPrint('MigrationRunner: 已执行过，跳过');
      return 0;
    }

    final vault = vaultDir ??
        Directory('${appDir.path}${Platform.pathSeparator}vault');

    if (!await vault.exists()) {
      debugPrint('MigrationRunner: vault 目录不存在（全新安装），跳过迁移');
      _executed = true;
      return 0;
    }

    final migrator = SchemaMigrator(
      directory: vault,
      migrations: allMigrations,
    );

    try {
      final count = await migrator.migrate();
      _executed = true;

      if (count > 0) {
        debugPrint('MigrationRunner: 成功执行 $count 个迁移');
        final log = await migrator.getMigrationLog();
        for (final entry in log) {
          debugPrint('  ${entry.status}: v${entry.fromVersion}→v${entry.toVersion} '
              '(${entry.durationMs}ms)');
        }
      }

      return count;
    } catch (e) {
      debugPrint('MigrationRunner: 迁移失败: $e');
      _executed = true;
      rethrow;
    }
  }

  /// 检查是否需要迁移（不执行）。
  static Future<bool> needsMigration(Directory appDir,
      {Directory? vaultDir}) async {
    final vault = vaultDir ??
        Directory('${appDir.path}${Platform.pathSeparator}vault');
    if (!await vault.exists()) return false;

    final migrator = SchemaMigrator(
      directory: vault,
      migrations: allMigrations,
    );

    return migrator.needsMigration();
  }

  /// 获取当前 schema 版本。
  static Future<int> getCurrentVersion(Directory appDir,
      {Directory? vaultDir}) async {
    final vault = vaultDir ??
        Directory('${appDir.path}${Platform.pathSeparator}vault');
    if (!await vault.exists()) return 0;

    final migrator = SchemaMigrator(
      directory: vault,
      migrations: allMigrations,
    );

    return migrator.getCurrentVersion();
  }

  @visibleForTesting
  static void reset() {
    _executed = false;
  }
}
