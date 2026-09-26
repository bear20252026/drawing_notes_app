// M12 笔记页（AFFiNE Page 1:1）：独立于画板的文档页面模块。
//
// 参照 AFFiNE（MIT, © 2020-present toeverything）Page 视图的交互与信息架构，
// 版权声明见 THIRD_PARTY_NOTICES.md。本模块与画板模块（features/notes 的
// edgeless/drawing 部分）零交叉引用：画板打开文档经由导航跳转到本模块。

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_motion.dart';

import 'package:drawing_notes_app/core/layout/responsive.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/shared/utils/time_format.dart';
import 'package:drawing_notes_app/shared/widgets/app_snack.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;
import 'package:drawing_notes_app/features/security/presentation/block_doc_password_reset_flow.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/doc/application/doc_export_io.dart';
import 'package:drawing_notes_app/features/doc/application/doc_link_index.dart';
import 'package:drawing_notes_app/features/doc/application/doc_html_export.dart';
import 'package:drawing_notes_app/features/doc/application/doc_pdf_adapter.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_markdown.dart';
import 'package:drawing_notes_app/features/doc/application/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_editor.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_outline_rail.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/utils/domain_display_labels.dart';

// O1 域分权（F9，2026-09-24）：保存导出/大纲页链/文档密码/信息标签四域 part。
// 新增同域私有逻辑请落对应 part；public API、字段、静态与 build 留在本体。
part 'doc_page_save_export.dart';
part 'doc_page_link_outline.dart';
part 'doc_page_password.dart';
part 'doc_page_info.dart';

part 'doc_page_widgets.dart';

/// 分享占位提示（桌面按钮与移动端图标共用）。
void _showShareSnackBar(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n?.docShareComingSoon ?? '分享功能即将支持')),
  );
}

/// AFFiNE 式笔记页：白底、居中窄栏、顶栏（收藏/信息/更多/分享）、右缘大纲。
///
/// 与画板完全分离：
/// - 不使用环境背景 / 玻璃拟态（画板视觉）；
/// - 不内嵌画布组件。
class DocPage extends StatefulWidget {
  const DocPage({
    super.key,
    required this.document,
    this.controller,
    this.isFavorite = false,
    this.onToggleFavorite,
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

  /// part 文件（extension）用的 setState 包装——State.setState 是
  /// protected，extension 中直接调用会报 invalid_use_of_protected_member。
  void pageSetState(VoidCallback fn) => setState(fn);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)?.docSaveFailed ?? '保存失败，请重试或手动保存',
            ),
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
        backgroundColor: scheme.surface,
        appBar: _DocHeader(
          title: _doc.title,
          isFavorite: _favorite,
          outlineOpen: _outlineOpen,
          statusLabel: _statusLabel(),
          statusColor: _saveStatus == _SaveStatus.unsaved
              ? AppleColor.favourite
              : (_saveStatus == _SaveStatus.saving
                    ? scheme.primary
                    : AppleColor.noteGreen),
          onSavePressed: _saveNow,
          onToggleFavorite: () {
            setState(() => _favorite = !_favorite);
            widget.onToggleFavorite?.call(_favorite);
          },
          // 桌面切换右缘停靠栏；移动端弹底部半屏面板（240 固定窄栏在手机上
          // 会吃掉约 60% 屏宽）。
          onToggleOutline: _onToggleOutline,
          onShowInfo: () => _showInfoDialog(context),
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
              duration: AppleMotion.dropdown,
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

  // ── P3 装配一致性：blockDocStore 兜底生成索引数据源与点击路由 ──
  //
  // U5b（审计 P1-19）：列表 Future 首次访问后缓存——反链面板每次保存
  // （updatedAt 变化触发 didUpdateWidget→_reload）原先都新建 Future
  // 全量读盘+解密所有笔记；现复用同一 Future 零 IO，仅内存重算
  // backlinksOf。取舍：本页会话内其他文档的新增/改名不会即时反映到
  // 反链列表（模态编辑页内不发生，宿主层列表始终走自己的加载路径）。
  Future<List<NoteBlockDoc>>? _allDocsFutureCache;
}
