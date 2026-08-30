// M12 笔记页（AFFiNE Page 1:1）：独立于画板的文档页面模块。
//
// 参照 AFFiNE（MIT, © 2020-present toeverything）Page 视图的交互与信息架构，
// 版权声明见 THIRD_PARTY_NOTICES.md。本模块与画板模块（features/notes 的
// edgeless/drawing 部分）零交叉引用：画板打开文档经由导航跳转到本模块。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:drawing_notes_app/core/saving/save_scheduler.dart';

import 'package:drawing_notes_app/features/doc/application/doc_markdown_export.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/doc/doc_outline_rail.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';

/// AFFiNE 式笔记页：白底、居中窄栏、顶栏（收藏/信息/更多/分享）、右缘大纲。
///
/// 与画板完全分离：
/// - 不使用环境背景 / 玻璃拟态（画板视觉）；
/// - 不内嵌画布组件；「在画板中打开」经 [onOpenInEdgeless] 回调由宿主路由。
class DocPage extends StatefulWidget {
  const DocPage({
    super.key,
    required this.document,
    this.controller,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onOpenInEdgeless,
  });

  /// 要编辑的笔记文档。
  final NoteBlockDoc document;

  /// 文档控制器（持久化由宿主注入；为 null 时仅编辑不落盘）。
  final DocController? controller;

  /// 当前收藏态（受控）。
  final bool isFavorite;

  /// 收藏切换回调。
  final ValueChanged<bool>? onToggleFavorite;

  /// 「在画板中打开」回调（宿主负责转换与路由）。
  final VoidCallback? onOpenInEdgeless;

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
  late final SaveScheduler _saveScheduler = SaveScheduler(
    save: () async {
      final editor = _editorKey.currentState;
      if (editor == null) return;
      final doc = editor.saveNow();
      widget.controller?.save(doc);
      _doc = doc;
    },
    onSaved: () {
      if (!mounted) return;
      setState(() {
        _saveStatus = _SaveStatus.saved;
        _lastSavedAt = DateTime.now();
      });
    },
    onError: (e, st) => debugPrint('笔记自动保存失败: $e'),
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

  /// 导出 Markdown（M12.5，AFFiNE Export 对齐）：写入系统文档目录下的
  /// 「绘图笔记导出」子目录，Snack 提示完整路径。
  Future<void> _exportMarkdown() async {
    try {
      final doc = _editorKey.currentState?.currentDoc ?? _doc;
      final md = noteBlockDocToMarkdown(doc);
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docsDir.path}$_sep绘图笔记导出');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final base = sanitizeFileName(doc.title.isEmpty ? '未命名' : doc.title);
      final file = File('${dir.path}$_sep$base.md');
      var path = file.path;
      var n = 1;
      while (file.existsSync()) {
        path = '${dir.path}$_sep$base (${n++}).md';
      }
      await File(path).writeAsString(md, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出 Markdown：$path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：${e.runtimeType}')));
    }
  }

  static String get _sep => Platform.pathSeparator;

  void _persist(NoteBlockDoc doc) {
    setState(() {
      _doc = doc;
      _saveStatus = _SaveStatus.saved;
      _lastSavedAt = DateTime.now();
    });
    widget.controller?.save(doc);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
        onToggleOutline: () => setState(() => _outlineOpen = !_outlineOpen),
        onShowInfo: () => _showInfoDialog(context),
        onOpenInEdgeless: widget.onOpenInEdgeless,
        onExportMarkdown: _exportMarkdown,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: DocEditor(
                  key: _editorKey,
                  showChrome: false,
                  document: _doc,
                  onSave: _persist,
                  onDirty: _onEditorDirty,
                ),
              ),
            ),
          ),
          // 右缘大纲（AFFiNE Outline Rail）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _outlineOpen
                ? DocOutlineRail(
                    key: const ValueKey('rail-on'),
                    entries: [
                      for (final e
                          in _editorKey.currentState?.outline() ?? const [])
                        OutlineEntry(id: e.id, level: e.level, text: e.text),
                    ],
                    onTapEntry: (id) =>
                        _editorKey.currentState?.scrollToBlock(id),
                    onClose: () => setState(() => _outlineOpen = false),
                  )
                : const SizedBox.shrink(key: ValueKey('rail-off')),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    final body = _doc.body;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_doc.title.isEmpty ? '未命名' : _doc.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('创建于', _fmtDate(_doc.createdAt)),
            _infoRow('更新于', _fmtDate(_doc.updatedAt)),
            _infoRow('块数量', '${body.length}'),
          ],
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

/// 顶栏：返回 + 标题 + ☆收藏 + ⓘ信息 + ⋯更多 + 大纲开关 + 分享。
class _DocHeader extends StatelessWidget implements PreferredSizeWidget {
  const _DocHeader({
    required this.title,
    required this.isFavorite,
    required this.outlineOpen,
    required this.onToggleFavorite,
    required this.onToggleOutline,
    required this.onShowInfo,
    required this.statusLabel,
    required this.statusColor,
    required this.onSavePressed,
    this.onOpenInEdgeless,
    this.onExportMarkdown,
  });

  final String title;
  final bool isFavorite;
  final bool outlineOpen;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleOutline;
  final VoidCallback onShowInfo;

  /// 保存状态文案（未保存 / 保存中… / 已保存 HH:mm）与主题色。
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onSavePressed;
  final VoidCallback? onOpenInEdgeless;

  /// 导出 Markdown（M12.5）。
  final VoidCallback? onExportMarkdown;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        title.isEmpty ? '未命名' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      actions: [
        // 保存状态（透明可见）：未保存 / 保存中… / 已保存 HH:mm
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '保存',
          icon: const Icon(Icons.save_outlined),
          onPressed: onSavePressed,
        ),
        IconButton(
          tooltip: isFavorite ? '取消收藏' : '收藏',
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: isFavorite ? const Color(0xFFF5A623) : null,
          ),
          onPressed: onToggleFavorite,
        ),
        IconButton(
          tooltip: '文档信息',
          icon: const Icon(Icons.info_outline_rounded, size: 20),
          onPressed: onShowInfo,
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (v) {
            if (v == 'edgeless') onOpenInEdgeless?.call();
            if (v == 'exportMd') onExportMarkdown?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'exportMd',
              child: Row(
                children: [
                  Icon(
                    Icons.data_object_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Text('导出 Markdown'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edgeless',
              enabled: onOpenInEdgeless != null,
              child: Row(
                children: [
                  Icon(
                    Icons.draw_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  const Text('在画板中打开'),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('分享功能即将支持')));
            },
            icon: const Icon(Icons.ios_share_rounded, size: 15),
            label: const Text('分享'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0066CC),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        IconButton(
          tooltip: '大纲',
          icon: Icon(
            Icons.format_list_bulleted_rounded,
            color: outlineOpen ? scheme.primary : null,
          ),
          onPressed: onToggleOutline,
        ),
      ],
    );
  }
}
