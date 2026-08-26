import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/auth/application/auth_service.dart';
import 'package:drawing_notes_app/features/auth/domain/value_objects/auth_result.dart';
import 'package:drawing_notes_app/features/auth/infrastructure/auth_repository_impl.dart';

void main() {
  group('AuthService', () {
    late AuthRepositoryImpl repository;
    late AuthService service;

    setUp(() {
      repository = AuthRepositoryImpl();
      service = AuthService(repository);
    });

    test('初始状态：未配置', () {
      expect(service.isConfigured, false);
      expect(service.requiresAuth, false);
    });

    test('AuthResult 密封类正确工作', () {
      const success = AuthSuccess();
      const failure = AuthFailure(reason: AuthFailureReason.invalidCredentials);

      expect(success.isSuccess, true);
      expect(success.isFailure, false);
      expect(failure.isSuccess, false);
      expect(failure.isFailure, true);
    });

    test('AuthFailureReason 枚举值正确', () {
      expect(AuthFailureReason.values.length, 7);
      expect(AuthFailureReason.invalidCredentials, isNotNull);
      expect(AuthFailureReason.locked, isNotNull);
      expect(AuthFailureReason.biometricUnavailable, isNotNull);
      expect(AuthFailureReason.biometricFailed, isNotNull);
      expect(AuthFailureReason.notConfigured, isNotNull);
      expect(AuthFailureReason.alreadyConfigured, isNotNull);
      expect(AuthFailureReason.unknown, isNotNull);
    });
  });
}
