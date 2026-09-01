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
  });
}
