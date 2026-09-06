// ============================================================================
// app_lock_service_test.dart —— 应用启动锁服务回归测试（2026-09-01）
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLockService', () {
    test('未配置时 verify 恒为 false', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.load();
      expect(service.isConfigured, isFalse);
      expect(await service.verify('1234'), isFalse);
    });

    test('setPin 后：正确 PIN 通过、错误 PIN 拒绝，且明文不落盘', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.setPin('9527');

      expect(service.isConfigured, isTrue);
      expect(await service.verify('9527'), isTrue);
      expect(await service.verify('0000'), isFalse);
      expect(await service.verify('95271'), isFalse);

      // 安全底线：shared_preferences 中不得出现 PIN 明文。
      final prefs = await SharedPreferences.getInstance();
      final values = prefs
          .getKeys()
          .map((k) => prefs.get(k))
          .whereType<String>()
          .toList();
      expect(values.contains('9527'), isFalse);
      expect(prefs.getKeys().any((k) => k.contains('app_lock')), isTrue);
    });

    test('disable 后恢复未配置且 verify 拒绝', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.setPin('1111');
      await service.disable();

      expect(service.isConfigured, isFalse);
      expect(await service.verify('1111'), isFalse);
    });

    test('新实例 load() 从持久化恢复已配置状态（冷启动路径）', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = AppLockService();
      await writer.setPin('2468');

      // 模拟冷启动：全新 service 实例从同一持久化层 load。
      final cold = AppLockService();
      expect(cold.isConfigured, isFalse);
      await cold.load();
      expect(cold.isConfigured, isTrue);
      expect(await cold.verify('2468'), isTrue);
    });

    test('覆盖 setPin：旧 PIN 失效，新 PIN 生效', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.setPin('1111');
      await service.setPin('2222');

      expect(await service.verify('1111'), isFalse);
      expect(await service.verify('2222'), isTrue);
    });

    test('批次②：setPin 记录长度，新实例 load 后 pinLength 恢复（6 位）', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = AppLockService();
      expect(writer.pinLength, AppLockService.defaultPinLength);
      await writer.setPin('135790'); // 6 位

      final cold = AppLockService();
      await cold.load();
      expect(cold.pinLength, 6);
      expect(await cold.verify('135790'), isTrue);
    });

    test('批次②：setPin 断言 4–12 位边界', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      expect(() => service.setPin('123'), throwsA(isA<AssertionError>()));
      expect(
        () => service.setPin('1234567890123'), // 13 位
        throwsA(isA<AssertionError>()),
      );
    });

    test('批次②：disable 后 pinLength 回到默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.setPin('12345678');
      await service.disable();
      expect(service.pinLength, AppLockService.defaultPinLength);
    });

    test('批次②：matchesAppLockPin——同码探测（≠开屏密码强制的底层）', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = AppLockService();
      await writer.setPin('9527');

      // 同码 → true；不同码 → false；未配置 → false。
      expect(await AppLockService.matchesAppLockPin('9527'), isTrue);
      expect(await AppLockService.matchesAppLockPin('9528'), isFalse);

      await writer.disable();
      expect(await AppLockService.matchesAppLockPin('9527'), isFalse);
    });

    test('宽限期：默认 30s，新实例 load 恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = AppLockService();
      await writer.setPin('1357');

      // 默认值（setPin 不触碰宽限）。
      expect(writer.graceDuration, const Duration(seconds: 30));

      // 模拟冷启动：新实例恢复持久化的宽限值。
      await writer.setGraceSeconds(60);
      final cold = AppLockService();
      await cold.load();
      expect(cold.graceDuration, const Duration(minutes: 1));
    });

    test('宽限期：档位 0/30/60/300 合法，其余拒绝；0 = 关闭', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.load();

      for (final seconds in AppLockService.graceChoices) {
        await service.setGraceSeconds(seconds);
        expect(service.graceDuration, Duration(seconds: seconds));
      }
      // 0 表示关闭（切后台立即锁定，即旧行为）。
      await service.setGraceSeconds(0);
      expect(service.graceDuration, Duration.zero);

      expect(() => service.setGraceSeconds(45), throwsArgumentError);
    });

    test('宽限期：损坏/越界持久值回默认 30s', () async {
      SharedPreferences.setMockInitialValues({'app_lock.grace_seconds': 999});
      final service = AppLockService();
      await service.load();
      expect(service.graceDuration, const Duration(seconds: 30));
    });
  });
}
