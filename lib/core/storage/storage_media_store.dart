import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

// C-08（审计 2026-09-27）：自 StorageService 的 part 五域拆为真协作类。
// 本类持有**媒体资产域**自有行为：缩略图（写/读/路径/删除）与受管离线
// 图片副本。设密文档不写缩略图（防首页预览泄露——用户拍板）；缩略图
// 读取 fail-closed（锁定返回 null，不泄露任何像素）。
// StorageService 保留门面，消费方 API 零变化。

/// 媒体资产域：缩略图与受管图片副本。
class StorageMediaStore {
  StorageMediaStore({
    required this.directories,
    required this.secrets,
    required this.pipeline,
    required this.codec,
    required this.isFilePasswordProtected,
    required this.keyProvider,
    required this.fireOnWrite,
  });


  /// 内部协作面：仅 StorageService 门面装配（C-08 拆分协作类，只读）。
  final StorageDirectories directories;
  final StorageSecretSession secrets;
  final StorageWritePipeline pipeline;
  final DocumentCodec codec;
  final Future<Uint8List?> Function()? keyProvider;
  final void Function() fireOnWrite;

  /// 文件密码域回调（构造序解环：门面把密码域的查询注给媒体域）。
  final Future<bool> Function(String docId) isFilePasswordProtected;

  String _thumbPathFor(String id) {
    if (!StorageDirectories.validIdPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', '缩略图 ID 不合法（路径遍历防护）');
    }
    // 调用方先 ensureThumbs（与原 _thumbsDir! 的懒加载时序一致）。
    return '${directories.thumbsDirOrThrow.path}${Platform.pathSeparator}$id.png';
  }

  /// 保存文档的缩略图（PNG 字节），供列表页快速展示。
  /// 缩略图与工程文件分离存储，损坏不影响工程文件。
  /// 批次①c：有主密钥时信封加密落盘（读取走 [thumbnailBytes]）。
  /// 批次②：单文件密码文档不写缩略图（防首页预览泄露——用户拍板）。
  Future<String> saveThumbnail(String docId, Uint8List pngBytes) async {
    if (secrets.filePasswordFor(docId) != null) return '';
    await directories.ensureThumbs();
    final file = File(_thumbPathFor(docId));
    final sealed = await _sealMediaBytes(file.path, pngBytes);
    final tmp = File('${file.path}.${LocalIdGenerator.next('thumb')}.tmp');
    // A1 修复（审计 2026-09-07）：tmp 写入/rename 失败时清理残留临时文件，
    // 否则崩溃半写的 .tmp 会堆积在缩略图目录（favorite_store 同款纪律）。
    try {
      await tmp.writeAsBytes(sealed, flush: true);
      await pipeline.replaceWithTemp(tmp, file);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
    fireOnWrite();
    return file.path;
  }

  /// 读取缩略图字节（批次①c）：密文自动解密；锁定返回 null
  /// （fail-closed——UI 显示占位图，不泄露任何像素）；明文 + 有密钥
  /// 时原样返回并尽力懒迁移为密文。不存在返回 null。
  /// 批次②：单文件密码文档恒返回 null（缩略图已被删除，防御性兜底）。
  Future<Uint8List?> thumbnailBytes(String docId) async {
    if (await isFilePasswordProtected(docId)) return null;
    await directories.ensureThumbs();
    final file = File(_thumbPathFor(docId));
    if (!file.existsSync()) return null;
    final raw = await file.readAsBytes();
    if (!VaultFileCodec.isEncrypted(raw)) {
      final key = await keyProvider?.call();
      if (key != null) {
        // 懒迁移（尽力而为）：明文缩略图重写为密文。
        try {
          final sealed = await _sealMediaBytes(file.path, raw);
          final tmp = File(
            '${file.path}.${LocalIdGenerator.next('thumb')}.tmp',
          );
          await tmp.writeAsBytes(sealed, flush: true);
          await pipeline.replaceWithTemp(tmp, file);
        } catch (_) {
          // 迁移失败不影响本次读取。
        }
      }
      return raw;
    }
    final key = await keyProvider?.call();
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
    await directories.ensureThumbs();
    final file = File(_thumbPathFor(docId));
    if (!file.existsSync()) return null;
    return file.path;
  }

  /// 删除缩略图（设密/改密/删除文档时调用——防首页预览泄露，用户拍板）。
  Future<void> deleteThumbnail(String id) async {
    try {
      await directories.ensureThumbs();
      final thumb = File(_thumbPathFor(id));
      if (thumb.existsSync()) await thumb.delete();
    } catch (_) {
      // 缩略图清理失败不影响密码设置本身。
    }
  }

  /// 将用户选择的图片复制为本应用管理的离线副本。
  ///
  /// 原文件被移动、删除或来自临时内容 URI 后，文档仍可正常恢复。写入使用
  /// 临时文件再替换，避免中途取消留下半张图片。
  Future<String> storeImage(String sourcePath, String docId) async {
    if (!StorageDirectories.validIdPattern.hasMatch(docId)) {
      throw ArgumentError.value(docId, 'docId', '文档 ID 不合法');
    }
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw ArgumentError.value(sourcePath, 'sourcePath', '图片文件不存在');
    }
    final extension = _safeImageExtension(source.path);
    final dir = await directories.ensureImages();
    final name = '${docId}_${LocalIdGenerator.next('img')}$extension';
    final destination = File('${dir.path}${Platform.pathSeparator}$name');
    final temporary = File('${destination.path}.tmp');
    try {
      // 批次①c：有主密钥 → 信封加密副本（读取走 VaultFileCodec.readImageBytes）。
      final raw = await source.readAsBytes();
      final stored = await _sealMediaBytes(destination.path, raw);
      await temporary.writeAsBytes(stored, flush: true);
      await pipeline.replaceWithTemp(temporary, destination);
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

  /// 收集文档引用的受管离线图片路径（删除流程读取引用清单用）。
  Future<Set<String>> managedImagePathsOf(DrawingDocument document) async {
    final paths = <String>{};
    for (final item in document.imageItems) {
      final managedPath = await _managedImagePathOrNull(item.filePath);
      if (managedPath != null) paths.add(managedPath);
    }
    return paths;
  }

  /// 媒体字节写入前准备（批次①c：缩略图 / 受管图片）：有主密钥 →
  /// 信封加密（AAD 绑定文件名）。锁定态与文档同口径 fail-closed；
  /// 未启用加密（无 keyProvider）保持明文兼容。
  Future<Uint8List> _sealMediaBytes(String path, Uint8List bytes) async {
    final provider = keyProvider;
    if (provider == null) return bytes;
    final key = await provider();
    if (key == null) throw const VaultFileLockException();
    return VaultFileCodec.encrypt(
      bytes,
      key,
      aadContext: VaultFileCodec.contextForPath(path),
    );
  }

  static String _safeImageExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '.png';
    final candidate = path.substring(dot).toLowerCase();
    const allowed = <String>{'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
    return allowed.contains(candidate) ? candidate : '.png';
  }

  /// 返回规范化后的受管离线图片路径；外部路径、嵌套路径和非法路径返回 null。
  ///
  /// [storeImage] 只向 `document_images/` 顶层写入文件。严格的父目录相等检查
  /// 防止文档 JSON 被篡改后借删除操作清理应用目录以外的任意文件。
  Future<String?> _managedImagePathOrNull(String path) async {
    if (path.isEmpty) return null;
    final root = await directories.ensureImages();
    final image = File(path).absolute;
    final parentPath = image.parent.absolute.uri.normalizePath().toFilePath();
    final rootPath = root.absolute.uri.normalizePath().toFilePath();
    if (parentPath != rootPath) return null;
    return image.uri.normalizePath().toFilePath();
  }

  /// 删除已经不被其他绘图文档引用的受管图片。任何文档**解码失败（含加密
  /// 文档在锁定态）即中止整个回收**——无法证明它是否引用了资产，保守策略
  /// 优先保证用户数据不被误删（安全审计 P2-4，2026-09-06：此前跳过失败
  /// 文档，其引用的图片可能被误判孤儿并删除）。
  Future<void> deleteUnreferencedManagedImages(
    Set<String> candidates, {
    required String excludingDocumentId,
  }) async {
    if (candidates.isEmpty) return;
    final referencedElsewhere = <String>{};
    final dir = await directories.ensureDocuments();
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final Uint8List raw;
      try {
        raw = await entity.readAsBytes();
      } catch (_) {
        return; // 读取失败：无法证明引用关系，保守中止回收。
      }
      final fileName = entity.uri.pathSegments.last;
      final docId = fileName.substring(0, fileName.length - '.json'.length);
      final Uint8List plain;
      try {
        plain = await pipeline.prepareDocBytes(docId, raw);
      } catch (_) {
        // 解码/解密失败（如锁定态的密文文档）：其 imageItems 不可知，
        // 贸然回收可能误删它引用的图片 → 保守中止本次回收。
        return;
      }
      try {
        final other = codec.decode(plain);
        if (other.id == excludingDocumentId) continue;
        for (final item in other.imageItems) {
          final managedPath = await _managedImagePathOrNull(item.filePath);
          if (managedPath != null) referencedElsewhere.add(managedPath);
        }
      } catch (_) {
        // 解析失败同样中止，避免将未知引用误判为孤儿资产。
        return;
      }
    }

    for (final candidate in candidates.difference(referencedElsewhere)) {
      try {
        final image = File(candidate);
        if (image.existsSync()) await image.delete();
      } on FileSystemException {
        // 主文档已经成功删除；图片回收失败可在未来维护扫描中重试。
      }
    }
  }
}
