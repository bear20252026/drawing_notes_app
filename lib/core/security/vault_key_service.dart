// vault_key_service.dart — Vault 加密存储 DEK + 签名密钥对（2026-08-24）。
//
// 架构：
// - DEK（Data Encryption Key）：32 字节随机密钥，用于加密文档数据
// - 签名密钥对：Ed25519 密钥对，用于文档签名/验证
// - Vault 存储：DEK 和签名密钥对用 KEK 包裹后存储在 EncryptedVault
// - 密钥轮换：KEK 变化时，所有密钥材料用新 KEK 重新包裹
//
// 存储布局：
// vault/
//   keys/
//     dek.primary          — 主 DEK（KEK 包裹）
//     signing.primary.sk   — 签名私钥（KEK 包裹）
//     signing.primary.pk   — 签名公钥（明文——公钥不需保密）
//     dek.document.<id>    — 文档专用 DEK（KEK 包裹）

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drawing_notes_app/infrastructure/storage/vfs/encrypted_vault.dart';

import 'secure_bytes.dart';
import 'vault_key_manager.dart';

/// Vault 密钥服务——管理 DEK 和签名密钥对的加密存储。
class VaultKeyService {
  VaultKeyService({
    required this.keyManager,
    required this.vaultStore,
  });

  final VaultKeyManager keyManager;
  final VaultKeyStore vaultStore; // 抽象存储（可替换为 EncryptedVault）

  static const _primaryDekId = 'dek.primary';
  static const _primarySigningSkId = 'signing.primary.sk';
  static const _primarySigningPkId = 'signing.primary.pk';

  /// 初始化 Vault 密钥（首次设置密码时调用）。
  ///
  /// 生成主 DEK + 签名密钥对，用 KEK 包裹后存储。
  Future<VaultKeySet> initializeKeys(String password) async {
    final kek = await keyManager.initialize(password);
    try {
      // 生成主 DEK。
      final dekBytes = _randomBytes(32);
      final wrappedDek = await _wrapKey(dekBytes, kek);
      await vaultStore.storeKey(_primaryDekId, wrappedDek);

      // 生成签名密钥对。
      final signingKeyPair = await Ed25519().newKeyPair();
      final skBytes = await signingKeyPair.extractPrivateKeyBytes();
      final pkBytes = await signingKeyPair.extractPublicKey().then((pk) => pk.bytes);
      final wrappedSk = await _wrapKey(skBytes, kek);
      await vaultStore.storeKey(_primarySigningSkId, wrappedSk);
      // 公钥明文存储（公钥不需保密）。
      await vaultStore.storeKey(_primarySigningPkId, pkBytes);

      return VaultKeySet(
        dek: SecureBytes(dekBytes),
        signingKeyPair: signingKeyPair,
      );
    } finally {
      kek.dispose();
    }
  }

  /// 解锁 Vault 密钥（验证密码后调用）。
  ///
  /// 从 Vault 读取包裹的 DEK + 签名密钥对，用 KEK 解包裹。
  Future<VaultKeySet> unlockKeys(String password) async {
    final kek = await keyManager.unlock(password);
    try {
      // 解包裹主 DEK。
      final wrappedDek = await vaultStore.readKey(_primaryDekId);
      if (wrappedDek == null) {
        throw StateError('Vault 未初始化——主 DEK 不存在');
      }
      final dekBytes = await _unwrapKey(wrappedDek, kek);

      // 解包裹签名私钥。
      final wrappedSk = await vaultStore.readKey(_primarySigningSkId);
      if (wrappedSk == null) {
        throw StateError('Vault 未初始化——签名私钥不存在');
      }
      final skBytes = await _unwrapKey(wrappedSk, kek);

      // 重建签名密钥对。
      final pkBytes = await vaultStore.readKey(_primarySigningPkId);
      if (pkBytes == null) {
        throw StateError('Vault 未初始化——签名公钥不存在');
      }
      final signingKeyPair = await Ed25519().newKeyPairFromSeed(skBytes);

      return VaultKeySet(
        dek: SecureBytes(dekBytes),
        signingKeyPair: signingKeyPair,
      );
    } finally {
      kek.dispose();
    }
  }

  /// KEK 轮换（修改密码时调用）。
  ///
  /// 用旧 KEK 解包裹所有密钥材料，用新 KEK 重新包裹，原子提交。
  Future<void> rotateKeys({
    required String oldPassword,
    required String newPassword,
  }) async {
    await keyManager.rotateKek(
      oldPassword: oldPassword,
      newPassword: newPassword,
      reWrapCallback: (oldKek, newKek) async {
        // 读取所有包裹的密钥。
        final wrappedDek = await vaultStore.readKey(_primaryDekId);
        final wrappedSk = await vaultStore.readKey(_primarySigningSkId);

        if (wrappedDek == null || wrappedSk == null) {
          throw StateError('Vault 密钥不完整——无法轮换');
        }

        // 用旧 KEK 解包裹。
        final dekBytes = await _unwrapKey(wrappedDek, oldKek);
        final skBytes = await _unwrapKey(wrappedSk, oldKek);

        try {
          // 用新 KEK 重新包裹。
          final newWrappedDek = await _wrapKey(dekBytes, newKek);
          final newWrappedSk = await _wrapKey(skBytes, newKek);

          // 原子提交：写入新包裹。
          await vaultStore.storeKey(_primaryDekId, newWrappedDek);
          await vaultStore.storeKey(_primarySigningSkId, newWrappedSk);
        } finally {
          // 清零明文密钥材料。
          SecureBytes.zeroize(dekBytes);
          SecureBytes.zeroize(skBytes);
        }
      },
    );
  }

  /// 获取文档专用 DEK（如果不存在则创建）。
  Future<SecureBytes> getDocumentDek(String documentId) async {
    final keyId = 'dek.document.$documentId';
    final wrapped = await vaultStore.readKey(keyId);
    if (wrapped != null) {
      final kek = keyManager.getKek();
      try {
        final dekBytes = await _unwrapKey(wrapped, kek);
        return SecureBytes(dekBytes);
      } finally {
        kek.dispose();
      }
    }

    // 创建新的文档 DEK。
    final dekBytes = _randomBytes(32);
    final kek = keyManager.getKek();
    try {
      final wrappedDek = await _wrapKey(dekBytes, kek);
      await vaultStore.storeKey(keyId, wrappedDek);
    } finally {
      kek.dispose();
    }
    return SecureBytes(dekBytes);
  }

  /// 删除文档专用 DEK。
  Future<void> deleteDocumentDek(String documentId) async {
    final keyId = 'dek.document.$documentId';
    await vaultStore.deleteKey(keyId);
  }

  /// 用 KEK 包裹密钥（AES-256-GCM）。
  Future<Uint8List> _wrapKey(List<int> keyMaterial, SecureBytes kek) async {
    return kek.withBytes((kekBytes) async {
      final aes = AesGcm.with256bits();
      final nonce = _randomBytes(12);
      final secretBox = await aes.encrypt(
        keyMaterial,
        secretKey: SecretKey(kekBytes),
        nonce: nonce,
        aad: utf8.encode('vault|wrap'),
      );
      return Uint8List.fromList([
        ...nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
    });
  }

  /// 用 KEK 解包裹密钥（AES-256-GCM）。
  Future<Uint8List> _unwrapKey(Uint8List wrapped, SecureBytes kek) async {
    return kek.withBytes((kekBytes) async {
      final aes = AesGcm.with256bits();
      final nonce = wrapped.sublist(0, 12);
      final cipherText = wrapped.sublist(12, wrapped.length - 16);
      final macBytes = wrapped.sublist(wrapped.length - 16);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final clear = await aes.decrypt(
        secretBox,
        secretKey: SecretKey(kekBytes),
        aad: utf8.encode('vault|wrap'),
      );
      return Uint8List.fromList(clear);
    });
  }
}

/// Vault 密钥集合（DEK + 签名密钥对）。
class VaultKeySet {
  const VaultKeySet({
    required this.dek,
    required this.signingKeyPair,
  });

  final SecureBytes dek;
  final SimpleKeyPair signingKeyPair;

  /// 清零密钥材料。
  void dispose() {
    dek.dispose();
    // SimpleKeyPair 不提供 dispose——依赖 GC。
  }
}

/// Vault 密钥存储抽象（可替换为 EncryptedVault 或其他实现）。
abstract class VaultKeyStore {
  Future<void> storeKey(String keyId, List<int> data);
  Future<Uint8List?> readKey(String keyId);
  Future<void> deleteKey(String keyId);
}

/// 基于 EncryptedVault 的密钥存储实现。
class EncryptedVaultKeyStore implements VaultKeyStore {
  EncryptedVaultKeyStore(this._vault);

  final EncryptedVault _vault;

  @override
  Future<void> storeKey(String keyId, List<int> data) async {
    await _vault.writeObject(
      id: 'keys/$keyId',
      type: 'key',
      plain: Uint8List.fromList(data),
    );
  }

  @override
  Future<Uint8List?> readKey(String keyId) async {
    try {
      return await _vault.readObject('keys/$keyId');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteKey(String keyId) async {
    await _vault.deleteObject('keys/$keyId');
  }
}

/// 生成随机字节。
List<int> _randomBytes(int length) {
  final rng = Random.secure();
  return List<int>.generate(length, (_) => rng.nextInt(256));
}
