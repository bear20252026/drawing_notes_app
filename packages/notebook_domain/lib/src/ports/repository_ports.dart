// notebook_domain——仓库端口（专家 I-006——2026-08-16——批次 A）。
//
// 依赖单向（专家 R-02/R-03）：Use Cases 依赖这些接口——具体实现（加密
// 存储/平台 IO）在 infrastructure adapter——domain 不依赖实现。纯 Dart
// （禁 Widget/BuildContext/Platform/File）。

/// 笔记本仓库端口（打开/保存/锁定——实现为 EncryptedNotebookRepositoryV2）。
abstract interface class NotebookRepositoryPort {
  /// 打开笔记本（返回会话句柄/认证载荷）。
  Future<String> open(String notebookId);

  /// 保存认证后密文载荷（主/备/临时均无明文——I-004）。
  Future<void> save(String notebookId, List<int> authenticatedPayload);

  /// 锁定笔记本（清除 scoped 密钥——R-05 锁定阻断）。
  Future<void> lock(String notebookId);
}

/// 媒体仓库端口（按 notebookId 隔离——实现为 MediaRepositoryV2——
/// 对象清单/所有者校验——I-009）。
abstract interface class MediaRepositoryPort {
  Future<List<int>> read(String notebookId, String mediaId);
  Future<String> store(String notebookId, List<int> plain);
}

/// 密钥提供端口（会话密钥/KDF——实现为平台 KeyStore/adapter——
/// KeyHandle/LockPolicy 由 notebook_domain.session 持有）。
abstract interface class KeyProviderPort {
  Future<List<int>> deriveKey(String passphrase, List<int> salt);
}
