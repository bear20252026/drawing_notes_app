import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/application/search_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';

/// 全文搜索页（借鉴 Joplin / nb 的全文搜索）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.searchService});

  final SearchService searchService;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<SearchResult> _results = const [];
  bool _searching = false;

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
      final storage = StorageService();
      final doc = await storage.load(meta.id);
      if (doc == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorPage(document: doc, docStorage: storage),
        ),
      );
      return;
    }
    // 笔记本命中：打开笔记本页面管理。
    final nbId = r.notebookId;
    if (nbId == null) return;
    final nbStorage = NotebookStorage();
    final nb = await nbStorage.load(nbId);
    if (nb == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(notebook: nb, storage: nbStorage),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全文搜索'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: '搜索文字块内容 / 标题…',
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.text.trim().isEmpty) {
      return const Center(
        child: Text('输入关键词开始搜索', style: TextStyle(color: Colors.grey)),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text('未找到匹配内容', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        return ListTile(
          leading: Icon(r.kind == 'drawing' ? Icons.brush : Icons.menu_book),
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
