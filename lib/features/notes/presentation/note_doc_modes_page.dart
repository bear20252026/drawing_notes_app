// 由 Claude 团队生成 | Drawing Notes App
// NoteDocModesPage：块文档「页面 / 无限画布」双模宿主（1:1 AFFiNE page↔edgeless 切换）。
//
// 页面模式（page）渲染 NoteEditorPage（线性块编辑）；
// 无限画布模式（edgeless）渲染 EdgelessPage（note 帧画布）。
// 切换时通过 note_block_doc_to_frames 拆分、mergeFramesToDoc 合并，
// 保证同一份 NoteBlockDoc 在两种模式下内容一致、可来回切换。
// EdgelessDoc（帧坐标/缩放）可选持久化到 EdgelessDocStore。

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc_to_frames.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/edgeless_doc_store.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/note_editor_page.dart';

/// 块文档的模式。
enum NoteDocMode { page, edgeless }

/// 块文档双模宿主页。
///
/// [document] 进入时的块文档；[onSave] 在合并回页面模式（或退出即返回）时
/// 收到最新 [NoteBlockDoc]；[embeddedBlockBuilder] 透传给内嵌块渲染；
/// [edgelessStore] 非空时为无限画布布局做持久化。
class NoteDocModesPage extends StatefulWidget {
  const NoteDocModesPage({
    super.key,
    required this.document,
    this.onSave,
    this.embeddedBlockBuilder,
    this.edgelessStore,
  });

  final NoteBlockDoc document;
  final ValueChanged<NoteBlockDoc>? onSave;
  final Widget? Function(NoteBlock block)? embeddedBlockBuilder;
  final EdgelessDocStore? edgelessStore;

  @override
  State<NoteDocModesPage> createState() => NoteDocModesPageState();
}

class NoteDocModesPageState extends State<NoteDocModesPage> {
  late NoteBlockDoc _doc;
  EdgelessDoc? _edgelessDoc;
  NoteDocMode _mode = NoteDocMode.page;
  bool _switching = false;
  final GlobalKey<NoteEditorPageState> _pageKey = GlobalKey<NoteEditorPageState>();

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
  }

  NoteEditorPageState? get _pageState => _pageKey.currentState;

  /// 进入无限画布模式：从当前页面模式的最新文档拆分出 note 帧。
  Future<void> _switchToEdgeless() async {
    if (_switching) return;
    _switching = true;
    final current = _pageState?.currentDoc ?? _doc;
    _doc = current;

    EdgelessDoc edl;
    final saved = widget.edgelessStore == null
        ? null
        : await widget.edgelessStore!.loadDoc(current.id);
    if (saved != null) {
      edl = saved; // 恢复上次的帧坐标 / 缩放 / 选择
    } else {
      final frames = noteBlockDocToFrames(
        current,
        docId: current.id,
        initialRect: const Rect.fromLTWH(80, 80, 360, 400),
      );
      edl = EdgelessDoc(
        id: current.id,
        frames: frames,
        camera: EdgelessCamera.initial,
        nextZIndex: frames.length + 1,
      );
    }
    if (!mounted) {
      _switching = false;
      return;
    }
    setState(() {
      _edgelessDoc = edl;
      _mode = NoteDocMode.edgeless;
    });
    _persistEdgeless();
    _switching = false;
  }

  /// 回到页面模式：把 note 帧合并回块文档并持久化。
  void _switchToPage() {
    if (_switching) return;
    final edl = _edgelessDoc;
    if (edl != null) {
      final merged = mergeFramesToDoc(
        edl.frames,
        id: _doc.id,
        title: _doc.title,
      );
      _doc = merged;
      widget.onSave?.call(merged);
      widget.edgelessStore?.saveDoc(edl);
    }
    setState(() => _mode = NoteDocMode.page);
  }

  void _persistEdgeless() {
    final edl = _edgelessDoc;
    if (edl != null) {
      unawaited(widget.edgelessStore?.saveDoc(edl) ?? Future<void>.value());
    }
  }

  void _onPageSave(NoteBlockDoc d) {
    // 仅记录最新文档，不做 setState：该回调可能在 NoteEditorPage 卸载
    // （finalizeTree）期间被调用，setState 会触发 "build 期间 markNeedsBuild"。
    _doc = d;
  }

  void _onEdgelessChanged(EdgelessDoc e) {
    setState(() => _edgelessDoc = e);
    _persistEdgeless();
  }

  bool get _inPageMode => _mode == NoteDocMode.page;

  /// 页面退出（返回）时收口：edgeless 模式合并回文档并落盘，再退出。
  void _handleExit() {
    if (_inPageMode) {
      final current = _pageState?.currentDoc ?? _doc;
      _doc = current;
      widget.onSave?.call(current);
    } else {
      final edl = _edgelessDoc;
      if (edl != null) {
        final merged = mergeFramesToDoc(
          edl.frames,
          id: _doc.id,
          title: _doc.title,
        );
        _doc = merged;
        widget.onSave?.call(merged);
        widget.edgelessStore?.saveDoc(edl);
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExit();
      },
      child: Scaffold(
        body: Column(
          children: [
            _buildModeBar(),
            Expanded(
              child: _inPageMode
                  ? NoteEditorPage(
                      key: _pageKey,
                      document: _doc,
                      onSave: _onPageSave,
                      embeddedBlockBuilder: widget.embeddedBlockBuilder,
                    )
                  : EdgelessPage(
                      initialDoc: _edgelessDoc!,
                      onChanged: _onEdgelessChanged,
                      embeddedBlockBuilder: widget.embeddedBlockBuilder,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBar() {
    return Material(
      elevation: 1,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _doc.title.isEmpty ? 'Untitled' : _doc.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SegmentedButton<NoteDocMode>(
                segments: const [
                  ButtonSegment(
                    value: NoteDocMode.page,
                    icon: Icon(Icons.notes_rounded),
                    label: Text('页面'),
                  ),
                  ButtonSegment(
                    value: NoteDocMode.edgeless,
                    icon: Icon(Icons.hub_rounded),
                    label: Text('无限画布'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  final target = selection.first;
                  if (target == _mode) return;
                  if (target == NoteDocMode.edgeless) {
                    _switchToEdgeless();
                  } else {
                    _switchToPage();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
