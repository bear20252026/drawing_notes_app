/// PM码（胁迫密码）服务测试。
///
/// 验证 PM码 核心功能：
/// 1. 设置 PM码
/// 2. 验证 PM码
/// 3. 修改 PM码
/// 4. 关闭 PM码
/// 5. 销毁真实密钥
///
/// 版权声明：本测试借鉴了以下开源项目的测试模式：
/// - kurpod (github.com/srv1n/kurpod) — AGPL-3.0
/// - Sanctum (github.com/Teycir/Sanctum) — 项目自定义许可
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/interfaces/pm_code_service.dart';
import 'package:drawing_notes_app/features/security/application/pm_code_use_cases.dart';
import 'package:drawing_notes_app/features/security/infrastructure/pm_code_repository_impl.dart';
import 'package:drawing_notes_app/features/security/domain/repositories/pm_code_repository.dart';

void main() {
  late PmCodeRepository repository;
  late PmCodeService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = PmCodeRepositoryImpl();
    service = PmCodeUseCases(repository: repository);
  });

  group('PmCodeService', () {
    test('初始状态：PM码未配置', () async {
      expect(await service.isConfigured(), isFalse);
      expect(await service.isSlotADestroyed(), isFalse);
    });

    test('设置PM码：成功', () async {
      final result = await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );
      expect(result, PmCodeSetupResult.success);
      expect(await service.isConfigured(), isTrue);
    });

    test('设置PM码：与正常密码相同 → 失败', () async {
      final result = await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '123456',
      );
      expect(result, PmCodeSetupResult.sameAsPassword);
    });

    test('设置PM码：太短 → 失败', () async {
      final result = await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '123',
      );
      expect(result, PmCodeSetupResult.tooShort);
    });

    test('验证PM码：正确 → 成功', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final (result, keyChain) = await service.verifyPmCode(pmCode: '654321');
      expect(result, PmCodeVerifyResult.success);
      expect(keyChain, isNotNull);
    });

    test('验证PM码：错误 → 失败', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final (result, keyChain) = await service.verifyPmCode(pmCode: '999999');
      expect(result, PmCodeVerifyResult.wrongPassword);
      expect(keyChain, isNull);
    });

    test('验证PM码：未配置 → notConfigured', () async {
      final (result, keyChain) = await service.verifyPmCode(pmCode: '654321');
      expect(result, PmCodeVerifyResult.notConfigured);
      expect(keyChain, isNull);
    });

    test('修改PM码：成功', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final result = await service.changePmCode(
        oldPmCode: '654321',
        newPmCode: '111111',
      );
      expect(result, PmCodeSetupResult.success);

      // 新PM码可以验证
      final (verifyResult, _) =
          await service.verifyPmCode(pmCode: '111111');
      expect(verifyResult, PmCodeVerifyResult.success);

      // 旧PM码不能验证
      final (oldVerifyResult, _) =
          await service.verifyPmCode(pmCode: '654321');
      expect(oldVerifyResult, PmCodeVerifyResult.wrongPassword);
    });

    test('关闭PM码：成功', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final success = await service.disablePmCode(pmCode: '654321');
      expect(success, isTrue);
      expect(await service.isConfigured(), isFalse);
    });

    test('关闭PM码：PM码错误 → 失败', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final success = await service.disablePmCode(pmCode: '999999');
      expect(success, isFalse);
      expect(await service.isConfigured(), isTrue);
    });

    test('销毁真实密钥：成功', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final destroyed = await service.destroyRealKey(pmCode: '654321');
      expect(destroyed, isTrue);
      expect(await service.isSlotADestroyed(), isTrue);
    });

    test('销毁真实密钥：PM码错误 → 失败', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final destroyed = await service.destroyRealKey(pmCode: '999999');
      expect(destroyed, isFalse);
      expect(await service.isSlotADestroyed(), isFalse);
    });

    test('PM码独立性：不同PM码产生不同指纹', () async {
      await service.setupPmCode(
        currentPassword: '123456',
        pmCode: '654321',
      );

      final (_, keyChain1) = await service.verifyPmCode(pmCode: '654321');
      expect(keyChain1, isNotNull);

      // 修改PM码
      await service.changePmCode(
        oldPmCode: '654321',
        newPmCode: '111111',
      );

      final (_, keyChain2) = await service.verifyPmCode(pmCode: '111111');
      expect(keyChain2, isNotNull);

      // 两个密钥链应该不同
      final bytes1 = await keyChain1!.$2.extractBytes();
      final bytes2 = await keyChain2!.$2.extractBytes();
      expect(bytes1, isNot(equals(bytes2)));
    });
  });
}
