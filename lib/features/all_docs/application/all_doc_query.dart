// 由 Claude 团队生成 | Drawing Notes App
// AllDocQuery：把画布 / 笔记本页 / 块文档三源统一为 AllDoc 列表 + 分组。
// 纯映射/聚合，无 IO；不可变输入 → 确定性输出。

import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';

/// 块文档的轻量 meta（供集成方从 NoteBlockDoc 提取）。
class BlockDocMeta {
  const BlockDocMeta({
    required this.id,
    required this.title,
    required this.folder,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.locked = false,
  });

  final String id;
  final String title;

  /// 标签 id 列表（M12.6）。
  final List<String> tags;
  final String folder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 是否受独立文件密码保护且本会话尚未解锁（N2）。
  final bool locked;
}

/// 全部文档查询结果（统一列表 + 分组）。
class AllDocQueryResult {
  const AllDocQueryResult({required this.docs, required this.sections});

  /// 全部文档（按 updatedAt desc 排序，已去重）。
  final List<AllDoc> docs;

  /// 分组后的区段（顺序 today→thisWeek→earlier→neverUpdated）。
  final List<AllDocSection> sections;

  /// 是否无任何文档。
  bool get isEmpty => docs.isEmpty;
}

/// 把三源（画布 / 笔记本页 / 块文档）统一为 [AllDocQueryResult]。
///
/// - 三源 → [AllDoc]（kind 正确映射；folder 用 item.folder / page.folder）。
/// - 去重（按 key = '$kind:$id'，先入优先）。
/// - 排序：updatedAt desc。
/// - 用 [groupOf](now) 分组（顺序 today→thisWeek→earlier→neverUpdated）。
/// - [favoriteOnly] 为 true 时只保留 isFavorite==true 的文档。
AllDocQueryResult buildAllDocs({
  required List<DocumentMeta> docs,
  required List<Notebook> notebooks,
  required List<BlockDocMeta> blockDocs,
  required DateTime now,
  bool favoriteOnly = false,
}) {
  final seen = <String>{};
  final all = <AllDoc>[];

  // 1. 画布文档 → AllDoc(kind=canvas)
  for (final d in docs) {
    final doc = AllDoc(
      id: d.id,
      title: d.title,
      kind: AllDocKind.canvas,
      folder: d.folder,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
      drawingId: d.id,
    );
    if (_tryAdd(seen, doc)) all.add(doc);
  }

  // 2. 笔记本页 → AllDoc(kind=note)
  // 锁定占位（保险库锁定时的 DNV 密文分页画布）→ 单行 locked 条目
  // （N2 口径统一：条目可见 + 锁标；无页面内容可展开）。
  for (final nb in notebooks) {
    if (nb.isLockedPlaceholder) {
      final doc = AllDoc(
        id: nb.id,
        title: nb.title,
        kind: AllDocKind.note,
        folder: '',
        createdAt: nb.createdAt,
        updatedAt: nb.updatedAt,
        notebookId: nb.id,
        locked: true,
      );
      if (_tryAdd(seen, doc)) all.add(doc);
      continue;
    }
    for (final page in nb.pages) {
      final doc = AllDoc(
        id: page.id,
        title: page.title,
        kind: AllDocKind.note,
        folder: page.folder,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt,
        isFavorite: page.favorite,
        notebookId: nb.id,
        pageId: page.id,
      );
      if (_tryAdd(seen, doc)) all.add(doc);
    }
  }

  // 3. 块文档 → AllDoc(kind=blockdoc)
  for (final bd in blockDocs) {
    final doc = AllDoc(
      id: bd.id,
      title: bd.title,
      kind: AllDocKind.blockdoc,
      folder: bd.folder,
      tags: bd.tags,
      createdAt: bd.createdAt,
      updatedAt: bd.updatedAt,
      locked: bd.locked,
    );
    if (_tryAdd(seen, doc)) all.add(doc);
  }

  // 3b. 跨 kind 按 id 去重（M12.5 根修）：同一逻辑笔记可能同时存在
  // NotebookPage（kind=note）与其迁移副本 NoteBlockDoc（kind=blockdoc，
  // id 相同——由 _openBlockDocFromPage 以 page.id 落库）。两行并存即
  // 用户看到的"同一笔记的两个标签"，且编辑互不回写导致内容不一致。
  // 处理：同 id 冲突时保留 blockdoc 行（现行可编辑形态），单一入口。
  // M12.5 合并语义：删除与 blockdoc 同 id 的 note 行（迁移分叉对中
  // blockdoc 是现行可编辑形态），其余全部保留——与出现顺序无关。
  final blockDocIds = {
    for (final d in all)
      if (d.kind == AllDocKind.blockdoc) d.id,
  };
  all.removeWhere(
    (d) => d.kind == AllDocKind.note && blockDocIds.contains(d.id),
  );

  // 4. 排序：updatedAt desc
  all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // 5. 收藏过滤
  final filtered = favoriteOnly
      ? all.where((d) => d.isFavorite).toList(growable: false)
      : all;

  // 6. 分组
  final sections = _buildSections(filtered, now);

  return AllDocQueryResult(docs: filtered, sections: sections);
}

/// 尝试按 dedupKey 添加；返回 true 表示新增，false 表示重复。
bool _tryAdd(Set<String> seen, AllDoc doc) => seen.add(doc.dedupKey);

/// 按分组构建 sections（顺序 today→thisWeek→earlier→neverUpdated）。
List<AllDocSection> _buildSections(List<AllDoc> docs, DateTime now) {
  final groups = <AllDocGroup, List<AllDoc>>{
    for (final g in AllDocGroup.values) g: [],
  };

  for (final doc in docs) {
    groups[groupOf(doc, now: now)]!.add(doc);
  }

  final sections = <AllDocSection>[];
  final orderedGroups = List.of(AllDocGroup.values)
    ..sort((a, b) => orderOfGroup(a).compareTo(orderOfGroup(b)));

  for (final g in orderedGroups) {
    final list = groups[g]!;
    if (list.isNotEmpty) {
      sections.add(
        AllDocSection(
          group: g,
          label: labelForGroup(g),
          docs: List.unmodifiable(list),
        ),
      );
    }
  }

  return sections;
}
