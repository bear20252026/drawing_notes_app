/// 块文档（NoteBlockDoc）本地存储门面。
///
/// 提供 [NoteBlockDoc] 的加载、保存、删除能力。存储键与现有
/// [NotebookStorage] 区分（独立 `blockdocs` 目录），避免混叠。
///
/// 目录结构（应用文档目录下）：
///   `appDir/blockdocs/`
///     `{docId}.json` —— 块文档序列化文件
///
/// 仅依赖 [NoteBlockDoc]（domain）+ dart:io + directoryProvider；
/// 不 import presentation，层方向严格 domain ← infrastructure。
///
/// L-03 拆分：回收站域与文件密码域为本库的 part（同库共享私有成员，
/// 行为与单文件完全一致；extension 包裹——类成员不可裸跨 part 文件）。
library;

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/rename_injection.dart';
import 'package:drawing_notes_app/core/storage/stale_tmp_cleanup.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/utils/time_serialization.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';

part 'note_block_doc_store_trash.dart';
part 'note_block_doc_store_password.dart';

/// 笔记（块文档）受独立文件密码保护且本会话未解锁（N2）。
///
/// loadDocument 在锁定态抛出此异常——调用方（打开路径）应先走
/// UnlockFlow 解锁（verifyBlockDocPassword 成功即入会话 DEK 缓存）。
class BlockDocLockedException implements Exception {
  const BlockDocLockedException();

  @override
  String toString() => 'BlockDocLockedException: 笔记已加密且会话未解锁';
}

/// 盘上那份笔记的受密状态——三态，**不是**「有没有信封」两态（审计 SYN-D1）。
///
/// `unreadable` 必须单独成立：它与 `notEnvelope` 在旧的两态形状里共用一个 null，
/// 而对写路径两者的含义相反（一个可以落盘，另一个必须拒写）。详见
/// `NoteBlockDocStore._readEnvelope`。
enum _EnvelopeRead {
  /// 没有 v5 文件密码信封：文件不存在、是主密钥信封、是明文、或内容损坏。
  notEnvelope,

  /// 是 v5 文件密码信封，`json` 里放着它的原文（写路径只能走 rewrap 腿）。
  envelope,

  /// 文件在，但**这一刻读不出它是什么**（句柄被占用 / 权限抖动 / 瞬时 IO 错误）。
  /// ⇒ 不许据此推断任何落盘动作。
  unreadable,
}

/// 块文档本地存储门面。
///
/// 用法：
/// ```dart
/// final store = NoteBlockDocStore();
/// await store.saveDocument(doc);
/// final loaded = await store.loadDocument(doc.id);
/// await store.deleteDocument(doc.id);
/// ```
class NoteBlockDocStore implements SessionSecretsHolder {
  /// 创建块文档存储门面。
  ///
  /// [directoryProvider] 为可选的目录提供者回调。测试时可注入临时目录，
  /// 生产环境默认使用系统文档目录。
  NoteBlockDocStore({
    this.directoryProvider,
    this.keyProvider,
    this.vaultConfigured,
  }) {
    // P1 修复：注册会话机密清理——切后台回锁时 DEK 一并擦除失效。
    SessionSecrets.register(this);
  }

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  /// 主密钥提供者（加密底座批次①c）：返回解锁态主密钥时，块文档 JSON
  /// 以 AES-256-GCM 信封落盘（AAD 绑定 `block:<id>`）；null 时明文兼容。
  final Future<Uint8List?> Function()? keyProvider;

  /// 保险库**是否已建立**（用户设过 PIN / 启用过加密）。
  ///
  /// 与 `StorageWritePipeline.encryptionInUse` 同一条口径（2026-10-07 收口）：
  /// 写路径必须把「取不到密钥」拆成两种语义——未建库时明文落盘是产品设计，
  /// 已建库却锁定时明文会把密文用户降级成明文。二者在 `keyProvider` 的
  /// 返回值上长得一样（都是 null），只能由装配层显式告知。
  final Future<bool> Function()? vaultConfigured;

  /// 写成功回调（首页刷新修复①）：保存/删除/恢复/彻底删除落盘成功后触发，
  /// 由装配层注入（AppServices.bumpDataVersion）——把刷新通知下沉到存储层，
  /// 覆盖所有写路径（笔记本内新建、DocPage 自动保存等），不再依赖调用点逐一通知。
  void Function()? onWrite;

  /// DN-207：测试专用**时序屏障**——在「陈旧快照校验通过」与「迁移落盘」之间
  /// await（生产恒 null）。与 `StorageWritePipeline.rewriteBarrierForTest` 同一
  /// 用意：这条竞态以前只能靠调度碰运气，用例既抓不住 bug 也守不住修复。
  /// 字段必须驻留主文件（extension 内不可声明实例字段）。
  @visibleForTesting
  Future<void> Function(String id)? rewriteBarrierForTest;

  /// SYN-D1：测试专用**读失败注入**——在「文件存在」与「读出其内容」之间抛
  /// （生产恒 null）。要造的是「这一刻读不出来」那一格（errno 32 句柄被占用、
  /// 权限抖动、瞬时 IO 错误），它和「盘上这份不是信封」在旧形状里是同一个 null，
  /// 而这两者对写路径的含义完全相反：一个可以落盘，另一个必须拒写。
  @visibleForTesting
  Future<void> Function(String id)? readBarrierForTest;

  /// 孤儿 tmp 清扫每实例只跑一次（见 `sweepStaleTempFiles` 与 `_writeFileAtomic`）。
  bool _staleTmpSwept = false;

  /// 批次 D 故障注入：在**备份已落盘**与**改名换入**之间 await（生产恒 null，
  /// 一次 null 判定）。与 `StorageWritePipeline.renameBarrierForTest` 同一用意，
  /// 好让「换入这一步真失败」这条腿也能确定地复现，而不是等 Windows 句柄冲突。
  @visibleForTesting
  Future<void> Function(String id, String tmpPath)? renameBarrierForTest;

  /// 批次 D 故障注入：把**其中一次**改名替换成「系统拒绝」，其余仍走真实 rename
  /// （生产恒 null）。实测依据与「拒绝」这个动作的统一定义都在
  /// `core/storage/rename_injection.dart`：兜底腿在真机上只在别人持句柄又刚好
  /// 放手的窗口里走得通（Windows 的 rename 本身会覆盖已存在目标；句柄占用时
  /// rename 报 5、紧随的 delete 报 32），所以它不能靠 sleep 赌、Linux CI 更是永远到不了。
  /// 返回 true = 这一次改名不执行，tmp 与目标原地不动。
  @visibleForTesting
  bool Function(String tmpPath, String destinationPath)? renameFaultForTest;

  /// 批次 D（CI kdf 分片随机红的根因，任务 #24）：等 **id 这条腿当前排队的写**
  /// 全部落完。测试用它把「等懒迁移把明文重写成密文」从掐表轮询换成确定信号——
  /// 以前 `--tags kdf` 串行分片会随机报「120 秒内未迁移」，可真正该问的是
  /// 「这条腿排队的写跑完了没有」，掐表答不了这个问题。
  ///
  /// 返回的就是队列里那个 Future 本体：不新建计时器、不加 sleep、不改变任何
  /// 生产行为（生产不调用，只有测试会取它）。队列为空时返回已完成的 Future，
  /// 调用方随后判一次字节即可——因此它只会让用例更快确定，不会更慢。
  @visibleForTesting
  Future<void> drainWritesForTest(String id) =>
      _writeChains[id] ?? Future<void>.value();


  Directory? _dir;

  /// 回收站目录缓存（字段必须驻留主文件——extension 内禁止声明实例字段；
  /// 读写经 part 扩展方法，见 note_block_doc_store_trash.dart）。
  Directory? _trashDir;

  // ==== 文件密码（N2：笔记单文件接入 v5 双保护器体系） ====
  //
  // 受密文件 = v5 信封 JSON 直落盘（{"mode":"password","v":5,"slots",
  // "payload"}，AAD 绑定 blockdoc id）——不再叠加主密钥信封（与分页画布
  // v5 同口径：一层密码保护独立成立）。会话 DEK 缓存（LUKS 同款）：
  // 解锁成功缓存 DEK，续写 rewrap 免 PBKDF2 重派生。

  static const EncryptionService _encryption = EncryptionService();

  /// 会话 DEK 缓存：解锁成功（verifyBlockDocPassword/encryptAndSave/
  /// 改密/重置）后缓存，saveDocument 续写复用（零 PBKDF2）。
  final Map<String, List<int>> _sessionDeks = <String, List<int>>{};

  /// 该笔记本会话内是否已解锁文件密码（DEK 在缓存中）。
  bool isBlockDocUnlocked(String id) => _sessionDeks.containsKey(id);

  /// 清除会话 DEK（切后台锁屏 / 移除密码 / 删除文档后调用）。
  /// DEK 字节先擦除再移除（防内存残留）。
  /// 头信息缓存同步失效——列表立即回「加密笔记」占位，不泄露真实标题。
  void forgetBlockDocPassword(String id) {
    final dek = _sessionDeks.remove(id);
    if (dek != null) {
      for (var i = 0; i < dek.length; i++) {
        dek[i] = 0;
      }
      _headerCache = null;
    }
  }

  /// P1 修复：清空全部会话 DEK（切后台回锁经 [SessionSecrets] 联动）。
  /// 逐个字节擦除 + 头缓存失效；幂等、永不抛错。
  @override
  void clearAllSessionSecrets() {
    try {
      for (final dek in _sessionDeks.values) {
        try {
          for (var i = 0; i < dek.length; i++) {
            dek[i] = 0;
          }
        } catch (_) {
          /* 幂等清理：单个 DEK 字节擦除失败继续下一个，清空流程永不抛错 */
        }
      }
      _sessionDeks.clear();
      _headerCache = null;
    } catch (_) {
      /* 幂等清理：会话 DEK 清空尽力而为（切后台回锁热路径），失败不外抛 */
    }
  }

  /// 读取指定笔记的落盘字节；若为 v5 文件密码信封则返回其 JSON 串，
  /// 否则（不存在/主密钥信封/明文/损坏/**这一刻读不出来**）返回 null。
  ///
  /// 密码域那几个流程只用得到「有没有信封、信封内容是什么」，null 对它们是安全的
  /// （每条 null 分支都抛错或返回 false，不写盘）。**写路径不许用这个方法**——
  /// 用 [_readEnvelope] 拿三态，见该方法的注释。
  Future<String?> _readEnvelopeJson(String id) async {
    final read = await _readEnvelope(id);
    return read.state == _EnvelopeRead.envelope ? read.json : null;
  }

  /// 盘上这份笔记的**三态**受密状态（审计 SYN-D1，第四轮 2026-10-15）。
  ///
  /// 旧形状就是上面那个 `String?`：「不存在 / 主密钥信封 / 明文 / 损坏」与
  /// 「读不出来（句柄被占用、权限抖动、IO 错误）」被压成**同一个 null**，而
  /// `saveDocument` 正是拿这个 null 走「未受密 ⇒ 可以落盘」那一支 ⇒
  /// **一次瞬时读失败就把 v5 文件密码信封整份盖成主密钥信封或明文**，
  /// 原密文连同那份 DEK 一起没了，用户再怎么输密码也开不了。
  ///
  /// 三态之后：只有 `envelope` 进 rewrap 腿、只有 `notEnvelope` 进未受密腿，
  /// `unreadable` **拒写**（抛错、盘上那份一字不动、下一轮自动保存再来）。
  /// 「拒写」而不是「按最坏假设加密落盘」：读不出来的这一次，我们连该用哪个
  /// AAD 分支都不确定，任何猜测都是在赌那份信封的生死。
  Future<({ _EnvelopeRead state, String? json })> _readEnvelope(String id) async {
    final path = await _pathFor(id);
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return (state: _EnvelopeRead.notEnvelope, json: null);
      }
      // 测试屏障（生产恒 null）：崩溃/失败窗口不能靠调度碰运气，要能确定地
      // 停在「文件在，但这一刻读不出内容」那一格——与 `rewriteBarrierForTest` 同纪律。
      await readBarrierForTest?.call(id);
      final raw = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(raw)) {
        // 主密钥信封——非文件密码，走下面的正常加密落盘腿。
        return (state: _EnvelopeRead.notEnvelope, json: null);
      }
      final text = utf8.decode(raw);
      return EncryptionService.isDualProtectorEnvelope(text)
          ? (state: _EnvelopeRead.envelope, json: text)
          : (state: _EnvelopeRead.notEnvelope, json: null);
    } on Object {
      return (state: _EnvelopeRead.unreadable, json: null);
    }
  }

  /// 该笔记是否受独立文件密码保护（v5 信封；不解密、不暴露内容）。
  ///
  /// SYN-D1 的另一半：读不出来时答 **true**（当成受密）。调用点的形状一律是
  /// 「未受密 ⇒ 直接放行动作」（`app_shell_routes.dart:107`、`home_page_tabs.dart:296`、
  /// `search_page.dart:118` 等），所以保守方向只有这一个——宁可让用户多解一次锁，
  /// 不能把一个可能受密的文件当明文去删/去盖。
  Future<bool> isBlockDocPasswordProtected(String id) async {
    final read = await _readEnvelope(id);
    return read.state != _EnvelopeRead.notEnvelope;
  }

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return AppDataRoot.defaultRootDir();
  }

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await _baseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// P0-H3 写尾队列：同 id 的写操作（保存/删除/恢复）串行化，
  /// 消除自动保存与软删除交错导致的「已删文档复活/新内容被覆盖」竞态。
  final Map<String, Future<void>> _writeChains = {};

  /// 把 [op] 挂到 [id] 的写链尾；链上某步失败不影响后续步骤。
  /// 任何写操作完成后使头信息缓存失效（P2-M5）。
  Future<T> _enqueue<T>(String id, Future<T> Function() op) {
    final prev = _writeChains[id] ?? Future<void>.value();
    final task = prev.then((_) => op());
    _writeChains[id] = task.then(
      (_) => _headerCache = null,
      onError: (_) => _headerCache = null,
    );
    return task;
  }

  /// 文档头信息缓存（P2-M5）：列表热路径（AllDocs/反向链接面板）不再
  /// 每次全量解析全部文档 JSON——冷路径解析一次，之后走内存。
  List<NoteBlockDocHeader>? _headerCache;

  Future<Uint8List?> _currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }

  /// 未注入探测器时保守按「已建库」处理：维持 fail-closed 语义，不让这个
  /// 新增的可选参数变成新的 fail-open 后门（与 StorageWritePipeline 同款）。
  /// 守卫只在 `keyProvider != null`（加密底座已接线）时生效——底座未接线的
  /// 裸实例明文落盘是产品设计，见 [_saveDocumentLocked]。
  Future<bool> encryptionInUse() async => await vaultConfigured?.call() ?? true;

  /// 读取后的字节准备（批次①c，与 StorageService 同纪律）：
  /// 密文+解锁 → 解密；密文+锁定 → [VaultFileLockException]；
  /// 明文+有钥 → 原样返回并经写链懒迁移。
  Future<Uint8List> _prepareDocBytes(String id, Uint8List raw) async {
    final key = await _currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'block:$id');
    }
    if (key != null) _enqueueRawRewrite(id, raw);
    return raw;
  }

  /// 懒迁移：明文块文档经写链重写为密文。
  ///
  /// P1 陈旧快照防护（对齐 storage_write_pipeline._isStillCurrentPlaintext）：
  /// 快照是读路径入队前捕获的，队列里排在前面的较新保存会被这份陈旧
  /// 明文反超覆盖（编辑内容静默回退）。重写前重读磁盘比对，不一致即放弃
  /// ——下次读取会重新排队（幂等）。
  void _enqueueRawRewrite(String id, Uint8List plaintext) {
    _enqueue(id, () async {
      final key = await _currentKey();
      if (key == null) return;
      final file = File(await _pathFor(id));
      if (!file.existsSync()) return; // 已被删除——不复活
      final current = await file.readAsBytes();
      if (!_bytesEqual(current, plaintext)) return; // 陈旧快照——放弃本次迁移
      // 测试可在这里插一步（生产恒 null）：确定性地制造
      // 「校验通过 → 文件被删 → 迁移落盘」这个窗口。
      await rewriteBarrierForTest?.call(id);
      final sealed = await VaultFileCodec.encrypt(
        plaintext,
        key,
        aadContext: 'block:$id',
      );
      // DN-207：密封（真 KDF，大载荷还进 isolate）是本条腿最长的一段 await，
      // 上面那次校验早就跨过它了——旧写法因此会把刚被删除、或刚被改写过内容的
      // 笔记重新写成密文（复活 / 反超）。落盘前的最后一刻再读一次盘并与快照比对
      // （与 StorageWritePipeline 的同名守卫同一判据），删除与改写都无处翻身。
      if (!file.existsSync() ||
          !_bytesEqual(await file.readAsBytes(), plaintext)) {
        AuditLogger.log(
          'note_block_doc.lazy_migration_aborted',
          success: false,
          detail: 'changed_before_write',
        );
        return;
      }
      // DN-205（第三轮专家审计 2026-10-13）：落盘交给**同一个** `_writeFileAtomic`。
      //
      // 此前这里自己手写 tmp + rename + 删旧目标，绕过了上一轮 DN-108 刚立起来的
      // 契约（`.bak` 备份失败即中止写入、失败时清理 tmp）。后果是「正常保存」比
      // 「后台迁移」更安全：第二次 rename 失败时正式文件已被删、`.bak` 又没写成，
      // 三个副本同时不存在——而这条腿是用户完全无感知的后台动作。
      // 三条写腿（正常保存 / 口令重封 / 懒加密迁移）必须共用同一份数据安全契约，
      // 否则每修一条就漏一条。
      await _writeFileAtomic(id, sealed);
    }).catchError((Object e) {
      // 迁移失败既不重试也不上抛（下次读取会重新排队——幂等），但**必须可诊断**：
      // 原来整个异常被 `catch (_) {}` 吞掉，「为什么这篇笔记过了三个月还是明文」
      // 在日志里查不到任何线索。行为不变，只是不再静默（同 AW13 的口径）。
      // detail 只带异常类型——路径与文档内容不进审计链。
      AuditLogger.log(
        'note_block_doc.lazy_migration_failed',
        success: false,
        detail: e.runtimeType.toString(),
      );
    });
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 轻量文档头（不含 body 块树）。
  /// 列出全部文档头（updatedAt 倒序；缓存命中时零 IO）。
  Future<List<NoteBlockDocHeader>> listDocHeaders() async {
    final cached = _headerCache;
    if (cached != null) return cached;
    await _ensureDir();
    final result = <NoteBlockDocHeader>[];
    // 审计 #15：明文头提取批量搬 isolate。原实现每文档在主 isolate 解析
    // 两次（isDualProtectorEnvelope 内部一次全量 jsonDecode + 取头一次），
    // N 文档冷启动 2N 次全量解析挤在主线程；现收集字节后单次 Isolate.run
    // 摊薄 spawn 开销，且 isolate 只回传头字段（body 树不跨 isolate
    // 序列化，避免搬运反噬）。加密文档解密后同样并入批量（session 级
    // 依赖留在主 isolate）。
    final plainJobs = <String, Uint8List>{}; // fileId → 明文 JSON 字节
    final statJobs = <String, File>{}; // fileId → 源文件（锁定兜底 stat）
    final dir = await _ensureDir();
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final name = entity.uri.pathSegments.last;
        final fileId = name.substring(0, name.length - '.json'.length);
        var bytes = await entity.readAsBytes();
        if (VaultFileCodec.isEncrypted(bytes)) {
          // fail-closed：锁定状态不暴露加密文档（跳过，不中断列表）。
          final key = await _currentKey();
          if (key == null) continue;
          bytes = await VaultFileCodec.decrypt(
            bytes,
            key,
            aadContext: 'block:$fileId',
          );
        }
        plainJobs[fileId] = bytes;
        statJobs[fileId] = entity;
      } catch (_) {
        continue; // 单文件读/解密失败跳过（fail-closed 语义不变）
      }
    }
    // 主密钥快照：迁移条件用（同一次列表调用期间 key 不会中途变化）。
    final mainKey = await _currentKey();
    final parsed = plainJobs.isEmpty
        ? const <String, List<Object?>>{}
        : await Isolate.run(() => _parsePlainHeaders(plainJobs));
    for (final entry in parsed.entries) {
      final fileId = entry.key;
      final f =
          entry.value; // [isEnvelope, id, title, tags, createdAt, updatedAt]
      if (f[0] as bool) {
        // N2：文件密码信封——会话已解锁（DEK 在缓存）解密出真实头信息；
        // 未解锁给锁定占位（标题/标签不泄露，fail-closed）。
        if (!isValidId(fileId)) continue;
        final dek = _sessionDeks[fileId];
        if (dek != null) {
          try {
            final clear = await _encryption.decryptBlockDocPayloadWithDek(
              docId: fileId,
              encryptedJson: utf8.decode(plainJobs[fileId]!),
              dek: dek,
            );
            final root = jsonDecode(clear) as Map<String, dynamic>;
            result.add(_buildHeader(fallbackId: fileId, map: root));
            continue;
          } catch (_) {
            continue; // 解密失败（DEK 失效/损坏）按损坏处理
          }
        }
        final stat = statJobs[fileId]?.statSync();
        final stamp = stat?.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
        result.add(
          NoteBlockDocHeader(
            id: fileId,
            // L-04：锁定占位标题不落盘——空串 + locked 标志，展示层经
            // DomainDisplayLabels.lockedDocTitle 统一渲染单一键。
            title: '',
            tags: const [],
            createdAt: stamp,
            updatedAt: stamp,
            locked: true,
          ),
        );
        continue;
      }
      // N2：v5 文件密码信封不参与主密钥懒迁移（受密文件直落盘，不做
      // 主密钥双信封——见 _saveDocumentLocked 注释）。非信封明文排队。
      if (isValidId(fileId) && mainKey != null) {
        _enqueueRawRewrite(fileId, plainJobs[fileId]!);
      }
      final id = f[1];
      if (id is! String || !isValidId(id)) continue; // 损坏/非法 id 跳过
      result.add(
        _buildHeader(
          fallbackId: fileId,
          map: {
            'id': id,
            'title': f[2],
            'tags': f[3],
            'createdAt': f[4],
            'updatedAt': f[5],
          },
        ),
      );
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _headerCache = result;
    return result;
  }

  /// 头字段构造收口（isolate 批量结果 / 信封解密两条路径共用）。
  static NoteBlockDocHeader _buildHeader({
    required String fallbackId,
    required Map<String, dynamic> map,
    bool locked = false,
  }) => NoteBlockDocHeader(
    id: map['id'] as String? ?? fallbackId,
    title: map['title'] as String? ?? '',
    tags: (map['tags'] as List? ?? const []).whereType<String>().toList(),
    createdAt: timeFromIso(
      map['createdAt'],
      fallback: DateTime.fromMillisecondsSinceEpoch(0),
    ),
    updatedAt: timeFromIso(
      map['updatedAt'],
      fallback: DateTime.fromMillisecondsSinceEpoch(0),
    ),
    locked: locked,
  );

  /// 校验 ID 是否安全（仅允许字母、数字、下划线、短横线）。
  static bool isValidId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  Future<String> _pathFor(String id) async {
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return '${(await _ensureDir()).path}${Platform.pathSeparator}$id.json';
  }

  /// 保存块文档到本地存储。
  ///
  /// 使用原子写入（先写 .tmp → 再 rename），并在覆盖前将现有文件
  /// 复制为 .bak 备份，确保写入中断时可恢复。
  Future<void> saveDocument(NoteBlockDoc doc) =>
      _enqueue(doc.id, () => _saveDocumentLocked(doc));

  /// isolate 编解码阈值（语义对齐 StorageService._isolateSealThreshold /
  /// DocumentCodec.isolateEncodeThreshold）：低于阈值时 isolate 往返
  /// （spawn + 拷贝）开销大于收益，直接主线程执行。单位为 UTF-16 码元
  /// 粗估值——中日韩字符 UTF-8 膨胀 ~3×，此处取半阈值保守判断（宁可
  /// 早进 isolate，不漏大文档）。
  static const int _isolateCodecThreshold = 32 * 1024;

  /// 粗估文档明文规模（不精确，仅作 isolate 阈值判断——块结构 JSON
  /// 开销按每块 ~64 码元计入，误差远小于阈值量级）。
  static int _estimateDocSize(NoteBlockDoc doc) {
    var size = doc.title.length + doc.tags.length * 12;
    for (final b in doc.body) {
      size += b.text.length + 64;
    }
    return size;
  }

  /// 编码文档为 JSON 字节。纯函数，可安全跑在 isolate 中（NoteBlockDoc
  /// 为纯数据类，可跨 isolate 传递）。
  static Uint8List _encodeDocBytes(NoteBlockDoc doc) {
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(doc.toJson())),
    );
  }

  /// 解析文档 JSON。纯函数，可安全跑在 isolate 中。
  static NoteBlockDoc _parseDocText(String text) =>
      NoteBlockDoc.fromJson(jsonDecode(text) as Map<String, dynamic>);

  /// 异步解析：小文本主线程，达阈值的文本进 isolate（审计 U4）。
  static Future<NoteBlockDoc> _parseDocTextAsync(String text) {
    if (text.length < _isolateCodecThreshold) {
      return Future.value(_parseDocText(text));
    }
    return Isolate.run(() => _parseDocText(text));
  }

  /// 异步编码：小文档主线程，达阈值的文档进 isolate（审计 U4：序列化
  /// 移出主 isolate，对齐画布侧 encodeSnapshotAsync 先例）。
  static Future<Uint8List> _encodeDocBytesAsync(NoteBlockDoc doc) {
    if (_estimateDocSize(doc) < _isolateCodecThreshold) {
      return Future.value(_encodeDocBytes(doc));
    }
    return Isolate.run(() => _encodeDocBytes(doc));
  }

  /// saveDocument 的串行化主体（调用方必须已持有该 id 的写链）。
  Future<void> _saveDocumentLocked(NoteBlockDoc doc) async {
    if (!isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    await _ensureDir();
    final plaintext = await _encodeDocBytesAsync(doc);

    // N2：文件密码拦截——受密文件续写必须走会话 DEK rewrap（v5 信封
    // 直落盘，仅重生成 payload 密文、槽位组原样保留——LUKS 语义）。
    // 无 DEK 时 fail-closed：绝不把明文覆盖到密文上（与 NotebookStorage
    // save 守卫同纪律）。DocPage 自动保存零改动——透明 rewrap。
    final read = await _readEnvelope(doc.id);
    // SYN-D1：读不出受密状态 ⇒ 拒写。这一格以前是 null ⇒ 当成「未受密」⇒
    // 一次瞬时读失败就把 v5 信封整份盖掉（原密文与那份 DEK 一起没了）。
    if (read.state == _EnvelopeRead.unreadable) {
      AuditLogger.log(
        'blockdoc.save.readUnknown',
        success: false,
        detail: doc.id,
      );
      throw StateError('笔记「${doc.id}」的受密状态此刻读不出来：拒绝落盘覆盖');
    }
    final envelope = read.json;
    if (envelope != null) {
      final dek = _sessionDeks[doc.id];
      if (dek == null) {
        throw StateError('笔记「${doc.id}」已加密且会话未解锁：禁止明文覆盖');
      }
      final map = jsonDecode(envelope) as Map<String, dynamic>;
      final sealed = utf8.encode(
        await _encryption.rewrapBlockDocPayloadV5(
          docId: doc.id,
          map: map,
          dek: dek,
          plaintext: utf8.decode(plaintext),
        ),
      );
      await _writeFileAtomic(doc.id, sealed);
      return;
    }

    // 批次①c：有主密钥 → 信封加密（AAD 绑定 block:<id>）。
    // 审计 U4：大载荷加密进 isolate（对齐 StorageService._sealDocBytes
    // 先例——VaultFileCodec.encrypt 为静态纯函数，可安全跨 isolate）。
    var data = plaintext;
    final key = await _currentKey();
    if (key != null) {
      if (data.length < _isolateCodecThreshold) {
        data = await VaultFileCodec.encrypt(
          data,
          key,
          aadContext: 'block:${doc.id}',
        );
      } else {
        data = await Isolate.run(
          () =>
              VaultFileCodec.encrypt(data, key, aadContext: 'block:${doc.id}'),
        );
      }
    } else if (keyProvider != null && await encryptionInUse()) {
      // 「取不到密钥」的两种含义由 [encryptionInUse] 统一拆分（与
      // StorageWritePipeline._sealDocBytes 同一条 P0 修复口径，2026-10-07）：
      // 底座已接线且保险库已建立但本会话未解锁——写明文会把既有密文降级
      // 成明文（锁定期间 SaveScheduler 的防抖/退避定时器照常开火，此处
      // 曾把密文文档静默覆盖成明文），fail-closed 抛锁；交由重试策略在
      // 解锁后自愈。底座未接线（keyProvider == null）的裸实例明文落盘
      // 仍是产品设计（未建库用户与既有测试口径不变）。
      throw const VaultFileLockException();
    }
    await _writeFileAtomic(doc.id, data);
  }

  /// 原子写（bak 备份 + tmp + rename）——保存/设密/改密/重置/移除共用。
  /// A4 修复（审计 2026-09-07）：tmp 写入/rename 失败时清理残留临时文件
  /// （favorite_store 同款纪律），防止半写 .tmp 堆积。
  ///
  /// DN-108 修复（专家审计 2026-10-12）：`.bak` 备份失败改为 **fail-closed
  /// 中止本次写入**，与 [StorageWritePipeline.writeSealedBytes] 同一契约。
  ///
  /// 此前这里是「备份失败不阻塞写入」，于是下面的 Windows 回退分支
  /// （删除旧目标 → 再换入 tmp）可能在**没有任何备份**的情况下删掉正式文件：
  /// 一旦第二次 rename 也失败，正式文件已删、`.bak` 不存在、tmp 又被 catch
  /// 清理 ⇒ 三个副本同时不存在。备份是删除-换入回退的崩溃恢复前提，
  /// 没有它就不允许进入破坏性分支。
  Future<void> _writeFileAtomic(String id, List<int> data) async {
    final path = await _pathFor(id);
    final file = File(path);
    // 孤儿 tmp 回收（审计 2026-10-16）：崩溃/被杀在 write 与 rename 之间时，这条腿
    // 以前没人清扫（只有保险库那条腿有）。实测本机真实数据根 `blockdocs/` 今天**没有**
    // 残留，所以这条接线是**预防**而非补漏。画布那条腿的递归扫（从数据根）顺带也能覆盖
    // blockdocs/ 这个**位置**，但只有本这条能保证「整个会话只写打字笔记、没存过一张画布」
    // 时也扫得到——不给它自己的触发点，就又是本仓那个「一修就漏一处」的形状。
    // 本地扫（不递归），判据见 `sweepStaleTempFiles`。
    if (!_staleTmpSwept) {
      _staleTmpSwept = true;
      await sweepStaleTempFiles(file.parent, auditScope: 'blockdocs');
    }
    final tmp = File('$path.${LocalIdGenerator.next('write')}.tmp');
    // 回滚前提：这次写入之前盘上有没有正式版。
    final hadPrevious = file.existsSync();
    try {
      await tmp.writeAsBytes(data, flush: true);
      if (file.existsSync()) {
        try {
          await file.copy('$path.bak');
        } catch (e) {
          // fail-closed：无备份即不得进入「删目标再换入」分支。
          throw FileSystemException('备份写入失败：$e', path);
        }
      }
      await renameBarrierForTest?.call(id, tmp.path);
      try {
        await renameIntoPlace(tmp, file, renameFaultForTest);
      } on FileSystemException {
        if (!file.existsSync()) rethrow;
        // 走到这里 .bak 必然已完整落盘（上一段的 fail-closed 保证），
        // 因此即使下面第二次 rename 失败，加载路径仍可从 .bak 恢复。
        await file.delete();
        await renameIntoPlace(tmp, file, renameFaultForTest);
      }
    } catch (_) {
      // 与画布腿同一条契约（批次 D 补）：第二次 rename 失败时正式文件已被删，
      // 只剩 `.bak`——读路径能回退，但 `listDocHeaders` 只认 `.json`，于是这篇
      // 从首页消失，同步侧「基线有、清单无」还会推导成用户删除并 `DELETE` 云端
      // 副本。失败的写必须把上一版放回去。
      _restoreFromBackup(file, hadPrevious);
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
    onWrite?.call();
  }

  /// 失败出口的回滚：只在 catch 分支执行，成功路径零额外 IO。
  /// 用 `copy` 保留 `.bak`（读路径的兜底依赖它仍在）。
  void _restoreFromBackup(File file, bool hadPrevious) {
    if (!hadPrevious) return;
    try {
      if (file.existsSync()) return;
      final bak = File('${file.path}.bak');
      if (!bak.existsSync()) return;
      bak.copySync(file.path);
      AuditLogger.log(
        'note_block_doc.write_rolled_back_from_backup',
        detail: file.path.split(Platform.pathSeparator).last,
      );
    } catch (_) {
      // 回滚失败不盖掉这次写入的原始异常。
    }
  }

  /// 加载指定 ID 的块文档。不存在返回 null，损坏时尝试 .bak 恢复。
  ///
  /// N2：受独立文件密码保护（v5 信封）的笔记——会话已解锁（DEK 在
  /// 缓存）直接解密返回；未解锁抛 [BlockDocLockedException]（fail-closed，
  /// 调用方先走 UnlockFlow）。
  Future<NoteBlockDoc?> loadDocument(String pageId) async {
    await _ensureDir();
    final path = await _pathFor(pageId);
    final file = File(path);
    final backup = File('$path.bak');
    if (!file.existsSync() && !backup.existsSync()) return null;
    Future<NoteBlockDoc> parse(File source) async {
      final raw = await _prepareDocBytes(pageId, await source.readAsBytes());
      final text = utf8.decode(raw);
      if (EncryptionService.isDualProtectorEnvelope(text)) {
        final dek = _sessionDeks[pageId];
        if (dek == null) throw const BlockDocLockedException();
        final clear = await _encryption.decryptBlockDocPayloadWithDek(
          docId: pageId,
          encryptedJson: text,
          dek: dek,
        );
        return _parseDocTextAsync(clear);
      }
      return _parseDocTextAsync(text);
    }

    try {
      return await parse(file.existsSync() ? file : backup);
    } on BlockDocLockedException {
      rethrow; // 锁定态不做 .bak 回退（fail-closed）
    } catch (_) {
      if (!backup.existsSync()) rethrow;
      return parse(backup);
    }
  }

  DateTime? _lastTrashPurge;

  /// 列出所有块文档 ID（不含 .json 后缀）。惰性清理过期回收站条目。
  ///
  /// P1-H4（审计 2026-08-31）：清理节流为 1 小时一次——listIds 是列表
  /// 热路径（反向链接面板/AllDocs/首页刷新都会调用），每次全盘扫描
  /// 回收站会造成可感知卡顿。
  Future<List<String>> listIds() async {
    await _ensureDir();
    final now = DateTime.now();
    final last = _lastTrashPurge;
    if (last == null || now.difference(last) > const Duration(hours: 1)) {
      _lastTrashPurge = now;
      try {
        await purgeExpiredTrash();
      } catch (_) {
        /* 尽力而为：惰性清理回收站失败不阻塞 listIds 热路径，下次调用再试 */
      }
    }
    final result = <String>[];
    await for (final entity in (await _ensureDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      result.add(name.substring(0, name.length - 5)); // 去掉 .json
    }
    return result;
  }

  /// 全量加载所有块文档（完整解析，含块树）。
  /// 高频调用方（如反向链接面板）请在上层做缓存——本方法每次全量 IO。
  ///
  /// N2：受文件密码保护且未解锁的笔记跳过（fail-closed——反向链接/
  /// 搜索不泄露受密内容）。
  Future<List<NoteBlockDoc>> loadAll() async {
    final docs = <NoteBlockDoc>[];
    for (final id in await listIds()) {
      try {
        final d = await loadDocument(id);
        if (d != null) docs.add(d);
      } on BlockDocLockedException {
        continue; // 锁定态跳过（解锁后自然出现）
      }
    }
    return docs;
  }

  /// 生成唯一 ID（前缀可自定义，默认 'doc'）。
  static String newId([String prefix = 'doc']) => LocalIdGenerator.next(prefix);
}

/// 文档轻量头信息（P2-M5）：列表装配只取头部字段，避免构建整棵块树。
class NoteBlockDocHeader {
  const NoteBlockDocHeader({
    required this.id,
    required this.title,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.locked = false,
  });

  final String id;
  final String title;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 是否受独立文件密码保护且本会话尚未解锁（N2）——
  /// 列表显示锁定占位（「加密笔记」），真实标题/标签不泄露。
  final bool locked;
}

/// 未加密明文 JSON 的头字段批量提取（审计 #15——[Isolate.run] 内执行）。
///
/// 返回 fileId → `[isEnvelope, id, title, tags, createdAt, updatedAt]`；
/// 解析失败/损坏 → `[false, null, null, null, null, null]`（调用侧跳过，
/// 与原逐文件 try-continue 行为一致）。仅回传头字段，body 树不跨 isolate
/// 序列化。依赖项 isolate 安全性：utf8/jsonDecode（dart:convert）+
/// [EncryptionService.isDualProtectorEnvelope]（纯静态解析）。
Map<String, List<Object?>> _parsePlainHeaders(Map<String, Uint8List> jobs) {
  final out = <String, List<Object?>>{};
  for (final entry in jobs.entries) {
    final fileId = entry.key;
    try {
      final text = utf8.decode(entry.value);
      if (EncryptionService.isDualProtectorEnvelope(text)) {
        out[fileId] = [true, null, null, null, null, null];
        continue;
      }
      final root = jsonDecode(text) as Map<String, dynamic>;
      out[fileId] = [
        false,
        root['id'],
        root['title'],
        (root['tags'] as List? ?? const []).whereType<String>().toList(),
        root['createdAt'],
        root['updatedAt'],
      ];
    } catch (_) {
      out[fileId] = const [false, null, null, null, null, null];
    }
  }
  return out;
}
