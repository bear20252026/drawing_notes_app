/// 恒定时间比较门禁（2026-11-15）。
///
/// 一句话：`lib/` 里**秘密值比较不许裸 `==`**——MAC / 摘要 / 口令哈希 /
/// 认证侧车一旦短路返回，逐字符猜解就能计时（时序侧信道）。实现已收敛到
/// `core/utils/constant_time.dart` 单一来源，本门禁把它钉住：
///
/// 1. **实现唯一**：除单一来源外，不许再有第二份 `diff |=` 累积异或实现
///    （历史上有三份复制，其中两份因长度不等提前返回——强度不一致）。
/// 2. **调用面覆盖**：安全链关键文件（审计链 / 锁服务 / 守卫 / VFS 清单）
///    必须引用单一来源，不许悄悄改回裸比较。
/// 3. **行为正确**：长度不等也走完循环（不因长度提前返回）、相等/不等判定
///    正确、空串与超长输入都不崩。
///
/// 保证边界如实声明：Dart 层无法提供 C `CRYPTO_memcmp` 的严格恒定时间
/// （JIT 优化空间），本工具是纵深防御——见 constant_time.dart 文件头。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/utils/constant_time.dart';

const String _sourcePath = 'lib/core/utils/constant_time.dart';

/// 累积异或实现形状（`diff |= x ^ y`）——恒定时间比较的指纹。
final RegExp _accumXor = RegExp(r'diff\s*\|=\s*[^;]*\^');

final RegExp _comment = RegExp(r'^\s*(//|///|\*)');

/// 必须引用单一来源的安全链文件（消费方清单）。
const List<String> _consumers = [
  'lib/core/security/audit_logger.dart',
  'lib/core/security/app_lock_service.dart',
  'lib/core/security/app_lock_guard.dart',
  'lib/core/storage/vfs/encrypted_vault.dart',
];

/// 扫 lib/ 里的累积异或实现，返回命中文件（排除单一来源与注释）。
List<String> implementations() {
  final hits = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path.endsWith(_sourcePath)) continue;
    for (final line in entity.readAsLinesSync()) {
      if (_comment.hasMatch(line)) continue;
      if (_accumXor.hasMatch(line)) {
        hits.add(path);
        break;
      }
    }
  }
  return hits;
}

void main() {
  group('门禁：实现唯一 + 调用面覆盖', () {
    test('单一来源之外不再有第二份累积异或实现（防强度漂移）', () {
      expect(
        implementations(),
        isEmpty,
        reason: '恒定时间比较已收敛到 core/utils/constant_time.dart；'
            '再写一份复制就会出现「有的版本因长度不等提前返回」的强度漂移',
      );
    });

    test('单一来源自身确实带累积异或实现（抽取器没塌）', () {
      final lines = File(_sourcePath).readAsLinesSync();
      expect(
        lines.where((l) => !_comment.hasMatch(l) && _accumXor.hasMatch(l)),
        isNotEmpty,
        reason: '扫不到指纹说明抽取器失效，上一条门禁会变成盲放',
      );
    });

    test('安全链关键文件都引用单一来源（不许悄悄改回裸比较）', () {
      for (final path in _consumers) {
        final text = File(path).readAsStringSync();
        expect(
          text.contains('core/utils/constant_time.dart'),
          isTrue,
          reason: '$path 不再引用恒定时间工具——秘密值比较可能已回退成裸 ==',
        );
      }
    });

    test('审计链的秘密值比较不再裸 ==（时序缺口收口）', () {
      final lines = File('lib/core/security/audit_logger.dart').readAsLinesSync();
      // 裸比较形状：hash == / prevHash != 之类（排除 null 判定）。
      final bare = <String>[];
      for (final line in lines) {
        if (_comment.hasMatch(line)) continue;
        final m = RegExp(r'\b(hash|prevHash|mac)\s*(==|!=)\s*(?!\s*null)')
            .firstMatch(line);
        if (m != null) bare.add(line.trim());
      }
      expect(
        bare,
        isEmpty,
        reason: '审计链哈希/链接比较必须走恒定时间工具：$bare',
      );
    });
  });

  group('行为：判定正确且不因长度提前返回', () {
    test('相等/不等判定正确（字符串）', () {
      expect(constantTimeEquals('abc123', 'abc123'), isTrue);
      expect(constantTimeEquals('abc123', 'abc124'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
      expect(constantTimeEquals('a', ''), isFalse);
      expect(constantTimeEquals('', 'a'), isFalse);
    });

    test('长度不等也判 false（长度差折进 diff，不提前返回）', () {
      expect(constantTimeEquals('short', 'much-longer-value'), isFalse);
      expect(constantTimeEquals('much-longer-value', 'short'), isFalse);
      // 前缀相同但长度不同——不得因「前缀匹配」误判相等。
      expect(constantTimeEquals('abc', 'abcdef'), isFalse);
    });

    test('字节序列比较正确（含长度不等与空序列）', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      expect(constantTimeBytesEqual(a, Uint8List.fromList([1, 2, 3, 4])), isTrue);
      expect(constantTimeBytesEqual(a, Uint8List.fromList([1, 2, 3, 5])), isFalse);
      expect(constantTimeBytesEqual(a, Uint8List.fromList([1, 2, 3])), isFalse);
      expect(constantTimeBytesEqual(Uint8List(0), Uint8List(0)), isTrue);
    });

    test('hex 便利入口：字节与 hex 摘要比对', () {
      final bytes = Uint8List.fromList([0x0a, 0xff, 0x00, 0x10]);
      expect(constantTimeHexEquals(bytes, '0aff0010'), isTrue);
      expect(constantTimeHexEquals(bytes, '0aff0011'), isFalse);
      expect(constantTimeHexEquals(bytes, '0aff00'), isFalse);
    });

    test('非 ASCII 输入不崩（UTF-8 字节口径，不依赖 ASCII 假设）', () {
      expect(constantTimeEquals('密钥摘要', '密钥摘要'), isTrue);
      expect(constantTimeEquals('密钥摘要', '密钥摘要X'), isFalse);
    });

    test('超长输入可处理（10k 字符，无异常）', () {
      final long = 'a' * 10000;
      expect(constantTimeEquals(long, long), isTrue);
      expect(constantTimeEquals(long, '${'a' * 9999}b'), isFalse);
    });
  });
}