import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

// C-08（审计 2026-09-27）：自 StorageService 的 part 五域拆为真协作类。
// 本类持有**会话机密域**自有状态：单文件密码与 v3 密钥材料（DEK/USB
// 槽位密文）的内存缓存——解锁一次本会话免重复输入（用户 2026-09-01
// 拍板「会话内记住」）；切后台回锁/重启后自动失效（内存态，不落盘）。
// StorageService 保留门面（SessionSecretsHolder 注册点不动），消费方
// API 零变化。

/// 会话机密域：文件密码 + v3 双保护器密钥材料的内存缓存。
///
/// D-2 擦除纪律：DEK/USB 槽位为字节材料，移出 map 前逐个 `fill(0)`；
/// 口令 String 不可变（Dart 语义），移出 map 即不可达。清空流程幂等、
/// 永不抛错（切后台回锁热路径）。
class StorageSecretSession {
  // ---- 单文件密码（批次②）：画作级独立密码（v2/v3 密码信封） ----
  final Map<String, String> _filePasswords = <String, String>{};

  // N4 批 2（v3 双保护器信封）会话密钥材料：
  // - DEK 按文档稳定复用（写入时不换 DEK）——否则每次保存都会作废
  //   重置盘槽位（LUKS 槽位语义要求 DEK 恒定，与 PIN 可随时换盐对偶）；
  // - USB 槽位密文原样保留（密文包裹的是 DEK，DEK 不变则槽位永续有效）。
  // 两者均为内存态：与文件密码同生命周期（forgetFilePassword 一并清零）。
  final Map<String, Uint8List> _docDeks = <String, Uint8List>{};
  final Map<String, Uint8List> _fileUsbWrapped = <String, Uint8List>{};

  /// 该文档本会话内是否已解锁文件密码（编辑器保存走同一密封路径）。
  String? filePasswordFor(String docId) => _filePasswords[docId];

  /// 缓存会话文件密码（verifyFilePassword 成功后调用）。
  void cacheFilePassword(String docId, String password) {
    _filePasswords[docId] = password;
  }

  /// 缓存 v3 解锁产物（DEK + USB 槽位密文；未绑定槽位时清除旧值）。
  void cacheV3Material(String docId, VaultFileV3Unlock unlock) {
    _docDeks[docId] = unlock.dek;
    final usb = unlock.usbWrapped;
    if (usb != null) {
      _fileUsbWrapped[docId] = usb;
    } else {
      _fileUsbWrapped.remove(docId);
    }
  }

  /// 缓存调用方自产的密钥材料（setFilePassword 自产 DEK / v2→v3 升级 /
  /// 重置盘重绕后回填）；[usbWrapped] 为 null 时清除旧槽位。
  void cacheDekMaterial(String docId, Uint8List dek, Uint8List? usbWrapped) {
    _docDeks[docId] = dek;
    if (usbWrapped != null) {
      _fileUsbWrapped[docId] = usbWrapped;
    } else {
      _fileUsbWrapped.remove(docId);
    }
  }

  /// 会话密钥材料读取（密封时复用会话 DEK/USB 槽位——续写续用）。
  Uint8List? dekFor(String docId) => _docDeks[docId];
  Uint8List? usbWrappedFor(String docId) => _fileUsbWrapped[docId];

  /// 清除会话文件密码（移除文件密码 / 文档删除后调用）。
  /// N4 批 2：DEK（内存清零——D-2 模式）与 USB 槽位缓存一并清除。
  void forgetFilePassword(String docId) {
    _filePasswords.remove(docId);
    final dek = _docDeks.remove(docId);
    if (dek != null) dek.fillRange(0, dek.length, 0);
    _fileUsbWrapped.remove(docId);
  }

  /// P1 修复 M-05：清空全部会话机密（切后台回锁联动经 SessionSecrets）。
  /// 口令 String 不可擦除（Dart 不可变）——移出 map 即不可达；DEK/USB
  /// 字节材料逐个 fill(0)。幂等、永不抛错。
  void clearAll() {
    try {
      _filePasswords.clear();
      for (final dek in _docDeks.values) {
        try {
          dek.fillRange(0, dek.length, 0);
        } catch (_) {
          /* 幂等清理：单个 DEK 擦除失败继续下一个，清空流程永不抛错 */
        }
      }
      _docDeks.clear();
      _fileUsbWrapped.clear();
    } catch (_) {
      /* 幂等清理：会话机密清空尽力而为（切后台回锁热路径），失败不外抛 */
    }
  }
}
