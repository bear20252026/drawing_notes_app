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
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 块文档本地存储门面。
///
/// 用法：
/// ```dart
/// final store = NoteBlockDocStore();
/// await store.saveDocument(doc);
/// final loaded = await store.loadDocument(doc.id);
/// await store.deleteDocument(doc.id);
/// ```
class NoteBlockDocStore {
  /// 创建块文档存储门面。
  ///
  /// [directoryProvider] 为可选的目录提供者回调。测试时可注入临时目录，
  /// 生产环境默认使用系统文档目录。
  NoteBlockDocStore({this.directoryProvider});

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  Directory? _dir;

  Future<Directory> _baseDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await _baseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// 校验 ID 是否安全（仅允许字母、数字、下划线、短横线）。
  static bool isValidId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

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
  Future<void> saveDocument(NoteBlockDoc doc) async {
    if (!isValidId(doc.id)) {
      throw ArgumentError.value(doc.id, 'doc.id', '文档 ID 不合法');
    }
    await _ensureDir();
    final data = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()),
    );
    final path = await _pathFor(doc.id);
    final file = File(path);
    final tmp = File('$path.${LocalIdGenerator.next('write')}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    if (await file.exists()) {
      try {
        await file.copy('$path.bak');
      } catch (_) {
        // 备份失败不阻塞写入
      }
    }
    try {
      await tmp.rename(path);
    } on FileSystemException {
      if (!await file.exists()) rethrow;
      await file.delete();
      await tmp.rename(path);
    }
  }

  /// 加载指定 ID 的块文档。不存在返回 null，损坏时尝试 .bak 恢复。
  Future<NoteBlockDoc?> loadDocument(String pageId) async {
    await _ensureDir();
    final path = await _pathFor(pageId);
    final file = File(path);
    final backup = File('$path.bak');
    if (!await file.exists() && !await backup.exists()) return null;
    try {
      final bytes = await (await file.exists() ? file : backup).readAsBytes();
      return NoteBlockDoc.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (_) {
      if (!await backup.exists()) rethrow;
      final bytes = await backup.readAsBytes();
      return NoteBlockDoc.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    }
  }

  /// 删除指定 ID 的块文档。返回是否实际删除了文件。
  Future<bool> deleteDocument(String pageId) async {
    await _ensureDir();
    final path = await _pathFor(pageId);
    final file = File(path);
    if (!await file.exists()) return false;
    await file.delete();
    try {
      final backup = File('$path.bak');
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // 备份删除失败忽略
    }
    return true;
  }

  /// 列出所有块文档 ID（不含 .json 后缀）。
  Future<List<String>> listIds() async {
    await _ensureDir();
    final result = <String>[];
    await for (final entity in (await _ensureDir()).list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      result.add(name.substring(0, name.length - 5)); // 去掉 .json
    }
    return result;
  }

  /// 生成唯一 ID（前缀可自定义，默认 'doc'）。
  static String newId([String prefix = 'doc']) => LocalIdGenerator.next(prefix);
}
