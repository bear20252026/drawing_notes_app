import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart';
import 'package:editor_core/editor_core.dart' hide SearchResult;

import '../../drawing/application/search_service.dart';
import '../../../l10n/app_localizations.dart';
import '../infrastructure/notebook_storage.dart';
import '../../editor_v2/presentation/editor_v2_screen.dart';
import 'notebook_view_page.dart';

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
      if (meta == null || !mounted) return;
      // Apple 风格：使用 V2 编辑器
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorV2Screen(
            documentId: meta.id,
            mode: UnifiedEditorMode.whiteboard,
          ),
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
                hintText: AppLocalizations.of(context)?.searchHint ?? '搜索文字块内容 / 标题…',
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
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)?.searchEmptyHint ?? '输入关键词开始搜索', style: const TextStyle(color: Color(0xFF8E8E93))),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)?.searchNoResults ?? '未找到匹配内容', style: const TextStyle(color: Color(0xFF8E8E93))),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        return GestureDetector(
          onTap: () => _openResult(r),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  r.kind == 'drawing' ? Icons.brush_rounded : Icons.menu_book_rounded,
                  size: 22,
                  color: const Color(0xFF0066CC),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1D1D1F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
