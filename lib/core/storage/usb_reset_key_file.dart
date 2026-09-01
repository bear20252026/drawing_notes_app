// ============================================================================
// usb_reset_key_file.dart —— U 盘恢复钥匙文件（加密底座批次④ 2026-09-01）
// ============================================================================
//
// 方案 B「钥匙槽位」（LUKS/BitLocker 多保护器模式，调研结论 2026-09-01）：
// U 盘上只有一把 32 字节 CSPRNG 随机钥匙文件，**不含任何主密钥副本**——
// 主密钥被它包裹后存在设备保险库的槽 2 里（见 VaultKeyService.addUsbKeySlot）。
//
// 安全属性（与 LUKS/KeePass 一致）：
// - 只偷 U 盘：解不开任何东西；
// - 只偷设备：还有防爆破守卫挡着；
// - 设备 + U 盘都拿到：等价于本人（两件东西分放两地正是防御的全部意义）。
//
// 文件格式复用 [PasswordDiskFile] FROG v1（37 字节定长：FROG + 0x01 + 32B），
// 但**文件名独立**（vault_reset.frogkey ≠ 笔记本密码盘 key.frogkey）——
// 同一格式、不同职责，互不干扰（单一事实来源：格式只此一份）。

import 'dart:io';
import 'dart:math';

import 'package:drawing_notes_app/core/storage/password_disk.dart';

/// vault_reset.frogkey 读写（U 盘恢复钥匙）。
class UsbResetKeyFile {
  UsbResetKeyFile._();

  /// 与笔记本密码盘 key.frogkey 隔离的专用文件名。
  static const String fileName = 'vault_reset.frogkey';

  static File _fileOf(String dir) =>
      File('$dir${Platform.pathSeparator}$fileName');

  /// 在 [dir] 下生成并写入随机 32B 恢复钥匙，返回钥匙内容（作外部密钥）。
  /// 目录不存在自动创建（0o700 语义由调用方环境保证，Windows 无 POSIX 权限）。
  static Future<List<int>> writeTo(String dir) async {
    final rng = Random.secure();
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    await Directory(dir).create(recursive: true);
    await _fileOf(dir).writeAsBytes(PasswordDiskFile.encode(key), flush: true);
    return key;
  }

  /// 读取 [dir] 下的恢复钥匙；文件缺失 / 格式无效返回 null（fail-closed）。
  static Future<List<int>?> readFrom(String dir) async {
    final file = _fileOf(dir);
    if (!await file.exists()) return null;
    try {
      return PasswordDiskFile.decode(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// 删除 [dir] 下的恢复钥匙文件（存在则删，返回是否删除成功）。
  static Future<bool> deleteFrom(String dir) async {
    final file = _fileOf(dir);
    if (!await file.exists()) return true;
    try {
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
