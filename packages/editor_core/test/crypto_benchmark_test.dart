// crypto_benchmark_test.dart——ChaCha20-Poly1305 vs AES-256-GCM 性能基准测试。
//
// 运行方式：
//   cd packages/editor_core
//   flutter test test/crypto_benchmark_test.dart --reporter expanded
//
// 对比 ChaCha20-Poly1305、XChaCha20-Poly1305、AES-256-GCM 在不同数据大小下的
// 加密/解密性能，验证平台自适应选择逻辑。

import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:editor_core/src/domain/crypto_utils.dart';

void main() {
  group('ChaCha20-Poly1305 基础功能', () {
    test('ChaCha20-Poly1305 加解密往返', () {
      final rng = Random(42);
      final key = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
      final nonce = Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
      final plaintext = Uint8List.fromList('Hello, ChaCha20-Poly1305!'.codeUnits);
      final aad = Uint8List.fromList('additional-data'.codeUnits);

      final ciphertext = chacha20Poly1305Encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      // 密文应比明文长 16 字节（Poly1305 tag）
      expect(ciphertext.length, plaintext.length + 16);

      final decrypted = chacha20Poly1305Decrypt(
        ciphertextWithTag: ciphertext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(decrypted, plaintext);
    });

    test('ChaCha20-Poly1305 认证失败检测', () {
      final rng = Random(42);
      final key = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
      final nonce = Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
      final plaintext = Uint8List.fromList('tamper test'.codeUnits);

      final ciphertext = chacha20Poly1305Encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
      );

      // 篡改密文
      final tampered = Uint8List.fromList(ciphertext);
      tampered[0] ^= 0xFF;

      expect(
        () => chacha20Poly1305Decrypt(
          ciphertextWithTag: tampered,
          key: key,
          nonce: nonce,
        ),
        throwsA(anything), // InvalidCipherTextException
      );
    });
  });

  group('XChaCha20-Poly1305 基础功能', () {
    test('XChaCha20-Poly1305 加解密往返', () {
      final rng = Random(42);
      final key = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
      final nonce = Uint8List.fromList(List.generate(24, (_) => rng.nextInt(256)));
      final plaintext = Uint8List.fromList('Hello, XChaCha20-Poly1305!'.codeUnits);
      final aad = Uint8List.fromList('additional-data'.codeUnits);

      final ciphertext = xchacha20Poly1305Encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(ciphertext.length, plaintext.length + 16);

      final decrypted = xchacha20Poly1305Decrypt(
        ciphertextWithTag: ciphertext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(decrypted, plaintext);
    });

    test('XChaCha20-Poly1305 认证失败检测', () {
      final rng = Random(42);
      final key = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
      final nonce = Uint8List.fromList(List.generate(24, (_) => rng.nextInt(256)));
      final plaintext = Uint8List.fromList('tamper test'.codeUnits);

      final ciphertext = xchacha20Poly1305Encrypt(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
      );

      final tampered = Uint8List.fromList(ciphertext);
      tampered[0] ^= 0xFF;

      expect(
        () => xchacha20Poly1305Decrypt(
          ciphertextWithTag: tampered,
          key: key,
          nonce: nonce,
        ),
        throwsA(anything),
      );
    });
  });

  group('平台自适应选择逻辑', () {
    test('移动端选择 XChaCha20-Poly1305', () {
      expect(selectAeadAlgorithm('android'), AeadAlgorithm.xchacha20Poly1305);
      expect(selectAeadAlgorithm('ios'), AeadAlgorithm.xchacha20Poly1305);
      expect(selectAeadAlgorithm('Android'), AeadAlgorithm.xchacha20Poly1305);
      expect(selectAeadAlgorithm('IOS'), AeadAlgorithm.xchacha20Poly1305);
    });

    test('桌面端选择 AES-256-GCM', () {
      expect(selectAeadAlgorithm('windows'), AeadAlgorithm.aes256Gcm);
      expect(selectAeadAlgorithm('macos'), AeadAlgorithm.aes256Gcm);
      expect(selectAeadAlgorithm('linux'), AeadAlgorithm.aes256Gcm);
      expect(selectAeadAlgorithm('web'), AeadAlgorithm.aes256Gcm);
    });

    test('未知平台默认 XChaCha20-Poly1305', () {
      expect(selectAeadAlgorithm('fuchsia'), AeadAlgorithm.xchacha20Poly1305);
      expect(selectAeadAlgorithm(''), AeadAlgorithm.xchacha20Poly1305);
    });
  });

  group('platformAeadEncrypt/Decrypt 往返', () {
    for (final platform in ['android', 'ios', 'windows', 'macos', 'linux', 'web']) {
      test('platform=$platform 加解密往返', () {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final plaintext = Uint8List.fromList('Platform AEAD test data'.codeUnits);
        final aad = Uint8List.fromList('context'.codeUnits);

        final result = platformAeadEncrypt(
          platform: platform,
          plaintext: plaintext,
          key: key,
          aad: aad,
        );

        expect(result.ciphertext.length, plaintext.length + 16);
        expect(result.nonce.isNotEmpty, true);

        final decrypted = platformAeadDecrypt(
          algorithm: result.algorithm,
          ciphertextWithTag: result.ciphertext,
          key: key,
          nonce: result.nonce,
          aad: aad,
        );

        expect(decrypted, plaintext);
      });
    }
  });

  group('性能基准测试', () {
    // 测试数据大小：1KB、64KB、1MB
    final sizes = [1024, 65536, 1048576];
    const iterations = 10; // 每个大小重复次数

    for (final size in sizes) {
      test('ChaCha20-Poly1305 vs AES-256-GCM @ ${_formatSize(size)}', () {
        final rng = Random(42);
        final key = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
        final plaintext = Uint8List.fromList(List.generate(size, (_) => rng.nextInt(256)));
        final aad = Uint8List.fromList('benchmark-aad'.codeUnits);

        // ── ChaCha20-Poly1305 ──
        final chacha20Nonce = Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
        final chacha20EncTimes = <int>[];
        final chacha20DecTimes = <int>[];
        Uint8List? chacha20Ciphertext;

        for (var i = 0; i < iterations; i++) {
          final sw = Stopwatch()..start();
          chacha20Ciphertext = chacha20Poly1305Encrypt(
            plaintext: plaintext,
            key: key,
            nonce: chacha20Nonce,
            aad: aad,
          );
          sw.stop();
          chacha20EncTimes.add(sw.elapsedMicroseconds);

          sw
            ..reset()
            ..start();
          chacha20Poly1305Decrypt(
            ciphertextWithTag: chacha20Ciphertext,
            key: key,
            nonce: chacha20Nonce,
            aad: aad,
          );
          sw.stop();
          chacha20DecTimes.add(sw.elapsedMicroseconds);
        }

        // ── XChaCha20-Poly1305 ──
        final xchacha20Nonce = Uint8List.fromList(List.generate(24, (_) => rng.nextInt(256)));
        final xchacha20EncTimes = <int>[];
        final xchacha20DecTimes = <int>[];
        Uint8List? xchacha20Ciphertext;

        for (var i = 0; i < iterations; i++) {
          final sw = Stopwatch()..start();
          xchacha20Ciphertext = xchacha20Poly1305Encrypt(
            plaintext: plaintext,
            key: key,
            nonce: xchacha20Nonce,
            aad: aad,
          );
          sw.stop();
          xchacha20EncTimes.add(sw.elapsedMicroseconds);

          sw
            ..reset()
            ..start();
          xchacha20Poly1305Decrypt(
            ciphertextWithTag: xchacha20Ciphertext,
            key: key,
            nonce: xchacha20Nonce,
            aad: aad,
          );
          sw.stop();
          xchacha20DecTimes.add(sw.elapsedMicroseconds);
        }

        // ── AES-256-GCM ──
        final gcmNonce = Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
        final gcmEncTimes = <int>[];
        final gcmDecTimes = <int>[];
        Uint8List? gcmCiphertext;

        for (var i = 0; i < iterations; i++) {
          final sw = Stopwatch()..start();
          gcmCiphertext = aes256GcmEncrypt(
            plaintext: plaintext,
            key: key,
            nonce: gcmNonce,
            aad: aad,
          );
          sw.stop();
          gcmEncTimes.add(sw.elapsedMicroseconds);

          sw
            ..reset()
            ..start();
          aes256GcmDecrypt(
            ciphertextWithTag: gcmCiphertext,
            key: key,
            nonce: gcmNonce,
            aad: aad,
          );
          sw.stop();
          gcmDecTimes.add(sw.elapsedMicroseconds);
        }

        // 计算平均值
        final chacha20EncAvg = _avg(chacha20EncTimes);
        final chacha20DecAvg = _avg(chacha20DecTimes);
        final xchacha20EncAvg = _avg(xchacha20EncTimes);
        final xchacha20DecAvg = _avg(xchacha20DecTimes);
        final gcmEncAvg = _avg(gcmEncTimes);
        final gcmDecAvg = _avg(gcmDecTimes);

        // 输出报告
        _printReport(size, iterations, {
          'ChaCha20-Poly1305': {'enc': chacha20EncAvg, 'dec': chacha20DecAvg},
          'XChaCha20-Poly1305': {'enc': xchacha20EncAvg, 'dec': xchacha20DecAvg},
          'AES-256-GCM': {'enc': gcmEncAvg, 'dec': gcmDecAvg},
        });

        // 验证：密文长度一致（均为明文 + 16 字节 tag）
        expect(chacha20Ciphertext!.length, size + 16);
        expect(xchacha20Ciphertext!.length, size + 16);
        expect(gcmCiphertext!.length, size + 16);
      });
    }
  });
}

double _avg(List<int> values) {
  if (values.isEmpty) return 0;
  // 去掉最高和最低，取中间值平均（减少抖动）
  final sorted = List<int>.from(values)..sort();
  final trimmed = sorted.sublist(1, sorted.length - 1);
  return trimmed.isEmpty
      ? values.reduce((a, b) => a + b) / values.length
      : trimmed.reduce((a, b) => a + b) / trimmed.length;
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${(bytes / 1048576).toStringAsFixed(0)}MB';
}

void _printReport(
  int size,
  int iterations,
  Map<String, Map<String, double>> results,
) {
  // ignore: avoid_print
  print('');
  // ignore: avoid_print
  print('════════════════════════════════════════════════════════════════');
  // ignore: avoid_print
  print('  性能基准测试：${_formatSize(size)} × $iterations 次');
  // ignore: avoid_print
  print('════════════════════════════════════════════════════════════════');
  // ignore: avoid_print
  print('  算法                  加密 (μs)    解密 (μs)    吞吐量 (MB/s)');
  // ignore: avoid_print
  print('  ────────────────────  ──────────   ──────────   ──────────────');

  for (final entry in results.entries) {
    final name = entry.key;
    final enc = entry.value['enc']!;
    final dec = entry.value['dec']!;
    final throughput = (size / (enc + dec)) * 1000000 / 1048576; // MB/s
    // ignore: avoid_print
    print(
      '  ${name.padRight(20)}'
      '  ${enc.toStringAsFixed(0).padLeft(8)}'
      '    ${dec.toStringAsFixed(0).padLeft(8)}'
      '    ${throughput.toStringAsFixed(1).padLeft(10)}',
    );
  }

  // ignore: avoid_print
  print('════════════════════════════════════════════════════════════════');
}
