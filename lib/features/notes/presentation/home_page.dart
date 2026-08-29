import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/shared/application/search_service.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/block_doc_search_accessor_impl.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/presentation/onboarding.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/password_disk_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/search_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';

part 'home_page_widgets.dart';
part 'home_page_tabs.dart';

/// 首页：无限画布绘图 / 分页笔记本列表管理。
///
/// 两个主工作区：
/// - 无限画布：独立图形、关系图和自由绘制作品；
/// - 分页笔记本：带纸张模板、文字和资料混排的文档页面。
///
/// 能力：
/// - 新建无限画布 / 新建笔记本
/// - 打开、删除（二次确认）
/// - 展示缩略图
///
/// 数据来源：本地文件存储（[StorageService] / [NotebookStorage]），无网络请求。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.notebookStorage,
    this.docStorage,
    this.themeController,
    this.editorPageBuilder,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;

  /// 主题控制器（深色模式切换，Phase 7）。
  final AppThemeController? themeController;

  /// 编辑器页面由应用组合根注入，notes 模块不直接依赖 drawing 的 UI。
  final EditorPageBuilder? editorPageBuilder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final NotebookStorage _nbStorage;
  late final StorageService _docStorage;
  late final NoteBlockDocStore _blockDocStore;

  List<Notebook> _notebooks = [];
  List<DocumentMeta> _documents = [];
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _nbStorage = widget.notebookStorage ?? NotebookStorage();
    _docStorage = widget.docStorage ?? StorageService();
    _blockDocStore = NoteBlockDocStore();
    _refresh();
    // 首次启动引导（Phase 7）：仅第一次打开时显示，可跳过。
    _showOnboarding();
  }

  Future<void> _showOnboarding() async {
    try {
      await OnboardingService().showIfFirstLaunch(context);
    } catch (_) {
      // 引导展示失败不影响正常使用。
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await _docStorage.listDocuments();
      final nbs = await _nbStorage.listAll();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _notebooks = nbs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取列表失败：${e.runtimeType}';
        _loading = false;
      });
    }
  }

  Widget _buildEditorPage({
    DrawingDocument? document,
    StorageService? documentStorage,
  }) {
    final builder = widget.editorPageBuilder;
    if (builder == null) {
      return const Scaffold(body: Center(child: Text('编辑器尚未由应用层装配')));
    }
    return builder(document: document, documentStorage: documentStorage);
  }

  Future<void> _openEditor({
    DrawingDocument? document,
    StorageService? documentStorage,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _buildEditorPage(
          document: document,
          documentStorage: documentStorage,
        ),
      ),
    );
  }

  // ---------------- 无限画布绘图 ----------------

  /// 新建无限画布并进入绘图工作区。
  Future<void> _createDrawing() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _NameDialog(title: '新建无限画布'),
    );
    if (name == null || name.trim().isEmpty) return;

    final doc = DrawingDocument(
      id: StorageService.newId(),
      title: name.trim(),
      infinite: true,
    );
    if (!mounted) return;
    await _openEditor(document: doc, documentStorage: _docStorage);
    _refresh();
  }

  /// 打开已有画作继续编辑。
  Future<void> _openDrawing(DocumentMeta meta) async {
    try {
      final doc = await _docStorage.load(meta.id);
      if (doc == null) {
        _showSnack('画作文件不存在或已损坏');
        return;
      }
      if (!mounted) return;
      await _openEditor(document: doc, documentStorage: _docStorage);
      _refresh();
    } catch (e) {
      _showSnack('打开画作失败：${e.runtimeType}');
    }
  }

  /// 删除画作（二次确认）。
  Future<void> _deleteDrawing(DocumentMeta meta) async {
    final ok = await _confirmDelete('删除画作', '确定删除画作「${meta.title}」吗？此操作不可恢复。');
    if (ok != true) return;
    try {
      await _docStorage.delete(meta.id);
      await _refresh();
    } catch (e) {
      _showSnack('删除失败：${e.runtimeType}');
    }
  }

  // ---------------- 笔记本 ----------------

  Future<void> _createNotebook() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _NameDialog(title: '新建笔记本'),
    );
    if (name == null || name.trim().isEmpty) return;

    final notebook = Notebook(
      id: NotebookStorage.newId('nb'),
      title: name.trim(),
    );
    try {
      await _nbStorage.save(notebook);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotebookViewPage(
            notebook: notebook,
            storage: _nbStorage,
            onChanged: _refresh,
            editorPageBuilder: widget.editorPageBuilder,
          ),
        ),
      );
      _refresh();
    } catch (e) {
      _showSnack('新建失败：${e.runtimeType}');
    }
  }

  Future<void> _deleteNotebook(Notebook nb) async {
    // 策略门禁（专家审计最优先④）：删除操作白名单判定（回收站——可恢复）。
    if (!const PolicyEngine().check('note.delete').isAllowed) {
      _showSnack('操作被策略拒绝（note.delete）');
      return;
    }
    final ok = await _confirmDelete(
      '删除笔记本',
      '确定删除笔记本「${nb.title}」吗？其中所有页面内容将一并删除，此操作不可恢复。',
    );
    if (ok != true) return;
    try {
      await _nbStorage.delete(nb.id);
      await _refresh();
    } catch (e) {
      _showSnack('删除失败：${e.runtimeType}');
    }
  }

  // ---------------- 通用 ----------------

  /// M-06 回收站对话框（专家审计 2026-08-15）：列出已删除文档（id/删除
  /// 时间）+ 恢复/永久删除/清空（UX Patterns 官方模式——Restore 主操作、
  /// 永久删除分离——操作后刷新列表）。
  Future<void> _showTrashDialog() async {
    final trash = await _docStorage.listTrash();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.trash ?? '回收站（30 天内可恢复）'),
        content: ConstrainedBox(
          // L-02 响应式（专家审计 2026-08-15）：maxWidth 而非固定宽度——
          // 窄屏自适应（原 SizedBox 固定 380 在窄屏可能溢出）。
          constraints: const BoxConstraints(maxWidth: 380),
          child: trash.isEmpty
              ? Text(AppLocalizations.of(context)?.homeTrashEmpty ?? '回收站为空')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: trash.length,
                  itemBuilder: (context, i) {
                    final item = trash[i];
                    final time = item.$3.toLocal().toString().substring(0, 16);
                    return ListTile(
                      title: Text(item.$2),
                      subtitle: Text(
                        AppLocalizations.of(context)?.homeDeletedAt(time) ??
                            '删除于 $time',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip:
                                AppLocalizations.of(context)?.homeRecover ??
                                '恢复',
                            icon: const Icon(Icons.restore),
                            onPressed: () async {
                              final id = await _docStorage.restoreTrash(
                                item.$1,
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _refresh();
                              if (id != null) _showSnack('已恢复「$id」');
                            },
                          ),
                          IconButton(
                            tooltip:
                                AppLocalizations.of(
                                  context,
                                )?.homeDeleteForever ??
                                '永久删除',
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () async {
                              final ok = await _confirmDelete(
                                '永久删除',
                                '确定永久删除「${item.$2}」吗？此操作不可恢复。',
                              );
                              if (ok == true) {
                                await _docStorage.deleteTrashPermanently(
                                  item.$1,
                                );
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                _refresh();
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (trash.isNotEmpty)
            TextButton(
              onPressed: () async {
                await _docStorage.purgeTrash();
                if (ctx.mounted) Navigator.of(ctx).pop();
                _refresh();
              },
              child: Text(
                AppLocalizations.of(context)?.homeEmptyTrash ?? '清空回收站',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)?.close ?? '关闭'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context)?.homeCancel ?? '取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context)?.delete ?? '删除'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 旧版加密格式提示（红蓝攻防 D-1 修复 2026-08-15）：
  /// v≤2 旧数据用 PBKDF2 10 万次迭代，弱密码可被 GPU 集群暴力破解——
  /// 解锁成功后提示用户重新保存以升级至 60 万次新标准。
  void _maybeWarnLegacyEncryption(Notebook nb) {
    final payload = nb.encryptedPayload;
    if (payload == null) return;
    if (EncryptionService.formatVersionOf(payload) <= 2) {
      _showSnack('检测到旧版加密格式（10 万次迭代），建议重新保存以升级至最新加密标准（60 万次）');
    }
  }

  /// 旧格式密码笔记本自动升级（hsh verify_and_upgrade 模式，
  /// D-1 完整修复 2026-08-15）：v≤2（PBKDF2 10 万次）解锁成功后自动用
  /// 当前参数（encrypt 现标 v=3/60 万次）重加密保存——零停机升级弱加密，
  /// 免用户手动操作。keyfile 模式需恢复密钥（用户抄写件）无法自动重加密，
  /// 保持 [_maybeWarnLegacyEncryption] 提示。
  Future<void> _upgradeLegacyPasswordEncryption(
    Notebook nb,
    String password,
  ) async {
    final payload = nb.encryptedPayload;
    if (payload == null) return;
    if (EncryptionService.formatVersionOf(payload) > 2) return;
    try {
      await _nbStorage.encryptAndSave(nb, password);
      _showSnack('已自动升级加密至最新标准（60 万次迭代）');
    } catch (_) {
      _showSnack('旧版加密格式：建议手动重新保存升级');
    }
  }

  void _onHomeMenuSelected(_HomeMenuItem item) {
    switch (item) {
      case _HomeMenuItem.passwordDisk:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PasswordDiskPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // 无限画布 / 笔记本（M11：「最近」时间线并入日历页）
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)?.appTitle ?? '绘图笔记'),
          actions: [
            IconButton(
              tooltip: AppLocalizations.of(context)?.search ?? '搜索全部内容',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchPage(
                    searchService: SearchService(
                      notebookAccessor: _nbStorage,
                      docStorage: _docStorage,
                      blockDocAccessor: BlockDocSearchAccessorImpl(store: _blockDocStore),
                    ),
                    notebookStorage: _nbStorage,
                    documentStorage: _docStorage,
                    editorPageBuilder: widget.editorPageBuilder,
                    blockDocStore: _blockDocStore,
                  ),
                ),
              ),
            ),
            // M-06 回收站入口（专家审计 2026-08-15）：查看/恢复/永久删除
            // 已删除文档（UX Patterns 官方模式——专用回收站界面）。
            IconButton(
              tooltip: AppLocalizations.of(context)?.trash ?? '回收站（30 天内可恢复）',
              icon: const Icon(Icons.delete_outline),
              onPressed: _showTrashDialog,
            ),
            IconButton(
              tooltip: 'WebDAV 本地优先同步',
              icon: const Icon(Icons.cloud_sync_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WebDavSyncSettingsPage(),
                ),
              ),
            ),
            if (widget.themeController != null)
              IconButton(
                tooltip: '切换外观（系统 / 浅色 / 深色）',
                icon: Icon(
                  widget.themeController!.mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                ),
                onPressed: widget.themeController!.cycle,
              ),
            PopupMenuButton<_HomeMenuItem>(
              tooltip: AppLocalizations.of(context)?.homeMore ?? '更多操作',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: _onHomeMenuSelected,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _HomeMenuItem.passwordDisk,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.usb_rounded),
                    title: Text('密码盘与恢复'),
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(AppDesign.controlRadius),
                sigma: 10,
                child: TabBar(
                  onTap: (i) => setState(() => _tabIndex = i),
                  tabs: const [
                    Tab(text: '无限画布'),
                    Tab(text: '笔记本'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: AmbientBackground(child: _buildBody()),
        floatingActionButton: _tabIndex == 0
            ? FloatingActionButton.extended(
                onPressed: _createDrawing,
                icon: const Icon(Icons.add),
                label: const Text('新建无限画布'),
              )
            : FloatingActionButton.extended(
                onPressed: _createNotebook,
                icon: const Icon(Icons.add),
                label: const Text('新建笔记本'),
              ),
      ),
    );
  }
}

enum _HomeMenuItem { passwordDisk }
