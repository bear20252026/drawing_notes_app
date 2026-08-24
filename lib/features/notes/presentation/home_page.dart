import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/di/providers.dart';
import 'package:drawing_notes_app/features/notes/presentation/search_widget.dart';
import 'package:drawing_notes_app/core/search/search_index.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/presentation/onboarding.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/editor_v2/presentation/editor_v2_screen.dart';
import 'package:editor_core/editor_core.dart' hide TabBar;
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/password_disk_page.dart';

part 'home_page_widgets.dart';

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
/// 主页面菜单项枚举。
enum _HomeMenuItem {
  passwordDisk,
}

///
/// 数据来源：本地文件存储（[StorageService] / [NotebookStorage]），无网络请求。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    this.notebookStorage,
    this.docStorage,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final NotebookStorage _nbStorage;
  late final StorageService _docStorage;

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
    await Navigator.of(context).push(
      MaterialPageRoute(
        // 统一架构 V2（2026-08-22）：新建画布 → EditorV2Screen
        // （画板模式——无限画布——问题已修——不用旧 V1 editor_page）。
        builder: (_) => EditorV2Screen(
          documentId: doc.id,
          mode: UnifiedEditorMode.whiteboard,
        ),
      ),
    );
    _refresh();
  }

  /// 打开已有画作继续编辑。
  Future<void> _openDrawing(DocumentMeta meta) async {
    try {
      final doc = await _docStorage.load(meta.id);
      if (doc == null) {
        _showSnack(AppLocalizations.of(context)?.homeErrorDrawingNotFound ?? '画作文件不存在或已损坏');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorPage(document: doc, docStorage: _docStorage),
        ),
      );
      _refresh();
    } catch (e) {
      _showSnack(AppLocalizations.of(context)?.homeErrorOpenDrawing('${e.runtimeType}') ?? '打开画作失败：${e.runtimeType}');
    }
  }

  /// 删除画作（二次确认）。
  Future<void> _deleteDrawing(DocumentMeta meta) async {
    final ok = await _confirmDelete(AppLocalizations.of(context)?.homeDeleteDrawing ?? '删除画作', AppLocalizations.of(context)?.homeConfirmDeleteDrawing(meta.title) ?? '确定删除画作「${meta.title}」吗？此操作不可恢复。');
    if (ok != true) return;
    try {
      await _docStorage.delete(meta.id);
      await _refresh();
    } catch (e) {
      _showSnack(AppLocalizations.of(context)?.homeErrorDeleteFailed('${e.runtimeType}') ?? '删除失败：${e.runtimeType}');
    }
  }

  // ---------------- 笔记本 ----------------

  Future<void> _createNotebook() async {
    final l10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(title: l10n?.newNotebook ?? '新建笔记本'),
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
          // 统一架构 V2（2026-08-22）：笔记本 → EditorV2Screen（note 模式——
          // AFFiNE Page 借鉴——单独界面（线性文档）——与画布（whiteboard
          // 无限画布）功能共通（同一编辑器——共用核心——不重复显示）——
          // 替代 V1 NotebookViewPage（material_ui 中文崩溃——修复无法使用）。
          builder: (_) => EditorV2Screen(
            documentId: notebook.id,
            mode: UnifiedEditorMode.note,
          ),
        ),
      );
      _refresh();
    } catch (e) {
      _showSnack(AppLocalizations.of(context)?.homeErrorCreateFailed('${e.runtimeType}') ?? '新建失败：${e.runtimeType}');
    }
  }

  Future<void> _deleteNotebook(Notebook nb) async {
    // 策略门禁（专家审计最优先④）：删除操作白名单判定（回收站——可恢复）。
    if (!const PolicyEngine().check('note.delete').isAllowed) {
      _showSnack(AppLocalizations.of(context)?.homeErrorPolicyDenied('note.delete') ?? '操作被策略拒绝（note.delete）');
      return;
    }
    final l10n = AppLocalizations.of(context);
    final ok = await _confirmDelete(
      l10n?.homeDeleteNotebook ?? '删除笔记本',
      l10n?.homeConfirmDeleteNotebook(nb.title) ?? '确定删除笔记本「${nb.title}」吗？其中所有页面内容将一并删除，此操作不可恢复。',
    );
    if (ok != true) return;
    try {
      await _nbStorage.delete(nb.id);
      await _refresh();
    } catch (e) {
      _showSnack(l10n?.homeErrorDeleteFailed('${e.runtimeType}') ?? '删除失败：${e.runtimeType}');
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
                            tooltip: AppLocalizations.of(context)?.homeRecover ??
                                '恢复',
                            icon: const Icon(Icons.restore),
                            onPressed: () async {
                              final id =
                                  await _docStorage.restoreTrash(item.$1);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _refresh();
                              if (id != null) _showSnack(AppLocalizations.of(context)?.homeRecovered(id) ?? '已恢复「$id」');
                            },
                          ),
                          IconButton(
                            tooltip: AppLocalizations.of(context)?.homeDeleteForever ??
                                '永久删除',
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () async {
                              final ok = await _confirmDelete(
                                AppLocalizations.of(context)?.homeDeleteForever ?? '永久删除',
                                AppLocalizations.of(context)?.homeConfirmPermanentDelete(item.$2) ?? '确定永久删除「${item.$2}」吗？此操作不可恢复。',
                              );
                              if (ok == true) {
                                await _docStorage
                                    .deleteTrashPermanently(item.$1);
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
              child: Text(AppLocalizations.of(context)?.homeEmptyTrash ?? '清空回收站'),
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
      _showSnack(AppLocalizations.of(context)?.homeLegacyEncryptionWarning ?? '检测到旧版加密格式（10 万次迭代），建议重新保存以升级至最新加密标准（60 万次）');
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
      _showSnack(AppLocalizations.of(context)?.homeEncryptionUpgraded ?? '已自动升级加密至最新标准（60 万次迭代）');
    } catch (_) {
      _showSnack(AppLocalizations.of(context)?.homeLegacyEncryptionManual ?? '旧版加密格式：建议手动重新保存升级');
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
      length: 3, // 画作 / 笔记本 / 时间线
      // 无障碍/效率：Ctrl+F（macOS ⌘F）全局唤起全文搜索。
      child: Focus(
        autofocus: true,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _openSearch,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _openSearch,
          },
          child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)?.appTitle ?? '绘图笔记'),
          actions: [
            Semantics(
              label: AppLocalizations.of(context)?.search ?? '搜索全部内容（Ctrl+F）',
              button: true,
              child: IconButton(
                tooltip: AppLocalizations.of(context)?.search ?? '搜索全部内容（Ctrl+F）',
                icon: const Icon(Icons.search_rounded),
                // 全文搜索 V2：倒排索引 + 高亮 + 手写徽章（见 search_widget.dart）。
                onPressed: _openSearch,
              ),
            ),
            // M-06 回收站入口（专家审计 2026-08-15）：查看/恢复/永久删除
            // 已删除文档（UX Patterns 官方模式——专用回收站界面）。
            Semantics(
              label: AppLocalizations.of(context)?.trash ?? '回收站（30 天内可恢复）',
              button: true,
              child: IconButton(
                tooltip: AppLocalizations.of(context)?.trash ?? '回收站（30 天内可恢复）',
                icon: const Icon(Icons.delete_outline),
                onPressed: _showTrashDialog,
              ),
            ),
            // 主题切换按钮（Riverpod 迁移：从 AppThemeController → themeModeProvider）。
            Builder(
              builder: (context) {
                final mode = ref.watch(themeModeProvider);
                return Semantics(
                  label: AppLocalizations.of(context)?.homeSwitchTheme ?? '切换外观（系统 / 浅色 / 深色）',
                  button: true,
                  value: mode == ThemeMode.dark ? '深色' : '浅色',
                  child: IconButton(
                    tooltip: AppLocalizations.of(context)?.homeSwitchTheme ?? '切换外观（系统 / 浅色 / 深色）',
                    icon: Icon(
                      mode == ThemeMode.dark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                    ),
                    onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
                  ),
                );
              },
            ),
            Semantics(
              label: AppLocalizations.of(context)?.homeMore ?? '更多操作',
              button: true,
              child: PopupMenuButton<_HomeMenuItem>(
                tooltip: AppLocalizations.of(context)?.homeMore ?? '更多操作',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: _onHomeMenuSelected,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _HomeMenuItem.passwordDisk,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.usb_rounded),
                      title: Text(AppLocalizations.of(context)?.homePasswordDiskAndRecovery ?? 'Password Disk & Recovery'),
                    ),
                  ),
                ],
              ),
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
                  tabs: [
                    Tab(icon: const Icon(Icons.dashboard_outlined), text: AppLocalizations.of(context)?.homeInfiniteCanvas ?? '无限画布'), // #14 图标区分
                    Tab(icon: const Icon(Icons.menu_book), text: AppLocalizations.of(context)?.homeNotebook ?? '笔记本'),
                    Tab(icon: const Icon(Icons.access_time), text: AppLocalizations.of(context)?.homeRecent ?? '最近'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: AmbientBackground(child: _buildBody()),
        floatingActionButton: _tabIndex == 0
            ? Semantics(
                label: AppLocalizations.of(context)?.homeNewInfiniteCanvas ?? '新建无限画布',
                button: true,
                child: FloatingActionButton.extended(
                  onPressed: _createDrawing,
                  icon: const Icon(Icons.add),
                  label: Text(AppLocalizations.of(context)?.homeNewInfiniteCanvas ?? '新建无限画布'),
                ),
              )
            : _tabIndex == 2
            ? Semantics(
                label: AppLocalizations.of(context)?.homeQuickRecord ?? '快速记录',
                button: true,
                child: FloatingActionButton.extended(
                  onPressed: _quickRecord,
                  icon: const Icon(Icons.edit_note),
                  label: Text(AppLocalizations.of(context)?.homeQuickRecord ?? '快速记录'),
                ),
              )
            : Semantics(
                label: AppLocalizations.of(context)?.newNotebook ?? '新建笔记本',
                button: true,
                child: FloatingActionButton.extended(
                  onPressed: _createNotebook,
                  icon: const Icon(Icons.edit_note), // #14 笔记本专用图标——区分画布
                  label: Text(AppLocalizations.of(context)?.newNotebook ?? '新建笔记本'),
                ),
              ),
          ), // Scaffold
        ), // CallbackShortcuts
      ), // Focus
    ); // DefaultTabController
  }

  /// 全文搜索 V2 入口：构建倒排索引 → 弹出搜索面板。
  ///
  /// 索引数据面：页面标题 + 文字块内容 + 手写字体文本（OCR）+ 画作标题。
  Future<void> _openSearch() async {
    final l10n = AppLocalizations.of(context);
    // 构建索引可能涉及解密读取，先显示加载指示（不可手动关闭）。
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: SizedBox(
            width: 220,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n?.searchHint ?? '正在建立搜索索引…')),
              ],
            ),
          ),
        ),
      ),
    );
    final SearchIndex index;
    try {
      index = await SearchIndexBuilder.build(
        notebookStorage: _nbStorage,
        docStorage: _docStorage,
      );
    } finally {
      // 无论成败都关闭加载指示（原实现等待加载框返回索引值，
      // 但加载框永不 pop → 搜索入口永久转圈，P0）。
      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SearchWidget(
              index: index,
              onOpenTarget: (target) async {
                Navigator.of(dialogContext).pop(); // 关闭搜索面板
                await _navigateToTarget(target);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 搜索结果跳转：复用首页既有的打开流程（含笔记本解锁）。
  Future<void> _navigateToTarget(SearchTarget target) async {
    try {
      if (target.notebookId != null) {
        final notebooks = await _nbStorage.listAll();
        for (final nb in notebooks) {
          for (final page in nb.pages) {
            if (page.id == target.pageId) {
              // 携带命中页 ID：进入笔记本后直接定位到该页（高亮跳转）。
              await _openNotebook(nb, initialPageId: target.pageId);
              return;
            }
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)?.searchNoResults ?? '未找到匹配内容')),
        );
      } else if (target.documentId != null) {
        final metas = await _docStorage.listDocuments();
        for (final meta in metas) {
          if (meta.id == target.documentId) {
            await _openDrawing(meta);
            return;
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)?.searchNoResults ?? '未找到匹配内容')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)?.exportFailed ?? '打开失败'}: $e')),
      );
    }
  }

  /// 极简快速记录入口（D7，借鉴 Memos"打开即写"）：直接新建画作并进入编辑器，
  /// 不弹名称对话框，用默认标题就地开始记录。
  void _quickRecord() {
    final doc = DrawingDocument(
      id: StorageService.newId(),
      title: '${AppLocalizations.of(context)?.homeQuickRecord ?? '快速记录'} ${_formatTime(DateTime.now())}',
      infinite: true,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        // 统一架构 V2（2026-08-22）：快速记录 → EditorV2Screen（画板模式）。
        builder: (_) => EditorV2Screen(
          documentId: doc.id,
          mode: UnifiedEditorMode.whiteboard,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _refresh, child: Text(AppLocalizations.of(context)?.retry ?? '重试')),
          ],
        ),
      );
    }
    return TabBarView(
      children: [
        _buildDrawingsTab(),
        _buildNotebooksTab(),
        _buildTimelineTab(),
      ],
    );
  }

  // ---------------- 时间线 Tab（A4，借鉴 Memos/Notes） ----------------

  /// 时间线视图：合并画作与笔记本页面，按更新时间倒序展示。
  Widget _buildTimelineTab() {
    // 条目携带跳转目标：画作 -> meta；页面 -> 笔记本 + 页面。
    final entries =
        <
          ({
            DateTime time,
            String type,
            String title,
            String sub,
            DocumentMeta? drawing,
            Notebook? notebook,
            NotebookPage? page,
          })
        >[];
    for (final m in _documents) {
      entries.add((
        time: m.updatedAt,
        type: '画作',
        title: m.title,
        sub: '画作',
        drawing: m,
        notebook: null,
        page: null,
      ));
    }
    for (final nb in _notebooks) {
      for (final p in nb.pages) {
        entries.add((
          time: p.updatedAt,
          type: '页面',
          title: '${nb.title} / ${p.title}',
          sub: p.folder.isNotEmpty ? '📁 ${p.folder}' : nb.title,
          drawing: null,
          notebook: nb,
          page: p,
        ));
      }
    }
    entries.sort((a, b) => b.time.compareTo(a.time));
    if (entries.isEmpty) {
      return const Center(
        child: Text('还没有任何内容，先新建画作或笔记本吧', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          return ListTile(
            leading: Icon(e.type == '画作' ? Icons.brush : Icons.menu_book),
            title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${e.sub} · ${_formatTime(e.time)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 可用性修复：时间线条目可点击跳转（此前点击无反应）。
            onTap: e.drawing != null
                ? () => _openDrawing(e.drawing!)
                : () => _openTimelineNotebook(e.notebook!),
          );
        },
      ),
    );
  }

  /// 时间线页面条目跳转：打开对应笔记本（加密笔记本会先要求输入密码）。
  Future<void> _openTimelineNotebook(Notebook nb) async {
    if (nb.encrypted) {
      await _openNotebook(nb);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        // 统一架构 V2（2026-08-22）：打开笔记本 → EditorV2Screen（note 模式——
        // 单独界面 + 功能共通——替代 V1 NotebookViewPage（material_ui）。
        builder: (_) => EditorV2Screen(
          documentId: nb.id,
          mode: UnifiedEditorMode.note,
        ),
      ),
    );
  }

  // ---------------- 画作 Tab ----------------

  Widget _buildDrawingsTab() {
    if (_documents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有无限画布，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.pagePadding,
          12,
          AppDesign.pagePadding,
          96,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 256,
          childAspectRatio: 0.82,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _documents.length,
        itemBuilder: (context, i) => _DrawingCard(
          meta: _documents[i],
          onTap: () => _openDrawing(_documents[i]),
          onDelete: () => _deleteDrawing(_documents[i]),
        ),
      ),
    );
  }

  // ---------------- 笔记本 Tab ----------------

  Widget _buildNotebooksTab() {
    if (_notebooks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('还没有笔记本，点击右下角按钮新建一个吧'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.pagePadding,
          8,
          AppDesign.pagePadding,
          96,
        ),
        itemCount: _notebooks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final nb = _notebooks[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
                child: const Icon(Icons.menu_book_rounded),
              ),
              title: Text(
                nb.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${nb.pages.length} 页 · 更新于 ${_formatTime(nb.updatedAt)}',
                ),
              ),
              trailing: IconButton(
                tooltip: '删除笔记本',
                icon: const Icon(Icons.delete_outline_rounded),
                color: Theme.of(context).colorScheme.error,
                onPressed: () => _deleteNotebook(nb),
              ),
              onTap: () => _openNotebook(nb),
            ),
          );
        },
      ),
    );
  }

  /// 打开笔记本：若已启用加密（C3/keyfile），先解锁后再进入。
  ///
  /// [initialPageId]：搜索高亮跳转的命中页 ID——加密笔记本进入
  /// NotebookViewPage 后自动打开该页；非加密笔记本走 EditorV2Screen
  /// （其暂无分页定位 API，待 EditorV2 分页能力落地后接入）。
  Future<void> _openNotebook(Notebook nb, {String? initialPageId}) async {
    var notebook = nb;
    // 会话内密码（仅内存，不落盘）：解密后传入页面，使编辑后能重加密保存。
    String? password;
    // 会话内 U盘主密钥（keyfile 模式）：插盘解锁后传入页面。
    List<int>? masterKey;
    if (nb.encrypted) {
      if (nb.encryptionMode == EncryptionMode.keyfile) {
        // U盘钥匙模式：弹密码盘选择目录 → 读取主密钥 → 解锁。
        final disk = createPasswordDisk();
        final dir = await disk.pickDirectory();
        if (dir == null || !mounted) return;
        masterKey = await disk.readKey(dir);
        if (masterKey == null) {
          _showSnack('未找到有效的密码盘（key.frogkey）');
          return;
        }
        final fresh = await _nbStorage.load(nb.id);
        if (fresh == null) return;
        try {
          final ok = await _nbStorage.decryptNotebookWithKey(fresh, masterKey);
          if (!ok) {
            _showSnack('密码盘无法解锁该笔记本');
            return;
          }
          notebook = fresh;
          _maybeWarnLegacyEncryption(fresh);
        } catch (_) {
          _showSnack('密码盘无法解锁该笔记本');
          return;
        }
      } else {
        password = await showDialog<String>(
          context: context,
          builder: (ctx) => const _PasswordDialog(title: '输入密码'),
        );
        if (password == null || !mounted) return;
        // 从存储重新加载（确保拿到密文载荷），用密码解密。
        final fresh = await _nbStorage.load(nb.id);
        if (fresh == null) return;
        try {
          final ok = await _nbStorage.decryptNotebook(fresh, password);
          if (!ok) {
            _showSnack('密码错误或数据已损坏');
            return;
          }
          notebook = fresh;
          await _upgradeLegacyPasswordEncryption(fresh, password);
          // H-03 密码模式媒体加密（方案 B）：解锁后全局盐派生注入
          // （媒体解密 key 与加密时一致）。
          final mediaSalt = await _nbStorage.ensureMediaSalt();
          await MediaCryptoService.instance
              .setSessionPassword(password, mediaSalt);
        } catch (_) {
          _showSnack('密码错误或数据已损坏');
          return;
        }
      }
    }
    if (!mounted) return;
    // 非加密笔记本 → EditorV2Screen（note 模式——#13 持久化修复）。
    // 加密笔记本 → NotebookViewPage（旧版流程——密码/密钥管理复杂，暂不迁移）。
    if (!notebook.encrypted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorV2Screen(
            documentId: notebook.id,
            mode: UnifiedEditorMode.note,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotebookViewPage(
            notebook: notebook,
            storage: _nbStorage,
            onChanged: _refresh,
            sessionPassword: password,
            sessionMasterKey: masterKey,
            initialPageId: initialPageId,
          ),
        ),
      );
    }
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
} 