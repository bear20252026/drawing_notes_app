import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 媒体加密服务（H-03 跨域专项基础组件，专家审计 2026-08-15）。
///
/// BusinessCrypto 层（掘金 HUKS 四层架构模式）：媒体资产（图片/PDF 副本）
/// 的加密逻辑集中于此，**不把长期密钥暴露给业务模块**；会话密钥解锁后
/// 注入（setSessionKey）、退出/锁定时清除（clearSessionKey——D-2 内存
/// 清理模式）。storeImage 加密写入与 EncryptedFileImage 渲染解密均经此
/// 服务（Flutter 官方 DI 模式：服务注入，密钥不散传）。
class MediaCryptoService {
  MediaCryptoService._();
  static final MediaCryptoService instance = MediaCryptoService._();

  List<int>? _sessionKey;

  /// 注入会话密钥（解锁后调用；密钥仅内存——不落盘）。
  void setSessionKey(List<int> key) => _sessionKey = List.of(key);

  /// 清除会话密钥（退出/锁定——fillRange 主动擦除，D-2 模式）。
  void clearSessionKey() {
    final key = _sessionKey;
    if (key != null) key.fillRange(0, key.length, 0);
    _sessionKey = null;
  }

  bool get isActive => _sessionKey != null;

  /// 加密媒体字节（AES-256-GCM——载荷 = [nonce(12), cipherText, tag(16)]，
  /// AAD 绑定用途 'media'——防跨用途密文交换）。
  Future<Uint8List> encryptBytes(Uint8List plain) async {
    final key = _sessionKey;
    if (key == null) throw StateError('会话密钥未注入（请先解锁）');
    final aes = AesGcm.with256bits();
    final rng = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => rng.nextInt(256)),
    );
    final box = await aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _mediaAad,
    );
    return Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// 解密媒体字节（EncryptedFileImage 渲染用）；密钥错误/损坏抛异常。
  Future<Uint8List> decryptBytes(Uint8List data) async {
    final key = _sessionKey;
    if (key == null) throw StateError('会话密钥未注入（请先解锁）');
    if (data.length <= 28) throw FormatException('媒体密文长度不合法');
    final nonce = data.sublist(0, 12);
    final cipher = data.sublist(12, data.length - 16);
    final mac = data.sublist(data.length - 16);
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
      aad: _mediaAad,
    );
    return Uint8List.fromList(clear);
  }

  /// 媒体 AAD：绑定应用/用途/版本（NIST SP 800-38D 上下文绑定）。
  static final Uint8List _mediaAad = Uint8List.fromList(
    utf8.encode('drawing-notes|media|v1'),
  );
}
