import 'dart:io';
import 'dart:typed_data';

import '../../security/audit_log_store.dart';
import '../../security/secure_bytes.dart';
import '../../security/vault_key_manager.dart';
import 'encrypted_vault.dart';
import 'vault_manifest.dart';

/// VFS 统一服务（专家目标架构 VFS 接入层——2026-08-16）。
///
/// objectstore_service ObjectId 模式（usecase + key——'media/xxx'/
/// 'index/xxx'——命名空间分组——Sentry 官方）+ nimbus Origin 抽象
/// （存储后端可插拔——未来同步同一代码路径）+ 掘金密文存储（AES-GCM +
/// 受控密钥下发——路径/URL 泄露只泄露密文）+ 腾讯云 EncryptionContext
/// （加密上下文绑定——解密需同样上下文——防跨上下文解密）。
///
/// 业务层只跟 key 打交道（VireFS 模式）——put/get/list——自动加密/版本/
/// 原子提交（EncryptedVault 后端）。供媒体/笔记本/审计对象接入。
///
/// 2026-08-24 更新：集成 VaultKeyManager（KEK 持久化）+ 审计日志。
class VaultService {
  VaultService({
    required this.directory,
    VaultKeyManager? keyManager,
  }) : _keyManager = keyManager ?? VaultKeyManager();

  /// 全局实例（媒体读取双轨——'vfs:' 前缀对象——解锁时 [configure] + setKey）。
  static VaultService? _instance;

  /// 获取全局实例（未初始化抛 StateError——解锁时 configure）。
  static VaultService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('VaultService 未初始化（解锁时 configure）');
    }
    return i;
  }

  /// 初始化全局实例（解锁时——目录与媒体仓库对齐；幂等——同目录复用）。
  static VaultService configure(Directory directory) {
    final current = _instance;
    if (current != null && current.directory.path == directory.path) {
      return current;
    }
    final service = VaultService(directory: directory);
    _instance = service;
    return service;
  }

  final Directory directory;
  final VaultKeyManager _keyManager;

  SecureBytes? _sessionKey;
  AuditLogStore? _auditLog;

  /// VaultKeyManager 实例（用于密钥轮换）。
  VaultKeyManager get keyManager => _keyManager;

  /// 审计日志存储。
  AuditLogStore? get auditLog => _auditLog;

  /// 会话密钥是否已注入。
  bool get hasKey => _sessionKey != null && !_sessionKey!.isDisposed;

  /// 是否已解锁。
  bool get isUnlocked => _keyManager.isUnlocked;

  /// 注入会话密钥（解锁后——媒体/笔记本对象加密用——AAD 上下文绑定——
  /// 腾讯云 EncryptionContext 模式——解密需同样上下文）。
  void setKey(List<int> key) {
    _sessionKey?.dispose(); // 清零旧密钥。
    _sessionKey = SecureBytes(key);
  }

  /// 注入 SecureBytes 会话密钥（推荐——自动管理生命周期）。
  void setSecureKey(SecureBytes key) {
    _sessionKey?.dispose();
    _sessionKey = key;
  }

  /// 清除会话密钥（锁定时——D-2 内存清零语义）。
  void clearKey() {
    _sessionKey?.dispose();
    _sessionKey = null;
  }

  /// 锁定 Vault（清零内存中的密钥 + 审计日志密钥）。
  void lock() {
    clearKey();
    _keyManager.lock();
    _auditLog?.dispose();
    _auditLog = null;
  }

  /// 初始化审计日志（首次解锁后调用）。
  Future<void> initializeAuditLog(SecureBytes auditEncryptionKey) async {
    _auditLog = AuditLogStore(
      directory: Directory('${directory.path}/audit'),
      encryptionKey: auditEncryptionKey,
    );
    await _auditLog!.initialize();
  }

  /// 追加审计日志条目。
  Future<void> logAudit({
    required String action,
    required String content,
  }) async {
    await _auditLog?.append(action: action, content: content);
  }

  EncryptedVault get _vault {
    final key = _sessionKey;
    if (key == null || key.isDisposed) {
      throw StateError('VaultService 未注入密钥（解锁后调用 setKey）');
    }
    // 从 SecureBytes 获取视图（不拷贝）。
    return key.withBytes((bytes) {
      return EncryptedVault(directory: directory, key: bytes);
    });
  }

  /// 写入对象（key 标识——'media/xxx'/'index/xxx'——usecase 命名空间——
  /// 自动加密/版本递增/原子提交）。
  Future<VaultManifestEntry> putObject(
    String key, {
    required Uint8List plain,
    String type = 'blob',
  }) async {
    final entry = await _vault.writeObject(id: key, type: type, plain: plain);
    await logAudit(
      action: 'vault.write',
      content: 'key=$key, type=$type, size=${plain.length}',
    );
    return entry;
  }

  /// 读取对象（key 标识——自动解密 + AAD 验证——篡改/错上下文认证失败）。
  Future<Uint8List> getObject(String key) async {
    final data = await _vault.readObject(key);
    await logAudit(
      action: 'vault.read',
      content: 'key=$key, size=${data.length}',
    );
    return data;
  }

  /// 对象清单（当前版本/大小/AAD 上下文）。
  Future<List<VaultManifestEntry>> listObjects() => _vault.listObjects();
}
