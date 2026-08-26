import 'dart:convert';
import 'dart:io';

import 'package:drawing_notes_app/infrastructure/storage/migration/migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('migration_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SchemaMigrator', () {
    test('初始版本为 0（无 version 文件）', () async {
      final migrator = SchemaMigrator(directory: tempDir, migrations: []);
      expect(await migrator.getCurrentVersion(), 0);
    });

    test('setVersion 写入版本文件', () async {
      final migrator = SchemaMigrator(directory: tempDir, migrations: []);
      await migrator.setVersion(5);
      expect(await migrator.getCurrentVersion(), 5);
    });

    test('latestVersion 返回最大 toVersion', () {
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(1, 2, (_) async {}),
        SchemaMigration(2, 3, (_) async {}),
        SchemaMigration(3, 4, (_) async {}),
      ]);
      expect(migrator.latestVersion, 4);
    });

    test('needsMigration 在版本落后时返回 true', () async {
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (_) async {}),
      ]);
      expect(await migrator.needsMigration(), true);
    });

    test('needsMigration 在已是最新时返回 false', () async {
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (_) async {}),
      ]);
      await migrator.setVersion(1);
      expect(await migrator.needsMigration(), false);
    });

    test('migrate 执行迁移并更新版本', () async {
      var executed = false;
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (ctx) async {
          executed = true;
          await ctx.writeJsonFile('test.json', {'migrated': true});
        }),
      ]);

      final count = await migrator.migrate();
      expect(count, 1);
      expect(executed, true);
      expect(await migrator.getCurrentVersion(), 1);

      final file =
          File('${tempDir.path}${Platform.pathSeparator}test.json');
      expect(await file.exists(), true);
      final content = jsonDecode(await file.readAsString());
      expect(content['migrated'], true);
    });

    test('migrate 链式执行多个迁移', () async {
      final order = <int>[];
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (_) async => order.add(1)),
        SchemaMigration(1, 2, (_) async => order.add(2)),
        SchemaMigration(2, 3, (_) async => order.add(3)),
      ]);

      final count = await migrator.migrate();
      expect(count, 3);
      expect(order, [1, 2, 3]);
      expect(await migrator.getCurrentVersion(), 3);
    });

    test('migrate 跳过已完成的迁移', () async {
      await (SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (_) async {}),
      ]))
          .setVersion(1);

      final executed = <int>[];
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (_) async => executed.add(1)),
        SchemaMigration(1, 2, (_) async => executed.add(2)),
      ]);

      final count = await migrator.migrate();
      expect(count, 1);
      expect(executed, [2]);
    });

    test('migrate 失败时回滚到原版本', () async {
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (ctx) async {
          await ctx.writeJsonFile('test.json', {'step': 1});
        }),
        SchemaMigration(1, 2, (_) async {
          throw Exception('迁移失败');
        }),
      ]);

      // 迁移失败应抛出 MigrationException（必须 await 异步异常）
      await expectLater(migrator.migrate(), throwsA(isA<MigrationException>()));
      // 回滚后版本应恢复到失败迁移的起始版本 (v1)
      expect(await migrator.getCurrentVersion(), 1);
    });

    test('getMigrationLog 返回迁移历史', () async {
      final migrator = SchemaMigrator(directory: tempDir, migrations: [
        SchemaMigration(0, 1, (_) async {}),
        SchemaMigration(1, 2, (_) async {}),
      ]);

      await migrator.migrate();
      final log = await migrator.getMigrationLog();
      expect(log.length, 2);
      expect(log[0].fromVersion, 0);
      expect(log[0].toVersion, 1);
      expect(log[0].status, 'success');
    });

    test('迁移链不连续时抛出 StateError', () {
      expect(
        () => SchemaMigrator(directory: tempDir, migrations: [
          SchemaMigration(0, 1, (_) async {}),
          SchemaMigration(2, 3, (_) async {}), // 跳过 1→2
        ]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('MigrationContext', () {
    test('readJsonFile 读取存在的文件', () async {
      final file =
          File('${tempDir.path}${Platform.pathSeparator}data.json');
      await file.writeAsString(jsonEncode({'key': 'value'}));

      final ctx = MigrationContext(
          directory: tempDir, fromVersion: 0, toVersion: 1);
      final data = await ctx.readJsonFile('data.json');
      expect(data, {'key': 'value'});
    });

    test('readJsonFile 不存在的文件返回 null', () async {
      final ctx = MigrationContext(
          directory: tempDir, fromVersion: 0, toVersion: 1);
      final data = await ctx.readJsonFile('nonexistent.json');
      expect(data, isNull);
    });

    test('writeJsonFile 原子写入', () async {
      final ctx = MigrationContext(
          directory: tempDir, fromVersion: 0, toVersion: 1);
      await ctx.writeJsonFile('output.json', {'test': true});
      final file =
          File('${tempDir.path}${Platform.pathSeparator}output.json');
      expect(await file.exists(), true);
      final content = jsonDecode(await file.readAsString());
      expect(content['test'], true);
    });
  });
}
