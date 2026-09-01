// U 盘恢复钥匙文件（批次④）读写测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/core/storage/usb_reset_key_file.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('usb_reset_key_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('UsbResetKeyFile', () {
    test('writeTo 生成 32B 钥匙并落盘（FROG v1 格式，37 字节）', () async {
      final key = await UsbResetKeyFile.writeTo(tmp.path);
      expect(key, hasLength(32));

      final file = File('${tmp.path}${Platform.pathSeparator}vault_reset.frogkey');
      expect(file.existsSync(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes, hasLength(37));
      expect(bytes[0], 0x46); // F
      expect(bytes[1], 0x52); // R
      expect(bytes[2], 0x4F); // O
      expect(bytes[3], 0x47); // G
      expect(bytes[4], 0x01); // v1

      // PasswordDiskFile.decode 能解析（格式单一事实来源）。
      expect(PasswordDiskFile.decode(bytes), equals(key));
    });

    test('readFrom 往返一致；格式无效返回 null', () async {
      final key = await UsbResetKeyFile.writeTo(tmp.path);
      expect(await UsbResetKeyFile.readFrom(tmp.path), equals(key));

      // 篡改 magic → 解析失败返回 null（fail-closed）。
      final file = File('${tmp.path}${Platform.pathSeparator}vault_reset.frogkey');
      final bytes = await file.readAsBytes();
      bytes[0] = 0x00;
      await file.writeAsBytes(bytes);
      expect(await UsbResetKeyFile.readFrom(tmp.path), isNull);
    });

    test('文件缺失 readFrom 返回 null；deleteFrom 幂等', () async {
      expect(await UsbResetKeyFile.readFrom(tmp.path), isNull);
      expect(await UsbResetKeyFile.deleteFrom(tmp.path), isTrue); // 无文件也 true

      await UsbResetKeyFile.writeTo(tmp.path);
      expect(await UsbResetKeyFile.deleteFrom(tmp.path), isTrue);
      expect(await UsbResetKeyFile.readFrom(tmp.path), isNull);
    });

    test('目录不存在时 writeTo 自动创建', () async {
      final nested = '${tmp.path}${Platform.pathSeparator}a${Platform.pathSeparator}b';
      final key = await UsbResetKeyFile.writeTo(nested);
      expect(key, hasLength(32));
      expect(await UsbResetKeyFile.readFrom(nested), equals(key));
    });

    test('与笔记本密码盘 key.frogkey 文件名隔离', () {
      expect(UsbResetKeyFile.fileName, 'vault_reset.frogkey');
      expect(UsbResetKeyFile.fileName, isNot(RealPasswordDisk.keyFileName));
    });
  });
}
