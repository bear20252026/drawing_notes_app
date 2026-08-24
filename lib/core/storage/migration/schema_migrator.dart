/// Schema 迁移管理器 —— 版本化存储格式迁移 + 自动检测 + 失败回滚。
///
/// 设计目标：
/// 1. 版本号→迁移函数映射（线性迁移链）
/// 2. 启动时自动检测当前版本并执行待执行迁移
/// 3. 迁移失败时回滚（基于备份文件）
/// 4. 迁移历史记录（migration_log.json）
///
/// 存储布局：
/// ```
/// <directory>/
///   schema_version.json    — 当前 schema 版本
///   migration_log.json     — 迁移历史记录
///   backups/               — 迁移前备份目录
///     <version>_<timestamp>/
/// ```
///
/// 使用方式：
/// ```dart
/// final migrator = SchemaMigrator(
///   directory: appDir,
///   migrations: [
///     SchemaMigration(1, 2, _migrateV1ToV2),
///     SchemaMigration(2, 3, _migrateV2ToV3),
///   ],
/// );
/// await migrator.migrate();
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class SchemaMigrator {
  SchemaMigrator({
    required this.directory,
    required List<SchemaMigration> migrations,
  }) : _migrations = List.unmodifiable(
          migrations..sort((a, b) => a.fromVersion.compareTo(b.fromVersion)),
        ) {
    _validateMigrationChain();
  }

  final Directory directory;
  final List<SchemaMigration> _migrations;

  /// 当前支持的最新 schema 版本。
  int get latestVersion =>
      _migrations.isEmpty ? 1 : _migrations.last.toVersion;

  File get _versionFile => File(
      '${directory.path}${Platform.pathSeparator}schema_version.json');

  File get _logFile => File(
      '${directory.path}${Platform.pathSeparator}migration_log.json');

  Directory get _backupDir => Directory(
      '${directory.path}${Platform.pathSeparator}backups');

  // ─── 公开 API ─────────────────────────────────────────────────────────

  /// 获取当前 schema 版本（未初始化返回 0）。
  Future<int> getCurrentVersion() async {
    if (!await _versionFile.exists()) return 0;
    try {
      final content = await _versionFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return (json['version'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('SchemaMigrator: 读取版本文件失败: $e');
      return 0;
    }
  }

  /// 检测是否有待执行的迁移。
  Future<bool> needsMigration() async {
    final current = await getCurrentVersion();
    return current < latestVersion;
  }

  /// 执行所有待执行的迁移（按版本顺序）。
  ///
  /// 返回成功执行的迁移数量。
  /// 迁移失败时自动回滚并抛出 [MigrationException]。
  Future<int> migrate() async {
    final current = await getCurrentVersion();
    if (current >= latestVersion) {
      debugPrint('SchemaMigrator: 已是最新版本 v$current，无需迁移');
      return 0;
    }

    final pending =
        _migrations.where((m) => m.fromVersion >= current).toList();
    debugPrint(
        'SchemaMigrator: 发现 ${pending.length} 个待执行迁移 (v$current → v$latestVersion)');

    var executed = 0;
    for (final migration in pending) {
      try {
        await _executeMigration(migration);
        executed++;
      } catch (e, stack) {
        debugPrint(
            'SchemaMigrator: 迁移 v${migration.fromVersion}→v${migration.toVersion} 失败: $e');
        debugPrint('SchemaMigrator: 开始回滚...');
        await _rollback(migration, current);
        throw MigrationException(
          '迁移 v${migration.fromVersion}→v${migration.toVersion} 失败: $e',
          migration: migration,
          originalError: e,
          stackTrace: stack,
        );
      }
    }

    debugPrint('SchemaMigrator: 迁移完成，共执行 $executed 个迁移');
    return executed;
  }

  /// 获取迁移历史记录。
  Future<List<MigrationLogEntry>> getMigrationLog() async {
    if (!await _logFile.exists()) return [];
    try {
      final content = await _logFile.readAsString();
      final list = jsonDecode(content) as List;
      return list
          .map((e) => MigrationLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SchemaMigrator: 读取迁移日志失败: $e');
      return [];
    }
  }

  /// 强制设置 schema 版本（谨慎使用）。
  Future<void> setVersion(int version) async {
    await directory.create(recursive: true);
    await _versionFile.writeAsString(jsonEncode({
      'version': version,
      'updatedAt': DateTime.now().toIso8601String(),
    }));
  }

  // ─── 内部实现 ─────────────────────────────────────────────────────────

  void _validateMigrationChain() {
    for (var i = 1; i < _migrations.length; i++) {
      final prev = _migrations[i - 1];
      final curr = _migrations[i];
      if (curr.fromVersion != prev.toVersion) {
        throw StateError(
          '迁移链不连续: v${prev.fromVersion}→v${prev.toVersion} 后期望 '
          'v${prev.toVersion}→...，实际为 v${curr.fromVersion}→v${curr.toVersion}',
        );
      }
    }
  }

  Future<void> _executeMigration(SchemaMigration migration) async {
    final stopwatch = Stopwatch()..start();
    debugPrint(
        'SchemaMigrator: 执行迁移 v${migration.fromVersion}→v${migration.toVersion}...');

    await _createBackup(migration.fromVersion);

    final context = MigrationContext(
      directory: directory,
      fromVersion: migration.fromVersion,
      toVersion: migration.toVersion,
    );
    await migration.execute(context);

    await setVersion(migration.toVersion);

    stopwatch.stop();
    await _appendLog(MigrationLogEntry(
      fromVersion: migration.fromVersion,
      toVersion: migration.toVersion,
      executedAt: DateTime.now(),
      durationMs: stopwatch.elapsedMilliseconds,
      status: 'success',
    ));

    debugPrint(
        'SchemaMigrator: 迁移 v${migration.fromVersion}→v${migration.toVersion} '
        '完成 (${stopwatch.elapsedMilliseconds}ms)');
  }

  Future<void> _createBackup(int version) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath =
        '${_backupDir.path}${Platform.pathSeparator}v${version}_$timestamp';
    final backup = Directory(backupPath);
    await backup.create(recursive: true);

    final filesToBackup = [_versionFile, _logFile];
    for (final file in filesToBackup) {
      if (await file.exists()) {
        final target = File(
            '${backup.path}${Platform.pathSeparator}${file.uri.pathSegments.last}');
        await file.copy(target.path);
      }
    }

    // 备份 objects 目录
    final objectsDir = Directory(
        '${directory.path}${Platform.pathSeparator}objects');
    if (await objectsDir.exists()) {
      final backupObjects =
          Directory('${backup.path}${Platform.pathSeparator}objects');
      await backupObjects.create(recursive: true);
      await for (final entity in objectsDir.list()) {
        if (entity is File) {
          final target = File(
              '${backupObjects.path}${Platform.pathSeparator}${entity.uri.pathSegments.last}');
          await entity.copy(target.path);
        }
      }
    }

    debugPrint('SchemaMigrator: 备份已创建 → $backupPath');
  }

  Future<void> _rollback(
      SchemaMigration failedMigration, int targetVersion) async {
    try {
      if (!await _backupDir.exists()) {
        debugPrint('SchemaMigrator: 无备份目录，无法回滚');
        return;
      }

      final backups = await _backupDir
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .where(
              (d) => d.path.contains('v${failedMigration.fromVersion}'))
          .toList();

      if (backups.isEmpty) {
        debugPrint(
            'SchemaMigrator: 未找到 v${failedMigration.fromVersion} 的备份');
        return;
      }

      backups.sort((a, b) => b.path.compareTo(a.path));
      final latestBackup = backups.first;

      await _restoreFromBackup(latestBackup);
      // 回滚到迁移链中前一个成功版本（fromVersion 是失败迁移的起始版本）
      await setVersion(failedMigration.fromVersion);

      await _appendLog(MigrationLogEntry(
        fromVersion: failedMigration.toVersion,
        toVersion: failedMigration.fromVersion,
        executedAt: DateTime.now(),
        durationMs: 0,
        status: 'rollback',
        reason: '迁移失败，已回滚',
      ));

      debugPrint(
          'SchemaMigrator: 回滚完成 → v${failedMigration.fromVersion}');
    } on Exception catch (e) {
      debugPrint('SchemaMigrator: 回滚失败: $e');
    }
  }

  Future<void> _restoreFromBackup(Directory backup) async {
    await for (final entity in backup.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final target = File(
            '${directory.path}${Platform.pathSeparator}${entity.uri.pathSegments.last}');
        await entity.copy(target.path);
      }
    }

    final backupObjects =
        Directory('${backup.path}${Platform.pathSeparator}objects');
    if (await backupObjects.exists()) {
      final targetObjects = Directory(
          '${directory.path}${Platform.pathSeparator}objects');
      if (await targetObjects.exists()) {
        await targetObjects.delete(recursive: true);
      }
      await targetObjects.create(recursive: true);
      await for (final entity in backupObjects.list()) {
        if (entity is File) {
          final target = File(
              '${targetObjects.path}${Platform.pathSeparator}${entity.uri.pathSegments.last}');
          await entity.copy(target.path);
        }
      }
    }
  }

  Future<void> _appendLog(MigrationLogEntry entry) async {
    final log = await getMigrationLog();
    log.add(entry);
    await directory.create(recursive: true);
    await _logFile.writeAsString(
      jsonEncode(log.map((e) => e.toJson()).toList()),
    );
  }
}

// ─── 数据结构 ────────────────────────────────────────────────────────────────

/// 单次迁移定义。
class SchemaMigration {
  const SchemaMigration(this.fromVersion, this.toVersion, this.execute);

  final int fromVersion;
  final int toVersion;
  final Future<void> Function(MigrationContext context) execute;

  @override
  String toString() => 'SchemaMigration(v$fromVersion → v$toVersion)';
}

/// 迁移执行上下文。
class MigrationContext {
  const MigrationContext({
    required this.directory,
    required this.fromVersion,
    required this.toVersion,
  });

  final Directory directory;
  final int fromVersion;
  final int toVersion;

  Future<Map<String, dynamic>?> readJsonFile(String filename) async {
    final file =
        File('${directory.path}${Platform.pathSeparator}$filename');
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MigrationContext: 读取 $filename 失败: $e');
      return null;
    }
  }

  /// 写入 JSON 文件（原子写入：tmp + rename）。
  Future<void> writeJsonFile(
      String filename, Map<String, dynamic> data) async {
    final file =
        File('${directory.path}${Platform.pathSeparator}$filename');
    final tmp = File('${file.path}.migration.tmp');
    await directory.create(recursive: true);
    await tmp.writeAsString(jsonEncode(data), flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }
}

/// 迁移日志条目。
class MigrationLogEntry {
  const MigrationLogEntry({
    required this.fromVersion,
    required this.toVersion,
    required this.executedAt,
    required this.durationMs,
    required this.status,
    this.reason,
  });

  final int fromVersion;
  final int toVersion;
  final DateTime executedAt;
  final int durationMs;
  final String status;
  final String? reason;

  Map<String, dynamic> toJson() => {
        'fromVersion': fromVersion,
        'toVersion': toVersion,
        'executedAt': executedAt.toIso8601String(),
        'durationMs': durationMs,
        'status': status,
        if (reason != null) 'reason': reason,
      };

  factory MigrationLogEntry.fromJson(Map<String, dynamic> json) =>
      MigrationLogEntry(
        fromVersion: (json['fromVersion'] as num).toInt(),
        toVersion: (json['toVersion'] as num).toInt(),
        executedAt: DateTime.parse(json['executedAt'] as String),
        durationMs: (json['durationMs'] as num).toInt(),
        status: json['status'] as String,
        reason: json['reason'] as String?,
      );
}

/// 迁移异常。
class MigrationException implements Exception {
  const MigrationException(
    this.message, {
    required this.migration,
    this.originalError,
    this.stackTrace,
  });

  final String message;
  final SchemaMigration migration;
  final Object? originalError;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'MigrationException: $message\nMigration: $migration';
}
