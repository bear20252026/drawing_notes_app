// 由 Claude 团队生成 | Drawing Notes App
// 块文档纯逻辑搜索索引：对 NoteBlockDoc 做内存遍历索引，
// 提供大小写不敏感、多 token AND 命中 + 摘要片段。
// 纯 Dart，无 flutter/io/controller/存储依赖。

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// 单条搜索结果。
class NoteBlockSearchHit {
  const NoteBlockSearchHit({
    required this.blockId,
    required this.snippet,
    required this.matchedTitle,
  });

  /// 命中块 id（若为文档标题命中，则等于文档 id）。
  final String blockId;

  /// 命中上下文摘要（query 在文本中首次出现位置前后各 ~20 字符）。
  final String snippet;

  /// 文档标题是否参与命中（标题包含全部 query token 时为 true）。
  final bool matchedTitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteBlockSearchHit &&
          runtimeType == other.runtimeType &&
          blockId == other.blockId &&
          snippet == other.snippet &&
          matchedTitle == other.matchedTitle;

  @override
  int get hashCode => Object.hash(blockId, snippet, matchedTitle);

  @override
  String toString() =>
      'NoteBlockSearchHit(blockId: $blockId, matchedTitle: $matchedTitle, snippet: "$snippet")';
}

/// 单个索引条目（内部使用）。
class _BlockEntry {
  _BlockEntry({
    required this.blockId,
    required this.blockText,
    required this.docTitle,
    required this.fullDocText,
    this.isTitle = false,
  });

  final String blockId;
  final String blockText;
  final String docTitle;
  final String fullDocText;

  /// 是否为文档标题伪条目（blockId = doc.id）。
  final bool isTitle;

  /// 该条目的匹配文本：标题伪条目用标题，其余用块自身文本。
  /// 注意不含 fullDocText，否则每块都会匹配全篇词，失去“命中该块”的语义。
  String get matchText => isTitle ? docTitle : blockText;
}

/// 块文档搜索索引。
///
/// 纯内存、纯逻辑。[indexDocument] 遍历文档 body（含递归 children），
/// 为每块建条目，并把文档标题作为独立伪条目（blockId=doc.id）索引。
/// [search] 做大小写不敏感、多 token AND 命中，返回命中块 id +
/// 摘要片段 + 是否标题命中。
class NoteBlockDocSearchIndex {
  final List<_BlockEntry> _entries = [];

  /// 索引一个文档。重复索引同一文档会追加条目（调用方负责去重或重建）。
  void indexDocument(NoteBlockDoc doc) {
    final fullDocText = _buildFullDocText(doc);
    // 标题作为独立伪条目，使标题命中可被搜索到。
    _entries.add(_BlockEntry(
      blockId: doc.id,
      blockText: doc.title,
      docTitle: doc.title,
      fullDocText: fullDocText,
      isTitle: true,
    ));
    for (final block in doc.body) {
      _indexBlock(block, doc.title, fullDocText);
    }
  }

  void _indexBlock(NoteBlock block, String docTitle, String fullDocText) {
    _entries.add(_BlockEntry(
      blockId: block.id,
      blockText: block.text,
      docTitle: docTitle,
      fullDocText: fullDocText,
    ));
    for (final child in block.children) {
      _indexBlock(child, docTitle, fullDocText);
    }
  }

  String _buildFullDocText(NoteBlockDoc doc) {
    final buffer = StringBuffer();
    if (doc.title.isNotEmpty) buffer.writeln(doc.title);
    for (final block in doc.body) {
      _appendBlockText(block, buffer);
    }
    return buffer.toString();
  }

  void _appendBlockText(NoteBlock block, StringBuffer buffer) {
    if (block.text.isNotEmpty) buffer.writeln(block.text);
    for (final child in block.children) {
      _appendBlockText(child, buffer);
    }
  }

  /// 搜索：大小写不敏感；多 token（空格分隔）全部命中才返回（AND）；
  /// 命中块返回 id + snippet + matchedTitle。空 query 返回空列表。
  List<NoteBlockSearchHit> search(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return const [];

    final titleHaystack = _titleTextOfEntries().toLowerCase();
    final titleMatchesAll = tokens.every((t) => titleHaystack.contains(t));

    final hits = <NoteBlockSearchHit>[];
    for (final entry in _entries) {
      final haystack = entry.matchText.toLowerCase();
      if (!tokens.every((t) => haystack.contains(t))) continue;

      final matchedTitle = entry.isTitle || titleMatchesAll;
      final snippet = _buildSnippet(entry.matchText, tokens.first);
      hits.add(NoteBlockSearchHit(
        blockId: entry.blockId,
        snippet: snippet,
        matchedTitle: matchedTitle,
      ));
    }
    return hits;
  }

  // 标题伪条目的文本（用于 matchedTitle 判定）。
  String _titleTextOfEntries() {
    for (final e in _entries) {
      if (e.isTitle) return e.docTitle;
    }
    return '';
  }

  List<String> _tokenize(String query) => query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  /// 构建摘要：在 source 中找到 token 首次出现位置，前后各截 ~20 字符，
  /// 截断处加省略号。
  String _buildSnippet(String source, String token) {
    const radius = 20;
    final lower = source.toLowerCase();
    final pos = lower.indexOf(token);
    if (pos < 0) return token;
    final start = (pos - radius).clamp(0, source.length);
    final end = (pos + token.length + radius).clamp(0, source.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < source.length ? '...' : '';
    return '$prefix${source.substring(start, end)}$suffix';
  }
}
