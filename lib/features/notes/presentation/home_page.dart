import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
// 批次②：单文件密码需与开屏密码比对（matchesAppLockPin 静态探测）。
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/shared/application/search_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/block_doc_search_accessor_impl.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
// 批次②：单文件密码——移除密码需回封 v1 主密钥信封，锁定时 fail-closed。
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart'
    show VaultFileException, VaultFileLockException;
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/onboarding.dart';
// N1 命名统一：画布 tab FAB 弹两选项（新建无限画布/新建分页画布）——
// 分页画布新建入口恢复（M12 曾移除「新建笔记本」入口）。
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/features/doc/application/doc_templates.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/search_page.dart';
// 首页刷新修复②（2026-09-01）：RouteAware 可见性兜底——从编辑器/笔记本页
// 返回时自动刷新，覆盖所有遗漏的写路径（IndexedStack 保活下 initState 不再执行）。
import 'package:drawing_notes_app/fix/security_and_sync_fix.dart'
    show SyncFix, SyncFixRouteAware, UnlockFlow;
// N4 批 2：忘记密码重置流 + 设密时插盘绑定重置密码盘。
import 'package:drawing_notes_app/fix/file_password_reset_flow.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';

part 'home_page_widgets.dart';
part 'home_page_tabs.dart';

/// 首页：画布（无限画布 / 分页画布）/ 笔记 两分栏列表管理。
///
/// 三个主工作区：
/// - 无限画布：独立图形、关系图和自由绘制作品；
/// - 分页画布：带纸张模板、文字和资料混排的多页文档（旧「笔记本」）；
/// - 笔记：直接打字的块文档（旧「打字笔记」）。
///
/// 能力：
/// - 新建画布（弹两选项：新建无限画布 / 新建分页画布）/ 新建笔记
/// - 打开、删除（二次确认）
/// - 展示缩略图
///
/// 数据来源：本地文件存储（[StorageService] / [NotebookStorage]），无网络请求。
class HomePage extends StatefulWidget {
  const HomePage({
    this.refreshSignal,
    super.key,
    this.notebookStorage,
    this.docStorage,
    this.editorPageBuilder,
    this.loadDocs,
    this.onOpenDoc,
    this.blockDocStore,
    this.onDataChanged,
  });

  final NotebookStorage? notebookStorage;
  final StorageService? docStorage;

  /// 编辑器页面由应用组合根注入，notes 模块不直接依赖 drawing 的 UI。
  final EditorPageBuilder? editorPageBuilder;

  /// 数据版本通知（shell 在文档新增/修改后自增）：触发首页刷新。
  final ValueListenable<int>? refreshSignal;

  /// 统一数据源（M12.4）：与 All Docs 共用同一装配 loader（buildAllDocs 三源）。
  /// 笔记 Tab 数据 = 装配结果中 kind∈{note, blockdoc} 的条目——
  /// 从根本上保证两处列表一致（用户反馈的"页面列表不同步"根因即双源分裂）。
  final Future<AllDocQueryResult> Function()? loadDocs;

  /// 块文档存储（R2 列表同步修复）：注入 shell 同一实例——
  /// 自建实例会导致 AllDocs 侧 listDocHeaders 缓存不失效（新笔记不显示）。
  final NoteBlockDocStore? blockDocStore;

  /// 数据变更通知（新建/删除/重命名后调用，驱动 AllDocs 刷新）。
  final VoidCallback? onDataChanged;

  /// 统一打开路径：与 All Docs 同一回调（note→NotebookViewPage，
  /// blockdoc→DocPage），保证两处点击行为一致。
  final void Function(AllDoc doc)? onOpenDoc;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SyncFixRouteAware {
  late final NotebookStorage _nbStorage;
  late final StorageService _docStorage;
  late final NoteBlockDocStore _blockDocStore;

  List<AllDoc> _notes = [];
  List<DocumentMeta> _documents = [];
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onDataVersionChanged);
    _nbStorage = widget.notebookStorage ?? NotebookStorage();
    _docStorage = widget.docStorage ?? StorageService();
    _blockDocStore = widget.blockDocStore ?? NoteBlockDocStore();
    _refresh();
    // 首次启动引导（Phase 7）：仅第一次打开时显示，可跳过。
    _showOnboarding();
  }

  void _onDataVersionChanged() {
    if (mounted) _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首页刷新修复②：订阅路由可见性——从笔记本页/编辑器 didPopNext 时刷新。
    SyncFix.routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void onPageVisibleAgain() {
    if (mounted) _refresh();
  }

  @override
  void dispose() {
    SyncFix.routeObserver.unsubscribe(this);
    widget.refreshSignal?.removeListener(_onDataVersionChanged);
    super.dispose();
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
      // 统一数据源（M12.4）：与 All Docs 同一装配；无 loader 时退回块文档单源。
      List<AllDoc> notes;
      final loader = widget.loadDocs;
      if (loader != null) {
        final result = await loader();
        notes = result.docs
            .where(
              (d) => d.kind == AllDocKind.note || d.kind == AllDocKind.blockdoc,
            )
            .toList(growable: false);
      } else {
        final noteIds = await _blockDocStore.listIds();
        notes = <AllDoc>[];
        for (final id in noteIds) {
          final d = await _blockDocStore.loadDocument(id);
          if (d != null) {
            notes.add(
              AllDoc(
                id: d.id,
                title: d.title,
                kind: AllDocKind.blockdoc,
                folder: '',
                createdAt: d.createdAt,
                updatedAt: d.updatedAt,
              ),
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _notes = notes;
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

  // ---------------- 画布（N1：画布 tab 收口无限画布/分页画布两类型） ----------------

  /// 「新建画布」：弹两选项（新建无限画布 / 新建分页画布）——
  /// 命名体系定案（2026-09-02）：无限画布=「画布」，旧笔记本=「分页画布」。
  Future<void> _createCanvas() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('新建画布'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const ListTile(
              leading: Icon(Icons.brush_rounded),
              title: Text('新建无限画布'),
              subtitle: Text('自由绘制、图形与关系图'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const ListTile(
              leading: Icon(Icons.auto_stories_rounded),
              title: Text('新建分页画布'),
              subtitle: Text('多页装订、纸张模板与图文混排'),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice) {
      await _createDrawing();
    } else {
      await _createNotebook();
    }
  }

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

  /// 新建分页画布并进入页面管理（旧「新建笔记本」入口恢复——N1）。
  Future<void> _createNotebook() async {
    final nb = Notebook(
      id: NotebookStorage.newId('notebook'),
      title: '未命名',
    );
    await _nbStorage.save(nb);
    widget.onDataChanged?.call();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: nb,
          storage: _nbStorage,
          blockDocStore: _blockDocStore,
          editorPageBuilder: widget.editorPageBuilder,
        ),
      ),
    );
    await _refresh();
  }

  /// 打开已有画布继续编辑。
  ///
  /// 批次②：受独立密码保护的画布先输密码（4–12 位可变长度密码盘，
  /// 验证成功即缓存进会话，本会话免重复输入）。
  Future<void> _openDrawing(DocumentMeta meta) async {
    try {
      // meta.locked 为列表占位（无会话密码）；再查一次文件头防元信息过期。
      if (meta.locked || await _docStorage.isFilePasswordProtected(meta.id)) {
        final unlocked = await _promptFilePassword(meta);
        if (!unlocked) return; // 用户取消 / 放弃
      }
      final doc = await _docStorage.load(meta.id);
      if (doc == null) {
        _showSnack('画布文件不存在或已损坏');
        return;
      }
      if (!mounted) return;
      await _openEditor(document: doc, documentStorage: _docStorage);
      _refresh();
    } catch (e) {
      _showSnack('打开画布失败：${e.runtimeType}');
    }
  }

  /// 加密画布解锁输入（验证通过密码已入会话缓存）。
  ///
  /// N4 批 2：左下角「忘记密码？」→ 重置密码盘重置流；重置成功后
  /// 会话已缓存新密码，本方法直接返回 true（调用方可继续打开）。
  Future<bool> _promptFilePassword(DocumentMeta meta) async {
    final pin = await UnlockFlow.show(
      context,
      title: '该画布已加密，输入独立密码',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
      footerLabel: '忘记密码？',
      onFooter: () {
        FilePasswordResetFlow.show(
          context,
          storage: _docStorage,
          docId: meta.id,
          docTitle: meta.title,
        );
      },
    );
    // pin 非空 = 验证通过；null 但会话已有密码 = 刚被重置流解锁。
    return pin != null || _docStorage.filePasswordFor(meta.id) != null;
  }

  // ---------------- 单文件密码管理（批次②） ----------------

  /// 画布密码操作 sheet：未设密 → 设置；已设密 → 修改 / 绑定重置盘 / 移除。
  Future<void> _showDrawingPasswordSheet(DocumentMeta meta) async {
    final protected = await _docStorage.isFilePasswordProtected(meta.id);
    final usbBound = protected && await _docStorage.hasFileUsbSlot(meta.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: Text('「${meta.title}」独立密码'),
              subtitle: Text(protected ? '此画布受独立密码保护' : '此画布当前未设置独立密码'),
            ),
            const Divider(height: 1),
            if (!protected)
              ListTile(
                leading: const Icon(Icons.add_moderator_outlined),
                title: const Text('设置独立密码'),
                subtitle: const Text('4–12 位数字，须与开屏密码不同'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startSetFilePassword(meta);
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('修改独立密码'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startChangeFilePassword(meta);
                },
              ),
              if (!usbBound)
                ListTile(
                  leading: const Icon(Icons.usb_rounded),
                  title: const Text('绑定重置密码盘'),
                  subtitle: const Text('绑定后忘记密码可插 U 盘免旧密码重置'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startBindFileUsb(meta);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.no_encryption_outlined),
                title: const Text('移除独立密码'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startRemoveFilePassword(meta);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 独立密码收集（两次一致才生效）；与开屏密码同码直接拒绝。
  Future<String?> _collectNewFilePassword(String title) async {
    final pin = await UnlockFlow.show(context, title: title, flexible: true);
    if (pin == null || !mounted) return null;
    // ≠开屏密码强制（哈希加盐不可比对，用 verify 探测）。
    if (await AppLockService.matchesAppLockPin(pin)) {
      _showSnack('独立密码不能与开屏密码相同');
      return null;
    }
    if (!mounted) return null; // matchesAppLockPin 为异步操作，跨缺口守卫
    final confirm = await UnlockFlow.show(
      context,
      title: '确认独立密码',
      flexible: true,
    );
    if (confirm == null) return null;
    if (confirm != pin) {
      _showSnack('两次输入不一致，请重试');
      return null;
    }
    return pin;
  }

  Future<void> _startSetFilePassword(DocumentMeta meta) async {
    final pin = await _collectNewFilePassword('设置独立密码');
    if (pin == null) return;
    if (!mounted) return;
    // N4 批 2：可选当场绑定重置密码盘（错过本次可事后在密码管理中绑定）。
    List<int>? resetDiskKey;
    final bindUsb = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('绑定重置密码盘？'),
        content: const Text(
          '绑定后忘记此画布的独立密码时，可插入重置密码盘（U 盘）免旧密码重置。\n\n'
          'U 盘上只有随机钥匙文件（password_reset_disk.key），画布数据不会离开设备。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('插盘绑定'),
          ),
        ],
      ),
    );
    if (bindUsb == true) {
      if (!mounted) return;
      final dir = await ResetDiskFile.pickDirectory();
      if (dir != null) {
        resetDiskKey = await ResetDiskFile.readFrom(dir);
        if (resetDiskKey == null && mounted) {
          _showSnack('未找到有效的重置密码盘文件（password_reset_disk.key），本次不绑定');
        }
      }
    }
    try {
      await _docStorage.setFilePassword(meta.id, pin, resetDiskKey: resetDiskKey);
      _showSnack(
        resetDiskKey == null
            ? '已为「${meta.title}」设置独立密码'
            : '已为「${meta.title}」设置独立密码并绑定重置密码盘',
      );
      await _refresh();
    } on VaultFileLockException {
      _showSnack('加密底座已锁定：请重新验证开屏密码后再设置');
    } catch (e) {
      _showSnack('设置失败：${e.runtimeType}');
    }
  }

  Future<void> _startChangeFilePassword(DocumentMeta meta) async {
    final old = await UnlockFlow.show(
      context,
      title: '验证当前独立密码',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
    );
    if (old == null || !mounted) return;
    final pin = await _collectNewFilePassword('设置新密码');
    if (pin == null) return;
    try {
      await _docStorage.changeFilePassword(meta.id, old, pin);
      _showSnack('已修改「${meta.title}」的独立密码');
      await _refresh();
    } on VaultFileException {
      _showSnack('原密码不正确或密文已损坏');
    } catch (e) {
      _showSnack('修改失败：${e.runtimeType}');
    }
  }

  /// 事后绑定重置密码盘（N4 批 2）：验证文件密码 → 插盘 → 嵌入 USB 槽位。
  Future<void> _startBindFileUsb(DocumentMeta meta) async {
    final pin = await UnlockFlow.show(
      context,
      title: '验证独立密码以绑定重置盘',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
    );
    if (pin == null || !mounted) return;
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !mounted) return;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      _showSnack('未找到有效的重置密码盘文件（password_reset_disk.key）');
      return;
    }
    try {
      await _docStorage.bindFileUsbSlot(meta.id, pin, usbKey);
      _showSnack('已为「${meta.title}」绑定重置密码盘');
      await _refresh();
    } on StateError catch (e) {
      _showSnack(e.message);
    } on VaultFileException {
      _showSnack('密码不正确或密文已损坏');
    } catch (e) {
      _showSnack('绑定失败：${e.runtimeType}');
    }
  }

  Future<void> _startRemoveFilePassword(DocumentMeta meta) async {
    final ok = await _confirmDelete(
      '移除独立密码',
      '移除后「${meta.title}」将回到加密底座保护（主密钥信封），不再需要独立密码。确定移除吗？',
    );
    if (ok != true) return;
    if (!mounted) return; // _confirmDelete 为异步操作，跨缺口守卫
    final pin = await UnlockFlow.show(
      context,
      title: '验证独立密码以移除',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
    );
    if (pin == null) return;
    try {
      await _docStorage.removeFilePassword(meta.id, pin);
      _showSnack('已移除「${meta.title}」的独立密码');
      await _refresh();
    } on VaultFileLockException {
      // fail-closed：绝不回明文。
      _showSnack('加密底座已锁定，无法回封：请重新验证开屏密码后再试');
    } on VaultFileException {
      _showSnack('密码不正确或密文已损坏');
    } catch (e) {
      _showSnack('移除失败：${e.runtimeType}');
    }
  }

  /// 删除画作（二次确认）。
  Future<void> _deleteDrawing(DocumentMeta meta) async {
    final ok = await _confirmDelete('删除画布', '确定删除画布「${meta.title}」吗？此操作不可恢复。');
    if (ok != true) return;
    try {
      await _docStorage.delete(meta.id);
      await _refresh();
    } catch (e) {
      _showSnack('删除失败：${e.runtimeType}');
    }
  }

  // ---------------- 笔记（块文档；M12：笔记本=笔记） ----------------

  Future<void> _createNote() async {
    // M12.6 模板库：新建时选择模板（空白/会议纪要/每日日志/待办清单）。
    final template = await showDialog<DocTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择笔记模板'),
        children: [
          for (final t in DocTemplate.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(t),
              child: ListTile(
                leading: Icon(_templateIcon(t)),
                title: Text(t.label),
                subtitle: Text(t.description),
              ),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;

    var blockId = 0;
    final doc = NoteBlockDoc(
      id: NoteBlockDocStore.newId(),
      body: buildTemplateBody(template, () => 'block_${blockId++}'),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _blockDocStore.saveDocument(doc);
    widget.onDataChanged?.call();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: doc,
          controller: DocController(
            onSave: (d) => _blockDocStore.saveDocument(d),
          ),
        ),
      ),
    );
    await _refresh();
  }

  /// 模板 → 图标（application 层不依赖 material，图标在展示层映射）。
  IconData _templateIcon(DocTemplate t) {
    switch (t) {
      case DocTemplate.blank:
        return Icons.crop_square_rounded;
      case DocTemplate.meeting:
        return Icons.groups_rounded;
      case DocTemplate.daily:
        return Icons.today_rounded;
      case DocTemplate.todoList:
        return Icons.checklist_rounded;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // 画布（无限画布/分页画布）/ 笔记（M11：「最近」时间线并入日历页）
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
                      blockDocAccessor: BlockDocSearchAccessorImpl(
                        store: _blockDocStore,
                      ),
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
            // 批次⑤：WebDAV/外观/应用锁/密码盘入口已收编至第四界面「设置」，
            // 顶栏只保留搜索与回收站两个文档操作。
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
                    Tab(text: '画布'),
                    Tab(text: '笔记'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: AmbientBackground(child: _buildBody()),
        floatingActionButton: _tabIndex == 0
            ? FloatingActionButton.extended(
                onPressed: _createCanvas,
                icon: const Icon(Icons.add),
                label: const Text('新建画布'),
              )
            : FloatingActionButton.extended(
                onPressed: _createNote,
                icon: const Icon(Icons.add),
                label: const Text('新建笔记'),
              ),
      ),
    );
  }
}
