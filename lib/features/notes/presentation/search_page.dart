import 'dart:async';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/shared/application/search_service.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
// N4 批 3：加密分页画布解锁拦截（与 app_shell 同口径）。
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/features/security/notebook_password_reset_flow.dart';
import 'package:drawing_notes_app/features/security/block_doc_password_reset_flow.dart';
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart'
    show VaultFileLockException;
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';

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
      // N2：受密笔记解锁拦截（搜索索引本身已排除未解锁的受密笔记，
      // 此处兜底防「搜索后设密/切后台清 DEK」竞态）。
      if (await blockStore.isBlockDocPasswordProtected(r.pageId!) &&
          !blockStore.isBlockDocUnlocked(r.pageId!)) {
        if (!mounted) return;
        final pin = await UnlockFlow.show(
          context,
          title: '该笔记已加密，输入密码',
          flexible: true,
          onVerify: (p) => blockStore.verifyBlockDocPassword(r.pageId!, p),
          footerLabel: '忘记密码？',
          onFooter: () {
            BlockDocPasswordResetFlow.show(
              context,
              store: blockStore,
              docId: r.pageId!,
            );
          },
        );
        if (pin == null && !blockStore.isBlockDocUnlocked(r.pageId!)) {
          return;
        }
      }
      // 锁定异常折叠为 null（fail-closed）——独立方法保证空安全提升。
      Future<NoteBlockDoc?> loadGuarded() async {
        try {
          return await blockStore.loadDocument(r.pageId!);
        } on BlockDocLockedException {
          return null; // 会话 DEK 已被清——不暴露内容
        }
      }

      final doc = await loadGuarded();
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
    // 锁定守卫（保险库中途锁定的竞态）：fail-closed 不暴露内容。
    final Notebook? loaded;
    try {
      loaded = await nbStorage.load(nbId);
    } on VaultFileLockException {
      return; // 保险库已锁定——请先重新验证开屏密码
    }
    if (loaded == null || !mounted) return;
    Notebook nb = loaded;
    // N4 批 3：加密分页画布解锁拦截（M12 回归修复——M12 前搜索页解锁
    // 路径存在，重做后丢失；与 app_shell 同口径）。占位条目（payload 为
    // null）不弹文件密码框——其锁定来自保险库而非文件密码。
    if (nb.encrypted &&
        nb.encryptedPayload != null &&
        nbStorage.notebookPasswordFor(nbId) == null) {
      final pin = await UnlockFlow.show(
        context,
        title: '该分页画布已加密，输入密码',
        flexible: true,
        onVerify: (p) => nbStorage.verifyNotebookPassword(nbId, p),
        footerLabel: '忘记密码？',
        onFooter: () {
          NotebookPasswordResetFlow.show(
            context,
            storage: nbStorage,
            notebookId: nbId,
            notebookTitle: nb.title,
          );
        },
      );
      if (pin == null && nbStorage.notebookPasswordFor(nbId) == null) {
        return; // 用户取消且会话无密码——不暴露内容
      }
    }
    final sessionPw = nbStorage.notebookPasswordFor(nbId);
    if (sessionPw != null) {
      final fresh = await nbStorage.load(nbId);
      if (fresh == null || !mounted) return;
      try {
        final ok = await nbStorage.decryptNotebook(fresh, sessionPw);
        if (!ok || !mounted) return;
        nb = fresh;
        final mediaSalt = await nbStorage.ensureMediaSalt();
        await MediaCryptoService.instance.setSessionPassword(
          sessionPw,
          mediaSalt,
        );
      } on FormatException {
        return; // 密码失效——fail-closed
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: nb,
          storage: nbStorage,
          editorPageBuilder: widget.editorPageBuilder,
          sessionPassword: sessionPw,
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
      // 让内容延伸到顶栏之后——玻璃才有东西可模糊。
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
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
                  borderRadius: BorderRadius.circular(AppleRadius.sm),
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
          style: TextStyle(color: AppleColor.inkSubtle),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.searchNoResults ?? '未找到匹配内容',
          style: TextStyle(color: AppleColor.inkSubtle),
        ),
      );
    }
    return ListView.builder(
      // 可滚动 padding——见 settings_page 同名注释。顶栏还挂着搜索框，
      // 让位高度要把 bottom 的 60 一起算进去。
      padding: EdgeInsets.only(
        top: GlassAppBar.bodyTopPadding(context, bottomHeight: 60),
      ),
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
