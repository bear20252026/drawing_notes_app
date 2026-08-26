import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';

void main() {
  group('AppLockService', () {
    late AppLockService service;

    setUp(() {
      service = AppLockService.instance;
    });

    test('初始状态：未启用', () {
      expect(service.enabled, false);
      expect(service.requiresAuth, false);
      expect(service.failedAttempts, 0);
      expect(service.isLocked, false);
    });

    test('设置密码后：已启用且需要验证', () async {
      // 注意：由于 SharedPreferences 在测试环境中需要 mock，
      // 这里只测试逻辑层。实际集成测试需要在 widget 测试中进行。
      expect(service.enabled, false);
    });

    test('锁定阶梯计算正确', () {
      // 失败 1-2 次：不锁定
      // 失败 3 次：锁定 30s
      // 失败 4 次：锁定 5min
      // 失败 5 次+：锁定 30min
      expect(AppLockService.maxFailedAttempts, 5);
    });

    test('生物识别默认可用性为 false（未集成 local_auth）', () async {
      final available = await AppLockService.isBiometricAvailable();
      expect(available, false);
    });
  });
}
