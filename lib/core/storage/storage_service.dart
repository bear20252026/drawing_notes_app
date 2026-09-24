import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/session_secrets.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/core/utils/time_serialization.dart';

// O1 域分权（F9，2026-09-24）：媒体资产/写入落盘/删除三域私有助手 part，
// 新增同域私有逻辑请落对应 part；public API、@override、字段与静态成员
// 留在本体（extension 成员对本库外不可见，public 不得下沉）。
part 'storage_service_media.dart';
part 'storage_service_write.dart';
part 'storage_service_trash.dart';

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
class StorageService implements DocumentRepository, SessionSecretsHolder {
  StorageService({
    DocumentCodec? codec,
    this.directoryProvider,
    this.keyProvider,
  }) : _codec = codec ?? const DocumentCodec() {
    // P1 修复 M-05：注册会话机密清理——切后台回锁时口令/DEK 一并失效。
    SessionSecrets.register(this);
  }

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

  /// P1 修复 M-05：清空全部会话机密（切后台回锁联动经 [SessionSecrets]）。
  /// 口令 String 不可擦除（Dart 不可变）——移出 map 即不可达；DEK/USB
  /// 字节材料逐个 fill(0)。幂等、永不抛错。
  @override
  void clearAllSessionSecrets() {
    try {
      _sessionFilePasswords.clear();
      for (final dek in _sessionDocDeks.values) {
        try {
          dek.fillRange(0, dek.length, 0);
        } catch (_) {
          /* 幂等清理：单个 DEK 擦除失败继续下一个，清空流程永不抛错 */
        }
      }
      _sessionDocDeks.clear();
      _sessionFileUsbWrapped.clear();
    } catch (_) {
      /* 幂等清理：会话机密清空尽力而为（切后台回锁热路径），失败不外抛 */
    }
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
    if (!dir.existsSync()) {
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
    if (!dir.existsSync()) {
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
    if (!dir.existsSync()) {
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
    if (!dir.existsSync()) {
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

  Future<String> saveThumbnail(String docId, Uint8List pngBytes) async {
    if (_sessionFilePasswords.containsKey(docId)) return '';
    await _ensureThumbsDir();
    final file = File(_thumbPathFor(docId));
    final sealed = await _sealMediaBytes(file.path, pngBytes);
    final tmp = File('${file.path}.${LocalIdGenerator.next('thumb')}.tmp');
    // A1 修复（审计 2026-09-07）：tmp 写入/rename 失败时清理残留临时文件，
    // 否则崩溃半写的 .tmp 会堆积在缩略图目录（favorite_store 同款纪律）。
    try {
      await tmp.writeAsBytes(sealed, flush: true);
      await _replaceWithTemp(tmp, file);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
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
    if (!file.existsSync()) return null;
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
    if (!file.existsSync()) return null;
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
    if (!source.existsSync()) {
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
        if (temporary.existsSync()) await temporary.delete();
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

  /// E-17：把 [op] 挂到 [id] 的写尾队列（与 save/_enqueueRawRewrite 共用
  /// [_writeTails]），返回 op 的原始结果。链上某步失败不影响后续步骤。
  static const int _isolateSealThreshold = 64 * 1024;

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
  @override
  Future<DrawingDocument?> load(String id) async {
    await _ensureDocumentsDir();
    final file = File(_pathFor(id));
    final bak = File('${_pathFor(id)}.bak');
    if (!file.existsSync() && !bak.existsSync()) return null;
    Future<Uint8List> preparedBytes(File source) async {
      final raw = await _readWithRetry(() async => await source.readAsBytes());
      return _prepareDocBytes(id, raw);
    }

    try {
      return _codec.decode(await preparedBytes(file.existsSync() ? file : bak));
    } on FormatException {
      // 正式文件损坏：尝试备份恢复。
      if (bak.existsSync()) {
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
            title: doc['title'] as String? ?? '',
            width: (doc['width'] as num?)?.toInt() ?? 2048,
            height: (doc['height'] as num?)?.toInt() ?? 1536,
            createdAt: timeFromIso(doc['createdAt']),
            updatedAt: timeFromIso(doc['updatedAt']),
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
      return f.statSync().modified;
    } catch (_) {
      return DateTime.now();
    }
  }

  /// 删除指定文档及其不再被任何其他文档引用的受管图片副本。
  ///
  /// 图片清理以文档中的引用清单为准，并且只会删除 [storeImage] 写入的
  /// `document_images/` 顶层文件。用户原始文件、外部路径、解码失败的文档及
  /// 仍被其他文档引用的资产全部保留，宁可留下可维护的孤儿文件也不冒误删风险。
  ///
  /// E-17 修复（审计 2026-09-07）：整个删除流程挂入与保存相同的 per-id
  /// 写尾队列——此前在途保存与删除交错会让已删文档复活（rename 进回收站
  /// 后，队列中的保存又写出正式文件）。note_block_doc_store 的 _enqueue
  /// （trash 域）是同款已修模式。
  @override
  Future<bool> delete(String id) =>
      _runDocExclusive(id, () => _deleteLocked(id));

  Future<String?> restoreTrash(String trashName) async {
    final trashDir = await _ensureTrashDir();
    await _ensureDocumentsDir();
    final src = File('${trashDir.path}${Platform.pathSeparator}$trashName');
    if (!src.existsSync()) return null;
    final id = trashName.split('_').first;
    if (!isValidId(id)) return null;
    return _runDocExclusive(id, () async {
      if (!src.existsSync()) return null;
      final dest = File(_pathFor(id));
      if (dest.existsSync()) return null; // 原 ID 已存在——拒绝覆盖
      await src.rename(dest.path);
      onWrite?.call();
      return id;
    });
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
        final stat = entity.statSync();
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
    if (!file.existsSync()) return false;
    await file.delete();
    return true;
  }

  /// 返回规范化后的受管离线图片路径；外部路径、嵌套路径和非法路径返回 null。
  ///
  /// [storeImage] 只向 `document_images/` 顶层写入文件。严格的父目录相等检查
  /// 防止文档 JSON 被篡改后借删除操作清理应用目录以外的任意文件。
  static String newId() => LocalIdGenerator.next('doc');
}
