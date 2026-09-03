// 重置密码盘钥匙文件（password_reset_disk.key）读写测试。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('password_reset_disk_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('ResetDiskFile', () {
    test('writeTo 生成 32B 钥匙并落盘（FROG v1 格式，37 字节）', () async {
      final key = await ResetDiskFile.writeTo(tmp.path);
      expect(key, hasLength(32));

      final file = File(
        '${tmp.path}${Platform.pathSeparator}password_reset_disk.key',
      );
      expect(file.existsSync(), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes, hasLength(37));
      expect(bytes[0], 0x46); // F
      expect(bytes[1], 0x52); // R
      expect(bytes[2], 0x4F); // O
      expect(bytes[3], 0x47); // G
      expect(bytes[4], 0x01); // v1
    });

    test('readFrom 往返一致；格式无效返回 null', () async {
      final key = await ResetDiskFile.writeTo(tmp.path);
      expect(await ResetDiskFile.readFrom(tmp.path), equals(key));

      // 篡改 magic → 解析失败返回 null（fail-closed）。
      final file = File(
        '${tmp.path}${Platform.pathSeparator}password_reset_disk.key',
      );
      final bytes = await file.readAsBytes();
      bytes[0] = 0x00;
      await file.writeAsBytes(bytes);
      expect(await ResetDiskFile.readFrom(tmp.path), isNull);
    });

    test('文件缺失 readFrom 返回 null；deleteFrom 幂等', () async {
      expect(await ResetDiskFile.readFrom(tmp.path), isNull);
      expect(await ResetDiskFile.deleteFrom(tmp.path), isTrue); // 无文件也 true

      await ResetDiskFile.writeTo(tmp.path);
      expect(await ResetDiskFile.deleteFrom(tmp.path), isTrue);
      expect(await ResetDiskFile.readFrom(tmp.path), isNull);
    });

    test('目录不存在时 writeTo 自动创建', () async {
      final nested =
          '${tmp.path}${Platform.pathSeparator}a${Platform.pathSeparator}b';
      final key = await ResetDiskFile.writeTo(nested);
      expect(key, hasLength(32));
      expect(await ResetDiskFile.readFrom(nested), equals(key));
    });

    test('旧版 vault_reset.frogkey 兼容回退（v1.5.x 绑定的 U 盘可用）', () async {
      final key = List<int>.generate(32, (i) => i + 1);
      final legacy = File(
        '${tmp.path}${Platform.pathSeparator}vault_reset.frogkey',
      );
      await legacy.writeAsBytes([
        0x46,
        0x52,
        0x4F,
        0x47,
        0x01,
        ...key,
      ], flush: true);

      // 无新文件、只有旧文件 → 读旧文件成功。
      expect(await ResetDiskFile.readFrom(tmp.path), equals(key));

      // deleteFrom 一并清理旧文件。
      expect(await ResetDiskFile.deleteFrom(tmp.path), isTrue);
      expect(legacy.existsSync(), isFalse);
    });

    test('文件名与旧密码盘 key.frogkey 体系隔离（已删除，防回归）', () {
      expect(ResetDiskFile.fileName, 'password_reset_disk.key');
      expect(ResetDiskFile.fileName, isNot('vault_reset.frogkey'));
      expect(ResetDiskFile.fileName, isNot('key.frogkey'));
    });
  });
}
