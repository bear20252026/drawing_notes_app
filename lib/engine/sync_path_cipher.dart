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
class SyncPathCipher {
  const SyncPathCipher();

  /// 加密文件名的扩展名（对齐 Saber `.sbe`）。
  static const String encryptedExtension = '.sbe';

  /// 派生确定性 nonce：SHA-256(主密钥 ‖ 文件名) 前 12 字节。
  /// 同一文件名必然得到同一 nonce，保证可逆且无额外索引。
  Future<Uint8List> _deriveNonce(
    List<int> masterKey,
    String plainName,
  ) async {
    final digest = await Sha256().hash([...masterKey, ...utf8.encode(plainName)]);
    return Uint8List.fromList(digest.bytes.take(12).toList());
  }

  /// 加密文件名：`note标题.json` → `3f9a…c2.sbe`。
  Future<String> encryptPath(String fileName, List<int> masterKey) async {
    final aes = AesGcm.with256bits();
    final nonce = await _deriveNonce(masterKey, fileName);
    final box = await aes.encrypt(
      utf8.encode(fileName),
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
      final nonce = await _deriveNonce(masterKey, candidate);
      final Uint8List combined;
      try {
        final body = encryptedName.substring(
          0,
          encryptedName.length - encryptedExtension.length,
        );
        combined = base64Url.decode(body.length % 4 == 1 ? '$body=' : body);
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
        return utf8.decode(clear);
      } on SecretBoxAuthenticationError {
        continue; // nonce 不符，试下一个候选
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}
