import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';

/// EncryptionService 静态方法单元测试（不依赖 SharedPreferences / 密码 — 纯计算）。
///
/// 覆盖：getProgressiveDelay / getProgressiveDelayInfo / isPinLengthValid /
///       formatVersionOf / progressiveDelaySeconds。
void main() {
  group('getProgressiveDelay', () {
    test('failCount ≤ 0 → 0', () {
      expect(EncryptionService.getProgressiveDelay(0), 0);
      expect(EncryptionService.getProgressiveDelay(-1), 0);
    });

    test('failCount=1 → 1s', () {
      expect(EncryptionService.getProgressiveDelay(1), 1);
    });

    test('failCount=2 → 5s', () {
      expect(EncryptionService.getProgressiveDelay(2), 5);
    });

    test('failCount=3 → 30s', () {
      expect(EncryptionService.getProgressiveDelay(3), 30);
    });

    test('failCount=4 → 300s (5min)', () {
      expect(EncryptionService.getProgressiveDelay(4), 300);
    });

    test('failCount=5 → 3600s (1h)', () {
      expect(EncryptionService.getProgressiveDelay(5), 3600);
    });

    test('failCount=6 → 3600s (超出序列长度取最大值)', () {
      expect(EncryptionService.getProgressiveDelay(6), 3600);
    });

    test('failCount=100 → 3600s (极大值)', () {
      expect(EncryptionService.getProgressiveDelay(100), 3600);
    });
  });

  group('getProgressiveDelayInfo', () {
    test('failCount=0 → "无延迟"', () {
      expect(EncryptionService.getProgressiveDelayInfo(0), '无延迟');
    });

    test('failCount=1 → "1秒"', () {
      expect(EncryptionService.getProgressiveDelayInfo(1), '1秒');
    });

    test('failCount=2 → "5秒"', () {
      expect(EncryptionService.getProgressiveDelayInfo(2), '5秒');
    });

    test('failCount=3 → "30秒"', () {
      expect(EncryptionService.getProgressiveDelayInfo(3), '30秒');
    });

    test('failCount=4 → "5分钟"', () {
      expect(EncryptionService.getProgressiveDelayInfo(4), '5分钟');
    });

    test('failCount=5 → "1小时"', () {
      expect(EncryptionService.getProgressiveDelayInfo(5), '1小时');
    });
  });

  group('isPinLengthValid', () {
    test('短 PIN → false', () {
      expect(EncryptionService.isPinLengthValid('12345'), isFalse);
      expect(EncryptionService.isPinLengthValid(''), isFalse);
    });

    test('kPinMinLength → true', () {
      expect(
        EncryptionService.isPinLengthValid(
          '1' * EncryptionService.kPinMinLength,
        ),
        isTrue,
      );
    });

    test('长 PIN → true', () {
      expect(EncryptionService.isPinLengthValid('12345678'), isTrue);
    });
  });

  group('formatVersionOf', () {
    test('v=5 → 5', () {
      expect(
        EncryptionService.formatVersionOf('{"v":5,"s":"","n":"","c":"","m":""}'),
        5,
      );
    });

    test('v=3 → 3', () {
      expect(
        EncryptionService.formatVersionOf('{"v":3,"s":"","n":"","c":"","m":""}'),
        3,
      );
    });

    test('无 v 字段 → 2（旧格式）', () {
      expect(
        EncryptionService.formatVersionOf('{"s":"","n":"","c":"","m":""}'),
        2,
      );
    });

    test('无效 JSON → 2（容错）', () {
      expect(EncryptionService.formatVersionOf('not-json'), 2);
    });

    test('v 不是 int → 2（容错）', () {
      expect(
        EncryptionService.formatVersionOf('{"v":"bad"}'),
        2,
      );
    });
  });

  group('progressiveDelaySeconds', () {
    test('序列长度为 5', () {
      expect(EncryptionService.progressiveDelaySeconds.length, 5);
    });

    test('序列递增', () {
      final seq = EncryptionService.progressiveDelaySeconds;
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], greaterThan(seq[i - 1]));
      }
    });

    test('首尾值正确', () {
      expect(EncryptionService.progressiveDelaySeconds.first, 1);
      expect(EncryptionService.progressiveDelaySeconds.last, 3600);
    });
  });

  group('kPinMinLength', () {
    test('值为 6', () {
      expect(EncryptionService.kPinMinLength, 6);
    });
  });
}
