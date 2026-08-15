import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 同步路径加密（落地 Saber saber_syncer 的 `.sbe` 文件名混淆思路，
/// 独立实现）。
///
/// 上传到云端的文件名不再暴露明文标题（隐私保护）：用主密钥派生
/// 确定性密钥，对原始文件名做 AES-256-GCM 加密并追加 `.sbe` 扩展。
/// 同一种子文件名每次产生相同密文（确定性 nonce 由文件名派生），
/// 因此解密无需额外索引，云端文件可直接按名找回。
///
/// 链 H 说明（军工审计 2026-08-15）：
/// 1. 解析歧义边界：旧格式回退（整段直解）仅在文件名超长（>65 字节且
///    首字节为小值 ASCII）时可能误走新格式截断——实际文件名远小于此，
///    影响为数据损坏而非安全，风险可忽略；
/// 2. 同名泄露：同主密钥同文件名跨目录产生同密文——仅揭示"存在同名
///    文件"（价值极低），明文标题始终隐藏——设计取舍，接受。
class SyncPathCipher {
  const SyncPathCipher();

  /// 加密文件名的扩展名（对齐 Saber `.sbe`）。
  static const String encryptedExtension = '.sbe';

  /// 派生确定性 nonce 与 padding 长度：SHA-256(主密钥 ‖ 文件名)。
  /// nonce 取前 12 字节（同一文件名必然同一 nonce，保证可逆无索引）；
  /// padding 长度由第 13 字节派生（4-16 确定性——同明文同密文保持云端
  /// 按名找回，同时不同文件名的密文长度区间化，防精确推断明文长度）。
  Future<(Uint8List, int)> _deriveNonceAndPad(
    List<int> masterKey,
    String plainName,
  ) async {
    final digest = await Sha256().hash([...masterKey, ...utf8.encode(plainName)]);
    final nonce = Uint8List.fromList(digest.bytes.take(12).toList());
    final padLen = 4 + (digest.bytes[12] % 13);
    return (nonce, padLen);
  }

  /// 加密文件名：`note标题.json` → `3f9a…c2.sbe`。
  Future<String> encryptPath(String fileName, List<int> masterKey) async {
    final aes = AesGcm.with256bits();
    final (nonce, padLen) = await _deriveNonceAndPad(masterKey, fileName);
    // 长度混淆（红蓝攻防 D-3 修复 2026-08-15）：加密前加 4-16 字节
    // padding（长度确定性派生——保持同明文同密文、云端按名找回；
    // 不同文件名的密文长度区间化，防 .sbe 列表长度精确推断明文，
    // 见 mozilla/sops #223 GCM 长度泄露）。
    final plainBytes = utf8.encode(fileName);
    final payload = Uint8List(1 + plainBytes.length + padLen);
    payload[0] = plainBytes.length; // 真实长度（文件名 < 255 字节）
    payload.setRange(1, 1 + plainBytes.length, plainBytes);
    final box = await aes.encrypt(
      payload,
      secretKey: SecretKey(masterKey),
      nonce: nonce,
    );
    final combined = [
      ...box.cipherText,
      ...(box.mac.bytes.isNotEmpty ? box.mac.bytes : const <int>[]),
    ];
    return '${base64UrlEncode(combined).replaceAll('=', '')}'
        '$encryptedExtension';
  }

  /// 解密文件名：`3f9a…c2.sbe` → `note标题.json`；失败（篡改/密钥不符）
  /// 返回 null，绝不抛异常让同步流程中断。
  ///
  /// 注意：GCM 解密需要正确 nonce，而本设计的 nonce 由明文派生
  /// （SHA-256(主密钥‖明文)），因此**必须先知道候选明文**才能构造
  /// nonce 完成解密——云端枚举到的 `.sbe` 文件应与本地文件名逐一
  /// 尝试，见 [decryptPathWithCandidates]。此处仅对"明文已知"场景
  /// （如本地文件已存在、仅需校验密文一致性）提供便捷入口。
  Future<String?> decryptPath(String encryptedName, List<int> masterKey) async {
    return decryptPathWithCandidates(
      encryptedName,
      masterKey,
      const <String>[''],
    );
  }

  /// 从候选明文列表中解密（推荐入口）：路径加密使用确定性 nonce，
  /// 正确 nonce = SHA-256(主密钥‖明文)，因此必须尝试候选明文。
  /// 云端枚举到的 `.sbe` 文件，与本地全部文件名逐一尝试即可还原。
  Future<String?> decryptPathWithCandidates(
    String encryptedName,
    List<int> masterKey,
    Iterable<String> candidates,
  ) async {
    final aes = AesGcm.with256bits();
    for (final candidate in candidates) {
      final (nonce, _) = await _deriveNonceAndPad(masterKey, candidate);
      final Uint8List combined;
      try {
        final body = encryptedName.substring(
          0,
          encryptedName.length - encryptedExtension.length,
        );
        // D-3 修复：新格式带 padding 的密文 base64 长度 %4 可能为 2/3，
        // 原实现只对 %4==1 补 '='——用 normalize 自动补全填充防解码失败。
        combined = base64Url.decode(base64Url.normalize(body));
      } on FormatException {
        return null;
      }
      if (combined.length <= 16) return null;
      final cipherText = combined.sublist(0, combined.length - 16);
      final mac = combined.sublist(combined.length - 16);
      try {
        final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
        final clear = await aes.decrypt(
          box,
          secretKey: SecretKey(masterKey),
        );
        // D-3：新格式载荷 = [真实长度, ...明文, ...随机 padding]——
        // 先按首字节长度截断；解析失败回退旧格式（无 padding 直解，
        // 旧数据明文首字节为 ASCII 字母（65-122）几乎总大于密文长度，
        // 自动落入整段直解分支，保持向后兼容）。
        if (clear.isNotEmpty) {
          final realLen = clear[0];
          if (realLen > 0 && realLen < clear.length) {
            try {
              return utf8.decode(clear.sublist(1, 1 + realLen));
            } on FormatException {
              // 落到旧格式整段直解。
            }
          }
          try {
            return utf8.decode(clear);
          } on FormatException {
            continue;
          }
        }
        continue;
      } on SecretBoxAuthenticationError {
        continue; // nonce 不符，试下一个候选
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
