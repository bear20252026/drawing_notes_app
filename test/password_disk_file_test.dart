
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/password_disk.dart';

/// PasswordDiskFile 单测：v1/v2 编解码/PIN 保护/格式校验。
void main() {
  group('PasswordDiskFile.generateKey', () {
    test('生成 32 字节密钥', () {
      final key = PasswordDiskFile.generateKey();
      expect(key.length, 32);
    });

    test('多次生成唯一', () {
      final keys = <List<int>>{};
      for (var i = 0; i < 100; i++) {
        keys.add(PasswordDiskFile.generateKey());
      }
      // 每个密钥应唯一（概率上）
      final encoded = keys.map((k) => k.join(',')).toSet();
      expect(encoded.length, 100);
    });
  });

  group('PasswordDiskFile.encode / decode（v1）', () {
    test('往返编解码', () {
      final key = PasswordDiskFile.generateKey();
      final encoded = PasswordDiskFile.encode(key);
      final decoded = PasswordDiskFile.decode(encoded);
      expect(decoded, key);
    });

    test('文件长度 37 字节', () {
      final encoded = PasswordDiskFile.encode(PasswordDiskFile.generateKey());
      expect(encoded.length, 37);
    });

    test('Magic 头 FROG', () {
      final encoded = PasswordDiskFile.encode(PasswordDiskFile.generateKey());
      expect(encoded[0], 0x46); // F
      expect(encoded[1], 0x52); // R
      expect(encoded[2], 0x4F); // O
      expect(encoded[3], 0x47); // G
    });

    test('版本号 0x01', () {
      final encoded = PasswordDiskFile.encode(PasswordDiskFile.generateKey());
      expect(encoded[4], 0x01);
    });

    test('错误长度返回 null', () {
      expect(PasswordDiskFile.decode([1, 2, 3]), isNull);
      expect(PasswordDiskFile.decode(List<int>.generate(50, (i) => i)), isNull);
    });

    test('错误 Magic 返回 null', () {
      final bad = List<int>.generate(37, (i) => i);
      bad[0] = 0x00; // 破坏 Magic
      expect(PasswordDiskFile.decode(bad), isNull);
    });

    test('错误版本号返回 null', () {
      final bad = List<int>.generate(37, (i) => i);
      bad[0] = 0x46;
      bad[1] = 0x52;
      bad[2] = 0x4F;
      bad[3] = 0x47;
      bad[4] = 0x99; // 错误版本
      expect(PasswordDiskFile.decode(bad), isNull);
    });
  });

  group('PasswordDiskFile.encodeWithPin / decodeWithPin（v2）', () {
    final key = PasswordDiskFile.generateKey();

    test('PIN 保护往返解密', () async {
      final encoded = await PasswordDiskFile.encodeWithPin(key: key, pin: '123456');
      final decoded = await PasswordDiskFile.decodeWithPin(encoded, '123456');
      expect(decoded, key);
    });

    test('v2 格式版本号 0x02', () async {
      final encoded = await PasswordDiskFile.encodeWithPin(key: key, pin: '123456');
      expect(encoded[4], 0x02);
    });

    test('PIN 错误返回 null', () async {
      final encoded = await PasswordDiskFile.encodeWithPin(key: key, pin: '123456');
      final decoded = await PasswordDiskFile.decodeWithPin(encoded, '999999');
      expect(decoded, isNull);
    });

    test('PIN < 6 位抛 ArgumentError', () async {
      expect(
        () => PasswordDiskFile.encodeWithPin(key: key, pin: '12345'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('损坏数据返回 null', () async {
      final encoded = await PasswordDiskFile.encodeWithPin(key: key, pin: '123456');
      // 破坏信封内容
      encoded[6] ^= 0xFF;
      final decoded = await PasswordDiskFile.decodeWithPin(encoded, '123456');
      expect(decoded, isNull);
    });

    test('非 v2 数据返回 null', () async {
      // 构造 v1 格式但长度够的数据
      final v1Data = PasswordDiskFile.encode(key);
      final decoded = await PasswordDiskFile.decodeWithPin(v1Data, '123456');
      expect(decoded, isNull);
    });

    test('太短数据返回 null', () async {
      final decoded = await PasswordDiskFile.decodeWithPin([1, 2, 3], '1234');
      expect(decoded, isNull);
    });
  });

  group('validateKeyFile 逻辑验证', () {
    test('v1 文件有效', () {
      final key = PasswordDiskFile.generateKey();
      final bytes = PasswordDiskFile.encode(key);
      expect(_validate(bytes), isTrue);
    });

    test('v2 文件有效', () async {
      final key = PasswordDiskFile.generateKey();
      final bytes = await PasswordDiskFile.encodeWithPin(key: key, pin: '123456');
      expect(_validate(bytes), isTrue);
    });

    test('Magic 错误无效', () {
      final bytes = List<int>.generate(37, (i) => i);
      bytes[0] = 0x00;
      expect(_validate(bytes), isFalse);
    });

    test('版本号无效', () {
      final bytes = List<int>.generate(37, (i) => i);
      bytes[0] = 0x46;
      bytes[1] = 0x52;
      bytes[2] = 0x4F;
      bytes[3] = 0x47;
      bytes[4] = 0x03; // 未知版本
      expect(_validate(bytes), isFalse);
    });

    test('长度不足无效', () {
      expect(_validate([0x46, 0x52, 0x4F, 0x47]), isFalse);
    });
  });
}

/// 模拟 validateKeyFile 核心逻辑（Magic + 版本校验）。
bool _validate(List<int> bytes) {
  return bytes.length >= 6 &&
      bytes[0] == 0x46 &&
      bytes[1] == 0x52 &&
      bytes[2] == 0x4F &&
      bytes[3] == 0x47 &&
      (bytes[4] == 0x01 || bytes[4] == 0x02);
}
