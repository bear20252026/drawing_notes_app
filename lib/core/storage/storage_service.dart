import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';

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
  StorageService({DocumentCodec? codec, this.directoryProvider})
    : _codec = codec ?? const DocumentCodec();

  final DocumentCodec _codec;

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  /// 文档存放目录（懒加载，首次调用时创建）。
  Directory? _documentsDir;

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
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}documents');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _documentsDir = dir;
    return dir;
  }

  Future<Directory> _ensureThumbsDir() async {
    if (_thumbsDir != null) return _thumbsDir!;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await getApplicationDocumentsDirectory();
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
        : await getApplicationDocumentsDirectory();
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
  static bool isValidId(String id) => RegExp(r'^[A-Za-z0-9_]+$').hasMatch(id);

  String _pathFor(String id) {
    assert(isValidId(id), '非法文档 ID: $id');
    return '${_documentsDir!.path}${Platform.pathSeparator}$id.json';
  }

  String _thumbPathFor(String id) {
    assert(isValidId(id), '非法文档 ID: $id');
    return '${_thumbsDir!.path}${Platform.pathSeparator}$id.png';
  }

  /// 保存文档的缩略图（PNG 字节），供列表页快速展示。
  /// 缩略图与工程文件分离存储，损坏不影响工程文件。
  Future<String> saveThumbnail(String docId, Uint8List pngBytes) async {
    await _ensureThumbsDir();
    final file = File(_thumbPathFor(docId));
    final tmp = File('${file.path}.${LocalIdGenerator.next('thumb')}.tmp');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await _replaceWithTemp(tmp, file);
    return file.path;
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
    await temporary.writeAsBytes(await source.readAsBytes(), flush: true);
    await _replaceWithTemp(temporary, destination);
    return destination.path;
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
  @override
  Future<String> save(DrawingDocument doc) {
    if (!isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    // 在进入异步队列前编码出不可变快照。编辑器继续修改 doc 时，队列中的
    // 某次保存仍代表其被请求时的完整版本，而不是可变对象的半成品状态。
    final data = _codec.encode(doc);
    final id = doc.id;
    final previous = _writeTails[id] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous.catchError((_) {}).then((_) => _saveEncoded(id, data));
    _writeTails[id] = operation;
    return operation
        .whenComplete(() {
          if (identical(_writeTails[id], operation)) _writeTails.remove(id);
        })
        .then((_) async {
          await _ensureDocumentsDir();
          return _pathFor(id);
        });
  }

  Future<void> _saveEncoded(String id, Uint8List data) async {
    await _ensureDocumentsDir();
    final finalFile = File(_pathFor(id));
    final tmp = File('${finalFile.path}.${LocalIdGenerator.next('write')}.tmp');
    await tmp.writeAsBytes(data, flush: true);

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
    try {
      final bytes = await _readWithRetry(
        () async => await (await file.exists() ? file : bak).readAsBytes(),
      );
      return _codec.decode(bytes);
    } on FormatException {
      // 正式文件损坏：尝试备份恢复。
      if (await bak.exists()) {
        final bytes = await _readWithRetry(() async => await bak.readAsBytes());
        return _codec.decode(bytes);
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
        await Future<void>.delayed(
          Duration(milliseconds: 50 * (attempt + 1)),
        );
      }
    }
  }

  /// 列出所有已保存文档（含元信息），按更新时间倒序。
  @override
  Future<List<DocumentMeta>> listDocuments() async {
    final dir = await _ensureDocumentsDir();
    final metas = <DocumentMeta>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final bytes = await entity.readAsBytes();
        final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final doc = root['document'] as Map<String, dynamic>;
        metas.add(
          DocumentMeta(
            id: doc['id'] as String,
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
            strokeCount: _countStrokes(doc['layers'] as List? ?? const []),
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

  // ignore: avoid-dynamic — 防御性恢复路径：文件损坏时跳过而非抛错，dynamic 属合理用法。
  int _countStrokes(List<dynamic> layers) {
    var n = 0;
    for (final l in layers) {
      n += (l['strokes'] as List? ?? const []).length;
    }
    return n;
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
      document = _codec.decode(await file.readAsBytes());
    } catch (_) {
      // 损坏文档仍允许用户删除，但不基于不可信内容删除任何资产。
    }

    final imagePaths = <String>{};
    if (document != null) {
      for (final item in document.imageItems) {
        final managedPath = await _managedImagePathOrNull(item.filePath);
        if (managedPath != null) imagePaths.add(managedPath);
      }
    }

    await file.delete();
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

    await _deleteUnreferencedManagedImages(imagePaths, excludingDocumentId: id);
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
