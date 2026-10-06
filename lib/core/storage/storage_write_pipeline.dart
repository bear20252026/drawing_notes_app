import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

// C-08（审计 2026-09-27）：自 StorageService 的 part 五域拆为真协作类。
// 本类持有**写入管线域**自有状态：每文档写入尾队列（同一文档按请求顺序
// 落盘，不同文档仍可并行，A/B 画布互不覆盖）、密封分流与原子替换。
// 消费方仅经 StorageService 门面（实现 DocumentRepository），API 零变化。

/// 写入管线域：文档独占队列、v3/v1/明文三级密封分流、懒迁移队列、
/// 临时文件原子替换（含 Windows 共享冲突退避）。
class StorageWritePipeline {
  StorageWritePipeline({
    required this.directories,
    required this.secrets,
    required this.keyProvider,
    this.vaultConfigured,
  });


  /// 内部协作面：仅 StorageService 门面装配（C-08 拆分协作类，只读）。
  final StorageDirectories directories;
  final StorageSecretSession secrets;
  final Future<Uint8List?> Function()? keyProvider;

  /// 保险库**是否已建立**（用户设过 PIN / 启用过加密）。
  ///
  /// 写路径必须把「取不到密钥」拆成两种语义，见 [_sealDocBytes]：未建库时
  /// 明文落盘是产品设计，已建库却锁定时明文会把密文用户降级成明文。
  /// 二者在 `keyProvider` 的返回值上长得一样（都是 null），只能由装配层
  /// 显式告知——`app.dart` 注入 `VaultKeyService.isConfigured`。
  final Future<bool> Function()? vaultConfigured;

  /// 未注入探测器时保守按「已建库」处理：维持 2026-09-06 P2-3 的 fail-closed
  /// 语义，不让这个新增的可选参数变成新的 fail-open 后门。
  ///
  /// 媒体域（`StorageMediaStore._sealMediaBytes`）共用本判定——写路径的
  /// 「未建库 vs 锁定」只允许有一处口径。
  Future<bool> encryptionInUse() async =>
      await vaultConfigured?.call() ?? true;

  /// 每个文档各自的写入尾队列。同一文档按请求顺序落盘，不同文档仍可并行，
  /// 因此 A/B 画布不会共享临时文件或相互覆盖较新的版本。
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  /// isolate 加密封包的字节阈值：小于该值时主线程同步封包（isolate
  /// 拷贝往返开销大于收益），大载荷移入 isolate 避免 UI 掉帧。
  static const int isolateSealThreshold = 64 * 1024;

  /// 把 [op] 挂到 [id] 的写尾队列（E-17，与 save/enqueueRawRewrite 共用
  /// [_writeTails]），返回 op 的原始结果。链上某步失败不影响后续步骤。
  Future<T> runDocExclusive<T>(String id, Future<T> Function() op) {
    final previous = _writeTails[id] ?? Future<void>.value();
    final task = previous.catchError((_) {}).then((_) => op());
    late final Future<void> chain;
    chain = task.then(
      (_) {
        if (identical(_writeTails[id], chain)) _writeTails.remove(id);
      },
      onError: (_) {
        if (identical(_writeTails[id], chain)) _writeTails.remove(id);
      },
    );
    _writeTails[id] = chain;
    return task;
  }

  /// 保存入队（门面 save 专用）：与 [runDocExclusive] 同一队列，但保持
  /// 原 save 链语义——`whenComplete` 自清理后把结果/错误原样传给门面的
  /// path/onWrite 后续链。
  Future<void> enqueueSave(String id, Future<void> Function() op) {
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) => op());
    _writeTails[id] = operation;
    return operation.whenComplete(() {
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    });
  }

  /// 当前主密钥（未启用加密返回 null——明文兼容是产品设计）。
  Future<Uint8List?> currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }

  /// 保存文档的原始快照（encode 后密封落盘）。
  Future<void> saveEncoded(String id, Uint8List data) async {
    await directories.ensureDocuments();
    final sealed = await _sealDocBytes(id, data);
    await writeSealedBytes(id, sealed);
  }

  /// 写入前的字节准备（批次② 三级分流）：
  /// ① 会话有文件密码 → v3 双保护器信封（N4 批 2：复用会话 DEK——
  ///    重置盘槽位跨保存持续有效）；
  /// ② 无文件密码 + 有主密钥 → v1 主密钥信封（AAD 绑定文档 ID）；
  /// ③ 保险库已启用但处于锁定态 → 抛 [VaultFileLockException]
  ///    （fail-closed，与读路径对齐；保存链按失败策略退避，解锁后自愈）；
  /// ④ 未启用加密（无 keyProvider）→ 明文兼容（旧数据行为）。
  ///
  /// U2 优化（2026-09-02，P1-10）：≥64KB 的载荷在 isolate 内完成
  /// AES-GCM 封包（参数均为可跨 isolate 传递的纯数据），加密期间的
  /// 字节处理不再占用主线程。
  Future<Uint8List> _sealDocBytes(String id, Uint8List data) async {
    final filePassword = secrets.filePasswordFor(id);
    if (filePassword != null) {
      final dek = secrets.dekFor(id);
      final usbWrapped = secrets.usbWrappedFor(id);
      Future<Uint8List> seal() => VaultFileCodec.encryptWithPasswordV3(
        data,
        filePassword,
        aadContext: 'doc:$id',
        dek: dek,
        usbWrapped: usbWrapped,
      );
      if (data.length < isolateSealThreshold) return seal();
      return Isolate.run(seal);
    }
    final provider = keyProvider;
    // 未启用加密（无 keyProvider）：明文落盘是产品设计（用户未设 PIN），
    // 与读路径「明文 + 无密钥 → 原样返回」对称。
    if (provider == null) return data;
    final key = await provider();
    if (key == null) {
      // 「取不到密钥」有两种完全不同的含义，必须分清（P0 修复，2026-10-06，
      // 由 cuj_01 真机取证定性）：
      //  ① 保险库**从未建立**（用户没设过 PIN）——明文落盘是产品设计，与
      //     NoteBlockDocStore 写路径同口径；一律拒绝会让这类用户**完全存不了
      //     画布**（异常被 SaveScheduler 退避吞掉，表现就是「画完关掉就没了」）；
      //  ② 已建立但本会话未解锁——写明文会把密文用户降级成明文，保持
      //     2026-09-06 P2-3 的 fail-closed，交由重试策略在解锁后自愈。
      if (!await encryptionInUse()) return data;
      throw const VaultFileLockException();
    }
    if (data.length < isolateSealThreshold) {
      return VaultFileCodec.encrypt(data, key, aadContext: 'doc:$id');
    }
    return Isolate.run(
      () => VaultFileCodec.encrypt(data, key, aadContext: 'doc:$id'),
    );
  }

  /// 读取后的字节准备（读路径自动分流，Joplin 懒迁移模式）：
  /// - v2 密码信封 + 会话有密码 → 解密；无密码 → [VaultFilePasswordLockException]；
  /// - v1 主密钥信封 + 已解锁 → 解密；锁定 → [VaultFileLockException]；
  /// - 明文 + 有密钥 → 原样返回并排队懒迁移（下次写队列将明文重写为密文）；
  /// - 明文 + 无密钥 → 原样返回（旧版本兼容）。
  Future<Uint8List> prepareDocBytes(String id, Uint8List raw) async {
    if (VaultFileCodec.isPasswordEnvelope(raw)) {
      final filePassword = secrets.filePasswordFor(id);
      if (filePassword == null) {
        throw const VaultFilePasswordLockException();
      }
      if (VaultFileCodec.isV3Envelope(raw)) {
        // N4 批 2：v3 双保护器信封——解锁并缓存 DEK/USB 槽位（续写续用）。
        final unlock = await VaultFileCodec.unlockWithPasswordV3(
          raw,
          filePassword,
          aadContext: 'doc:$id',
        );
        secrets.cacheV3Material(id, unlock);
        return unlock.plain;
      }
      return VaultFileCodec.decryptWithPassword(
        raw,
        filePassword,
        aadContext: 'doc:$id',
      );
    }
    final key = await currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
    }
    if (key != null) enqueueRawRewrite(id, raw);
    return raw;
  }

  /// 懒迁移：把明文字节经既有写尾队列重写为密文（与保存共用并发纪律）。
  ///
  /// P1 修复（本次）：入队时捕获的 `plaintext` 是**读路径 await 之前**的快照
  /// （listDocuments 读 raw → 若干 await → 才入队），队列里排在它前面的较新
  /// 保存会被这份陈旧快照反超覆盖（编辑内容静默回退）。现在在队列内重读当前
  /// 文件字节，与快照不一致（或文件已消失）就放弃本次迁移——下次读取会重新
  /// 排队（幂等），语义对齐 file_password_concurrency_test 断言的「重封写不
  /// 是覆盖陈旧明文」。
  void enqueueRawRewrite(String id, Uint8List plaintext) {
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      if (!await _isStillCurrentPlaintext(id, plaintext)) return;
      await saveEncoded(id, plaintext);
    });
    _writeTails[id] = operation;
    operation.whenComplete(() {
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    });
  }

  /// 迁移前置校验：磁盘当前字节仍是入队时捕获的明文快照才允许重写。
  /// 读取失败/文件缺失一律判否（fail-closed——宁可这次不迁移，也不覆盖新内容）。
  Future<bool> _isStillCurrentPlaintext(String id, Uint8List snapshot) async {
    if (!StorageDirectories.validIdPattern.hasMatch(id)) return false;
    try {
      await directories.ensureDocuments();
      final file = File(directories.documentPathFor(id));
      if (!file.existsSync()) return false; // 已删除/已进回收站——不复活
      return _bytesEqual(await file.readAsBytes(), snapshot);
    } catch (_) {
      return false;
    }
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 把已密封字节原子落盘（含 .bak 备份——与 saveEncoded 同纪律）。
  ///
  /// A2/A3 修复（审计 2026-09-07）：
  /// - `.bak` 备份失败改为 fail-closed——复制失败时中止本次写入（正式文件
  ///   保持完好、清理 tmp 后抛「备份写入失败」）。此前静默吞错会在 Windows
  ///   回退路径（先删目标再 rename）下失去崩溃恢复保障：rename 期崩溃 =
  ///   旧版无 .bak、新版未落盘，文档表现为丢失。
  /// - tmp 写入/rename 任一失败都清理残留临时文件，防止半写 .tmp 堆积。
  /// 失败路径顺序保证：copy bak 在 rename tmp→dest 之前，任何失败发生时
  /// 正式文件都未被删除/覆盖。
  Future<void> writeSealedBytes(String id, Uint8List sealed) async {
    await directories.ensureDocuments();
    final finalFile = File(directories.documentPathFor(id));
    final tmp = File('${finalFile.path}.${LocalIdGenerator.next('write')}.tmp');
    try {
      await tmp.writeAsBytes(sealed, flush: true);

      // 备份上一版：若平台不允许直接覆盖目标文件，恢复路径仍保留上一份
      // 完整数据。备份是 Windows 删除-换入回退的崩溃恢复前提——失败即中止。
      if (finalFile.existsSync()) {
        try {
          await finalFile.copy('${finalFile.path}.bak');
        } catch (e) {
          throw FileSystemException('备份写入失败：$e', finalFile.path);
        }
      }
      await replaceWithTemp(tmp, finalFile);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
  }

  /// 首选 rename（POSIX 原子替换）；若 Windows 拒绝覆盖已有文件，则在已经
  /// 生成 `.bak` 的前提下删除旧目标并立即换入完整临时文件。加载逻辑会在
  /// 正式文件缺失或损坏时读取 `.bak`，因此崩溃窗口不会表现为文档消失。
  ///
  /// Windows 共享冲突退避（2026-09-24 懒迁移 flake 根因修复）：杀毒/
  /// 索引器/并发读会短暂持有目标句柄——delete 抛 errno 32，甚至 delete
  /// 返回后的 delete-pending 窗口里 rename 也会失败。与 [readWithRetry]
  /// 同思路做有界退避重试：`.bak` 已先行落盘，重试不放大风险；耗尽后
  /// 按原样抛出（备份仍在，读路径可恢复）。
  Future<void> replaceWithTemp(File tmp, File destination) async {
    for (var attempt = 1;; attempt++) {
      try {
        try {
          await tmp.rename(destination.path);
        } on FileSystemException {
          if (!destination.existsSync()) rethrow;
          await destination.delete();
          await tmp.rename(destination.path);
        }
        return;
      } on FileSystemException catch (e) {
        // errno 5（拒绝访问）多为 delete-pending 句柄窗口，同属瞬态。
        final code = e.osError?.errorCode;
        final transient = code == 32 || code == 5;
        if (!transient || attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 25 * attempt));
      }
    }
  }

  /// 带重试的文件读取：瞬时 IO 错误（`FileSystemException`）自动重试
  /// [retries] 次，间隔 50ms 递增；最终仍失败则向上抛出
  /// （对齐 Saber FileManager：避免 U 盘/网络盘抖动误报"文档损坏"）。
  static Future<Uint8List> readWithRetry(
    Future<Uint8List> Function() read, {
    int retries = 3,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await read();
      } on FileSystemException {
        if (attempt >= retries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
      }
    }
  }
}
