/// VFS 存储 Schema 迁移注册表。
///
/// 所有存储格式迁移在此注册。新增迁移时：
/// 1. 实现迁移函数 `_migrateVNToVN1`
/// 2. 在 [allMigrations] 列表中添加 `SchemaMigration(N, N+1, _migrateVNToVN1)`
/// 3. 确保迁移链连续（fromVersion = 上一个的 toVersion）
///
/// 当前 Schema 版本：2
library;

import 'package:flutter/foundation.dart';

import 'schema_migrator.dart';

/// 所有已注册的迁移（按版本顺序排列）。
final List<SchemaMigration> allMigrations = [
  const SchemaMigration(1, 2, _migrateV1ToV2),
];

// ─── v1 → v2：manifest 格式规范化 ─────────────────────────────────────────

/// v1 → v2 迁移：
///
/// 变更内容：
/// 1. manifest.json 中 `nodes` 改为 `entries`（规范化命名）
/// 2. 添加 `schemaVersion` 字段到 manifest
/// 3. 添加 `migratedAt` 时间戳
Future<void> _migrateV1ToV2(MigrationContext context) async {
  final manifest = await context.readJsonFile('manifest.json');
  if (manifest == null) {
    debugPrint('Migration v1→v2: manifest.json 不存在，跳过');
    return;
  }

  final updated = Map<String, dynamic>.from(manifest);

  // 标准化字段名（如果旧字段存在）
  if (updated.containsKey('nodes') && !updated.containsKey('entries')) {
    updated['entries'] = updated.remove('nodes');
  }

  updated['schemaVersion'] = 2;
  updated['migratedAt'] = DateTime.now().toIso8601String();
  updated['encryptionVersion'] ??= 1;

  await context.writeJsonFile('manifest.json', updated);
  debugPrint('Migration v1→v2: manifest.json 已更新');
}
