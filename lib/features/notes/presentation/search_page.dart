import 'dart:async';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/shared/application/search_service.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';

/// 全文搜索页（借鉴 Joplin / nb 的全文搜索）。
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.searchService,
    this.notebookStorage,
    this.documentStorage,
    this.editorPageBuilder,
    this.blockDocStore,
  });

  final SearchService searchService;
  final NotebookStorage? notebookStorage;
  final StorageService? documentStorage;
  final EditorPageBuilder? editorPageBuilder;
  final NoteBlockDocStore? blockDocStore;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<SearchResult> _results = const [];
  bool _searching = false;
  // M-08 去抖（专家审计 2026-08-15）：停止输入 300ms 后才触发搜索——
  // 防每键全盘扫描（Flutter 官方 Riverpod debounce 模式——Timer 取消
  // 旧任务 + 延迟触发）。
  Timer? _debounceTimer;

  /// M-08 去抖入口：停止输入 300ms 后触发搜索。
  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final results = await widget.searchService.search(query);
    // 评审发现 P3：丢弃乱序响应——仅当查询仍是当前输入时应用结果，
    // 否则旧查询的扫描结果会覆盖新查询（慢扫描后完成时）。
    if (!mounted) return;
    if (query.trim() != _controller.text.trim()) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _openResult(SearchResult r) async {
    if (r.kind == 'drawing') {
      final meta = r.drawingMeta;
      if (meta == null) return;
      final storage = widget.documentStorage ?? StorageService();
      final builder = widget.editorPageBuilder;
      final doc = await storage.load(meta.id);
      if (doc == null || !mounted || builder == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => builder(document: doc, documentStorage: storage),
        ),
      );
      return;
    }
    // 块文档命中：打开双模宿主（页面/无限画布）。
    if (r.kind == 'blockdoc') {
      final blockStore = widget.blockDocStore ?? NoteBlockDocStore();
      final doc = await blockStore.loadDocument(r.pageId!);
      if (doc == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocPage(
            document: doc,
            blockDocStore: blockStore,
            controller: DocController(
              onSave: (d) => blockStore.saveDocument(d),
            ),
          ),
        ),
      );
      return;
    }
    // 笔记本命中：打开笔记本页面管理。
    final nbId = r.notebookId;
    if (nbId == null) return;
    final nbStorage = widget.notebookStorage ?? NotebookStorage();
    final nb = await nbStorage.load(nbId);
    if (nb == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: nb,
          storage: nbStorage,
          editorPageBuilder: widget.editorPageBuilder,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.searchTitle ?? '全文搜索'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText:
                    AppLocalizations.of(context)?.searchHint ?? '搜索文字块内容 / 标题…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return Center(child: CircularProgressIndicator());
    }
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.searchEmptyHint ?? '输入关键词开始搜索',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.searchNoResults ?? '未找到匹配内容',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        return ListTile(
          leading: Icon(
            r.kind == 'drawing'
                ? Icons.brush
                : r.kind == 'blockdoc'
                ? Icons.hub_rounded
                : Icons.menu_book,
          ),
          title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            r.snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openResult(r),
        );
      },
    );
  }
}
