import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/home/presentation/folder_tree_builder.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 主页 —— 文件夹目录式的层级浏览。
///
/// 所有内容按文件夹路径组织成可展开的层级目录，并且【同一个文件夹里既能
/// 放画板，也能放笔记页】——画板与笔记不再割裂成两页。点击文件即可打开，
/// 每个文件可通过菜单移动到任意文件夹（跨层级）。
///
/// 数据由 app 组合层通过 [loadNotebooks] / [onOpenNotebook] / [onMoveNote]
/// 注入，页面只依赖 notes / drawing 的 domain 实体与 core 存储，避免触碰
/// 其它 feature 的 infrastructure/presentation 边界。
class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({
    super.key,
    this.storage,
    this.loadNotebooks,
    this.onOpenNotebook,
    this.onMoveNote,
    this.editorPageBuilder,
  });

  final StorageService? storage;
  final Future<List<Notebook>> Function()? loadNotebooks;
  final void Function(String notebookId)? onOpenNotebook;
  final Future<void> Function(String notebookId, String pageId, String newFolder)?
      onMoveNote;
  final EditorPageBuilder? editorPageBuilder;

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  FolderTree? _tree;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docsFuture = widget.storage?.listDocuments();
    final nbsFuture = widget.loadNotebooks?.call();
    final docs = await (docsFuture ?? Future.value(const <DocumentMeta>[]));
    final nbs = await (nbsFuture ?? Future.value(const <Notebook>[]));
    if (!mounted) return;
    setState(() {
      _tree = FolderTree.build(docs: docs, notebooks: nbs);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AmbientBackground(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(scheme)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppDesign.pagePadding,
                  4,
                  AppDesign.pagePadding,
                  AppDesign.pagePadding,
                ),
                sliver: _buildBody(scheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    final counts = _counts();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.pagePadding,
        16,
        AppDesign.pagePadding,
        12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主页',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${counts.$1} 个文件夹 · ${counts.$2} 个文件',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (int, int) _counts() {
    final tree = _tree;
    if (tree == null) return (0, 0);
    var folders = 0;
    var files = 0;
    void walk(FolderNode n) {
      folders += n.children.length;
      files += n.items.length;
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(tree.root);
    return (folders, files);
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final tree = _tree;
    if (tree == null || (tree.root.children.isEmpty && tree.root.items.isEmpty)) {
      return SliverToBoxAdapter(
        child: _emptyState(scheme),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        ..._buildItemsFor(tree.root),
      ]),
    );
  }

  List<Widget> _buildItemsFor(FolderNode node) {
    final out = <Widget>[];

    // 先放本层的文件（画板 + 笔记混排）
    for (final item in node.items) {
      out.add(_itemTile(item));
      out.add(const SizedBox(height: 8));
    }

    // 再放本层的子文件夹
    for (final child in node.children) {
      out.add(_folderTile(child));
      out.add(const SizedBox(height: 8));
    }

    return out;
  }

  Widget _folderTile(FolderNode node) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius:
          const BorderRadius.all(Radius.circular(AppDesign.controlRadius)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          shape: const RoundedRectangleBorder(),
          leading: Icon(Icons.folder_outlined,
              color: scheme.tertiary, size: 22),
          title: Text(
            node.name,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
          ),
          subtitle: Text(
            '${node.children.length} 个文件夹 · ${node.items.length} 个文件',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: _buildItemsFor(node),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemTile(FolderItem item) {
    final scheme = Theme.of(context).colorScheme;
    final isCanvas = item.kind == FolderItemKind.canvas;

    return GlassSurface(
      borderRadius:
          const BorderRadius.all(Radius.circular(AppDesign.controlRadius)),
      child: InkWell(
        onTap: () => _openItem(item),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppDesign.controlRadius)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (isCanvas
                          ? scheme.primaryContainer
                          : scheme.tertiaryContainer)
                      .withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppDesign.controlRadius),
                  ),
                ),
                child: Icon(
                  isCanvas ? Icons.brush_outlined : Icons.edit_note,
                  size: 20,
                  color: isCanvas ? scheme.primary : scheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? '未命名' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCanvas ? '画板' : '笔记',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移动到文件夹…',
                onPressed: () => _moveItem(item),
                icon: Icon(Icons.folder_outlined,
                    size: 18, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return GlassSurface(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      borderRadius:
          const BorderRadius.all(Radius.circular(AppDesign.cardRadius)),
      child: Column(
        children: [
          Icon(Icons.folder_open_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text('还没有内容', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '去「画板 · 笔记本」页画点东西或写几页笔记，就会以文件夹的方式整理在这里。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _openItem(FolderItem item) async {
    if (item.kind == FolderItemKind.canvas) {
      final storage = widget.storage;
      final builder = widget.editorPageBuilder;
      if (storage == null || builder == null) return;
      final doc = await storage.load(item.drawingId ?? '');
      if (doc == null || !mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => builder(document: doc, documentStorage: storage),
        ),
      );
      return;
    }
    widget.onOpenNotebook?.call(item.notebookId ?? '');
  }

  Future<void> _moveItem(FolderItem item) async {
    final path = await _promptFolderPath(item.title);
    if (path == null) return;

    if (item.kind == FolderItemKind.canvas) {
      final storage = widget.storage;
      if (storage == null) return;
      final doc = await storage.load(item.drawingId ?? '');
      if (doc == null) return;
      doc.folder = path;
      await storage.save(doc);
    } else {
      await widget.onMoveNote?.call(
        item.notebookId ?? '',
        item.pageId ?? '',
        path,
      );
    }
    await _load();
  }

  Future<String?> _promptFolderPath(String itemTitle) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移动到文件夹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '「$itemTitle」 的文件夹路径，用 / 分隔层级（留空为根目录）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '路径，如 工作/项目A',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('移动'),
          ),
        ],
      ),
    );
    return result;
  }
}
