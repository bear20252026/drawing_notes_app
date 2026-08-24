// editor_core——BackupService 测试（自动备份+恢复+版本管理+完整性校验）。

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:editor_core/src/domain/backup_service.dart';

void main() {
  group('SemanticVersion', () {
    test('parse version string', () {
      final v = SemanticVersion.parse('1.2.3');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.preRelease, '');
      expect(v.buildMetadata, '');
    });

    test('parse version with preRelease', () {
      final v = SemanticVersion.parse('1.2.3-beta');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.preRelease, 'beta');
    });

    test('parse version with build metadata', () {
      final v = SemanticVersion.parse('1.2.3+build.123');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.buildMetadata, 'build.123');
    });

    test('parse version with preRelease and build metadata', () {
      final v = SemanticVersion.parse('1.2.3-beta+build.123');
      expect(v.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
      expect(v.preRelease, 'beta');
      expect(v.buildMetadata, 'build.123');
    });

    test('version string output', () {
      final v = SemanticVersion(major: 1, minor: 2, patch: 3);
      expect(v.version, '1.2.3');
      expect(v.fullVersion, '1.2.3');
    });

    test('version string with preRelease', () {
      final v = SemanticVersion(
        major: 1,
        minor: 2,
        patch: 3,
        preRelease: 'beta',
      );
      expect(v.version, '1.2.3-beta');
    });

    test('incrementMajor', () {
      final v = SemanticVersion(major: 1, minor: 2, patch: 3);
      final v2 = v.incrementMajor();
      expect(v2.major, 2);
      expect(v2.minor, 0);
      expect(v2.patch, 0);
    });

    test('incrementMinor', () {
      final v = SemanticVersion(major: 1, minor: 2, patch: 3);
      final v2 = v.incrementMinor();
      expect(v2.major, 1);
      expect(v2.minor, 3);
      expect(v2.patch, 0);
    });

    test('incrementPatch', () {
      final v = SemanticVersion(major: 1, minor: 2, patch: 3);
      final v2 = v.incrementPatch();
      expect(v2.major, 1);
      expect(v2.minor, 2);
      expect(v2.patch, 4);
    });

    test('compareTo', () {
      final v1 = SemanticVersion(major: 1, minor: 0, patch: 0);
      final v2 = SemanticVersion(major: 2, minor: 0, patch: 0);
      final v3 = SemanticVersion(major: 1, minor: 1, patch: 0);

      expect(v1.compareTo(v2), lessThan(0));
      expect(v2.compareTo(v1), greaterThan(0));
      expect(v1.compareTo(v3), lessThan(0));
      expect(v1.compareTo(v1), 0);
    });

    test('equality', () {
      final v1 = SemanticVersion(major: 1, minor: 2, patch: 3);
      final v2 = SemanticVersion(major: 1, minor: 2, patch: 3);
      final v3 = SemanticVersion(major: 1, minor: 2, patch: 4);

      expect(v1, equals(v2));
      expect(v1, isNot(equals(v3)));
    });
  });

  group('BackupMetadata', () {
    test('toJson and fromJson roundtrip', () {
      final original = BackupMetadata(
        id: 'backup-123',
        version: const SemanticVersion(major: 1, minor: 2, patch: 3),
        createdAt: DateTime(2026, 8, 24),
        status: BackupStatus.completed,
        sha256: 'abc123',
        sizeBytes: 1024,
        frequency: BackupFrequency.daily,
        description: 'Test backup',
        tags: ['important', 'daily'],
      );

      final json = original.toJson();
      final restored = BackupMetadata.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.version, original.version);
      expect(restored.status, original.status);
      expect(restored.sha256, original.sha256);
      expect(restored.sizeBytes, original.sizeBytes);
      expect(restored.frequency, original.frequency);
      expect(restored.description, original.description);
      expect(restored.tags, original.tags);
    });
  });

  group('BackupData', () {
    test('verifyIntegrity succeeds for valid backup', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sha = 'e41724a43e98e15598c335afa40e9fcf3c78c1970b038572ba2c42e69ac67e39'; // SHA-256 of [1,2,3,4,5]
      
      final metadata = BackupMetadata(
        id: 'test',
        version: const SemanticVersion(major: 1, minor: 0, patch: 0),
        createdAt: DateTime.now(),
        status: BackupStatus.completed,
        sha256: sha,
      );

      final backup = BackupData(metadata: metadata, payload: data);
      expect(backup.verifyIntegrity(), true);
    });

    test('verifyIntegrity fails for corrupted backup', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = BackupMetadata(
        id: 'test',
        version: const SemanticVersion(major: 1, minor: 0, patch: 0),
        createdAt: DateTime.now(),
        status: BackupStatus.completed,
        sha256: 'wrong-hash',
      );

      final backup = BackupData(metadata: metadata, payload: data);
      expect(backup.verifyIntegrity(), false);
    });
  });

  group('BackupService', () {
    late BackupService service;
    late InMemoryBackupStorage storage;

    setUp(() {
      storage = InMemoryBackupStorage();
      service = BackupService(storage: storage);
    });

    test('createBackup without encryption', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = await service.createBackup(
        data: data,
        encrypt: false,
        description: 'Test backup',
      );

      expect(metadata.status, BackupStatus.completed);
      expect(metadata.description, 'Test backup');
      expect(metadata.sha256, isNotEmpty);
    });

    test('createBackup with encryption', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = await service.createBackup(
        data: data,
        encrypt: true,
        password: 'test-password',
        description: 'Encrypted backup',
      );

      expect(metadata.status, BackupStatus.completed);
      expect(metadata.description, 'Encrypted backup');
    });

    test('restoreBackup without decryption', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = await service.createBackup(
        data: data,
        encrypt: false,
      );

      final result = await service.restoreBackup(backupId: metadata.id);
      expect(result.success, true);
      expect(result.restoredVersion, service.currentVersion);
    });

    test('restoreBackup with decryption', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = await service.createBackup(
        data: data,
        encrypt: true,
        password: 'test-password',
      );

      final result = await service.restoreBackup(
        backupId: metadata.id,
        password: 'test-password',
      );
      expect(result.success, true);
    });

    test('restoreBackup fails with wrong password', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = await service.createBackup(
        data: data,
        encrypt: true,
        password: 'correct-password',
      );

      final result = await service.restoreBackup(
        backupId: metadata.id,
        password: 'wrong-password',
      );
      expect(result.success, false);
      expect(result.message.contains('Decryption failed'), true);
    });

    test('restoreBackup fails for non-existent backup', () async {
      final result = await service.restoreBackup(backupId: 'non-existent');
      expect(result.success, false);
      expect(result.message, 'Backup not found');
    });

    test('listBackups returns all backups', () async {
      await service.createBackup(
        data: Uint8List.fromList([1]),
        encrypt: false,
      );
      await service.createBackup(
        data: Uint8List.fromList([2]),
        encrypt: false,
      );

      final backups = await service.listBackups();
      expect(backups.length, 2);
    });

    test('deleteBackup removes backup', () async {
      final metadata = await service.createBackup(
        data: Uint8List.fromList([1]),
        encrypt: false,
      );

      await service.deleteBackup(metadata.id);
      final backups = await service.listBackups();
      expect(backups.isEmpty, true);
    });

    test('verifyBackup succeeds for valid backup', () async {
      final metadata = await service.createBackup(
        data: Uint8List.fromList([1, 2, 3]),
        encrypt: false,
      );

      final isValid = await service.verifyBackup(metadata.id);
      expect(isValid, true);
    });

    test('backup rotation keeps maxBackups', () async {
      // Create more backups than maxBackups
      for (var i = 0; i < 15; i++) {
        await service.createBackup(
          data: Uint8List.fromList([i]),
          encrypt: false,
        );
      }

      final backups = await service.listBackups();
      expect(backups.length, defaultMaxBackups);
    });

    test('version management', () {
      expect(service.currentVersion, const SemanticVersion(major: 1, minor: 0, patch: 0));

      service.incrementPatch();
      expect(service.currentVersion, const SemanticVersion(major: 1, minor: 0, patch: 1));

      service.incrementMinor();
      expect(service.currentVersion, const SemanticVersion(major: 1, minor: 1, patch: 0));

      service.incrementMajor();
      expect(service.currentVersion, const SemanticVersion(major: 2, minor: 0, patch: 0));
    });
  });
}
