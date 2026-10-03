// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 同步应用服务（C-05，审计 2026-09-27）：同步用例门面 + 装配收口。
//
// 审计条目 C-05：设置页（presentation）此前自行 new 基础设施 store
// （WebDavConfigStore + SecureSyncSecretStore）、自选加密方案（Noop/AES +
// PBKDF2 派生）并直接构建 SyncService（transport/documentStore/baselineStore
// 全套装配）——DI 旁路。本类把装配收进 application 层：
// - presentation 只与本门面对话（构造注入，页面不再 import 基础设施模块）；
// - 组合根（AppServices → AppShell → SettingsPage）注入，生产路径恒有；
// - 默认装配生产实现，构造参数留注入口（测试用内存/临时目录实现）。
//
// 风格贴近 lib/app/app_services.dart 门面：持有 store 实例、无 dispose 语义
// （store 与 App 同生命周期；每次同步的 transport 在 syncNow 内用毕即 close）。

import 'dart:convert';

import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_sync_store.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_cipher.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/core/sync/sync_retry_policy.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/file_sync_baseline_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/sync_secret_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/webdav_config_store.dart';

/// presentation 所需的纯值类型随门面再导出：页面无需直接 import 传输/服务
/// 实现文件（C-05：presentation 不再触碰 SyncService / 传输客户端模块，
/// 只保留纯 DTO / 异常类型的可见性）。
export 'package:drawing_notes_app/core/sync/sync_service.dart' show SyncResult;
export 'package:drawing_notes_app/core/storage/webdav_sync_client.dart'
    show WebDavSyncException;

/// 一次同步的收敛结果（成功带 [result]，失败带最后一次 [error]）。
///
/// [error] 可能为 Exception/Error（同步失败原样），也可能为 String
/// （重试策略文案，如「达到最大重试次数」）——与原设置页 `_runWithRetry`
/// 的返回形状一致，由 humanizeWebDavSyncError 统一转人话。
typedef SyncRunOutcome = ({SyncResult? result, Object? error});

/// WebDAV 同步控制器：设置页的用例门面（加载配置 / 保存 / 立即同步）。
class SyncController {
  /// [configStore]/[secretStore]/[documentStore]/[baselineStore] 可注入
  /// （测试用内存实现/临时目录实现）；缺省装配生产实现。
  ///
  /// documentStore 默认自建 [NoteBlockDocStore] 并接共享保险库密钥——
  /// 保险库解锁时同步能读写 DNV 密文文档（锁定时 keyProvider 返回 null，
  /// fail-closed）。刻意不复用 AppServices.blockDocStore（后者无 keyProvider，
  /// 同步语义不同）。
  SyncController({
    WebDavConfigStore? configStore,
    SyncSecretStore? secretStore,
    SyncDocumentStore? documentStore,
    SyncBaselineStore? baselineStore,
  }) : _configStore = configStore ?? WebDavConfigStore(SecureSyncSecretStore()),
       _secretStore = secretStore ?? SecureSyncSecretStore(),
       _documentStore =
           documentStore ??
           NoteBlockDocSyncStore(
             NoteBlockDocStore(
               keyProvider: () async => VaultKeyService.sharedMasterKeyOrNull,
             ),
           ),
       _baselineStore = baselineStore ?? FileSyncBaselineStore();

  final WebDavConfigStore _configStore;
  final SyncSecretStore _secretStore;
  final SyncDocumentStore _documentStore;
  final SyncBaselineStore _baselineStore;

  /// 保存前 TLS 门禁（与保存路径同一预检）：非空 baseUrl 必须 https
  /// （本地回环 http 例外）。非法抛 [ArgumentError]。
  static void requireHttpsBaseUrl(String baseUrl) =>
      WebDavConfigStore.requireHttpsBaseUrl(baseUrl);

  /// 读取非机密同步配置（baseUrl / username / syncSalt）。
  Future<WebDavSyncConfig> loadConfig() => _configStore.load();

  /// 读取机密（WebDAV 密码 / 同步口令；OS 凭据库）。
  Future<SyncSecrets> readSecrets() => _secretStore.read();

  /// 保存配置 + 机密（S-03 方案 A 语义在此收口）。
  ///
  /// - 空表单值 = 沿用已存（明文不回填，空是常态）——把「未改」与「清空」
  ///   合并为同一分支，本页不提供「删除已存口令」入口（footgun：清空后
  ///   同步要么认证失败、要么被 fail-closed 挡住）；
  /// - 口令非空时复用已有盐（保证派生 key 对已上传密文稳定），无盐则生成；
  /// - https 门禁抛 [ArgumentError] 时不上盘任何数据（fail-closed），
  ///   由调用方捕获后向用户明示。
  ///
  /// 返回合并已存后的生效机密，供页面刷新「已保存」存在性标记。
  Future<({String password, String passphrase})> save({
    required String baseUrl,
    required String username,
    required String password,
    required String passphrase,
  }) async {
    final existing = await _configStore.load();
    final stored = await _secretStore.read();
    // S-03 方案 A：空输入框 = 沿用已存口令（明文不回填，空是常态）。
    final effectivePassphrase =
        passphrase.trim().isNotEmpty
            ? passphrase.trim()
            : (stored.syncPassphrase ?? '');
    final effectivePassword =
        password.isNotEmpty ? password : (stored.webdavPassword ?? '');
    String? saltBase64;
    if (effectivePassphrase.isNotEmpty) {
      // 复用已有盐（若无则生成新的），保证派生 key 对已上传密文保持稳定。
      saltBase64 = existing.syncSalt;
      if (saltBase64 == null || saltBase64.isEmpty) {
        saltBase64 = base64Encode(generateSalt());
      }
    }
    // P1 修复：save 内 https 门禁抛 ArgumentError——调用方捕获后明示，不崩溃。
    await _configStore.save(
      WebDavSyncConfig(
        baseUrl: baseUrl.trim(),
        username: username.trim(),
        syncSalt: saltBase64,
      ),
    );
    await _secretStore.write(
      SyncSecrets(
        webdavPassword: effectivePassword.isEmpty ? null : effectivePassword,
        syncPassphrase:
            effectivePassphrase.isEmpty ? null : effectivePassphrase,
      ),
    );
    return (password: effectivePassword, passphrase: effectivePassphrase);
  }

  /// 组装并执行一次完整同步（transport + cipher + SyncService + 有界重试）。
  ///
  /// - 加密方案在此收口（C-05「自选加密方案」上移）：已配置口令（含盐）→
  ///   派生主密钥用 AES；否则 Noop（明文透传）。
  /// - 装配失败（如 KDF 派生异常）原样抛出；同步执行失败经 [SyncRetryPolicy]
  ///   有界收敛，以 outcome.error 返回（不抛）——与原设置页行为一致。
  /// - 每次同步独立构建 transport，用毕 [SyncService.close]（finally）。
  Future<SyncRunOutcome> syncNow({
    required Uri baseUrl,
    required String username,
    required String password,
    required String passphrase,
    required String? syncSalt,
    required ConflictHandler conflictHandler,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final cipher = await _buildCipher(
      syncSalt: syncSalt,
      syncPassphrase: passphrase,
    );
    final service = SyncService(
      transport: WebDavSyncClient(
        baseUrl: baseUrl,
        username: username,
        // S-03 方案 A：口令不回填 → 用生效值（表单非空 ? 表单 : 已存），
        // 否则留空提交会拿空串去认证。
        password: password,
      ),
      documentStore: _documentStore,
      baselineStore: _baselineStore,
      cipher: cipher,
      conflictHandler: conflictHandler,
      onProgress: onProgress,
    );
    try {
      // 有界自动重试：派生密钥复用同一 service，失败按策略退避。
      final retry = SyncRetryPolicy();
      final start = DateTime.now();
      var attempt = 0;
      while (attempt < retry.maxAttempts) {
        try {
          final r = await service.syncNow();
          return (result: r, error: null);
        } catch (e) {
          attempt++;
          if (attempt >= retry.maxAttempts) {
            return (result: null, error: e);
          }
          final elapsed = DateTime.now().difference(start);
          final input = SyncRetryInput(failureCount: attempt, elapsed: elapsed);
          final decision = retry.decide(input);
          if (decision == SyncRetryDecision.giveUp) {
            return (result: null, error: e);
          }
          final wait = retry.delayFor(attempt);
          if (wait > Duration.zero) await Future<void>.delayed(wait);
        }
      }
      // 不可达兜底（与原实现同构）：循环能退出即 attempt 已达上限，
      // 上方 catch 已先行 return。
      return (result: null, error: '达到最大重试次数');
    } finally {
      service.close();
    }
  }

  // 已配置口令（含盐）→ 派生主密钥并用 AES 加密器；否则用 Noop（明文透传）。
  Future<SyncCipher> _buildCipher({
    required String? syncSalt,
    required String syncPassphrase,
  }) async {
    if (syncSalt == null || syncSalt.isEmpty || syncPassphrase.isEmpty) {
      return const NoopSyncCipher();
    }
    final salt = base64Decode(syncSalt);
    final key = await deriveMasterKey(syncPassphrase, salt);
    return AesSyncCipher(key: key);
  }
}
