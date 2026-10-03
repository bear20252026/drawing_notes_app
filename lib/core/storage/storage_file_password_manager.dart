import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_media_store.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

// C-08（审计 2026-09-27）：自 StorageService 的 part 五域拆为真协作类。
// 本类承载**文件密码域**公开 API（批次②/N2：v2/v3 密码信封 + U 盘重置
// 槽位）：校验/设置/修改/绑定重置盘/重置/移除。所有重封落盘挂入
// per-document 独占队列（E-17）——与在途保存/删除交错时按请求顺序执行。
// StorageService 保留门面，消费方 API 零变化。

/// 文件密码域：画作级独立密码的完整管理面。
class StorageFilePasswordManager {
  StorageFilePasswordManager({
    required this.directories,
    required this.secrets,
    required this.pipeline,
    required this.media,
    required this.fireOnWrite,
  });


  /// 内部协作面：仅 StorageService 门面装配（C-08 拆分协作类，只读）。
  final StorageDirectories directories;
  final StorageSecretSession secrets;
  final StorageWritePipeline pipeline;
  final StorageMediaStore media;
  final void Function() fireOnWrite;

  /// 读取当前正式文件（缺失回退 .bak）；两者都不存在返回 null。
  Future<Uint8List?> _readCurrentRaw(String id) async {
    await directories.ensureDocuments();
    final file = File(directories.documentPathFor(id));
    final bak = File('${file.path}.bak');
    if (file.existsSync()) return file.readAsBytes();
    if (bak.existsSync()) return bak.readAsBytes();
    return null;
  }

  /// 该文档是否受独立文件密码保护（读文件头版本字节，不解密）。
  Future<bool> isFilePasswordProtected(String id) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null) return false;
    return VaultFileCodec.isPasswordEnvelope(raw);
  }

  /// 校验文件密码；正确则缓存进会话（解锁一次本会话免重复输入）。
  /// v3 信封同时缓存 DEK / USB 槽位（续写续用）。
  Future<bool> verifyFilePassword(String id, String password) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) return false;
    try {
      if (VaultFileCodec.isV3Envelope(raw)) {
        final unlock = await VaultFileCodec.unlockWithPasswordV3(
          raw,
          password,
          aadContext: 'doc:$id',
        );
        secrets.cacheV3Material(id, unlock);
      } else {
        await VaultFileCodec.decryptWithPassword(
          raw,
          password,
          aadContext: 'doc:$id',
        );
      }
    } on VaultFileException {
      return false;
    }
    secrets.cacheFilePassword(id, password);
    return true;
  }

  /// 该文档是否绑定了重置密码盘（v3 信封且含 USB 槽位；读头部不解密）。
  Future<bool> hasFileUsbSlot(String id) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null) return false;
    return VaultFileCodec.hasUsbSlotV3(raw);
  }

  /// 为未设密文档设置独立文件密码（v3 双保护器信封重封 + 删除缩略图）。
  ///
  /// 前提：文档当前为明文或 v1 主密钥信封（应用锁已解锁时可读）。
  /// 已设密时抛 [StateError]（走 [changeFilePassword]）。
  /// [resetDiskKey] 非空时同时嵌入重置盘槽位（设密时插盘绑定——LUKS
  /// 同款：U 盘钥匙不在设备上，错过本次可事后走 [bindFileUsbSlot]）。
  ///
  /// E-17 同步（审计 2026-09-07）：重封落盘挂入该文档的 per-document
  /// 独占队列——与在途保存/删除交错时按请求顺序执行，且保证在队列中
  /// 重新读取最新已落盘明文后再重封（非陈旧快照）。
  Future<void> setFilePassword(
    String id,
    String password, {
    List<int>? resetDiskKey,
  }) {
    // P1 fail-closed（空密码收口第三层）：空串绝不封成「已加密」信封
    // ——UI 与收集方各有前置校验，此处兜底任何绕过路径。
    if (password.isEmpty) throw ArgumentError('密码不能为空');
    return pipeline.runDocExclusive(
      id,
      () => _setFilePasswordLocked(id, password, resetDiskKey: resetDiskKey),
    );
  }

  Future<void> _setFilePasswordLocked(
    String id,
    String password, {
    List<int>? resetDiskKey,
  }) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null) {
      throw StateError('文档不存在');
    }
    if (VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档已设置文件密码，请使用修改密码');
    }
    // 取明文：v1 信封需主密钥（锁定时 fail-closed）。
    Uint8List plain;
    if (VaultFileCodec.isEncrypted(raw)) {
      final key = await pipeline.currentKey();
      if (key == null) throw const VaultFileLockException();
      plain = await VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
    } else {
      plain = raw;
    }
    // DEK 由会话生成并缓存（续写复用，重置盘槽位跨保存有效的前提）。
    final dek = VaultFileCodec.generateDek();
    final usbWrapped = resetDiskKey == null
        ? null
        : await VaultFileCodec.wrapUsbSlotV3(
            usbKey: resetDiskKey,
            dek: dek,
            aadContext: 'doc:$id',
          );
    secrets.cacheFilePassword(id, password);
    secrets.cacheDekMaterial(id, dek, usbWrapped);
    try {
      final sealed = await VaultFileCodec.encryptWithPasswordV3(
        plain,
        password,
        aadContext: 'doc:$id',
        dek: dek,
        usbWrapped: usbWrapped,
      );
      await pipeline.writeSealedBytes(id, sealed);
    } catch (_) {
      secrets.forgetFilePassword(id); // 密封失败不残留会话密码（防后续写回明文语义错乱）
      rethrow;
    }
    await media.deleteThumbnail(id);
    fireOnWrite();
  }

  /// 修改文件密码（验证旧密码 → 重封）。旧密码错误抛 [VaultFileException]。
  ///
  /// N4 批 2：v2 旧文件自动升级为 v3（引入 DEK，暂无重置盘槽位——可
  /// 事后绑定）；v3 文件 DEK 与重置盘槽位原样保留（改密≠换钥匙）。
  ///
  /// E-17 同步（审计 2026-09-07）：重封落盘挂入 per-document 独占队列，
  /// 与在途保存/删除交错时按请求顺序执行（重新读取最新文件再重封）。
  Future<void> changeFilePassword(
    String id,
    String oldPassword,
    String newPassword,
  ) {
    // P1 fail-closed：新密码空串拒绝（旧密码允许历史遗留空值通过校验，
    // 否则既有已设空密码的文档将无法改密自救）。
    if (newPassword.isEmpty) throw ArgumentError('密码不能为空');
    return pipeline.runDocExclusive(
      id,
      () => _changeFilePasswordLocked(id, oldPassword, newPassword),
    );
  }

  Future<void> _changeFilePasswordLocked(
    String id,
    String oldPassword,
    String newPassword,
  ) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档未设置文件密码');
    }
    if (VaultFileCodec.isV3Envelope(raw)) {
      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        raw,
        oldPassword,
        aadContext: 'doc:$id',
      ); // 旧密码错误在此抛出——会话缓存尚未改动
      secrets.cacheV3Material(id, unlock);
      secrets.cacheFilePassword(id, newPassword);
      try {
        final sealed = await VaultFileCodec.encryptWithPasswordV3(
          unlock.plain,
          newPassword,
          aadContext: 'doc:$id',
          dek: unlock.dek,
          usbWrapped: unlock.usbWrapped,
        );
        await pipeline.writeSealedBytes(id, sealed);
      } catch (_) {
        secrets.cacheFilePassword(id, oldPassword); // 回滚会话缓存到仍有效的旧密码
        rethrow;
      }
      await media.deleteThumbnail(id);
      fireOnWrite();
      return;
    }
    final plain = await VaultFileCodec.decryptWithPassword(
      raw,
      oldPassword,
      aadContext: 'doc:$id',
    );
    // v2 → v3 升级：生成新 DEK，暂不嵌重置盘槽位（钥匙不在设备上）。
    final dek = VaultFileCodec.generateDek();
    secrets.cacheDekMaterial(id, dek, null);
    secrets.cacheFilePassword(id, newPassword);
    try {
      final sealed = await VaultFileCodec.encryptWithPasswordV3(
        Uint8List.fromList(plain),
        newPassword,
        aadContext: 'doc:$id',
        dek: dek,
      );
      await pipeline.writeSealedBytes(id, sealed);
    } catch (_) {
      secrets.cacheFilePassword(id, oldPassword); // 回滚会话缓存到仍有效的旧密码
      rethrow;
    }
    await media.deleteThumbnail(id);
    fireOnWrite();
  }

  /// 绑定重置密码盘到已设密文档（事后绑定通道；须验证文件密码）。
  /// 已绑定 / 非 v3 信封抛 [StateError]；密码错误抛 [VaultFileException]。
  ///
  /// E-17 同步（审计 2026-09-07）：重封落盘挂入 per-document 独占队列
  /// （避免与在途保存交错的陈旧读取/覆盖）。
  Future<void> bindFileUsbSlot(String id, String password, List<int> usbKey) {
    return pipeline.runDocExclusive(
      id,
      () => _bindFileUsbSlotLocked(id, password, usbKey),
    );
  }

  Future<void> _bindFileUsbSlotLocked(
    String id,
    String password,
    List<int> usbKey,
  ) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档未设置文件密码');
    }
    if (!VaultFileCodec.isV3Envelope(raw)) {
      throw StateError('旧版密码文件：请先修改一次密码升级格式后再绑定');
    }
    if (VaultFileCodec.hasUsbSlotV3(raw)) {
      throw StateError('该文档已绑定重置密码盘');
    }
    final unlock = await VaultFileCodec.unlockWithPasswordV3(
      raw,
      password,
      aadContext: 'doc:$id',
    );
    final usbWrapped = await VaultFileCodec.wrapUsbSlotV3(
      usbKey: usbKey,
      dek: unlock.dek,
      aadContext: 'doc:$id',
    );
    final sealed = await VaultFileCodec.encryptWithPasswordV3(
      unlock.plain,
      password,
      aadContext: 'doc:$id',
      dek: unlock.dek,
      usbWrapped: usbWrapped,
    );
    secrets.cacheV3Material(
      id,
      VaultFileV3Unlock(unlock.plain, unlock.dek, usbWrapped),
    );
    secrets.cacheFilePassword(id, password);
    await pipeline.writeSealedBytes(id, sealed);
    await media.deleteThumbnail(id);
    fireOnWrite();
  }

  /// 重置密码盘重置文件密码（N4 批 2：忘记密码通道）。
  ///
  /// USB 钥匙解出 DEK → 新盐重绕密码槽（载荷密文与重置盘槽位原样保留，
  /// LUKS 同款）。**不需要旧密码**；成功后会话已缓存新密码（可直接打开）。
  /// 非密码信封 / 未绑定重置盘 / 盘不匹配 → 返回 false（fail-closed）。
  ///
  /// E-17 同步（审计 2026-09-07）：重封落盘挂入 per-document 独占队列。
  Future<bool> resetFilePasswordWithUsb(
    String id,
    List<int> usbKey,
    String newPassword,
  ) {
    // P1 fail-closed：重置即设新密码，空串拒绝。
    if (newPassword.isEmpty) throw ArgumentError('密码不能为空');
    return pipeline.runDocExclusive(
      id,
      () => _resetFilePasswordWithUsbLocked(id, usbKey, newPassword),
    );
  }

  Future<bool> _resetFilePasswordWithUsbLocked(
    String id,
    List<int> usbKey,
    String newPassword,
  ) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isV3Envelope(raw)) return false;
    final VaultFileV3Rewrap rewrap;
    try {
      rewrap = await VaultFileCodec.rewrapPasswordSlotV3(
        raw,
        usbKey,
        newPassword,
        aadContext: 'doc:$id',
      );
    } on VaultFileException {
      return false;
    }
    secrets.cacheDekMaterial(id, rewrap.dek, rewrap.usbWrapped);
    secrets.cacheFilePassword(id, newPassword);
    await pipeline.writeSealedBytes(id, rewrap.blob);
    await media.deleteThumbnail(id);
    fireOnWrite();
    return true;
  }

  /// 移除文件密码：回封为 v1 主密钥信封（应用锁未解锁时拒绝——
  /// 明文落盘不可接受，fail-closed）。密码错误抛 [VaultFileException]。
  ///
  /// E-17 同步（审计 2026-09-07）：回封落盘挂入 per-document 独占队列，
  /// 避免与在途保存交错的陈旧读取/覆盖。
  Future<void> removeFilePassword(String id, String password) {
    return pipeline.runDocExclusive(
      id,
      () => _removeFilePasswordLocked(id, password),
    );
  }

  Future<void> _removeFilePasswordLocked(String id, String password) async {
    final raw = await _readCurrentRaw(id);
    if (raw == null || !VaultFileCodec.isPasswordEnvelope(raw)) {
      throw StateError('该文档未设置文件密码');
    }
    Uint8List plain;
    if (VaultFileCodec.isV3Envelope(raw)) {
      final unlock = await VaultFileCodec.unlockWithPasswordV3(
        raw,
        password,
        aadContext: 'doc:$id',
      );
      secrets.cacheV3Material(id, unlock);
      plain = unlock.plain;
    } else {
      plain = await VaultFileCodec.decryptWithPassword(
        raw,
        password,
        aadContext: 'doc:$id',
      );
    }
    final key = await pipeline.currentKey();
    if (key == null) {
      throw const VaultFileLockException();
    }
    final sealed = await VaultFileCodec.encrypt(
      plain,
      key,
      aadContext: 'doc:$id',
    );
    secrets.forgetFilePassword(id);
    await pipeline.writeSealedBytes(id, sealed);
    fireOnWrite();
  }
}
