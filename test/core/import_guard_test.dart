// import_guard.dart 单元测试（drawing_notes_app）。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/import_guard.dart';

void main() {
  group('ImportGuard', () {
    test('初始状态为 idle，无 current token', () {
      final guard = ImportGuard.initial();
      expect(guard.lifecycle, ImportLifecycleState.idle);
      expect(guard.currentToken, isNull);
    });

    test('beginImport 返回 generation=1 的 token 并进入 active', () {
      final guard = ImportGuard.initial();
      final token = guard.beginImport();

      expect(token.generation, 1);
      expect(guard.lifecycle, ImportLifecycleState.active);
      expect(guard.currentToken, token);
      expect(guard.isCurrent(token), isTrue);
      expect(guard.isStale(token), isFalse);
    });

    test('连续两次 beginImport：第一次 token 在第二次后变 stale', () {
      final guard = ImportGuard.initial();
      final first = guard.beginImport();
      final second = guard.beginImport();

      // 第一次 token 已过期
      expect(guard.isStale(first), isTrue);
      expect(guard.isCurrent(first), isFalse);

      // 第二次 token 为 current
      expect(guard.isCurrent(second), isTrue);
      expect(guard.isStale(second), isFalse);
    });

    test('页面退出（invalidateAll）后 complete 旧 token 不生效', () {
      final guard = ImportGuard.initial();
      final token = guard.beginImport();

      guard.invalidateAll();
      expect(guard.lifecycle, ImportLifecycleState.stale);

      // 旧 token 的 complete 被拒绝
      final result = guard.complete(token);
      expect(result, isFalse);
      // guard 仍保持 stale 状态（complete 未生效）
      expect(guard.lifecycle, ImportLifecycleState.stale);
    });

    test('active 中 cancel 生效并进入 cancelled 状态', () {
      final guard = ImportGuard.initial();
      final token = guard.beginImport();

      final result = guard.cancel(token);
      expect(result, isTrue);
      expect(guard.lifecycle, ImportLifecycleState.cancelled);
      expect(guard.currentToken, isNull);
    });

    test('已 stale 的 complete 被拒绝（返回 false）', () {
      final guard = ImportGuard.initial();
      final old = guard.beginImport();
      guard.beginImport(); // 使 old 变 stale

      expect(guard.isStale(old), isTrue);
      final result = guard.complete(old);
      expect(result, isFalse);
    });

    test('generation 严格递增', () {
      final guard = ImportGuard.initial();
      final t1 = guard.beginImport();
      final t2 = guard.beginImport();
      final t3 = guard.beginImport();

      expect(t1.generation, 1);
      expect(t2.generation, 2);
      expect(t3.generation, 3);
      expect(t2.generation > t1.generation, isTrue);
      expect(t3.generation > t2.generation, isTrue);
    });

    test('invalidateAll 后所有历史 token 均为 stale', () {
      final guard = ImportGuard.initial();
      final t1 = guard.beginImport();
      final t2 = guard.beginImport();

      guard.invalidateAll();

      expect(guard.isStale(t1), isTrue);
      expect(guard.isStale(t2), isTrue);
      expect(guard.isCurrent(t1), isFalse);
      expect(guard.isCurrent(t2), isFalse);
    });

    test('complete 后 guard 回到 idle，可再次 beginImport', () {
      final guard = ImportGuard.initial();
      final token = guard.beginImport();

      expect(guard.complete(token), isTrue);
      expect(guard.lifecycle, ImportLifecycleState.idle);
      expect(guard.currentToken, isNull);

      final next = guard.beginImport();
      expect(next.generation, 2);
      expect(guard.lifecycle, ImportLifecycleState.active);
    });

    test('cancel 非 current token 返回 false', () {
      final guard = ImportGuard.initial();
      final old = guard.beginImport();
      guard.beginImport(); // old 变 stale

      final result = guard.cancel(old);
      expect(result, isFalse);
    });

    test('token 的 isCurrent / isStale 实例方法委托给 guard', () {
      final guard = ImportGuard.initial();
      final token = guard.beginImport();

      expect(token.isCurrent(guard), isTrue);
      expect(token.isStale(guard), isFalse);

      guard.beginImport();
      expect(token.isCurrent(guard), isFalse);
      expect(token.isStale(guard), isTrue);
    });

    test('token 相等性：同 generation 相等', () {
      final t1 = ImportRequestToken(5);
      final t2 = ImportRequestToken(5);
      final t3 = ImportRequestToken(6);

      expect(t1 == t2, isTrue);
      expect(t1 == t3, isFalse);
      expect(t1.hashCode == t2.hashCode, isTrue);
    });
  });
}
