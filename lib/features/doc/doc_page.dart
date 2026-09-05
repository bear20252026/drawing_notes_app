// M12 笔记页（AFFiNE Page 1:1）：独立于画板的文档页面模块。
//
// 参照 AFFiNE（MIT, © 2020-present toeverything）Page 视图的交互与信息架构，
// 版权声明见 THIRD_PARTY_NOTICES.md。本模块与画板模块（features/notes 的
// edgeless/drawing 部分）零交叉引用：画板打开文档经由导航跳转到本模块。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/layout/responsive.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;
import 'package:drawing_notes_app/features/security/block_doc_password_reset_flow.dart';
import 'package:drawing_notes_app/features/doc/application/doc_export_io.dart';
import 'package:drawing_notes_app/features/doc/application/doc_link_index.dart';
import 'package:drawing_notes_app/features/doc/application/doc_html_export.dart';
import 'package:drawing_notes_app/features/doc/application/doc_pdf_adapter.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_markdown.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/doc/doc_outline_rail.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

part 'doc_page_widgets.dart';

/// 分享占位提示（桌面按钮与移动端图标共用）。
void _showShareSnackBar(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('分享功能即将支持')));
}

/// AFFiNE 式笔记页：白底、居中窄栏、顶栏（收藏/信息/更多/分享）、右缘大纲。
///
/// 与画板完全分离：
/// - 不使用环境背景 / 玻璃拟态（画板视觉）；
/// - 不内嵌画布组件；「在画布中打开」经 [onOpenInEdgeless] 回调由宿主路由。
class DocPage extends StatefulWidget {
  const DocPage({
    super.key,
    required this.document,
    this.controller,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onOpenInEdgeless,
    this.tagStore,
    this.allDocsLoader,
    this.onOpenDocById,
    this.blockDocStore,
  });

  /// 要编辑的笔记文档。
  final NoteBlockDoc document;

  /// 文档控制器（持久化由宿主注入；为 null 时仅编辑不落盘）。
  final DocController? controller;

  /// 当前收藏态（受控）。
  final bool isFavorite;

  /// 收藏切换回调。
  final ValueChanged<bool>? onToggleFavorite;

  /// 「在画布中打开」回调（宿主负责转换与路由）。
  final VoidCallback? onOpenInEdgeless;

  /// 标签注册表（M12.6 标签编辑）；null 时内部自建（全局文件）。
  final TagStore? tagStore;

  /// 全量块文档读取（M12.7 反向链接索引用）；null 时隐藏反向链接面板。
  final Future<List<NoteBlockDoc>> Function()? allDocsLoader;

  /// 点击反向链接条目打开对应文档（宿主路由）。
  final void Function(String docId)? onOpenDocById;

  /// 块文档存储（P3 装配一致性）：未显式提供 allDocsLoader/onOpenDocById
  /// 时，用它在 DocPage 内部自建反向链接索引数据源与点击路由——
  /// 各入口（搜索/笔记本管理/首页）无需各自接线即可获得完整能力。
  final NoteBlockDocStore? blockDocStore;

  @override
  State<DocPage> createState() => _DocPageState();
}

/// 保存状态（AFFiNE 语义：未保存 → 保存中 → 已保存）。
enum _SaveStatus { unsaved, saving, saved }

class _DocPageState extends State<DocPage> {
  late NoteBlockDoc _doc;
  bool _favorite = false;
  bool _outlineOpen = false;
  _SaveStatus _saveStatus = _SaveStatus.saved;
  DateTime? _lastSavedAt;
  final GlobalKey<DocEditorState> _editorKey = GlobalKey<DocEditorState>();

  /// 是否有待写盘改动（P0-H2 退出 flush 判据）。
  bool _pendingChanges = false;

  late final SaveScheduler _saveScheduler = SaveScheduler(
    save: () async {
      final editor = _editorKey.currentState;
      if (editor == null) return;
      final doc = editor.saveNow();
      _doc = doc;
      // P0-H1：等磁盘写完才返回——scheduler.onSaved 在此之后触发，
      // 「已保存」状态不再早于落盘。原实现此处与 _persist 各写一次（双写）。
      await widget.controller?.save(doc);
    },
    onSaved: () {
      if (!mounted) return;
      setState(() {
        _saveStatus = _SaveStatus.saved;
        _lastSavedAt = DateTime.now();
        _pendingChanges = false;
      });
    },
    onError: (e, st) {
      // P0-H1：保存失败必须让用户知道（原仅 debugPrint）。
      if (mounted) {
        setState(() => _saveStatus = _SaveStatus.unsaved);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试或手动保存')));
      }
    },
  );

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _favorite = widget.isFavorite;
  }

  @override
  void dispose() {
    _saveScheduler.dispose();
    super.dispose();
  }

  /// 编辑变为脏：显示"未保存"并交由 SaveScheduler 防抖自动保存。
  void _onEditorDirty() {
    _pendingChanges = true;
    if (mounted && _saveStatus != _SaveStatus.unsaved) {
      setState(() => _saveStatus = _SaveStatus.unsaved);
    }
    _saveScheduler.markDirty();
  }

  /// 手动保存：立即落盘（保存中 → 已保存 由调度器回调驱动）。
  Future<void> _saveNow() async {
    if (mounted) setState(() => _saveStatus = _SaveStatus.saving);
    await _saveScheduler.saveNow();
  }

  String _statusLabel() {
    switch (_saveStatus) {
      case _SaveStatus.unsaved:
        return '未保存';
      case _SaveStatus.saving:
        return '保存中…';
      case _SaveStatus.saved:
        final t = _lastSavedAt;
        if (t == null) return '已保存';
        return '已保存 '
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  void didUpdateWidget(DocPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.document != oldWidget.document) {
      _doc = widget.document;
    }
    if (widget.isFavorite != oldWidget.isFavorite) {
      _favorite = widget.isFavorite;
    }
  }

  /// 通用导出：转换后经 [writeExportFile] 落盘，Snack 提示路径。
  Future<void> _export({
    required String extension,
    required String Function(NoteBlockDoc doc) convert,
    required String label,
  }) async {
    try {
      final doc = _editorKey.currentState?.currentDoc ?? _doc;
      final path = await writeExportFile(
        baseName: doc.title.isEmpty ? '未命名' : doc.title,
        extension: extension,
        content: convert(doc),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出 $label：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败，请重试')));
    }
  }

  /// 导出门禁（P1-M1）：md/html/pdf 均需白名单放行，fail-closed。
  bool _exportAllowed(String operation) {
    final result = const PolicyEngine().enforceCheck(operation);
    if (!result.isAllowed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作被策略拒绝（$operation）')));
    }
    return result.isAllowed;
  }

  /// 导出 Markdown / HTML / PDF（AFFiNE Export 对齐）。
  Future<void> _exportMarkdown() {
    if (!_exportAllowed('note.export.markdown')) return Future.value();
    return _export(
      extension: 'md',
      convert: noteBlockDocToMarkdown,
      label: 'Markdown',
    );
  }

  Future<void> _exportHtml() {
    if (!_exportAllowed('note.export.html')) return Future.value();
    return _export(
      extension: 'html',
      convert: noteBlockDocToHtml,
      label: 'HTML',
    );
  }

  Future<void> _exportPdf() {
    if (!_exportAllowed('note.export.pdf')) return Future.value();
    return _exportPdfBytes();
  }

  Future<void> _exportPdfBytes() async {
    try {
      final doc = _editorKey.currentState?.currentDoc ?? _doc;
      final bytes = await noteBlockDocToPdf(doc);
      final path = await writeExportFileBytes(
        baseName: doc.title.isEmpty ? '未命名' : doc.title,
        extension: 'pdf',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出 PDF：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败，请重试')));
    }
  }

  void _persist(NoteBlockDoc doc) {
    // P0-H1：仅同步快照到页面状态；「已保存」状态与落盘一律由
    // SaveScheduler（await 写盘后的 onSaved）单一驱动，消除假已保存。
    setState(() {
      _doc = doc;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // P0-H2：有未落盘改动时拦截返回，先 flush（saveNow 同步等待写盘）
    // 再真正退出——消除防抖窗口内的编辑丢失。
    return PopScope(
      canPop: !_pendingChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveScheduler.saveNow();
        if (!mounted) return;
        setState(() => _pendingChanges = false);
        Navigator.of(this.context).pop();
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF1A1A1E) : Colors.white,
        appBar: _DocHeader(
          title: _doc.title,
          isFavorite: _favorite,
          outlineOpen: _outlineOpen,
          statusLabel: _statusLabel(),
          statusColor: _saveStatus == _SaveStatus.unsaved
              ? const Color(0xFFF5A623)
              : (_saveStatus == _SaveStatus.saving
                    ? scheme.primary
                    : const Color(0xFF30D158)),
          onSavePressed: _saveNow,
          onToggleFavorite: () {
            setState(() => _favorite = !_favorite);
            widget.onToggleFavorite?.call(_favorite);
          },
          // 桌面切换右缘停靠栏；移动端弹底部半屏面板（240 固定窄栏在手机上
          // 会吃掉约 60% 屏宽）。
          onToggleOutline: _onToggleOutline,
          onShowInfo: () => _showInfoDialog(context),
          onOpenInEdgeless: widget.onOpenInEdgeless,
          onExportMarkdown: _exportMarkdown,
          onExportHtml: _exportHtml,
          onInsertPageLink: _insertPageLink,
          onExportPdf: _exportPdf,
          onManagePassword: widget.blockDocStore == null
              ? null
              : _showPasswordSheet,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: DocEditor(
                          key: _editorKey,
                          showChrome: false,
                          document: _doc,
                          onSave: _persist,
                          onDirty: _onEditorDirty,
                        ),
                      ),
                      // 反向链接面板（M12.7，AFFiNE Backlinks 对齐）：
                      // 列出引用了本文档的笔记，点击跳转。
                      if (_effectiveAllDocsFuture != null)
                        _BacklinksPanel(
                          currentDoc: _doc,
                          docsFuture: _effectiveAllDocsFuture!,
                          onOpenDocById:
                              widget.onOpenDocById ?? _openDocByIdInternal,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 右缘大纲（AFFiNE Outline Rail）——仅桌面形态；移动端走底部面板。
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: (isDesktopLayout(context) && _outlineOpen)
                  ? DocOutlineRail(
                      key: const ValueKey('rail-on'),
                      entries: _outlineEntries(),
                      onTapEntry: (id) =>
                          _editorKey.currentState?.scrollToBlock(id),
                      onClose: () => setState(() => _outlineOpen = false),
                    )
                  : const SizedBox.shrink(key: ValueKey('rail-off')),
            ),
          ],
        ),
      ),
    );
  }

  /// 从编辑器抽取大纲条目（桌面停靠栏与移动底部面板共用）。
  List<OutlineEntry> _outlineEntries() => [
    for (final e in _editorKey.currentState?.outline() ?? const [])
      OutlineEntry(id: e.id, level: e.level, text: e.text),
  ];

  /// 大纲开关：桌面切换右缘停靠栏，移动端弹底部半屏面板。
  ///
  /// 移动端不用停靠栏的原因：240 的固定宽度在 ~400dp 手机屏上会吃掉约 60%
  /// 屏宽，正文只剩 160dp（与「全部文档」侧栏同一个坑）。AFFiNE mobile 的
  /// 做法是把这类面板改为 sheet 覆盖层，内容临时浮于正文之上。
  void _onToggleOutline() {
    if (!isDesktopLayout(context)) {
      showDocOutlineSheet(
        context: context,
        entries: _outlineEntries(),
        onTapEntry: (id) => _editorKey.currentState?.scrollToBlock(id),
      );
      return;
    }
    setState(() => _outlineOpen = !_outlineOpen);
  }

  /// 选择目标文档 → 在文末追加 [[标题]] 页面引用（M12.7 反向链接）。
  Future<void> _insertPageLink() async {
    final all = await _effectiveAllDocsFuture;
    if (all == null || !mounted) return;
    final candidates = all.where((d) => d.id != _doc.id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final target = await GlassDialog.show<NoteBlockDoc>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('插入页面链接'),
        children: [
          for (final d in candidates.take(50))
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(d),
              child: ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: Text(d.title.isEmpty ? '未命名' : d.title),
                subtitle: Text(
                  '更新于 '
                  '${d.updatedAt.year}-'
                  '${d.updatedAt.month.toString().padLeft(2, '0')}-'
                  '${d.updatedAt.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
        ],
      ),
    );
    if (target == null) return;
    _editorKey.currentState?.appendPageLink(target);
  }

  // ── P3 装配一致性：blockDocStore 兜底生成索引数据源与点击路由 ──
  //
  // U5b（审计 P1-19）：列表 Future 首次访问后缓存——反链面板每次保存
  // （updatedAt 变化触发 didUpdateWidget→_reload）原先都新建 Future
  // 全量读盘+解密所有笔记；现复用同一 Future 零 IO，仅内存重算
  // backlinksOf。取舍：本页会话内其他文档的新增/改名不会即时反映到
  // 反链列表（模态编辑页内不发生，宿主层列表始终走自己的加载路径）。
  Future<List<NoteBlockDoc>>? _allDocsFutureCache;

  Future<List<NoteBlockDoc>>? get _effectiveAllDocsFuture {
    final loader = widget.allDocsLoader;
    if (loader != null) return _allDocsFutureCache ??= loader();
    final store = widget.blockDocStore;
    if (store == null) return null;
    return _allDocsFutureCache ??= () async {
      final docs = <NoteBlockDoc>[];
      for (final id in await store.listIds()) {
        try {
          final d = await store.loadDocument(id);
          if (d != null) docs.add(d);
        } on BlockDocLockedException {
          continue; // N2：受密未解锁的笔记不进反向链接索引（fail-closed）
        }
      }
      return docs;
    }();
  }

  void _openDocByIdInternal(String id) {
    final store = widget.blockDocStore;
    if (store == null) return;
    // N2：受密未解锁的笔记点击反向链接 → 先解锁（与宿主路由同口径）。
    store
        .isBlockDocPasswordProtected(id)
        .then((protected) async {
          if (protected && !store.isBlockDocUnlocked(id)) {
            if (!mounted) return false;
            final pin = await UnlockFlow.show(
              context,
              title: '该笔记已加密，输入密码',
              flexible: true,
              onVerify: (p) => store.verifyBlockDocPassword(id, p),
              footerLabel: '忘记密码？',
              onFooter: () {
                BlockDocPasswordResetFlow.show(
                  context,
                  store: store,
                  docId: id,
                );
              },
            );
            if (pin == null && !store.isBlockDocUnlocked(id)) return false;
          }
          return true;
        })
        .then((allowed) async {
          if (allowed != true) return null;
          try {
            return await store.loadDocument(id);
          } on BlockDocLockedException {
            return null; // 会话 DEK 已被清——不暴露内容
          }
        })
        .then((doc) {
          if (!mounted || doc == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DocPage(
                document: doc,
                controller: DocController(onSave: (d) => store.saveDocument(d)),
                blockDocStore: store,
                tagStore: widget.tagStore,
              ),
            ),
          );
        });
  }

  // ── N2：文件密码管理（与画布/分页画布同口径；入口在 ⋯ 菜单） ──

  /// 笔记密码操作 sheet：未设密 → 设置；已设密 → 修改 / 绑定重置盘 / 移除。
  Future<void> _showPasswordSheet() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final protected = await store.isBlockDocPasswordProtected(_doc.id);
    final usbBound = protected && await store.hasBlockDocUsbSlot(_doc.id);
    if (!mounted) return;
    final name = _doc.title.isEmpty ? '未命名' : _doc.title;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: Text('「$name」独立密码'),
              subtitle: Text(protected ? '此笔记受独立密码保护' : '此笔记当前未设置独立密码'),
            ),
            const Divider(height: 1),
            if (!protected)
              ListTile(
                leading: const Icon(Icons.add_moderator_outlined),
                title: const Text('设置独立密码'),
                subtitle: const Text('4–12 位数字，须与开屏密码不同'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startSetPassword();
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('修改独立密码'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startChangePassword();
                },
              ),
              if (!usbBound)
                ListTile(
                  leading: const Icon(Icons.usb_rounded),
                  title: const Text('绑定重置密码盘'),
                  subtitle: const Text('绑定后忘记密码可插 U 盘免旧密码重置'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startBindUsb();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.no_encryption_outlined),
                title: const Text('移除独立密码'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startRemovePassword();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 独立密码收集（两次一致才生效）；与开屏密码同码直接拒绝。
  Future<String?> _collectNewPassword(String title) async {
    final pin = await UnlockFlow.show(context, title: title, flexible: true);
    if (pin == null || !mounted) return null;
    // ≠开屏密码强制（哈希加盐不可比对，用 verify 探测）。
    if (await AppLockService.matchesAppLockPin(pin)) {
      _snack('独立密码不能与开屏密码相同');
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
      _snack('两次输入不一致，请重试');
      return null;
    }
    return pin;
  }

  Future<void> _startSetPassword() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final pin = await _collectNewPassword('设置独立密码');
    if (pin == null) return;
    if (!mounted) return;
    // 可选当场绑定重置密码盘（错过本次可事后在密码管理中绑定）。
    List<int>? resetDiskKey;
    final bindUsb = await GlassDialog.confirm(
      context,
      title: '绑定重置密码盘？',
      content:
          '绑定后忘记此笔记的独立密码时，可插入重置密码盘（U 盘）免旧密码重置。\n\n'
          'U 盘上只有随机钥匙文件（password_reset_disk.key），笔记数据不会离开设备。',
      confirmText: '插盘绑定',
      cancelText: '暂不',
    );
    if (bindUsb == true) {
      if (!mounted) return;
      final dir = await ResetDiskFile.pickDirectory();
      if (dir != null) {
        resetDiskKey = await ResetDiskFile.readFrom(dir);
        if (resetDiskKey == null && mounted) {
          _snack('未找到有效的重置密码盘文件（password_reset_disk.key），本次不绑定');
        }
      }
    }
    try {
      await store.encryptAndSave(_doc, pin, usbKey: resetDiskKey);
      _snack(
        resetDiskKey == null
            ? '已为「${_doc.title.isEmpty ? '未命名' : _doc.title}」设置独立密码'
            : '已设置独立密码并绑定重置密码盘',
      );
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('设置失败，请重试');
    }
  }

  Future<void> _startChangePassword() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final old = await UnlockFlow.show(
      context,
      title: '验证当前独立密码',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(_doc.id, p),
    );
    if (old == null || !mounted) return;
    final pin = await _collectNewPassword('设置新密码');
    if (pin == null) return;
    try {
      await store.changeBlockDocPassword(_doc.id, old, pin);
      _snack('已修改「${_doc.title.isEmpty ? '未命名' : _doc.title}」的独立密码');
    } on FormatException {
      _snack('原密码不正确或密文已损坏');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('修改失败，请重试');
    }
  }

  /// 事后绑定重置密码盘：验证文件密码 → 插盘 → 嵌入 USB 槽位。
  Future<void> _startBindUsb() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final pin = await UnlockFlow.show(
      context,
      title: '验证独立密码以绑定重置盘',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(_doc.id, p),
    );
    if (pin == null || !mounted) return;
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !mounted) return;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      _snack('未找到有效的重置密码盘文件（password_reset_disk.key）');
      return;
    }
    try {
      await store.bindBlockDocUsbSlot(_doc.id, pin, usbKey);
      _snack('已绑定重置密码盘');
    } on FormatException {
      _snack('密码不正确或已绑定重置密码盘');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('绑定失败，请重试');
    }
  }

  Future<void> _startRemovePassword() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final name = _doc.title.isEmpty ? '未命名' : _doc.title;
    final ok = await GlassDialog.confirm(
      context,
      title: '移除独立密码',
      content: '移除后「$name」不再需要独立密码即可打开。确定移除吗？',
      confirmText: '移除',
      dangerous: true,
    );
    if (ok != true) return;
    if (!mounted) return;
    final pin = await UnlockFlow.show(
      context,
      title: '验证独立密码以移除',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(_doc.id, p),
    );
    if (pin == null) return;
    try {
      await store.removeBlockDocPassword(_doc.id, pin);
      _snack('已移除「$name」的独立密码');
    } on FormatException {
      _snack('密码不正确或密文已损坏');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('移除失败，请重试');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 文档信息对话框（含标签编辑——M12.6 标签系统入口）。
  void _showInfoDialog(BuildContext context) {
    final tagStore = widget.tagStore ?? TagStore();
    final title = _doc.title.isEmpty ? '未命名' : _doc.title;
    GlassDialog.show<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('创建于', _fmtDate(_doc.createdAt)),
              _infoRow('更新于', _fmtDate(_doc.updatedAt)),
              _infoRow('块数量', '${_doc.body.length}'),
              const SizedBox(height: 12),
              const Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Flexible(
                child: FutureBuilder<List<DocTag>>(
                  future: tagStore.listTags(),
                  builder: (context, snap) {
                    final allTags = snap.data ?? const <DocTag>[];
                    final assigned = allTags
                        .where((t) => _doc.tags.contains(t.id))
                        .toList();
                    final available = allTags
                        .where((t) => !_doc.tags.contains(t.id))
                        .toList();
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in assigned)
                            Chip(
                              label: Text(t.name),
                              onDeleted: () => _toggleDocTag(t.id),
                            ),
                          for (final t in available)
                            ActionChip(
                              label: Text('+ ${t.name}'),
                              onPressed: () => _toggleDocTag(t.id),
                            ),
                          ActionChip(
                            label: const Icon(Icons.add_rounded, size: 18),
                            onPressed: () => _createTagInline(tagStore),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 给当前文档加/移除标签（编辑即保存）。
  Future<void> _toggleDocTag(String tagId) async {
    final tags = List.of(_doc.tags);
    if (tags.contains(tagId)) {
      tags.remove(tagId);
    } else {
      tags.add(tagId);
    }
    final updated = _doc.copyWith(tags: tags, updatedAt: DateTime.now());
    setState(() => _doc = updated);
    await widget.controller?.save(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
    _showInfoDialog(context);
  }

  /// 快速新建标签（输入名称 → 默认紫色）。
  Future<void> _createTagInline(TagStore tagStore) async {
    final controller = TextEditingController();
    // P3：对话框结束后释放 controller（审计低危 L1）。
    try {
      final name = await GlassDialog.show<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('新建标签'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '标签名称'),
          ),
          actions: AppleDialog.actions([
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('创建'),
            ),
          ]),
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      final tag = await tagStore.addTag(name);
      if (tag != null && !_doc.tags.contains(tag.id)) {
        await _toggleDocTag(tag.id);
      }
    } finally {
      controller.dispose();
    }
  }

  Widget _infoRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}/${d.month}/${d.day} '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
