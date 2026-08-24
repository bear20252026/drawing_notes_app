/// 全文搜索索引（倒排索引）。
///
/// 支持笔记文本搜索，目标性能 <100ms/1000笔记。
/// 手写内容搜索基于已有 OCR 元数据，无需实现 OCR 引擎。
library;

/// 搜索结果项。
class SearchResult {
  const SearchResult({
    required this.noteId,
    required this.noteTitle,
    required this.matchedText,
    required this.matchStart,
    required this.matchLength,
    this.isOcrMatch = false,
  });

  /// 笔记 ID。
  final String noteId;

  /// 笔记标题。
  final String noteTitle;

  /// 匹配的文本片段。
  final String matchedText;

  /// 匹配起始位置。
  final int matchStart;

  /// 匹配长度。
  final int matchLength;

  /// 是否为 OCR 手写匹配。
  final bool isOcrMatch;
}

/// 全文搜索索引。
class SearchIndex {
  /// 词项 -> 文档 ID 集合。
  final Map<String, Set<String>> _invertedIndex = {};

  /// 文档 ID -> 文档标题。
  final Map<String, String> _docTitles = {};

  /// 文档 ID -> 文档全文。
  final Map<String, String> _docTexts = {};

  /// 文档 ID -> OCR 文本（手写识别结果）。
  final Map<String, String> _ocrTexts = {};

  /// 小写缓存副本（子串扫描用——避免每次查询重复 toLowerCase）。
  final Map<String, String> _lowerTexts = {};
  final Map<String, String> _lowerOcrTexts = {};

  /// 已索引文档数量。
  int get documentCount => _docTexts.length;

  /// 索引一个文档。
  void indexDocument({
    required String docId,
    required String title,
    required String text,
    String? ocrText,
  }) {
    // 移除旧索引。
    removeDocument(docId);

    _docTitles[docId] = title;
    _docTexts[docId] = text;
    if (ocrText != null && ocrText.isNotEmpty) {
      _ocrTexts[docId] = ocrText;
    }

    // 维护小写缓存（子串扫描兜底用）。
    _lowerTexts[docId] = text.toLowerCase();
    if (ocrText != null && ocrText.isNotEmpty) {
      _lowerOcrTexts[docId] = ocrText.toLowerCase();
    } else {
      _lowerOcrTexts.remove(docId);
    }

    // 分词并建立倒排索引。
    final tokens = _tokenize(text);
    for (final token in tokens) {
      _invertedIndex.putIfAbsent(token, () => {}).add(docId);
    }

    // 索引 OCR 文本。
    if (ocrText != null && ocrText.isNotEmpty) {
      final ocrTokens = _tokenize(ocrText);
      for (final token in ocrTokens) {
        _invertedIndex.putIfAbsent('ocr:$token', () => {}).add(docId);
      }
    }
  }

  /// 移除文档索引。
  void removeDocument(String docId) {
    _docTexts.remove(docId);
    _docTitles.remove(docId);
    _ocrTexts.remove(docId);
    _lowerTexts.remove(docId);
    _lowerOcrTexts.remove(docId);

    // 从倒排索引中移除。
    for (final entry in _invertedIndex.values) {
      entry.remove(docId);
    }
    // 清理空集合。
    _invertedIndex.removeWhere((_, v) => v.isEmpty);
  }

  /// 搜索文档。
  ///
  /// 混合匹配策略：
  /// 1) 倒排索引按词 AND 匹配（拉丁语系词边界精确）；
  /// 2) 子串扫描兜底 —— 中文等无空格语言整句分词后是单一长 token，
  ///    查询子串无法经倒排命中；且「仅标题 / 仅 OCR 命中」的文档
  ///    不在任何正文倒排表里。对小写缓存做 contains 扫描补齐
  ///    （1000 级文档为毫秒级开销，见性能基准测试）。
  List<SearchResult> search(String query, {int limit = 50}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final tokens = _tokenize(query);

    // 阶段一：倒排索引求交集（AND 语义）。
    Set<String>? candidateIds;
    for (final token in tokens) {
      final ids = _invertedIndex[token] ?? {};
      if (candidateIds == null) {
        candidateIds = Set.from(ids);
      } else {
        candidateIds = candidateIds.intersection(ids);
      }
      if (candidateIds.isEmpty) break;
    }
    candidateIds ??= {};

    // 阶段二：子串扫描兜底（标题 / 正文 / OCR 小写副本）。
    final lowerQuery = query.toLowerCase();
    for (final id in _docTitles.keys) {
      if (candidateIds.contains(id)) continue;
      final inTitle = _docTitles[id]!.toLowerCase().contains(lowerQuery);
      final inText = _lowerTexts[id]?.contains(lowerQuery) ?? false;
      final inOcr = _lowerOcrTexts[id]?.contains(lowerQuery) ?? false;
      if (inTitle || inText || inOcr) candidateIds.add(id);
    }

    if (candidateIds.isEmpty) return [];

    // 生成搜索结果。
    final results = <SearchResult>[];
    for (final docId in candidateIds) {
      final title = _docTitles[docId] ?? '';
      final text = _docTexts[docId] ?? '';
      final ocrText = _ocrTexts[docId];

      // 在主文本中查找匹配。
      // 多词查询优先整句匹配；词间有间隔时（如 hello … world）
      // 退化到首词片段，保证 AND 候选文档仍然可见。
      var matched = false;
      var match = _findMatch(text, query);
      var matchedLength = query.length;
      if (match == null && tokens.isNotEmpty && tokens.first != query) {
        match = _findMatch(text, tokens.first);
        matchedLength = tokens.first.length;
      }
      if (match != null) {
        results.add(SearchResult(
          noteId: docId,
          noteTitle: title,
          matchedText: match.$1,
          matchStart: match.$2,
          matchLength: matchedLength,
        ));
        matched = true;
      }

      // 在 OCR 文本中查找匹配。
      if (!matched && ocrText != null) {
        var ocrMatch = _findMatch(ocrText, query);
        var ocrMatchedLength = query.length;
        if (ocrMatch == null && tokens.isNotEmpty && tokens.first != query) {
          ocrMatch = _findMatch(ocrText, tokens.first);
          ocrMatchedLength = tokens.first.length;
        }
        if (ocrMatch != null) {
          results.add(SearchResult(
            noteId: docId,
            noteTitle: title,
            matchedText: ocrMatch.$1,
            matchStart: ocrMatch.$2,
            matchLength: ocrMatchedLength,
            isOcrMatch: true,
          ));
          matched = true;
        }
      }

      // 标题命中兜底（正文与 OCR 均未命中时，以标题作为高亮片段）。
      if (!matched) {
        final titleIdx = title.toLowerCase().indexOf(lowerQuery);
        if (titleIdx != -1) {
          results.add(SearchResult(
            noteId: docId,
            noteTitle: title,
            matchedText: title,
            matchStart: titleIdx,
            matchLength: query.length,
          ));
        }
      }
    }

    // 按匹配质量排序（标题匹配优先）。
    results.sort((a, b) {
      final aInTitle = a.noteTitle.toLowerCase().contains(query.toLowerCase());
      final bInTitle = b.noteTitle.toLowerCase().contains(query.toLowerCase());
      if (aInTitle && !bInTitle) return -1;
      if (!aInTitle && bInTitle) return 1;
      return a.noteTitle.compareTo(b.noteTitle);
    });

    return results.take(limit).toList();
  }

  /// 清空所有索引。
  void clear() {
    _invertedIndex.clear();
    _docTitles.clear();
    _docTexts.clear();
    _ocrTexts.clear();
    _lowerTexts.clear();
    _lowerOcrTexts.clear();
  }

  // ---------------------------------------------------------------------------
  // 私有方法
  // ---------------------------------------------------------------------------

  /// 分词：将文本拆分为小写词项集合。
  Set<String> _tokenize(String text) {
    final normalized = text.toLowerCase();
    // 按非字母数字字符分词。
    final words = normalized.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
    return words.where((w) => w.isNotEmpty).toSet();
  }

  /// 在文本中查找匹配位置。
  /// 返回 (匹配片段, 起始位置) 或 null。
  (String, int)? _findMatch(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index == -1) return null;

    // 提取匹配上下文（前后各 20 字符）。
    final start = (index - 20).clamp(0, text.length);
    final end = (index + query.length + 20).clamp(0, text.length);
    final snippet = text.substring(start, end);

    return (snippet, index);
  }
}
