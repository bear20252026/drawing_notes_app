// ============================================================================
// app_lock_guard_test.dart —— 防爆破守卫回归测试（批次③ 2026-09-01）
// ============================================================================
//
// 覆盖：失败计数、第 10 次起指数冷却与封顶、冷却期内拒绝、成功清零、
// 持久化恢复（重启不清零）、时钟回拨无效（单调钟+高水位线）、
// 记录被篡改 fail-closed、冷却期内尝试不延长冷却。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_guard.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';

/// 可手动推进的假时钟（起点取真实当前时间，保证高于任何真实系统时间
/// 之外的干扰——trustedNow 取 max，假时钟必须占主导）。
class FakeClock {
  FakeClock(DateTime start) : ms = start.millisecondsSinceEpoch;
  int ms;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms);

  /// 推进 n 毫秒并返回推进后的毫秒值。
  int advance(int milliseconds) {
    ms += milliseconds;
    return ms;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 本文件用假时钟建模冷却时间（advance 精确跨段），要求 KDF 零真实耗时——
  // 否则生产 Argon2id 的真实耗时爬行（单调钟取 max）会击穿假时钟推进量，
  // 锁还“剩”着，正确 PIN 照样被拒（行为正确，测试时钟模型失效）。
  // 轻量档 + 同 isolate 直派生；真实迁移链由 app_lock_service_test 覆盖。
  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  // 冷却基准取 10 秒：远大于测试过程的真实时间流逝（单调钟爬行），
  // 保证「仍在冷却」的断言稳定；推进假时钟即可跨过冷却期。
  const base = Duration(seconds: 10);
  const cap = Duration(seconds: 30);

  /// 跨过冷却期的安全余量：trustedNow = max(假时钟, 真实单调钟, 高水位线)，
  /// 真实单调钟随测试真实耗时爬行（秒级），余量必须盖过它。
  const skip = Duration(seconds: 5);

  (FakeClock, AppLockService) makeService({SharedPreferences? prefs}) {
    final clock = FakeClock(DateTime.now());
    final secret = VaultKeyService.randomBytes(32);
    final guard = LockoutGuard(
      clock: clock.call,
      lockoutBase: base,
      lockoutCap: cap,
      secretLoader: () async => secret,
    );
    final service = AppLockService(
      preferencesLoader: () async => prefs ?? SharedPreferences.getInstance(),
      guard: guard,
    );
    return (clock, service);
  }

  Future<void> failNTimes(AppLockService service, String pin, int n) async {
    for (var i = 0; i < n; i++) {
      expect(await service.verify('wrong-${i}_$pin'), isFalse);
    }
  }

  test('失败 9 次不锁定；第 10 次失败起进入冷却，正确 PIN 也被拒', () async {
    SharedPreferences.setMockInitialValues({});
    final (clock, service) = makeService();
    await service.setPin('135790');

    await failNTimes(service, '135790', 9);
    expect(service.isLockedOut, isFalse);
    expect(service.failedAttempts, 9);

    // 第 10 次（仍为错误 PIN）：锁定开始。
    expect(await service.verify('wrong-10th'), isFalse);
    expect(service.isLockedOut, isTrue);
    expect(service.lockoutRemaining, greaterThan(Duration.zero));
    expect(service.lockoutRemaining, lessThanOrEqualTo(base));

    // 冷却期内连正确 PIN 也拒绝（fail-closed）。
    expect(await service.verify('135790'), isFalse);
    expect(service.isLockedOut, isTrue);
    clock.advance(base.inMilliseconds + skip.inMilliseconds);
    expect(await service.verify('135790'), isTrue);
  });

  test('指数递增：10 次→1×base，11 次→2×base，第 12 次起触顶封顶', () async {
    SharedPreferences.setMockInitialValues({});
    final (clock, service) = makeService();
    await service.setPin('135790');

    await failNTimes(service, '135790', 10);
    expect(service.isLockedOut, isTrue);
    expect(service.lockoutRemaining.inSeconds, inInclusiveRange(9, 10));

    // 跨过第一段冷却，第 11 次失败（错误 PIN）→ 2×base。
    clock.advance(base.inMilliseconds + skip.inMilliseconds);
    expect(await service.verify('wrong-11th'), isFalse);
    expect(service.lockoutRemaining.inSeconds, inInclusiveRange(19, 20));
    // 第二段冷却期内正确 PIN 同样被拒。
    expect(await service.verify('135790'), isFalse);

    // 再跨过，第 12 次 → 4×base = 40s，已被 30s cap 封顶。
    clock.advance(2 * base.inMilliseconds + skip.inMilliseconds);
    expect(await service.verify('wrong-12th'), isFalse);
    expect(service.lockoutRemaining.inSeconds, inInclusiveRange(29, 30));

    // 封顶冷却结束后正确 PIN 可通过。
    clock.advance(cap.inMilliseconds + skip.inMilliseconds);
    expect(await service.verify('135790'), isTrue);
  });

  test('成功解锁清零计数：9 次失败 → 成功 → 再失败 9 次仍不锁定', () async {
    SharedPreferences.setMockInitialValues({});
    final (_, service) = makeService();
    await service.setPin('135790');

    await failNTimes(service, '135790', 9);
    expect(await service.verify('135790'), isTrue);
    expect(service.failedAttempts, 0);

    await failNTimes(service, '135790', 9);
    expect(service.isLockedOut, isFalse);
  });

  test('重启恢复：失败计数与冷却期跨实例持久化（重启不清零）', () async {
    SharedPreferences.setMockInitialValues({});
    final clock = FakeClock(DateTime.now());
    final secret = VaultKeyService.randomBytes(32);
    Future<List<int>> secretLoader() async => secret;
    Future<SharedPreferences> prefsLoader() async =>
        SharedPreferences.getInstance();

    final service1 = AppLockService(
      preferencesLoader: prefsLoader,
      guard: LockoutGuard(
        clock: clock.call,
        lockoutBase: base,
        lockoutCap: cap,
        secretLoader: secretLoader,
      ),
    );
    await service1.setPin('135790');
    await failNTimes(service1, '135790', 10);
    expect(service1.isLockedOut, isTrue);

    // 模拟重启：全新 service + 全新 guard 实例（同一持久化层 + 同一密钥）。
    final service2 = AppLockService(
      preferencesLoader: prefsLoader,
      guard: LockoutGuard(
        clock: clock.call,
        lockoutBase: base,
        lockoutCap: cap,
        secretLoader: secretLoader,
      ),
    );
    await service2.load();
    expect(service2.isConfigured, isTrue);
    expect(service2.failedAttempts, 10);
    expect(service2.isLockedOut, isTrue);
    // 时钟未推进 → 冷却仍在（高水位线兜底）。
    expect(await service2.verify('135790'), isFalse);

    clock.advance(base.inMilliseconds + skip.inMilliseconds);
    expect(await service2.verify('135790'), isTrue);
  });

  test('时钟回拨无效：冷却期内把系统时钟调到过去，冷却不缩短', () async {
    SharedPreferences.setMockInitialValues({});
    final (clock, service) = makeService();
    await service.setPin('135790');

    await failNTimes(service, '135790', 10);
    final remainingBefore = service.lockoutRemaining;
    expect(remainingBefore, greaterThan(Duration.zero));

    // 把「系统时钟」大幅回拨（模拟改设备时间绕过冷却）。
    clock.ms -= const Duration(days: 30).inMilliseconds;

    // 单调钟 + 高水位线兜底：冷却状态不变。
    expect(service.isLockedOut, isTrue);
    expect(await service.verify('135790'), isFalse);
  });

  test('冷却期内的失败尝试不延长冷却', () async {
    SharedPreferences.setMockInitialValues({});
    final (clock, service) = makeService();
    await service.setPin('135790');

    await failNTimes(service, '135790', 10);
    expect(service.isLockedOut, isTrue);

    // 冷却期内反复尝试：剩余时间只应自然减少，不应重置/延长。
    for (var i = 0; i < 5; i++) {
      expect(await service.verify('135790'), isFalse);
    }
    expect(service.isLockedOut, isTrue);
    expect(service.lockoutRemaining, lessThanOrEqualTo(base));
    expect(
      service.lockoutRemaining,
      greaterThan(base - const Duration(seconds: 3)),
    );

    clock.advance(base.inMilliseconds + skip.inMilliseconds);
    expect(await service.verify('135790'), isTrue);
  });

  test('记录被篡改（签名不合法）→ fail-closed 进入最长冷却', () async {
    SharedPreferences.setMockInitialValues({
      'app_lock.guard.record': '{"c":0,"u":0,"hw":0}', // 伪造的干净记录
      'app_lock.guard.sig': 'deadbeef', // 非法签名
    });
    final (_, service) = makeService();
    await service.setPin('135790');
    await service.load();

    expect(service.isLockedOut, isTrue);
    expect(service.lockoutRemaining, lessThanOrEqualTo(cap));
    expect(await service.verify('135790'), isFalse);
  });

  test('disable 清除守卫记录：关闭应用锁后冷却状态一并消失', () async {
    SharedPreferences.setMockInitialValues({});
    final (_, service) = makeService();
    await service.setPin('135790');

    await failNTimes(service, '135790', 10);
    expect(service.isLockedOut, isTrue);

    await service.disable();
    expect(service.isLockedOut, isFalse);
    expect(service.failedAttempts, 0);
  });
}
