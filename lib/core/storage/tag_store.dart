// 由 Claude 团队生成 | Drawing Notes App
// 标签（Tags）持久化门面（M12.6，AFFiNE Tags 对齐）。
//
/// 标签注册表：id → (name, color)。文档（NoteBlockDoc.tags）只存标签 id，
/// 删除/重命名标签不影响文档数据。
/// 存储文件（应用文档目录下）：
///   `appDir/all_docs_tags.json`
///     `{"tags": [{"id","name","color","createdAt"}]}`
///
/// 仅依赖 dart:io + directoryProvider；不 import presentation，
/// 层方向严格 domain ← infrastructure（与 FavoriteStore 同模式）。
library;

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'dart:convert';
import 'dart:io';


/// 单个标签定义。
class DocTag {
  const DocTag({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  factory DocTag.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final color = json['color'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (name is! String ||
        name.trim().isEmpty ||
        color is! String ||
        createdAt == null) {
      // 损坏条目 fail-closed（返回 null 由调用方跳过）。
      throw const FormatException('invalid tag entry');
    }
    return DocTag(
      id: json['id'] as String,
      name: name.trim(),
      color: color,
      createdAt: createdAt,
    );
  }

  final String id;
  final String name;

  /// ARGB hex，如 '0xFFBF5AF2'。
  final String color;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// 标签注册表持久化门面。
class TagStore {
  TagStore({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  File? _file;

  Future<File> _fileRef() async {
    if (_file != null) return _file!;
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    _file = File('${base.path}${Platform.pathSeparator}all_docs_tags.json');
    return _file!;
  }

  /// 读取全部标签（损坏时返回空表，fail-open）。
  Future<List<DocTag>> listTags() async {
    try {
      final file = await _fileRef();
      if (!await file.exists()) return const <DocTag>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return const <DocTag>[];
      final list = decoded['tags'];
      if (list is! List) return const <DocTag>[];
      final tags = <DocTag>[];
      for (final entry in list) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          tags.add(DocTag.fromJson(entry));
        } on FormatException {
          continue; // 跳过损坏条目
        }
      }
      return tags;
    } catch (_) {
      return const <DocTag>[];
    }
  }

  /// 新增标签（同名忽略重复，返回最终标签；名称去空白后为空则返回 null）。
  Future<DocTag?> addTag(String name, {String? color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final tags = await listTags();
    final existing = tags.where((t) => t.name == trimmed).firstOrNull;
    if (existing != null) return existing;
    final tag = DocTag(
      id: 'tag_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      color: color ?? '0xFFBF5AF2',
      createdAt: DateTime.now(),
    );
    await _writeTags([...tags, tag]);
    return tag;
  }

  /// 重命名标签。
  Future<void> renameTag(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final tags = await listTags();
    await _writeTags([
      for (final t in tags)
        if (t.id == id)
          DocTag(
            id: t.id,
            name: trimmed,
            color: t.color,
            createdAt: t.createdAt,
          )
        else
          t,
    ]);
  }

  /// 删除标签（文档侧仅丢失该标签引用，文档本身不受影响）。
  Future<void> deleteTag(String id) async {
    final tags = await listTags();
    await _writeTags(tags.where((t) => t.id != id).toList());
  }

  Future<void> _writeTags(List<DocTag> tags) async {
    final file = await _fileRef();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'tags': [for (final t in tags) t.toJson()],
      }),
    );
    await tmp.rename(file.path);
  }
}
