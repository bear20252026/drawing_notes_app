import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';

/// 媒体加密盐 + KDF 版本（M1 修复 2026-11-11）。
///
/// 旧版 `media_crypto_salt` 文件只持久 16B 盐，KDF 在 `setSessionPassword`
/// 里硬编码 PBKDF2-600k——Argon2id 升级无法只靠换 KDF 参数实现（旧盐
/// 派生的媒体会全部解不开）。故盐文件升级为带版本前缀的自描述格式：
/// `[1B 版本][16B 盐]`。读路径按版本分派 KDF，新写入恒用 Argon2id。
///
/// 版本 1（旧文件，无前缀）：PBKDF2-HMAC-SHA256 600k（向后兼容读旧数据）。
/// 版本 2（新写入）：Argon2id 生产参数（64 MiB / t2 / p2）。
class MediaSalt {
  const MediaSalt({required this.bytes, required this.kdf});

  /// 16 字节盐（明文无害）。
  final List<int> bytes;

  /// 本盐对应的 KDF 参数（版本分派的单一事实来源）。
  final KdfParams kdf;

  /// 旧文件格式常量：纯 16B 盐，无版本前缀 ⇒ 版本 1。
  static const int legacyFileLength = 16;
  static const int versionByteCount = 1;
  static const int saltLength = 16;

  /// 版本 1 的 KDF（PBKDF2-600k）——与 H-03 时代产线一致。
  static const KdfParams legacyKdf = KdfParams.pbkdf2(600000);

  /// 版本 2 的 KDF（Argon2id 生产）——新写入一律用它。
  static const KdfParams argon2idKdf = KdfParams.argon2idProduction;

  /// 版本 1 标记（旧文件无显式版本字节，靠长度判定）。
  static const int versionLegacy = 1;
  static const int versionArgon2id = 2;

  /// 解析盐文件字节：
  /// - 恰好 16B ⇒ 旧版（版本 1，PBKDF2）。
  /// - 17B 且首字节 == 2 ⇒ 版本 2（Argon2id）。
  /// - 其余 ⇒ [ArgumentError]（fail-closed：不猜，避免用错 KDF 解不开
  ///   已加密媒体）。
  factory MediaSalt.parse(List<int> raw) {
    if (raw.length == legacyFileLength) {
      return MediaSalt(bytes: List.of(raw), kdf: legacyKdf);
    }
    if (raw.length == versionByteCount + saltLength) {
      final v = raw[0];
      if (v == versionArgon2id) {
        return MediaSalt(
          bytes: List.of(raw.sublist(versionByteCount)),
          kdf: argon2idKdf,
        );
      }
    }
    throw ArgumentError('媒体加密盐文件格式无法识别（长度 ${raw.length}）');
  }

  /// 序列化为盐文件字节（新写入恒为版本 2 + 16B 盐）。
  List<int> encode() => [versionArgon2id, ...bytes];

  /// 旧版纯盐（16B）——供测试与向后兼容路径使用。
  static MediaSalt legacy(List<int> bytes) =>
      MediaSalt(bytes: List.of(bytes), kdf: legacyKdf);

  @override
  bool operator ==(Object other) =>
      other is MediaSalt &&
      other.kdf == kdf &&
      _listEquals(other.bytes, bytes);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(kdf, Object.hashAll(bytes));

  @override
  String toString() => 'MediaSalt(kdf=$kdf, salt=${bytes.length}B)';
}

/// 媒体加密服务（H-03 跨域专项基础组件，专家审计 2026-08-15）。
///
/// BusinessCrypto 层（掘金 HUKS 四层架构模式）：媒体资产（图片/PDF 副本）
/// 的加密逻辑集中于此，**不把长期密钥暴露给业务模块**；会话密钥解锁后
/// 注入（setSessionKey）、退出/锁定时清除（clearSessionKey——D-2 内存
/// 清理模式）。storeImage 加密写入与 EncryptedFileImage 渲染解密均经此
/// 服务（Flutter 官方 DI 模式：服务注入，密钥不散传）。
///
/// 注册为 [SessionSecretsHolder]（P0-7，审计 2026-10-09）：此前会话媒体
/// 密钥只在笔记本页 dispose 时清理——搜索页/路由仅注入密码就派生密钥、
/// 导航离开后无任何生命周期钩子清它，AppLockGate.hidden 的 SessionSecrets
/// 联动也够不到。注册后切后台统一掉锁清零。
class MediaCryptoService implements SessionSecretsHolder {
  MediaCryptoService._() {
    SessionSecrets.register(this);
  }

  // C-06 裁决（审计 2026-09-27，2026-10-03 落地）：对外全局可达性已收敛——
  // features/shared 零 `.instance` 直取（消费方一律构造注入，实例由组合根
  // 装配：AppServices 缺省持有 + app.dart/default_editor_page_builder 组装
  // 传线），由 test/security_static_access_gate_test.dart 门禁锁死；core
  // 内部互调（kek_session_cache 派生等）属解锁生命周期作用域的会话单例
  // 实现细节，保留静态语义、不注入。本体收敛留后续批次。
  static final MediaCryptoService instance = MediaCryptoService._();

  List<int>? _sessionKey;
  String? _notebookId;

  /// 注入全局媒体会话密钥（解锁时由外部派生/解包后传入——兼容旧路径）。
  void setSessionKey(List<int> key) => _sessionKey = List.of(key);

  /// 注入每笔记数据密钥 K_note（专家审计最优先行动③——Knovya 每笔记
  /// DEK 隔离模式 2026-08-16）：媒体加解密使用该笔记的 K_note，AAD 绑定
  /// 笔记本 ID（note_id——防跨笔记密文交换；一笔记密钥泄露不影响其他
  /// 笔记）。密钥由调用方从笔记本加密载荷解包/派生后传入（K_user 包裹
  /// K_note——信封加密——SiYuan KEK 包络模式）。
  void setNotebookKey(String notebookId, List<int> noteKey) {
    _notebookId = notebookId;
    _sessionKey = List.of(noteKey);
  }

  /// 清除每笔记密钥（锁定时——D-2 内存清零语义）。
  void clearNotebookKey() => clearSessionKey();

  /// 密码模式注入（H-03 方案 B——HelloPrivacy salt.dat 模式）：按盐版本
  /// 分派 KDF 派生 key 后注入（与会话密钥注入统一——服务不感知模式）。
  /// [salt] 为全局持久盐（明文无害——盐无需保密）；跨会话用同一全局
  /// 盐重派生（解密媒体 key 一致）。
  ///
  /// N3 提速 B 方案：走 KekSessionCache——同 (密码,盐) 重复解锁零重算。
  ///
  /// **M1 修复（2026-11-11）**：读取路径按 [MediaSalt.kdf] 版本分派——
  /// 旧盐（版本 1）仍用 PBKDF2-600k 解旧媒体；新盐（版本 2）用 Argon2id
  /// 生产参数。新写入一律 [MediaSalt.encode]（版本 2），不再新增 PBKDF2 盐。
  /// 调用方传入 [MediaSalt]（来自 [NotebookStorage.ensureMediaSalt]）。
  Future<void> setSessionPassword(String password, MediaSalt salt) async {
    final key = await KekSessionCache.instance.deriveKek(
      password,
      salt.bytes,
      salt.kdf,
    );
    _sessionKey = List.of(key);
    // KekSessionCache 返回独立副本，注入后源副本就地清零（P0 密钥零化）。
    key.fillRange(0, key.length, 0);
  }

  /// 兼容旧调用点：纯 16B 盐视为 [MediaSalt.legacy]（PBKDF2-600k）。
  ///
  /// 仅测试与任何直接传裸盐的旧代码使用；生产路径一律走
  /// [setSessionPassword] + [MediaSalt]（带版本）。保留此重载是为了
  /// 不让旧调用点在 KDF 升级后静默改变语义——裸盐没有版本信息，
  /// fail-closed 地按旧版（PBKDF2）处理。
  Future<void> setSessionPasswordLegacy(String password, List<int> salt) =>
      setSessionPassword(password, MediaSalt.legacy(salt));

  /// 生成 16 字节全局盐（密码模式媒体加密派生用——明文无害）。
  static List<int> generateSalt() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256));
  }

  /// 清除会话密钥（退出/锁定——fillRange 主动擦除，D-2 模式）。
  void clearSessionKey() {
    final key = _sessionKey;
    if (key != null) key.fillRange(0, key.length, 0);
    _notebookId = null;
    _sessionKey = null;
  }

  @override
  void clearAllSessionSecrets() => clearSessionKey();

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
      aad: _currentAad,
    );
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
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
    // 单一 AAD 口径（2026-11-10）：只认当前 [_currentAad]——存在每笔记上下文
    // 时绑定 notebookId，否则为应用级 'drawing-notes|media|v1'。旧版『无
    // noteId 回退分支』已移除（不兼容旧版媒体密文）：AAD 不符即认证失败，
    // 不做第二次尝试（避免把 AAD 降级变成可试探的旁路）。
    final clear = await aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(key),
      aad: _currentAad,
    );
    return Uint8List.fromList(clear);
  }

  /// 媒体 AAD 基：绑定应用/用途/版本（NIST SP 800-38D 上下文绑定）。
  /// 存在每笔记上下文时附加笔记本 ID（'|notebookId'——Knovya AAD
  /// binding note_id——防跨笔记密文交换）。
  static final Uint8List _mediaAad = Uint8List.fromList(
    utf8.encode('drawing-notes|media|v1'),
  );

  Uint8List get _currentAad => _notebookId == null
      ? _mediaAad
      : Uint8List.fromList([..._mediaAad, ...utf8.encode('|$_notebookId')]);

  /// 媒体密文文件头魔数（H-03 双端接入 2026-08-15）：AES 密文与随机噪声
  /// 不可区分（无法用图片魔数检测）——用应用层文件头标记密文。
  static const List<int> _fileMagic = [0x44, 0x41, 0x4E]; // 'DAN'
  static const int _fileVersion = 1;

  /// 加密并封装为文件格式：[DAN, 版本, ...密文载荷]。
  Future<Uint8List> encryptFile(Uint8List plain) async {
    final payload = await encryptBytes(plain);
    return Uint8List.fromList([..._fileMagic, _fileVersion, ...payload]);
  }

  /// 读取媒体文件：DAN 文件头 → 解密；否则原样返回（明文兼容——
  /// 旧数据/未加密笔记本）。
  Future<Uint8List> readMediaFile(Uint8List data) async {
    if (isEncryptedFile(data)) {
      return decryptBytes(Uint8List.fromList(data.sublist(4)));
    }
    return data;
  }

  /// 检测媒体文件是否为 DAN 密文（旧明文迁移用——明文重加密判断）。
  static bool isEncryptedFile(List<int> data) =>
      data.length >= 4 &&
      data[0] == _fileMagic[0] &&
      data[1] == _fileMagic[1] &&
      data[2] == _fileMagic[2];
}
