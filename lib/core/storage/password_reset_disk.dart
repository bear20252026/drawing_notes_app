// ============================================================================
// password_reset_disk.dart —— 重置密码盘（U 盘，2026-09-02 命名体系定案）
// ============================================================================
//
// 全应用唯一一把 U 盘：「重置密码盘」。
// 开屏密码与文件密码忘记时，插入此 U 盘 → 点「忘记密码」→ 重置新密码。
//
// 方案 B「钥匙槽位」（LUKS/BitLocker 多保护器模式）：
// U 盘上只有一把 32 字节 CSPRNG 随机钥匙文件，**不含任何主密钥副本**——
// 开屏密码的钥匙被它包裹后存在设备保险库槽 2（VaultKeyService.addUsbKeySlot）；
// 文件密码的钥匙槽位由 VaultFileCodec v3 信封承载（N4 批 2 接入）。
//
// 安全属性（与 LUKS/KeePass 一致）：
// - 只偷 U 盘：解不开任何东西；
// - 只偷设备：还有防爆破守卫挡着；
// - 设备 + U 盘都拿到：等价于本人（两件东西分放两地正是防御的全部意义）。
//
// 文件格式：FROG v1（37 字节定长：FROG magic + 0x01 + 32B 随机钥匙），
// 编解码在本文件内联（原 password_disk.dart 已随「解锁钥匙」体系删除）。

import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';

/// 重置密码盘钥匙文件读写（password_reset_disk.key）。
class ResetDiskFile {
  ResetDiskFile._();

  /// 重置密码盘专用文件名。
  static const String fileName = 'password_reset_disk.key';

  /// 旧版文件名（v1.5.x 的 vault_reset.frogkey）：读取时兼容回退，
  /// 老用户已绑定的 U 盘换新版本后依然可用。
  static const String legacyFileName = 'vault_reset.frogkey';

  static File _fileOf(String dir, String name) =>
      File('$dir${Platform.pathSeparator}$name');

  /// 让用户选择重置密码盘位置（U 盘目录），取消返回 null。
  static Future<String?> pickDirectory() async {
    final dir = await getDirectoryPath(confirmButtonText: '选择重置密码盘位置');
    return dir == null || dir.isEmpty ? null : dir;
  }

  /// 在 [dir] 下生成并写入随机 32B 钥匙，返回钥匙内容（作外部密钥）。
  /// 目录不存在自动创建（0o700 语义由调用方环境保证，Windows 无 POSIX 权限）。
  static Future<List<int>> writeTo(String dir) async {
    final rng = Random.secure();
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    await Directory(dir).create(recursive: true);
    await _fileOf(dir, fileName).writeAsBytes(_encode(key), flush: true);
    return key;
  }

  /// 读取 [dir] 下的重置钥匙；fail-closed：文件缺失 / 格式无效返回 null。
  ///
  /// 兼容回退：优先读新文件名 [fileName]；不存在时尝试旧文件名
  /// [legacyFileName]（v1.5.x 绑定的 U 盘无需重新制作）。
  static Future<List<int>?> readFrom(String dir) async {
    for (final name in const [fileName, legacyFileName]) {
      final file = _fileOf(dir, name);
      if (!await file.exists()) continue;
      try {
        final key = _decode(await file.readAsBytes());
        if (key != null) return key;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 删除 [dir] 下的重置钥匙文件（新旧文件名都删，返回是否全部成功）。
  static Future<bool> deleteFrom(String dir) async {
    var ok = true;
    for (final name in const [fileName, legacyFileName]) {
      final file = _fileOf(dir, name);
      if (!await file.exists()) continue;
      try {
        await file.delete();
      } catch (_) {
        ok = false;
      }
    }
    return ok;
  }

  // ---- FROG v1 内联编解码（37 字节定长，原 PasswordDiskFile 单一来源）----

  /// 组装钥匙文件字节：Magic `FROG` + 版本 0x01 + 32B 钥匙。
  static List<int> _encode(List<int> key) => const [
    0x46, 0x52, 0x4F, 0x47, // F R O G
    0x01, // v1
  ] + key;

  /// 解析钥匙文件字节；格式无效返回 null。
  static List<int>? _decode(List<int> bytes) {
    if (bytes.length != 37) return null;
    const magic = [0x46, 0x52, 0x4F, 0x47];
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return null;
    }
    if (bytes[4] != 0x01) return null;
    return bytes.sublist(5);
  }
}
