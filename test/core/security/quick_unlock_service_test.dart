// ============================================================================
// quick_unlock_service_test.dart —— 系统验证快速解锁回归测试（批D1）
// ============================================================================
//
// 口径（用户 2026-09-02 拍板）：快速解锁**仅作用于开屏锁**；文件密码
// 不参与（文件密码 KEK 从不进入系统解锁密钥库——本测试同时锁定该边界：
// 开关副本只与保险库 MK 同源）。
//
// 覆盖：开关持久化 / 副本生命周期（开=存、关=删）/ 系统验证门槛
// （fail-closed）/ 副本注入保险库 / 锁屏门按钮显隐。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_gate.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 可编程假系统验证后端（代替 local_auth——测试环境无插件注册）。
class FakeAuthBackend implements SystemAuthBackend {
  FakeAuthBackend({this.supported = true, this.authenticateResult = true});

  bool supported;
  bool authenticateResult;
  int authenticateCalls = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    authenticateCalls++;
    return authenticateResult;
  }
}

VaultKeyService _tempVault() {
  final dir = Directory.systemTemp.createTempSync('quick_unlock_test');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return VaultKeyService(
    vaultFileResolver: () async =>
        File('${dir.path}${Platform.pathSeparator}vault.key.json'),
  );
}

QuickUnlockService _service(
  FakeAuthBackend backend,
  MemorySystemUnlockKeyStore store,
) {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return QuickUnlockService(
    backend: backend,
    keyStore: store,
    preferencesLoader: SharedPreferences.getInstance,
    // CI 的 Linux runner 上真实 Platform 门恒 false——注入与 OS 解耦。
    platformSupported: () => true,
  );
}

void main() {
  setUp(() {
    // 批B 约定：测试注入轻量 KDF（Argon2id 生产档 348ms/次不可接受）。
    KdfParams.newSlotDefault = KdfParams.testLight;
    // P0 连带：开屏 PIN 同样走 isolate 派生，widget 组在 FakeAsync 下
    // 后台结果永不回投——同 isolate 直派生防挂起（生产路径不受影响）。
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
  });

  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  group('QuickUnlockService 开关与副本生命周期', () {
    test('开启：系统验证通过 → 存 MK 副本 + 持久化开关 + isReady', () async {
      final backend = FakeAuthBackend();
      final store = MemorySystemUnlockKeyStore();
      final service = _service(backend, store);
      final vault = _tempVault();

      expect(await service.isReady(), isFalse);

      await vault.initialize('1234');
      await service.enable(pin: '1234', vault: vault);

      expect(await service.isEnabled(), isTrue);
      expect(await service.isReady(), isTrue);
      expect(backend.authenticateCalls, 1);
      // 副本已存在（内容为 base64 的 32B MK，可还原）。
      final encoded = await store.read();
      expect(encoded, isNotNull);
      expect(base64Decode(encoded!), vault.masterKey);
    });

    test('系统验证未通过：抛异常且不落任何副本（fail-closed）', () async {
      final backend = FakeAuthBackend(authenticateResult: false);
      final store = MemorySystemUnlockKeyStore();
      final service = _service(backend, store);
      final vault = _tempVault()..debugInjectMasterKey(List.filled(32, 7));

      await expectLater(
        service.enable(pin: '1234', vault: vault),
        throwsA(isA<QuickUnlockException>()),
      );
      expect(await store.contains(), isFalse);
      expect(await service.isEnabled(), isFalse);
      expect(await service.isReady(), isFalse);
    });

    test('关闭：副本立即删除（关=删，无残留）', () async {
      final backend = FakeAuthBackend();
      final store = MemorySystemUnlockKeyStore();
      final service = _service(backend, store);
      final vault = _tempVault();

      await vault.initialize('1234');
      await service.enable(pin: '1234', vault: vault);
      expect(await service.isReady(), isTrue);

      await service.disable();
      expect(await store.contains(), isFalse);
      expect(await service.isEnabled(), isFalse);
      expect(await service.isReady(), isFalse);
    });

    test('后端不支持（无硬件/系统未配置）：开启被拒绝', () async {
      final backend = FakeAuthBackend(supported: false);
      final service = _service(backend, MemorySystemUnlockKeyStore());
      final vault = _tempVault()..debugInjectMasterKey(List.filled(32, 7));

      await expectLater(
        service.enable(pin: '1234', vault: vault),
        throwsA(isA<QuickUnlockException>()),
      );
    });
  });

  group('authenticateAndUnlock（锁屏一键解锁）', () {
    test('成功路径：副本注入保险库（isUnlocked + 密钥一致）', () async {
      final backend = FakeAuthBackend();
      final service = _service(backend, MemorySystemUnlockKeyStore());
      final vault = _tempVault();

      await vault.initialize('1234');
      final mk = vault.masterKey;
      // 模拟真实生命周期：锁定后仅靠副本恢复。
      vault.lock();
      expect(vault.isUnlocked, isFalse);

      await service.enable(pin: '1234', vault: vault);
      final ok = await service.authenticateAndUnlock(vault: vault);

      expect(ok, isTrue);
      expect(vault.isUnlocked, isTrue);
      expect(vault.masterKey, mk);
    });

    test('系统验证未通过：返回 false 且保险库保持锁定', () async {
      final backend = FakeAuthBackend();
      final service = _service(backend, MemorySystemUnlockKeyStore());
      final vault = _tempVault();

      await vault.initialize('1234');
      await service.enable(pin: '1234', vault: vault);
      vault.lock();
      // 解锁阶段验证不过（开启时已验证过一次——两次验证独立发生）。
      backend.authenticateResult = false;

      final ok = await service.authenticateAndUnlock(vault: vault);

      expect(ok, isFalse);
      expect(vault.isUnlocked, isFalse);
    });

    test('副本缺失（被外部清掉）：返回 false，不崩溃', () async {
      final backend = FakeAuthBackend();
      final store = MemorySystemUnlockKeyStore();
      final service = _service(backend, store);
      final vault = _tempVault();

      await vault.initialize('1234');
      await service.enable(pin: '1234', vault: vault);
      vault.lock();
      await store.clear();

      expect(await service.authenticateAndUnlock(vault: vault), isFalse);
      expect(vault.isUnlocked, isFalse);
    });

    test('开关未开（未 enable 过）：直接返回 false', () async {
      final service = _service(FakeAuthBackend(), MemorySystemUnlockKeyStore());
      final vault = _tempVault();

      expect(await service.authenticateAndUnlock(vault: vault), isFalse);
      expect(vault.isUnlocked, isFalse);
    });
  });

  group('VaultKeyService.adoptMasterKey', () {
    test('注入后进入解锁态且密钥一致；lock() 擦除', () {
      final vault = _tempVault();
      final key = List<int>.generate(32, (i) => i);

      expect(vault.isUnlocked, isFalse);
      vault.adoptMasterKey(key);
      expect(vault.isUnlocked, isTrue);
      expect(vault.masterKey, key);

      // 注入的是独立拷贝：外部修改原列表不影响保险库。
      key[0] = 99;
      expect(vault.masterKey[0], isNot(99));

      vault.lock();
      expect(vault.isUnlocked, isFalse);
    });
  });

  group('AppLockGate 快速解锁按钮', () {
    // 注意：testWidgets 运行在 FakeAsync zone——真实 isolate KDF
    // （vault.initialize）永远无法完成，必须用 debugInjectMasterKey +
    // 预置副本绕开（KDF 正确性由上方纯 test 单元用例覆盖）。

    testWidgets('就绪时锁屏出现「系统验证解锁」按钮，点击直接解锁', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_lock.quick_unlock_enabled': true,
      });
      final service = AppLockService(
        preferencesLoader: SharedPreferences.getInstance,
      );
      await service.setPin('1234');

      final vault = _tempVault();
      final mk = List<int>.generate(32, (i) => i + 1);
      vault.debugInjectMasterKey(mk);
      final store = MemorySystemUnlockKeyStore();
      await store.write(base64Encode(mk));

      final quickUnlock = QuickUnlockService(
        backend: FakeAuthBackend(),
        keyStore: store,
        preferencesLoader: SharedPreferences.getInstance,
        platformSupported: () => true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockGate(
            service: service,
            vault: vault,
            quickUnlock: quickUnlock,
            child: const Text('SECRET_HOME'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('输入密码'), findsOneWidget);
      expect(find.text('系统验证解锁'), findsOneWidget);

      // 走快速解锁：系统验证通过 → 副本注入 → 直接进入主页。
      await tester.tap(find.text('系统验证解锁'));
      await tester.pumpAndSettle();
      expect(find.text('SECRET_HOME'), findsOneWidget);
      expect(find.text('输入密码'), findsNothing);
      expect(vault.isUnlocked, isTrue);
    });

    testWidgets('未就绪（开关关）时按钮不出现，仅 PIN 通道', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = AppLockService(
        preferencesLoader: SharedPreferences.getInstance,
      );
      final quickUnlock = QuickUnlockService(
        backend: FakeAuthBackend(),
        keyStore: MemorySystemUnlockKeyStore(),
        preferencesLoader: SharedPreferences.getInstance,
        platformSupported: () => true,
      );
      final vault = _tempVault();
      await service.setPin('1234');

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockGate(
            service: service,
            vault: vault,
            quickUnlock: quickUnlock,
            child: const Text('SECRET_HOME'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('输入密码'), findsOneWidget);
      expect(find.text('系统验证解锁'), findsNothing);
    });
  });
}
