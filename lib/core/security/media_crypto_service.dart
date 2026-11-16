import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/security/session_secrets.dart';

// MediaSalt（全局媒体盐 + KDF 版本）已删除（K_note 接线 2026-11-16）：
// 媒体加密不再走「全局会话密码 + 持久盐」派生，改用每笔记本 K_note
// （v5 信封 slots.media 封存，AAD 绑定笔记本 ID）——无盐文件、无全局密钥。

/// 媒体加密服务（H-03 跨域专项基础组件；K_note 生产接线 2026-11-16）。
///
/// BusinessCrypto 层：媒体资产（图片/PDF 副本）的加密逻辑集中于此，
/// **不把长期密钥暴露给业务模块**。
///
/// **K_note 唯一口径（2026-11-16，业主确认无存量用户、不兼容旧格式）**：
/// 每笔记本一把独立媒体密钥 K_note（32B CSPRNG），封存在笔记本 v5 信封的
/// `slots.media`（DEK 包裹，AAD 绑定笔记本 ID）。媒体加解密一律
/// `encryptFile(notebookId, …)` / `readMediaFile(notebookId, …)` 按笔记本
/// 取钥；AAD 恒为 `drawing-notes|media|v1|<notebookId>`——**无全局密钥
/// 回退**（防跨笔记密文交换；一笔记密钥泄露不影响其他笔记）。
/// 旧「全局会话密码派生」路径（setSessionPassword/setSessionKey）已删除。
///
/// **LRU 密钥映射（业主决策 2026-11-15）**：最多驻留 [maxNotebookKeys]（32）
/// 本笔记的 K_note；超限逐出最久未用并**立即零化**（用时再从信封解包）。
///
/// 注册为 [SessionSecretsHolder]（P0-7）：回锁/切后台经 SessionSecrets
/// 统一清零全部驻留 K_note。
class MediaCryptoService implements SessionSecretsHolder {
  MediaCryptoService._() {
    SessionSecrets.register(this);
  }

  // C-06 裁决（审计 2026-09-27）：features/shared 零 `.instance` 直取，
  // 消费方一律构造注入（门禁 security_static_access_gate_test 锁死）。
  static final MediaCryptoService instance = MediaCryptoService._();

  /// LRU 上限（业主决策：32 本）。超限逐出最久未用并零化。
  static const int maxNotebookKeys = 32;

  /// notebookId → K_note（LinkedHashMap 插入序 = LRU 序；命中即移到队尾）。
  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  /// 注入某笔记本的 K_note（调用方从 v5 信封解包后传入）。复制入参；
  /// 重复注入同笔记本 = 覆盖（旧值零化）；超 LRU 上限逐出最久未用。
  void setNotebookKey(String notebookId, List<int> noteKey) {
    final prev = _keys.remove(notebookId);
    if (prev != null) prev.fillRange(0, prev.length, 0);
    _keys[notebookId] = Uint8List.fromList(noteKey);
    while (_keys.length > maxNotebookKeys) {
      final oldest = _keys.keys.first;
      final evicted = _keys.remove(oldest)!;
      evicted.fillRange(0, evicted.length, 0); // 逐出即零化。
    }
  }

  /// 某笔记本的 K_note 是否已驻留。
  bool hasKeyFor(String notebookId) => _keys.containsKey(notebookId);

  /// 清除某笔记本密钥（锁定/离开——fillRange 主动擦除，D-2 模式）。
  void clearNotebookKey(String notebookId) {
    final key = _keys.remove(notebookId);
    if (key != null) key.fillRange(0, key.length, 0);
  }

  /// 清除全部驻留 K_note（退出/锁定）。
  void clearSessionKey() {
    for (final key in _keys.values) {
      key.fillRange(0, key.length, 0);
    }
    _keys.clear();
  }

  @override
  void clearAllSessionSecrets() => clearSessionKey();

  /// 是否有任一笔记本密钥驻留（storeImage 加密分支判据）。
  bool get isActive => _keys.isNotEmpty;

  /// 生成 32B 随机 K_note（新笔记本/懒补槽用）。
  static List<int> generateNotebookKey() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  Uint8List _requireKey(String notebookId) {
    final key = _keys[notebookId];
    if (key == null) {
      throw StateError('笔记本媒体密钥未注入（请先解锁该笔记本）');
    }
    // LRU 命中：移到队尾（LinkedHashMap remove+重插）。
    _keys.remove(notebookId);
    _keys[notebookId] = key;
    return key;
  }

  /// 加密媒体字节（AES-256-GCM——载荷 = [nonce(12), cipherText, tag(16)]，
  /// AAD 绑定用途 + 笔记本 ID）。
  Future<Uint8List> encryptBytes(String notebookId, Uint8List plain) async {
    // 密钥快照（框架级收口 2026-11-15，审计 M-3）：_requireKey 返回映射内
    // 活缓冲——await 期间回锁/逐出 fillRange 会清零同一缓冲（use-after-zero，
    // 可能以全零密钥产出「合法」密文）。入口复制快照，构造性消除该竞态；
    // 快照用完即焚（零化口径）。
    final key = Uint8List.fromList(_requireKey(notebookId));
    try {
      return await _encryptBytesWithKey(notebookId, plain, key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<Uint8List> _encryptBytesWithKey(
    String notebookId,
    Uint8List plain,
    Uint8List key,
  ) async {
    final aes = AesGcm.with256bits();
    final rng = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => rng.nextInt(256)),
    );
    final box = await aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _aadFor(notebookId),
    );
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// 解密媒体字节（EncryptedFileImage 渲染用）；密钥错误/损坏抛异常。
  /// AAD 不符即认证失败，不做第二次尝试（防 AAD 降级试探旁路）。
  Future<Uint8List> decryptBytes(String notebookId, Uint8List data) async {
    // 密钥快照（同 encryptBytes——M-3 use-after-zero 构造性消除）。
    final key = Uint8List.fromList(_requireKey(notebookId));
    try {
      return await _decryptBytesWithKey(notebookId, data, key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<Uint8List> _decryptBytesWithKey(
    String notebookId,
    Uint8List data,
    Uint8List key,
  ) async {
    if (data.length <= 28) throw FormatException('媒体密文长度不合法');
    final nonce = data.sublist(0, 12);
    final cipher = data.sublist(12, data.length - 16);
    final mac = data.sublist(data.length - 16);
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
      aad: _aadFor(notebookId),
    );
    return Uint8List.fromList(clear);
  }

  /// 媒体 AAD：应用/用途/版本 + 笔记本 ID（NIST SP 800-38D 上下文绑定，
  /// Knovya note_id binding——防跨笔记密文交换）。**恒含 notebookId**。
  static final Uint8List _mediaAad = Uint8List.fromList(
    utf8.encode('drawing-notes|media|v1'),
  );

  static Uint8List _aadFor(String notebookId) => Uint8List.fromList(
    [..._mediaAad, ...utf8.encode('|$notebookId')],
  );

  /// 媒体密文文件头魔数：AES 密文与随机噪声不可区分——应用层文件头标记。
  static const List<int> _fileMagic = [0x44, 0x41, 0x4E]; // 'DAN'
  static const int _fileVersion = 1;

  /// 加密并封装为文件格式：[DAN, 版本, ...密文载荷]。
  Future<Uint8List> encryptFile(String notebookId, Uint8List plain) async {
    final payload = await encryptBytes(notebookId, plain);
    return Uint8List.fromList([..._fileMagic, _fileVersion, ...payload]);
  }

  /// 读取媒体文件：DAN 文件头 → 按笔记本 K_note 解密；否则原样返回
  /// （未加密笔记本的明文媒体——非密文不涉及密钥）。
  Future<Uint8List> readMediaFile(String notebookId, Uint8List data) async {
    if (isEncryptedFile(data)) {
      return decryptBytes(notebookId, Uint8List.fromList(data.sublist(4)));
    }
    return data;
  }

  /// 检测媒体文件是否为 DAN 密文。
  static bool isEncryptedFile(List<int> data) =>
      data.length >= 4 &&
      data[0] == _fileMagic[0] &&
      data[1] == _fileMagic[1] &&
      data[2] == _fileMagic[2];
}
