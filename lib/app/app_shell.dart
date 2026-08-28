import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/home/presentation/home_dashboard_page.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notes_writing_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/schedule/domain/schedule_entry.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_page.dart';

/// 应用导航壳：4 个顶层目的地。
///
/// 信息架构（对齐 AFFiNE 的「根枢纽 + 多分区」分层）：
///   0. 主页      —— 首页枢纽
///   1. 画板·笔记本 —— 当前核心（画板 / 笔记本库）【复用现有 HomePage】
///   2. 日程·日期  —— 按日期组织 / 日程
///   3. 纯笔记    —— 直接打字的笔记页
///
/// 响应式：宽屏（>= [_railBreakpoint]）用侧边栏 [NavigationRail]，
///         窄屏用底部 [NavigationBar]。两端共享同一导航模型与状态。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.notebookStorage,
    this.docStorage,
    this.themeController,
    this.editorPageBuilder,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;
  final AppThemeController? themeController;
  final EditorPageBuilder? editorPageBuilder;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 宽屏断点：>=900 判定为桌面/平板，用侧边栏。
  static const double _railBreakpoint = 900;

  int _index = 0;

  /// 4 个目的地。用 [IndexedStack] 承载，保持各自状态（切走再切回不丢）。
  late final List<Widget> _destinations = [
    HomeDashboardPage(
      storage: widget.docStorage,
      loadNotebooks: () async => widget.notebookStorage?.listAll() ?? const [],
      onOpenNotebook: _openNotebook,
      onMoveNote: (notebookId, pageId, newFolder) =>
          _moveNote(notebookId, pageId, newFolder),
      editorPageBuilder: widget.editorPageBuilder,
    ),
    HomePage(
      notebookStorage: widget.notebookStorage,
      docStorage: widget.docStorage,
      themeController: widget.themeController,
      editorPageBuilder: widget.editorPageBuilder,
    ),
    SchedulePage(
      storage: widget.docStorage,
      loadNotebooks: () async => widget.notebookStorage?.listAll() ?? const [],
      onOpen: _openEntry,
    ),
    const NotesWritingPage(),
  ];

  /// 底部导航栏（窄屏）目的地：[NavigationBar] 的 [NavigationDestination]。
  List<NavigationDestination> _barDestinations() {
    return const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '主页',
      ),
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: '画板·笔记本',
      ),
      NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: '日程',
      ),
      NavigationDestination(
        icon: Icon(Icons.edit_note_outlined),
        selectedIcon: Icon(Icons.edit_note),
        label: '笔记',
      ),
    ];
  }

  /// 侧边栏（宽屏）目的地：[NavigationRail] 的 [NavigationRailDestination]。
  List<NavigationRailDestination> _railDestinations() {
    return const [
      NavigationRailDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: Text('主页'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('画板·笔记本'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_today),
        label: Text('日程'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.edit_note_outlined),
        selectedIcon: Icon(Icons.edit_note),
        label: Text('笔记'),
      ),
    ];
  }

  /// 日程看板里点击某条记录 -> 跳转到对应页面。
  Future<void> _openEntry(ScheduleEntry entry) async {
    final nav = Navigator.of(context, rootNavigator: true);

    if (entry.kind == ScheduleEntryKind.drawing) {
      final storage = widget.docStorage;
      if (storage == null) return;
      final doc = await storage.load(entry.id);
      if (doc == null) return;
      final builder = widget.editorPageBuilder;
      nav.push(
        MaterialPageRoute(
          builder: (_) => builder != null
              ? builder(document: doc, documentStorage: storage)
              : const Scaffold(
                  body: Center(child: Text('编辑器尚未由应用层装配')),
                ),
        ),
      );
      return;
    }

    await _openNotebook(entry.notebookId ?? '');
  }

  /// 打开某个笔记本（用于日程看板 / 主页文件夹的笔记条目跳转）。
  Future<void> _openNotebook(String notebookId) async {
    final nbStorage = widget.notebookStorage;
    if (nbStorage == null) return;
    final nav = Navigator.of(context, rootNavigator: true);
    final nb = await nbStorage.load(notebookId);
    if (nb == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: nb,
          storage: nbStorage,
          editorPageBuilder: widget.editorPageBuilder,
        ),
      ),
    );
  }

  /// 把某个笔记本页移动到指定文件夹路径（主页文件夹视图「移动到」）。
  Future<void> _moveNote(
    String notebookId,
    String pageId,
    String newFolder,
  ) async {
    final nbStorage = widget.notebookStorage;
    if (nbStorage == null) return;
    final nb = await nbStorage.load(notebookId);
    if (nb == null) return;
    var changed = false;
    for (final page in nb.pages) {
      if (page.id == pageId) {
        page.folder = newFolder;
        changed = true;
        break;
      }
    }
    if (changed) {
      await nbStorage.save(nb);
    }
  }

  void _onSelect(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _railBreakpoint;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _onSelect,
                  labelType: NavigationRailLabelType.all,
                  destinations: _railDestinations(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(index: _index, children: _destinations),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          body: IndexedStack(index: _index, children: _destinations),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onSelect,
            destinations: _barDestinations(),
          ),
        );
      },
    );
  }
}
