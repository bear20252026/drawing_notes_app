import 'dart:typed_data';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

/// 笔记本媒体密钥（K_note）的**唯一取钥权威**（会话密钥生命周期收口，
/// 2026-11-15 框架级修复）。
///
/// 背景（审计 H-1/H-2/H-3/M-2/M-3/M-4 的共同根源）：此前「该不该加密」
/// 靠消费点各自嗅探 `MediaCryptoService.hasKeyFor`（密钥在不在内存），
/// 把 LRU 逐出/回锁清零/尚未 ensure 这些*内存状态*误当成「不加密」的
/// *语义信号*，于是加密笔记本的媒体会回退明文落盘；取钥/懒补/注入/清零
/// 散落在存储与页面各处，无统一编排，竞态与降级缝隙长在级与级之间。
///
/// 本编排器把三件事收归单一权威：
/// 1. **加密意图与密钥可得性分离**：消费方只问「给我这本的媒体密钥」
///    （[sealMedia]/[openMedia]），由编排器依据*笔记本加密声明*
///    （[NotebookMediaEnvelopePort.isEncryptedNotebook]）决定——要么返回
///    密钥产物，要么 fail-closed 抛 [VaultFileLockException]，**永远不把
///    「明文」这个选项交给加密笔记本**。业务层不再出现 hasKeyFor 嗅探。
/// 2. **会话世代（epoch）令牌**：[SessionEpoch] 随 [SessionSecrets.clearAll]
///    递增；一切慢操作（Argon2id 解包/懒补槽落盘）完成后校验世代，
///    回锁后的在途注入被*构造性*作废（M-4），不靠调用方复查锁态。
/// 3. **per-id 串行编排**：同一笔记本的 ensure 共享一条在途 Future
///    （并发双 ensure 只生成一把 K_note，H-3）；懒补槽的读-改-写经
///    [NotebookMediaEnvelopePort.patchEncryptedPayload] 在存储的独占
///    写队列内完成（端口实现方负责队列内重读，非陈旧快照）。
///
/// 三态契约（H-2）：信封端口解包 K_note 时——**无 media 槽**返回 null
/// （编排器懒补）；**密码错误/槽损坏**抛 [FormatException]（编排器
/// fail-closed，绝不把损坏槽当「无槽」生成临时密钥）。
///
/// 本类不持有长期密钥：K_note 驻留在 [MediaCryptoService] 的 LRU 映射
/// （上限 32、逐出零化）；编排器只负责「何时取、取不到怎么办、何时作废」。
class NotebookMediaKeys implements SessionSecretsHolder {
  NotebookMediaKeys({required this.media, required this.envelopes}) {
    SessionSecrets.register(this);
  }

  /// 进程级缺省编排器（组合根未显式装配时的兜底——AppServices 缺省链）。
  ///
  /// 信封端口为「未装配」fail-closed 实现：一切解包/补槽请求抛
  /// [VaultFileLockException]——**绝不把未知笔记本当明文**（空端口恒
  /// false 会让加密笔记本媒体明文落盘，正是本次修复要消灭的降级）。
  /// 明文媒体的 openMedia 不触端口（非 DAN 原样返回），不受影响。
  /// 生产由 app.dart 用真实 NotebookStorage 端口装配并注入 NotebookStorage
  /// 与 AppServices，本兜底只服务测试直构与未装配场景。
  static final NotebookMediaKeys instance = NotebookMediaKeys(
    media: MediaCryptoService.instance,
    envelopes: const _UnwiredEnvelopes(),
  );

  /// 媒体加密原语（LRU 密钥映射 + AES-GCM；本编排器是其唯一注入方）。
  final MediaCryptoService media;

  /// 笔记本信封端口（存储侧实现：加密声明/会话密码/解包/补槽/落盘）。
  final NotebookMediaEnvelopePort envelopes;

  /// per-id 在途 ensure（并发去重：同本共享一条 Future，H-3）。
  final Map<String, Future<void>> _inflight = <String, Future<void>>{};

  /// per-id 遗忘世代：页面 dispose/回锁清钥后递增——在途 ensure 完成时
  /// 发现世代已变即放弃注入（防「清钥后被在途操作复活」，M-4 的 per-id 腿；
  /// 全局回锁腿由 [SessionEpoch] 覆盖）。
  final Map<String, int> _forgetGen = <String, int>{};

  /// 确保某笔记本的 K_note 已驻留（解锁/导入媒体/渲染 miss 时调用）。
  ///
  /// - 已驻留 → 直接返回；
  /// - 同本已有在途 ensure → 共享之（并发只生成一把密钥）；
  /// - 明文笔记本 → 无操作；
  /// - 加密笔记本：会话密码解包 media 槽；无槽则懒补（生成→补装→
  ///   独占队列内落盘）；无会话密码抛 [VaultFileLockException]；
  ///   密码错误/槽损坏抛 [FormatException]——**绝不降级为临时密钥**。
  Future<void> ensure(String notebookId) {
    if (media.hasKeyFor(notebookId)) return Future<void>.value();
    final existing = _inflight[notebookId];
    if (existing != null) return existing;
    final task = _ensureOnce(notebookId);
    _inflight[notebookId] = task;
    // 清理在途台账：用 then(onError) 而非 whenComplete——whenComplete 返回的
    // 派生 Future 会继承 task 的错误，若无人 await 该派生 Future 即成未处理
    // 异步错误（调用方只接住了 task 本体）。onError 吞掉派生链的错误传播，
    // task 本体的错误仍原样交给调用方。
    task.then(
      (_) => _dropInflight(notebookId, task),
      onError: (_) => _dropInflight(notebookId, task),
    );
    return task;
  }

  void _dropInflight(String notebookId, Future<void> task) {
    if (identical(_inflight[notebookId], task)) {
      _inflight.remove(notebookId);
    }
  }

  Future<void> _ensureOnce(String notebookId) async {
    final epoch = SessionEpoch.current;
    final gen = _forgetGen[notebookId] ?? 0;
    if (!await envelopes.isEncryptedNotebook(notebookId)) return; // 明文笔记本。
    final password = await envelopes.sessionPassword(notebookId);
    if (password == null) throw const VaultFileLockException();
    var key = await envelopes.unwrapMediaKey(notebookId, password);
    if (key == null) {
      // 懒补槽（仅「无槽」会走到这里——损坏/错密码在端口内已抛错）。
      key = MediaCryptoService.generateNotebookKey();
      try {
        await envelopes.attachMediaSlot(notebookId, password, key);
      } catch (_) {
        // M-4（第二轮审计 2026-11-17）：补槽抛错（回锁/落盘失败）时已生成
        // 的密钥是本方法独占副本，零化后原样上抛——此前无 try/finally，
        // 世代校验只覆盖成功路，抛错路径密钥堆驻留。
        key.fillRange(0, key.length, 0);
        rethrow;
      }
    }
    // 慢操作（Argon2id ×2 + 落盘）期间可能回锁/页面退出——世代校验，
    // 过期即作废：不注入、源副本零化（M-4 构造性消除）。
    if (SessionEpoch.current != epoch ||
        (_forgetGen[notebookId] ?? 0) != gen) {
      key.fillRange(0, key.length, 0);
      throw const VaultFileLockException();
    }
    media.setNotebookKey(notebookId, key);
    key.fillRange(0, key.length, 0); // 注入后源副本零化（服务内已复制）。
  }

  /// 密封媒体字节（写路径唯一入口——storeImage/PDF 导入共用）。
  ///
  /// 加密笔记本：ensure 后按 K_note 加密（DAN）——缺钥/锁定一律抛
  /// [VaultFileLockException]，**不存在明文回退**（H-1）。
  /// 明文笔记本：返回 null，由调用方走既有 DNV/明文兼容分支。
  Future<Uint8List?> sealMedia(String notebookId, Uint8List plain) async {
    if (!await envelopes.isEncryptedNotebook(notebookId)) return null;
    await ensure(notebookId);
    return media.encryptFile(notebookId, plain);
  }

  /// 打开媒体密文（读路径唯一入口——渲染/PDF 导出共用）。
  ///
  /// DAN 密文必须有笔记本上下文；LRU 逐出后自动经 [ensure] 重解包
  /// （M-2：不再渲染空白）；回锁/无会话密码 fail-closed。
  /// 非 DAN 字节原样返回（明文媒体——未加密笔记本）。
  Future<Uint8List> openMedia(String? notebookId, Uint8List data) async {
    if (!MediaCryptoService.isEncryptedFile(data)) return data;
    if (notebookId == null) {
      throw StateError('DAN 媒体密文缺少笔记本上下文（无法解密）');
    }
    await ensure(notebookId);
    return media.readMediaFile(notebookId, data);
  }

  /// 遗忘某笔记本密钥（页面 dispose/删除笔记本）：清钥 + 递增遗忘世代
  /// （在途 ensure 作废）。其他已打开笔记本不受影响。
  void forget(String notebookId) {
    _forgetGen[notebookId] = (_forgetGen[notebookId] ?? 0) + 1;
    media.clearNotebookKey(notebookId);
  }

  /// 全局回锁联动（SessionSecrets.clearAll 注册表调用）：清空全部驻留
  /// K_note 与在途编排状态。幂等、永不抛错。
  @override
  void clearAllSessionSecrets() {
    try {
      media.clearSessionKey();
      _inflight.clear();
      _forgetGen.clear();
    } catch (_) {
      /* 幂等清理：回锁热路径，失败不外抛 */
    }
  }
}

/// 笔记本信封端口（存储侧实现——编排器不触碰文件 IO/队列细节）。
///
/// 实现方纪律（NotebookStorage）：
/// - [unwrapMediaKey]：无 media 槽 → null；密码错误/槽损坏 → 抛
///   [FormatException]（三态不可压扁，H-2）；
/// - [attachMediaSlot]：生成密钥补装进信封并**在 per-id 独占写队列内
///   重读最新落盘内容后只替换 encryptedPayload 字段**（H-3：不得整本
///   陈旧快照回写）；已有槽幂等返回。
abstract class NotebookMediaEnvelopePort {
  /// 该笔记本是否声明加密（读磁盘当前信封，非内存快照）。
  Future<bool> isEncryptedNotebook(String notebookId);

  /// 该笔记本的会话密码（未解锁返回 null）。
  Future<String?> sessionPassword(String notebookId);

  /// 解包 K_note：无槽 null；密码错误/槽损坏抛 [FormatException]。
  Future<List<int>?> unwrapMediaKey(String notebookId, String password);

  /// 懒补 media 槽并持久化（独占队列内读-改-写；幂等）。
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  );
}

/// 未装配兜底端口（[NotebookMediaKeys.instance] 专用）：一切笔记本
/// 密钥请求 fail-closed——未知笔记本绝不按明文处理（防降级）。
class _UnwiredEnvelopes implements NotebookMediaEnvelopePort {
  const _UnwiredEnvelopes();

  @override
  Future<bool> isEncryptedNotebook(String notebookId) async =>
      throw const VaultFileLockException();

  @override
  Future<String?> sessionPassword(String notebookId) async => null;

  @override
  Future<List<int>?> unwrapMediaKey(String notebookId, String password) async =>
      throw const VaultFileLockException();

  @override
  Future<void> attachMediaSlot(
    String notebookId,
    String password,
    List<int> mediaKey,
  ) async => throw const VaultFileLockException();
}