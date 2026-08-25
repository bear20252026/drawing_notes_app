// Schema migration + crypto utility tests.
import 'package:editor_core/editor_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SchemaMigrationManager', () {
    late SchemaMigrationManager manager;

    setUp(() {
      manager = SchemaMigrationManager();
    });

    test('currentVersion returns current schema version', () {
      expect(manager.currentVersion, greaterThan(0));
    });

    test('needsMigration returns false for current version', () {
      final doc = <String, dynamic>{
        'schemaVersion': manager.currentVersion,
      };
      expect(manager.needsMigration(doc), isFalse);
    });

    test('needsMigration returns true for older version', () {
      final doc = <String, dynamic>{
        'schemaVersion': 1,
      };
      expect(manager.needsMigration(doc), isTrue);
    });

    test('migrateToLatest updates schema version', () {
      final doc = <String, dynamic>{
        'schemaVersion': 1,
        'title': 'Test',
      };
      final migrated = manager.migrateToLatest(doc);
      expect(migrated['schemaVersion'], manager.currentVersion);
    });

    test('migrateToLatest preserves existing fields', () {
      final doc = <String, dynamic>{
        'schemaVersion': 1,
        'title': 'My Document',
        'layers': <dynamic>[],
      };
      final migrated = manager.migrateToLatest(doc);
      expect(migrated['title'], 'My Document');
      expect(migrated['layers'], isA<List>());
    });
  });

  group('sha256Hex', () {
    test('returns consistent hash for same input', () {
      final hash1 = sha256Hex([1, 2, 3]);
      final hash2 = sha256Hex([1, 2, 3]);
      expect(hash1, equals(hash2));
    });

    test('returns 64-char hex string', () {
      final hash = sha256Hex([0]);
      expect(hash.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
    });

    test('different input produces different hash', () {
      final hash1 = sha256Hex([1]);
      final hash2 = sha256Hex([2]);
      expect(hash1, isNot(equals(hash2)));
    });

    test('empty input produces valid hash', () {
      final hash = sha256Hex([]);
      expect(hash.length, equals(64));
    });
  });

  group('deriveKeyFromPassword', () {
    test('returns 32-byte key', () {
      final key = deriveKeyFromPassword(password: 'test');
      expect(key.length, equals(32));
    });

    test('same password produces same key', () {
      final key1 = deriveKeyFromPassword(password: 'hello');
      final key2 = deriveKeyFromPassword(password: 'hello');
      expect(key1, equals(key2));
    });

    test('different passwords produce different keys', () {
      final key1 = deriveKeyFromPassword(password: 'pass1');
      final key2 = deriveKeyFromPassword(password: 'pass2');
      expect(key1, isNot(equals(key2)));
    });

    test('different rounds produce different keys', () {
      final key1 = deriveKeyFromPassword(password: 'test', rounds: 1);
      final key2 = deriveKeyFromPassword(password: 'test', rounds: 5);
      expect(key1, isNot(equals(key2)));
    });
  });

  group('secureRandomBytes', () {
    test('returns requested length', () {
      final bytes = secureRandomBytes(32);
      expect(bytes.length, equals(32));
    });

    test('returns different values on each call', () {
      final bytes1 = secureRandomBytes(16);
      final bytes2 = secureRandomBytes(16);
      expect(bytes1, isNot(equals(bytes2)));
    });

    test('zero length returns empty', () {
      final bytes = secureRandomBytes(0);
      expect(bytes.length, equals(0));
    });

    test('supports various lengths', () {
      expect(secureRandomBytes(1).length, equals(1));
      expect(secureRandomBytes(64).length, equals(64));
      expect(secureRandomBytes(256).length, equals(256));
    });
  });

  group('DataIntegrityChecker', () {
    test('hashDocument returns consistent hash', () {
      final doc = <String, dynamic>{
        'title': 'Test',
        'layers': <dynamic>[],
      };
      final hash1 = DataIntegrityChecker.hashDocument(doc);
      final hash2 = DataIntegrityChecker.hashDocument(doc);
      expect(hash1, equals(hash2));
    });

    test('hashDocument returns non-empty hash', () {
      final doc = <String, dynamic>{'title': 'Test'};
      final hash = DataIntegrityChecker.hashDocument(doc);
      expect(hash.isNotEmpty, isTrue);
    });
  });
}
