// 全文搜索 UI（借鉴 Joplin / nb 全文搜索面板）。
//
// 基于倒排索引核心 [SearchIndex]：
// - [SearchIndexBuilder]：从笔记本存储 + 文档存储构建索引
//   （页面标题 + 文字块内容 + 手写字体文本作为 OCR 文本）
// - [SearchWidget]：搜索框 + 结果列表（匹配片段高亮 + 手写徽章）+ 跳转回调
//
// docId 编码约定（[SearchDocIds] / SearchTarget.parse）：
// - 页面命中    `nb:<notebookId>|<pageId>`
// - 手写字体命中 `ocr:<notebookId>|<pageId>`
// - 独立画作    `drawing:<documentId>`
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/search/search_index.dart';
import '../../../core/storage/storage_service.dart';
import '../infrastructure/notebook_storage.dart';
import '../../../l10n/app_localizations.dart';

/// 从本地存储构建 [SearchIndex]。
///
/// 数据面与 [SearchService] 一致（笔记本文字块 + 独立画作标题），
/// 但走倒排索引以支持多词 AND 查询与 O(1) 词项定位。
class SearchIndexBuilder {
  SearchIndexBuilder._();

  /// 手写字体标识（与 properties_panel 字体循环一致）。
  static const String handwritingFont = 'handwriting';

  /// 构建索引：每页一个文档条目。
  static Future<SearchIndex> build({
    NotebookStorage? notebookStorage,
    StorageService? docStorage,
  }) async {
    final nbStorage = notebookStorage ?? NotebookStorage();
    final storage = docStorage ?? StorageService();
    final index = SearchIndex();

    final notebooks = await nbStorage.listAll();
    for (final nb in notebooks) {
      for (final page in nb.pages) {
        final buffer = StringBuffer(page.title);
        final ocrBuffer = StringBuffer();
        for (final t in page.textItems) {
          buffer.write(' ');
          buffer.write(t.text);
          if ((t.fontFamily ?? '') == handwritingFont) {
            ocrBuffer..write(' ')..write(t.text);
          }
        }
        index.indexDocument(
          docId: SearchDocIds.notebook(nb.id, page.id),
          title: '${nb.title} / ${page.title}',
          text: buffer.toString(),
          ocrText: ocrBuffer.isEmpty ? null : ocrBuffer.toString(),
        );
      }
    }

    // 独立画作：标题检索（正文留空）。
    final metas = await storage.listDocuments();
    for (final m in metas) {
      index.indexDocument(
        docId: SearchDocIds.drawing(m.id),
        title: m.title,
        text: '',
      );
    }
    return index;
  }
}

/// docId 编码工具（命名空间类，避免顶级函数污染）。
abstract final class SearchDocIds {
  static String notebook(String notebookId, String pageId) =>
      'nb:$notebookId|$pageId';
  static String drawing(String documentId) => 'drawing:$documentId';
}

/// docId 编解码（搜索结果 -> 导航目标）。
class SearchTarget {
  const SearchTarget.page(this.notebookId, this.pageId)
      : documentId = null;
  const SearchTarget.drawing(this.documentId)
      : notebookId = null,
        pageId = null;

  final String? notebookId;
  final String? pageId;
  final String? documentId;

  /// 解析 [SearchDocIds] 生成的 docId。
  static SearchTarget? parse(String docId) {
    if (docId.startsWith('nb:') || docId.startsWith('ocr:')) {
      final body =
          docId.substring(docId.indexOf(':') + 1); // <nbId>|<pageId>
      final sep = body.indexOf('|');
      if (sep <= 0 || sep == body.length - 1) return null;
      return SearchTarget.page(body.substring(0, sep), body.substring(sep + 1));
    }
    if (docId.startsWith('drawing:')) {
      final id = docId.substring('drawing:'.length);
      if (id.isEmpty) return null;
      return SearchTarget.drawing(id);
    }
    return null;
  }
}

/// 全文搜索面板：搜索框 + 结果列表。
///
/// 结果行显示匹配片段（命中词高亮）、手写徽章（OCR 命中）；
/// 点击行触发 [onOpenTarget] 由宿主负责路由。
class SearchWidget extends StatefulWidget {
  const SearchWidget({
    super.key,
    required this.index,
    this.onOpenTarget,
    this.autofocusField = true,
  });

  /// 已构建好的搜索索引。
  final SearchIndex index;

  /// 点击结果回调（pop 前由宿主处理导航）。
  final void Function(SearchTarget target)? onOpenTarget;

  /// 是否自动聚焦输入框。
  final bool autofocusField;

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  final TextEditingController _controller = TextEditingController();
  List<SearchResult> _results = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _results = widget.index.search(value.trim(), limit: 50);
      });
    });
  }

  void _open(SearchResult r) {
    final target = SearchTarget.parse(r.noteId);
    if (target == null) return;
    widget.onOpenTarget?.call(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: widget.autofocusField,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText:
                l10n?.searchHint ?? '搜索文字块内容 / 标题…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: l10n?.cancel ?? '清除',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(child: _buildResults(l10n)),
      ],
    );
  }

  Widget _buildResults(AppLocalizations? l10n) {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            l10n?.searchEmptyHint ?? '输入关键词开始搜索',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            l10n?.searchNoResults ?? '未找到匹配内容',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        final isDrawing = r.noteId.startsWith('drawing:');
        return ListTile(
          leading: Icon(isDrawing ? Icons.brush : Icons.menu_book),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  r.noteTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r.isOcrMatch) const _HandwritingBadge(),
            ],
          ),
          subtitle: _HighlightedSnippet(result: r, query: query),
          onTap: () => _open(r),
        );
      },
    );
  }
}

/// “手写”徽章：标记 OCR 命中（Leader 需求 #5）。
class _HandwritingBadge extends StatelessWidget {
  const _HandwritingBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '手写',
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSecondaryContainer, // M3 配色对比度达标
        ),
      ),
    );
  }
}

/// 匹配片段高亮（Leader 需求 #3）。
///
/// SearchIndex.matchStart 是全文绝对位置，而 matchedText 是前后各 20 字符
/// 的片段；此处换算片段内偏移后用 [TextSpan] 分三段着色。
class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({required this.result, required this.query});

  final SearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    final snippet = result.matchedText;
    final snippetStart = (result.matchStart - 20).clamp(0, snippet.length);
    final offsetInSnippet = result.matchStart - snippetStart;
    var end = offsetInSnippet + result.matchLength;
    // 防御：索引数据与结果不同步时避免 RangeError。
    if (offsetInSnippet > snippet.length || end > snippet.length) {
      return Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: TextStyle(color: scheme.onSurfaceVariant),
        children: [
          if (offsetInSnippet > 0)
            TextSpan(text: snippet.substring(0, offsetInSnippet)),
          TextSpan(
            text: snippet.substring(offsetInSnippet, end),
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.bold,
              backgroundColor: scheme.primaryContainer,
            ),
          ),
          if (end < snippet.length) TextSpan(text: snippet.substring(end)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
