import 'dart:io';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

// C-08（审计 2026-09-27）：自 StorageService 的 part 五域拆为真协作类——
// 此前 O1 域分权（F9）只做了物理 part 拆分，单类仍同时持有五个职责的
// 全部私有态（C-04 对 editor_page 的同款批评）。本类持有**目录域**自有
// 状态：四个懒加载目录与其路径推导。StorageService 保留门面，消费方
// API 零变化。

/// 存储目录域：应用文档/回收站/缩略图/受管图片四个目录的懒加载与路径。
///
/// 路径推导集中于此（含 ID 路径遍历防护的运行时强制校验）；其余协作类
/// 经本类取路径，不再各自缓存 `Directory?`。
class StorageDirectories {
  StorageDirectories({this.directoryProvider});

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  Directory? _documentsDir;
  Directory? _trashDir;
  Directory? _thumbsDir;
  Directory? _imagesDir;

  Future<Directory> _ensure(
    Directory? cached,
    String name,
    void Function(Directory) set,
  ) async {
    if (cached != null) return cached;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}$name');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    set(dir);
    return dir;
  }

  /// 文档存放目录（懒加载，首次调用时创建）：`appDir/documents/`。
  Future<Directory> ensureDocuments() => _ensure(
    _documentsDir,
    'documents',
    (d) => _documentsDir = d,
  );

  /// 回收站目录（M-06：删除移入 + 30 天保留——Android 官方模式）。
  Future<Directory> ensureTrash() => _ensure(
    _trashDir,
    'documents_trash',
    (d) => _trashDir = d,
  );

  /// 缩略图存放目录。
  Future<Directory> ensureThumbs() => _ensure(
    _thumbsDir,
    'thumbnails',
    (d) => _thumbsDir = d,
  );

  /// 独立绘图文档导入图片的离线副本目录。
  Future<Directory> ensureImages() => _ensure(
    _imagesDir,
    'document_images',
    (d) => _imagesDir = d,
  );

  /// 已确保的缩略图目录（调用方须先 [ensureThumbs]——与原懒加载时序一致）。
  Directory get thumbsDirOrThrow => _thumbsDir!;

  /// 文档正式文件路径（`documents/<id>.json`）。
  ///
  /// 链 A 修复（军工审计 2026-08-15）：assert-only 校验在 release 失效——
  /// 运行时强制校验（load/delete/saveThumbnail 均经此统一防护路径遍历）。
  String documentPathFor(String id) {
    if (!StorageDirectories.validIdPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', '文档 ID 不合法（路径遍历防护）');
    }
    return '${_documentsDir!.path}${Platform.pathSeparator}$id.json';
  }

  /// ID 合法形态：仅字母、数字、下划线、'-'（与 DocumentCodec._validDocumentId
  /// 一致，消除合法文档无法保存的不一致；'-' 无路径遍历风险）。
  static final RegExp validIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');
}
