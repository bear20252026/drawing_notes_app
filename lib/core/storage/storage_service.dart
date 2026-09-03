import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

part 'storage_service_file_password.dart';

/// 本地文件存储服务：负责工程文件的保存、读取、列表、删除。
///
/// 目录结构（应用文档目录下）：
///   `appDir/documents/`
///     `docId.json` —— 工程文件（含全部图层与笔画）
///
/// 设计要点：
/// - 全部为本地文件操作，不发起任何网络请求（符合开发计划约束）；
/// - 保存采用"先写临时文件再原子替换"，防止写入中断导致文件损坏；
/// - 存储层与绘图引擎层解耦：UI/引擎不感知文件格式细节，
///   后续若更换为数据库（sqflite）或云同步，只需替换本类实现
///   （已通过 [DocumentRepository] 接口抽象，见 repository.dart）。
class StorageService implements DocumentRepository {
  StorageService({
    DocumentCodec? codec,
    this.directoryProvider,
    this.keyProvider,
  }) : _codec = codec ?? const DocumentCodec();

  final DocumentCodec _codec;

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  /// 主密钥提供者（加密底座批次①b）：返回解锁态主密钥时，文档 JSON 以
  /// AES-256-GCM 信封落盘（`DNV` 魔数，AAD 绑定文档 ID）；返回 null
  /// （未设密码 / 保险库锁定）时保持明文兼容。由组合根注入。
  final Future<Uint8List?> Function()? keyProvider;

  // ---- 单文件密码（批次②）：画作级独立密码（v2 密码信封） ----
  //
  // 会话级密码缓存：解锁一次后本次使用期间免重复输入（用户 2026-09-01
  // 拍板「会话内记住」）；切后台回锁/重启后自动失效（内存态，不落盘）。
  final Map<String, String> _sessionFilePasswords = <String, String>{};

  // N4 批 2（v3 双保护器信封）会话密钥材料：
  // - DEK 按文档稳定复用（写入时不换 DEK）——否则每次保存都会作废
  //   重置盘槽位（LUKS 槽位语义要求 DEK 恒定，与 PIN 可随时换盐对偶）；
  // - USB 槽位密文原样保留（密文包裹的是 DEK，DEK 不变则槽位永续有效）。
  // 两者均为内存态：与文件密码同生命周期（forgetFilePassword 一并清零）。
  final Map<String, Uint8List> _sessionDocDeks = <String, Uint8List>{};
  final Map<String, Uint8List> _sessionFileUsbWrapped = <String, Uint8List>{};

  /// 该文档本会话内是否已解锁文件密码（编辑器保存走同一密封路径）。
  String? filePasswordFor(String docId) => _sessionFilePasswords[docId];

  /// 缓存会话文件密码（verifyFilePassword 成功后调用）。
  void cacheFilePassword(String docId, String password) {
    _sessionFilePasswords[docId] = password;
  }

  /// 缓存 v3 解锁产物（DEK + USB 槽位密文；未绑定槽位时清除旧值）。
  void _cacheV3Material(String docId, VaultFileV3Unlock unlock) {
    _sessionDocDeks[docId] = unlock.dek;
    final usb = unlock.usbWrapped;
    if (usb != null) {
      _sessionFileUsbWrapped[docId] = usb;
    } else {
      _sessionFileUsbWrapped.remove(docId);
    }
  }

  /// 清除会话文件密码（移除文件密码 / 文档删除后调用）。
  /// N4 批 2：DEK（内存清零——D-2 模式）与 USB 槽位缓存一并清除。
  void forgetFilePassword(String docId) {
    _sessionFilePasswords.remove(docId);
    final dek = _sessionDocDeks.remove(docId);
    if (dek != null) dek.fillRange(0, dek.length, 0);
    _sessionFileUsbWrapped.remove(docId);
  }

  /// 写成功回调（首页刷新修复①）：画布保存/缩略图更新/删除落盘成功后触发，
  /// 由装配层注入（AppServices.bumpDataVersion），驱动首页/AllDocs 刷新。
  void Function()? onWrite;

  /// 文档存放目录（懒加载，首次调用时创建）。
  Directory? _documentsDir;

  /// M-06 修复（专家审计 2026-08-15）：回收站目录与保留期——删除移入
  /// 回收站（Android 官方 createTrashRequest/Files by Google 30 天模式）。
  Directory? _trashDir;
  static const Duration _trashRetention = Duration(days: 30);

  /// 缩略图存放目录。
  Directory? _thumbsDir;

  /// 独立绘图文档导入图片的离线副本目录。
  Directory? _imagesDir;

  /// 每个文档各自的写入尾队列。同一文档按请求顺序落盘，不同文档仍可并行，
  /// 因此 A/B 画布不会共享临时文件或相互覆盖较新的版本。
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  Future<Directory> _ensureDocumentsDir() async {
    if (_documentsDir != null) return _documentsDir!;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}documents');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _documentsDir = dir;
    return dir;
  }

  /// 回收站目录（M-06：删除移入 + 30 天保留——Android 官方模式）。
  Future<Directory> _ensureTrashDir() async {
    if (_trashDir != null) return _trashDir!;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    final dir = Directory(
      '${appDir.path}${Platform.pathSeparator}documents_trash',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _trashDir = dir;
    return dir;
  }

  Future<Directory> _ensureThumbsDir() async {
    if (_thumbsDir != null) return _thumbsDir!;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}thumbnails');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _thumbsDir = dir;
    return dir;
  }

  Future<Directory> _ensureImagesDir() async {
    if (_imagesDir != null) return _imagesDir!;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    final dir = Directory(
      '${appDir.path}${Platform.pathSeparator}document_images',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _imagesDir = dir;
    return dir;
  }

  /// 校验文档 ID 是否安全（仅允许字母、数字、下划线）。
  ///
  /// 安全说明：ID 直接拼入文件路径，若允许 `../` 等字符会造成路径遍历。
  /// 所有合法 ID 由 [newId] 生成；此校验作为防御性边界。
  /// 允许 '-'（与 DocumentCodec._validDocumentId 一致，消除合法文档
  /// 无法保存的不一致；'-' 无路径遍历风险）。
  static bool isValidId(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  /// 列表页单文件大小上限（链 9 修复 2026-08-15）：防恶意超大 .json
  /// 在 listDocuments 时 OOM（与 DocumentCodec 100MB 预检一致）。
  static const int _maxListMetaBytes = 100 * 1024 * 1024;

  String _pathFor(String id) {
    // 链 A 修复（军工审计 2026-08-15）：assert-only 校验在 release 失效——
    // 运行时强制校验（load/delete/saveThumbnail 均经此统一防护路径遍历）。
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '文档 ID 不合法（路径遍历防护）');
    }
    return '${_documentsDir!.path}${Platform.pathSeparator}$id.json';
  }

  String _thumbPathFor(String id) {
    if (!isValidId(id)) {
      throw ArgumentError.value(id, 'id', '缩略图 ID 不合法（路径遍历防护）');
    }
    return '${_thumbsDir!.path}${Platform.pathSeparator}$id.png';
  }

  /// 保存文档的缩略图（PNG 字节），供列表页快速展示。
  /// 缩略图与工程文件分离存储，损坏不影响工程文件。
  /// 批次①c：有主密钥时信封加密落盘（读取走 [thumbnailBytes]）。
  /// 批次②：单文件密码文档不写缩略图（防首页预览泄露——用户拍板）。
  Future<String> saveThumbnail(String docId, Uint8List pngBytes) async {
    if (_sessionFilePasswords.containsKey(docId)) return '';
    await _ensureThumbsDir();
    final file = File(_thumbPathFor(docId));
    final sealed = await _sealMediaBytes(file.path, pngBytes);
    final tmp = File('${file.path}.${LocalIdGenerator.next('thumb')}.tmp');
    await tmp.writeAsBytes(sealed, flush: true);
    await _replaceWithTemp(tmp, file);
    onWrite?.call();
    return file.path;
  }

  /// 读取缩略图字节（批次①c）：密文自动解密；锁定返回 null
  /// （fail-closed——UI 显示占位图，不泄露任何像素）；明文 + 有密钥
  /// 时原样返回并尽力懒迁移为密文。不存在返回 null。
  /// 批次②：单文件密码文档恒返回 null（缩略图已被删除，防御性兜底）。
  Future<Uint8List?> thumbnailBytes(String docId) async {
    if (await isFilePasswordProtected(docId)) return null;
    await _ensureThumbsDir();
    final file = File(_thumbPathFor(docId));
    if (!await file.exists()) return null;
    final raw = await file.readAsBytes();
    if (!VaultFileCodec.isEncrypted(raw)) {
      final key = await _currentKey();
      if (key != null) {
        // 懒迁移（尽力而为）：明文缩略图重写为密文。
        try {
          final sealed = await _sealMediaBytes(file.path, raw);
          final tmp = File(
            '${file.path}.${LocalIdGenerator.next('thumb')}.tmp',
          );
          await tmp.writeAsBytes(sealed, flush: true);
          await _replaceWithTemp(tmp, file);
        } catch (_) {
          // 迁移失败不影响本次读取。
        }
      }
      return raw;
    }
    final key = await _currentKey();
    if (key == null) return null;
    try {
      return await VaultFileCodec.decrypt(
        raw,
        key,
        aadContext: VaultFileCodec.contextForPath(file.path),
      );
    } catch (_) {
      // 损坏缩略图不影响列表展示（与明文时代 errorBuilder 行为一致）。
      return null;
    }
  }

  /// 读取缩略图文件路径（不存在返回 null）。
  Future<String?> thumbnailPath(String docId) async {
    await _ensureThumbsDir();
    final file = File(_thumbPathFor(docId));
    if (!await file.exists()) return null;
    return file.path;
  }

  /// 将用户选择的图片复制为本应用管理的离线副本。
  ///
  /// 原文件被移动、删除或来自临时内容 URI 后，文档仍可正常恢复。写入使用
  /// 临时文件再替换，避免中途取消留下半张图片。
  Future<String> storeImage(String sourcePath, String docId) async {
    if (!isValidId(docId)) {
      throw ArgumentError.value(docId, 'docId', '文档 ID 不合法');
    }
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(sourcePath, 'sourcePath', '图片文件不存在');
    }
    final extension = _safeImageExtension(source.path);
    final dir = await _ensureImagesDir();
    final name = '${docId}_${LocalIdGenerator.next('img')}$extension';
    final destination = File('${dir.path}${Platform.pathSeparator}$name');
    final temporary = File('${destination.path}.tmp');
    try {
      // 批次①c：有主密钥 → 信封加密副本（读取走 VaultFileCodec.readImageBytes）。
      final raw = await source.readAsBytes();
      final stored = await _sealMediaBytes(destination.path, raw);
      await temporary.writeAsBytes(stored, flush: true);
      await _replaceWithTemp(temporary, destination);
      return destination.path;
    } catch (_) {
      // 图片复制失败时不留下可被误识别为下一次写入的临时副本。
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常，调用方仍得到真实失败原因。
      }
      rethrow;
    }
  }

  static String _safeImageExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.png';
    final candidate = path.substring(dot).toLowerCase();
    const allowed = <String>{'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
    return allowed.contains(candidate) ? candidate : '.png';
  }

  /// 保存文档。成功后返回文件路径。
  ///
  /// 崩溃恢复：写入新版本前，把上一版正式文件备份为 `.bak`，
  /// 加载时若正式文件损坏可自动回退到备份（借鉴 nb 版本回溯思想）。
  ///
  /// 链 G 说明（军工审计 2026-08-15）：`.bak` 保留上一版内容（含用户已
  /// 删除的对象——崩溃恢复的必要代价，仅最近 1 版且 delete 时彻底清理）；
  /// 敏感内容建议启用加密（密文 .bak 无明文残留）。
  @override
  Future<String> save(DrawingDocument doc) {
    if (!isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    // 在进入异步队列前编码出不可变快照。编辑器继续修改 doc 时，队列中的
    // 某次保存仍代表其被请求时的完整版本，而不是可变对象的半成品状态。
    // U2 优化（2026-09-02，P1-10）：主线程只构建快照 Map，jsonEncode +
    // UTF-8 交给 isolate（大文档时），保存瞬间不再阻塞 UI。
    final snapshot = DocumentCodec.snapshotOf(doc);
    final id = doc.id;
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      final data = await DocumentCodec.encodeSnapshotAsync(snapshot);
      await _saveEncoded(id, data);
    });
    _writeTails[id] = operation;
    return operation
        .whenComplete(() {
          if (identical(_writeTails[id], operation)) _writeTails.remove(id);
        })
        .then((_) async {
          await _ensureDocumentsDir();
          return _pathFor(id);
        })
        .then((path) {
          onWrite?.call();
          return path;
        });
  }

  Future<Uint8List?> _currentKey() async {
    final provider = keyProvider;
    if (provider == null) return null;
    return provider();
  }

  /// isolate 加密封包的字节阈值：小于该值时主线程同步封包（isolate
  /// 拷贝往返开销大于收益），大载荷移入 isolate 避免 UI 掉帧。
  static const int _isolateSealThreshold = 64 * 1024;

  /// 写入前的字节准备（批次② 三级分流）：
  /// ① 会话有文件密码 → v3 双保护器信封（N4 批 2：复用会话 DEK——
  ///    重置盘槽位跨保存持续有效）；
  /// ② 无文件密码 + 有主密钥 → v1 主密钥信封（AAD 绑定文档 ID）；
  /// ③ 均无 → 明文兼容（旧数据行为）。
  ///
  /// U2 优化（2026-09-02，P1-10）：≥64KB 的载荷在 isolate 内完成
  /// AES-GCM 封包（参数均为可跨 isolate 传递的纯数据），加密期间的
  /// 字节处理不再占用主线程。
  Future<Uint8List> _sealDocBytes(String id, Uint8List data) async {
    final filePassword = _sessionFilePasswords[id];
    if (filePassword != null) {
      final dek = _sessionDocDeks[id];
      final usbWrapped = _sessionFileUsbWrapped[id];
      Future<Uint8List> seal() => VaultFileCodec.encryptWithPasswordV3(
        data,
        filePassword,
        aadContext: 'doc:$id',
        dek: dek,
        usbWrapped: usbWrapped,
      );
      if (data.length < _isolateSealThreshold) return seal();
      return Isolate.run(seal);
    }
    final key = await _currentKey();
    if (key == null) return data;
    if (data.length < _isolateSealThreshold) {
      return VaultFileCodec.encrypt(data, key, aadContext: 'doc:$id');
    }
    return Isolate.run(
      () => VaultFileCodec.encrypt(data, key, aadContext: 'doc:$id'),
    );
  }

  /// 媒体字节写入前准备（批次①c：缩略图 / 受管图片）：有主密钥 →
  /// 信封加密（AAD 绑定文件名）。
  Future<Uint8List> _sealMediaBytes(String path, Uint8List bytes) async {
    final key = await _currentKey();
    if (key == null) return bytes;
    return VaultFileCodec.encrypt(
      bytes,
      key,
      aadContext: VaultFileCodec.contextForPath(path),
    );
  }

  /// 读取后的字节准备（读路径自动分流，Joplin 懒迁移模式）：
  /// - v2 密码信封 + 会话有密码 → 解密；无密码 → [VaultFilePasswordLockException]；
  /// - v1 主密钥信封 + 已解锁 → 解密；锁定 → [VaultFileLockException]；
  /// - 明文 + 有密钥 → 原样返回并排队懒迁移（下次写队列将明文重写为密文）；
  /// - 明文 + 无密钥 → 原样返回（旧版本兼容）。
  Future<Uint8List> _prepareDocBytes(String id, Uint8List raw) async {
    if (VaultFileCodec.isPasswordEnvelope(raw)) {
      final filePassword = _sessionFilePasswords[id];
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
        _cacheV3Material(id, unlock);
        return unlock.plain;
      }
      return VaultFileCodec.decryptWithPassword(
        raw,
        filePassword,
        aadContext: 'doc:$id',
      );
    }
    final key = await _currentKey();
    if (VaultFileCodec.isEncrypted(raw)) {
      if (key == null) throw const VaultFileLockException();
      return VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
    }
    if (key != null) _enqueueRawRewrite(id, raw);
    return raw;
  }

  /// 懒迁移：把明文字节经既有写尾队列重写为密文（与保存共用并发纪律）。
  void _enqueueRawRewrite(String id, Uint8List plaintext) {
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) async {
      await _saveEncoded(id, plaintext);
    });
    _writeTails[id] = operation;
    operation.whenComplete(() {
      if (identical(_writeTails[id], operation)) _writeTails.remove(id);
    });
  }

  Future<void> _saveEncoded(String id, Uint8List data) async {
    await _ensureDocumentsDir();
    final sealed = await _sealDocBytes(id, data);
    await _writeSealedBytes(id, sealed);
  }

  /// 把已密封字节原子落盘（含 .bak 备份——与 _saveEncoded 同纪律）。
  Future<void> _writeSealedBytes(String id, Uint8List sealed) async {
    await _ensureDocumentsDir();
    final finalFile = File(_pathFor(id));
    final tmp = File('${finalFile.path}.${LocalIdGenerator.next('write')}.tmp');
    await tmp.writeAsBytes(sealed, flush: true);

    // 备份上一版：若平台不允许直接覆盖目标文件，恢复路径仍保留上一份完整数据。
    if (await finalFile.exists()) {
      try {
        await finalFile.copy('${finalFile.path}.bak');
      } catch (_) {
        // 备份失败不改变本次写入流程；目标文件仍未被提前删除。
      }
    }
    await _replaceWithTemp(tmp, finalFile);
  }

  /// 首选 rename（POSIX 原子替换）；若 Windows 拒绝覆盖已有文件，则在已经
  /// 生成 `.bak` 的前提下删除旧目标并立即换入完整临时文件。加载逻辑会在
  /// 正式文件缺失或损坏时读取 `.bak`，因此崩溃窗口不会表现为文档消失。
  Future<void> _replaceWithTemp(File tmp, File destination) async {
    try {
      await tmp.rename(destination.path);
    } on FileSystemException {
      if (!await destination.exists()) rethrow;
      await destination.delete();
      await tmp.rename(destination.path);
    }
  }

  /// 加载指定文档。文件不存在返回 null，格式损坏抛出异常（由调用方提示）。
  ///
  /// 崩溃恢复：正式文件损坏时，尝试读取 `.bak` 上一版备份。
  /// 读失败重试（对齐 Saber FileManager）：瞬时 IO 错误自动重试 3 次，
  /// 避免 U 盘/网络盘抖动导致误报"文档损坏"。
  @override
  Future<DrawingDocument?> load(String id) async {
    await _ensureDocumentsDir();
    final file = File(_pathFor(id));
    final bak = File('${_pathFor(id)}.bak');
    if (!await file.exists() && !await bak.exists()) return null;
    Future<Uint8List> preparedBytes(File source) async {
      final raw = await _readWithRetry(() async => await source.readAsBytes());
      return _prepareDocBytes(id, raw);
    }

    try {
      return _codec.decode(
        await preparedBytes(await file.exists() ? file : bak),
      );
    } on FormatException {
      // 正式文件损坏：尝试备份恢复。
      if (await bak.exists()) {
        return _codec.decode(await preparedBytes(bak));
      }
      rethrow;
    }
  }

  /// 带重试的文件读取：瞬时 IO 错误（`FileSystemException`）自动重试
  /// [retries] 次，间隔 50ms 递增；最终仍失败则向上抛出。
  static Future<Uint8List> _readWithRetry(
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

  /// 列出所有已保存文档（含元信息），按更新时间倒序。
  @override
  Future<List<DocumentMeta>> listDocuments() async {
    // M-06：列表时自动清理过期回收站项（30 天保留——Android 官方模式）。
    await purgeTrash();
    final dir = await _ensureDocumentsDir();
    final metas = <DocumentMeta>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        // 链 9 修复（军工审计 2026-08-15）：列表页大小预检——原实现无
        // 限制 readAsBytes + jsonDecode，恶意超大 .json（如 90MB）会在
        // 打开主页时 OOM（D-4 只约束 load 路径）。
        if (await entity.length() > _maxListMetaBytes) continue;
        final raw = await entity.readAsBytes();
        // 批次①b：文件名即文档 ID（save 以 doc.id 命名），AAD 绑定用。
        final fileName = entity.uri.pathSegments.last;
        final fileId = fileName.substring(0, fileName.length - '.json'.length);
        var bytes = raw;
        var locked = false;
        if (VaultFileCodec.isPasswordEnvelope(raw)) {
          // 批次②：单文件密码信封——会话有密码 → 正常读元信息；
          // 无密码 → 锁定占位（不暴露标题等任何元信息）。
          final filePassword = _sessionFilePasswords[fileId];
          if (filePassword == null) {
            locked = true;
          } else if (VaultFileCodec.isV3Envelope(raw)) {
            // N4 批 2：v3 信封——解锁并缓存 DEK/USB 槽位。
            final unlock = await VaultFileCodec.unlockWithPasswordV3(
              raw,
              filePassword,
              aadContext: 'doc:$fileId',
            );
            _cacheV3Material(fileId, unlock);
            bytes = unlock.plain;
          } else {
            bytes = await VaultFileCodec.decryptWithPassword(
              raw,
              filePassword,
              aadContext: 'doc:$fileId',
            );
          }
        } else if (VaultFileCodec.isEncrypted(raw)) {
          final key = await _currentKey();
          // fail-closed：锁定状态不暴露加密文档（跳过，不中断整个列表）。
          if (key == null) continue;
          bytes = await VaultFileCodec.decrypt(
            raw,
            key,
            aadContext: 'doc:$fileId',
          );
        } else if (await _currentKey() != null) {
          // 懒迁移：明文文档排队重写为密文。
          if (isValidId(fileId)) _enqueueRawRewrite(fileId, raw);
        }
        if (locked) {
          if (!isValidId(fileId)) continue;
          metas.add(
            DocumentMeta(
              id: fileId,
              title: '加密画布',
              width: 0,
              height: 0,
              createdAt: DateTime.now(),
              updatedAt: await _fileModifiedOrNow(entity),
              layerCount: 0,
              strokeCount: 0,
              locked: true,
            ),
          );
          continue;
        }
        final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final doc = root['document'] as Map<String, dynamic>;
        final docId = doc['id'];
        // 链 A 修复（军工审计 2026-08-15）：列表 id 校验——恶意工程文件
        // 可携带任意 id，过滤不合法 id 防路径遍历（load/delete 入口）。
        if (docId is! String || !isValidId(docId)) continue;
        metas.add(
          DocumentMeta(
            id: docId,
            title: doc['title'] as String? ?? '未命名',
            width: (doc['width'] as num?)?.toInt() ?? 2048,
            height: (doc['height'] as num?)?.toInt() ?? 1536,
            createdAt:
                DateTime.tryParse(doc['createdAt'] as String? ?? '') ??
                DateTime.now(),
            updatedAt:
                DateTime.tryParse(doc['updatedAt'] as String? ?? '') ??
                DateTime.now(),
            layerCount: (doc['layers'] as List? ?? const []).length,
            strokeCount: _countStrokes(
              (doc['layers'] as List? ?? const []).cast<Map<String, Object?>>(),
            ),
            folder: doc['folder'] is String ? doc['folder'] as String : '',
          ),
        );
      } on FormatException {
        // 跳过损坏文件，不中断整个列表。
        continue;
      } catch (_) {
        continue;
      }
    }
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return metas;
  }

  int _countStrokes(List<Map<String, Object?>> layers) {
    var n = 0;
    for (final l in layers) {
      n += (l['strokes'] as List? ?? const []).length;
    }
    return n;
  }

  /// 文件修改时间（失败回退当前时间——锁定占位元信息排序用）。
  static Future<DateTime> _fileModifiedOrNow(File f) async {
    try {
      return (await f.stat()).modified;
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 删除指定文档及其不再被任何其他文档引用的受管图片副本。
  ///
  /// 图片清理以文档中的引用清单为准，并且只会删除 [storeImage] 写入的
  /// `document_images/` 顶层文件。用户原始文件、外部路径、解码失败的文档及
  /// 仍被其他文档引用的资产全部保留，宁可留下可维护的孤儿文件也不冒误删风险。
  @override
  Future<bool> delete(String id) async {
    await _ensureDocumentsDir();
    final file = File(_pathFor(id));
    if (!await file.exists()) return false;

    // 必须在删除主文件前读取其引用；无法读取时不进行资产回收，保证数据安全。
    DrawingDocument? document;
    try {
      var raw = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(raw)) {
        final key = await _currentKey();
        // 锁定/无密钥：解不开就不读——文档置 null，保守跳过资产回收。
        if (key != null) {
          raw = await VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
        }
      }
      document = _codec.decode(raw);
    } catch (_) {
      // 损坏/锁定文档仍允许用户删除，但不基于不可信内容删除任何资产。
    }

    final imagePaths = <String>{};
    if (document != null) {
      for (final item in document.imageItems) {
        final managedPath = await _managedImagePathOrNull(item.filePath);
        if (managedPath != null) imagePaths.add(managedPath);
      }
    }

    // M-06 修复（专家审计 2026-08-15）：删除移入回收站（30 天保留——
    // Android 官方 createTrashRequest 模式），非永久删除——误删可恢复。
    final trashDir = await _ensureTrashDir();
    await file.rename(
      '${trashDir.path}${Platform.pathSeparator}'
      '${id}_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final backup = File('${file.path}.bak');
    if (await backup.exists()) {
      await backup.delete();
    }

    // 清理缩略图（尽力而为，缩略图缺失不影响使用）。
    try {
      await _ensureThumbsDir();
      final thumb = File(_thumbPathFor(id));
      if (await thumb.exists()) {
        await thumb.delete();
      }
    } catch (_) {
      // 缩略图清理失败不影响文档删除与后续资产回收。
    }
    forgetFilePassword(id); // 批次②：删除后清除会话文件密码缓存

    await _deleteUnreferencedManagedImages(imagePaths, excludingDocumentId: id);
    onWrite?.call();
    return true;
  }

  /// 恢复回收站项（M-06）：trashName 如 `doc123_1720000000000.json`——
  /// 移回 documents/ 目录。返回恢复后的文档 ID；失败（原 ID 冲突等）返回 null。
  Future<String?> restoreTrash(String trashName) async {
    final trashDir = await _ensureTrashDir();
    final src = File('${trashDir.path}${Platform.pathSeparator}$trashName');
    if (!await src.exists()) return null;
    final id = trashName.split('_').first;
    if (!isValidId(id)) return null;
    final dest = File(_pathFor(id));
    if (await dest.exists()) return null; // 原 ID 已存在——拒绝覆盖
    await src.rename(dest.path);
    onWrite?.call();
    return id;
  }

  /// 列出回收站项（M-06）：返回 (trashName, 原始 id, 删除时间)，最近在前。
  Future<List<(String, String, DateTime)>> listTrash() async {
    final trashDir = await _ensureTrashDir();
    final items = <(String, String, DateTime)>[];
    await for (final entity in trashDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      final parts = name.split('_');
      if (parts.length < 2 || !isValidId(parts.first)) continue;
      final ts = int.tryParse(parts[1].split('.').first) ?? 0;
      items.add((name, parts.first, DateTime.fromMillisecondsSinceEpoch(ts)));
    }
    items.sort((a, b) => b.$3.compareTo(a.$3));
    return items;
  }

  /// 清理过期回收站项（M-06）：超过保留期（默认 30 天）永久删除。
  Future<int> purgeTrash({Duration retention = _trashRetention}) async {
    final trashDir = await _ensureTrashDir();
    final now = DateTime.now();
    var purged = 0;
    await for (final entity in trashDir.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) > retention) {
          await entity.delete();
          purged++;
        }
      } catch (_) {
        // 单个清理失败忽略。
      }
    }
    return purged;
  }

  /// 永久删除单个回收站项（M-06 UI：Delete forever 与 Restore 分离——
  /// UX Patterns 官方模式）。返回是否删除成功。
  Future<bool> deleteTrashPermanently(String trashName) async {
    final trashDir = await _ensureTrashDir();
    // 防路径遍历：trashName 仅允许 `id_时间戳.json` 形态。
    if (!RegExp(r'^[A-Za-z0-9_-]+_\d+\.json$').hasMatch(trashName)) {
      return false;
    }
    final file = File('${trashDir.path}${Platform.pathSeparator}$trashName');
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// 返回规范化后的受管离线图片路径；外部路径、嵌套路径和非法路径返回 null。
  ///
  /// [storeImage] 只向 `document_images/` 顶层写入文件。严格的父目录相等检查
  /// 防止文档 JSON 被篡改后借删除操作清理应用目录以外的任意文件。
  Future<String?> _managedImagePathOrNull(String path) async {
    if (path.isEmpty) return null;
    final root = await _ensureImagesDir();
    final image = File(path).absolute;
    final parentPath = image.parent.absolute.uri.normalizePath().toFilePath();
    final rootPath = root.absolute.uri.normalizePath().toFilePath();
    if (parentPath != rootPath) return null;
    return image.uri.normalizePath().toFilePath();
  }

  /// 删除已经不被其他绘图文档引用的受管图片。文档解码失败时跳过该文档，
  /// 因为无法证明它是否引用了资产；这种保守策略优先保证用户数据不被误删。
  Future<void> _deleteUnreferencedManagedImages(
    Set<String> candidates, {
    required String excludingDocumentId,
  }) async {
    if (candidates.isEmpty) return;
    final referencedElsewhere = <String>{};
    final dir = await _ensureDocumentsDir();
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final other = _codec.decode(await entity.readAsBytes());
        if (other.id == excludingDocumentId) continue;
        for (final item in other.imageItems) {
          final managedPath = await _managedImagePathOrNull(item.filePath);
          if (managedPath != null) referencedElsewhere.add(managedPath);
        }
      } catch (_) {
        // 跳过无法安全解析的文档，避免将未知引用误判为孤儿资产。
        continue;
      }
    }

    for (final candidate in candidates.difference(referencedElsewhere)) {
      try {
        final image = File(candidate);
        if (await image.exists()) await image.delete();
      } on FileSystemException {
        // 主文档已经成功删除；图片回收失败可在未来维护扫描中重试。
      }
    }
  }

  /// 生成一个唯一的文档 ID。
  static String newId() => LocalIdGenerator.next('doc');
}
