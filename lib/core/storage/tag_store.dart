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
import 'package:drawing_notes_app/core/storage/sidecar_read_guard.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';
import 'package:drawing_notes_app/core/utils/time_serialization.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
    final createdAt = timeFromIsoOrNull(json['createdAt']);
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
    'createdAt': timeToIso(createdAt),
  };
}

/// 标签注册表持久化门面。
class TagStore {
  TagStore({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  File? _file;

  /// 每实例只落一条「读不出来」审计、只抢救一份原件（见 `sidecar_read_guard.dart`）。
  bool _unreadableNoted = false;
  bool _corruptPreserved = false;

  /// 已被抢救出来的那份原件的保留件文件名（`.corrupt-*`；没抢救过为 null）。
  ///
  /// STO-004 乙（业主 2026-10-16 点名）：这件事以前只进审计，用户看不见——
  /// 「标签看起来全空了」与「标签被保住了一份可恢复的原件」是两码事，后者必须
  /// 说出来。本字段只是**给展示层的事实**，判据仍在 `sidecar_read_guard.dart` 一份。
  String? get salvagedOriginalName => _salvagedOriginalName;
  String? _salvagedOriginalName;

  /// 写尾队列（D-15 修复 2026-09-07）：add/rename/delete 的读-改-写
  /// 串行化——快速连点时并发读改写会相互覆盖丢标签（favorite_store
  /// 同款 _enqueue 模式）。
  Future<void> _tail = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() fn) {
    final task = _tail.then((_) => fn());
    _tail = task.then((_) {}, onError: (_) {});
    return task;
  }

  /// 标签名长度上限（D-15：防无界超长名撑爆持久化文件与 UI）。
  static const int maxTagNameLength = 128;

  /// 控制字符（D-15：C0 控制字符 + DEL——不可见且会破坏 JSON 展示）。
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// 清洗标签名：剥离控制字符 → trim → 超 128 字符截断（与 UI 输入习惯
  /// 一致，选截断而非拒绝；清洗后为空串则调用方按无效处理）。
  static String sanitizeTagName(String name) {
    final cleaned = name.replaceAll(_controlChars, '').trim();
    if (cleaned.length > maxTagNameLength) {
      return cleaned.substring(0, maxTagNameLength);
    }
    return cleaned;
  }

  Future<File> _fileRef() async {
    if (_file != null) return _file!;
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    _file = File('${base.path}${Platform.pathSeparator}all_docs_tags.json');
    return _file!;
  }

  /// 读取全部标签。
  ///
  /// STO-004 的可观测半边（审计 2026-10-16）：判据换成三态（见 `sidecar_read_guard.dart`），
  /// 「文件在但读不出来」不再与「文件不在」共用一个答案——两者都仍然返回空表（**产品语义
  /// 未变**，「读失败即拒绝覆盖」那半边属默认阻断、需业主点名），但前者会落一条审计，
  /// 且下一次整体覆盖前会先把原件复制成 `.corrupt-*`（见 [_writeTags]）。
  Future<List<DocTag>> listTags() async {
    final file = await resolveSidecarFile(_fileRef);
    if (file == null) return const <DocTag>[]; // 目录解析失败：同改动前，不抛给 UI
    final read = readSidecarList(file, 'tags');
    if (read.state != SidecarRead.readable) {
      if (read.state == SidecarRead.unreadable) {
        noteUnreadableSidecar('tag_registry', alreadyNoted: _unreadableNoted);
        _unreadableNoted = true;
      }
      return const <DocTag>[];
    }
    final tags = <DocTag>[];
    for (final entry in read.items) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        tags.add(DocTag.fromJson(entry));
      } on FormatException {
        continue; // 跳过损坏条目（条目级 fail-closed，不影响整表判读）
      }
    }
    return tags;
  }

  /// 新增标签（同名忽略重复，返回最终标签；名称去空白后为空则返回 null）。
  /// D-15：入口清洗（控制字符剥离 + 128 上限截断）+ 写尾队列串行化。
  Future<DocTag?> addTag(String name, {String? color}) => _enqueue(() async {
    final trimmed = sanitizeTagName(name);
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
  });

  /// 重命名标签。
  /// D-15：入口清洗同 addTag；目标名已被**其他**标签占用时保持不变更
  /// （方法签名无返回值——幂等跳过，避免出现两个同名标签）。
  Future<void> renameTag(String id, String newName) => _enqueue(() async {
    final trimmed = sanitizeTagName(newName);
    if (trimmed.isEmpty) return;
    final tags = await listTags();
    if (tags.any((t) => t.name == trimmed && t.id != id)) return;
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
  });

  /// 删除标签（文档侧仅丢失该标签引用，文档本身不受影响）。
  Future<void> deleteTag(String id) => _enqueue(() async {
    final tags = await listTags();
    await _writeTags(tags.where((t) => t.id != id).toList());
  });

  /// A8 修复（2026-09-07）：固定名 `.tmp` 可被劫持且并发写互踩 → 随机后缀
  /// tmp；rename 失败按 storage_service._replaceWithTemp 模式先删目标再
  /// rename（Windows 覆盖拒绝回退）；任一失败清理 tmp 后 rethrow。
  Future<void> _writeTags(List<DocTag> tags) async {
    final file = await _fileRef();
    // 覆盖前抢救（STO-004 可观测半边）：盘上此刻仍读不出来时先复制一份 `.corrupt-*`，
    // 否则这次「按空表追加」的写会把用户的全部标签抹得一点痕迹都不剩。复制不阻断写入。
    final preserved = await preserveUnreadableSidecar(
      file,
      listKey: 'tags',
      auditScope: 'tag_registry',
      alreadyPreserved: _corruptPreserved,
    );
    if (preserved != null) {
      _corruptPreserved = true;
      _salvagedOriginalName ??= File(preserved).uri.pathSegments.last;
    }
    final r = Random.secure();
    final suffix = hexEncode(List<int>.generate(8, (_) => r.nextInt(256)));
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    try {
      await tmp.writeAsString(
        jsonEncode({
          'tags': [for (final t in tags) t.toJson()],
        }),
        flush: true,
      );
      try {
        await tmp.rename(file.path);
      } on FileSystemException {
        if (!file.existsSync()) rethrow;
        await file.delete();
        await tmp.rename(file.path);
      }
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        // 清理失败不覆盖原始存储异常。
      }
      rethrow;
    }
  }
}
