import 'dart:async';
import 'dart:convert';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/text_scale_helper.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/core/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/core/rendering/shape_renderer.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/security/session_guard.dart';
import 'package:drawing_notes_app/core/storage/vfs/vault_service.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/pdf_import_service.dart';
import 'package:drawing_notes_app/core/storage/recovery_key_generator.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/presentation_page.dart';

part 'notebook_view_page_widgets.dart';
part 'notebook_view_page_imports.dart';
part 'notebook_view_page_manage.dart';

/// 笔记本内页面管理页（Phase 5）。
///
/// 能力：
/// - 查看笔记本所有页面（缩略图 + 标题）
/// - 新建页面（默认空白，复用画布能力）
/// - 删除页面（二次确认）
/// - 点击页面进入编辑器（手写 + 文字 + 图片混排）
///
/// [onChanged] 用于通知首页刷新列表。
class NotebookViewPage extends StatefulWidget {
  const NotebookViewPage({
    super.key,
    required this.notebook,
    required this.storage,
    this.onChanged,
    this.sessionPassword,
    this.sessionMasterKey,
    this.initialPageId,
  });

  final Notebook notebook;
  final NotebookStorage storage;
  final VoidCallback? onChanged;

  /// 搜索高亮跳转：携带命中页 ID 时，进入笔记本后自动打开该页
  /// （全文搜索「高亮跳转」链路——首页 _navigateToTarget 传入）。
  final String? initialPageId;

  /// 会话内密码（仅内存持有，不落盘）：解密密码模式笔记本后传入，
  /// 使保存时可重加密最新内容（修复"编辑后无法保存"的致命问题）。
  final String? sessionPassword;

  /// 会话内 U盘主密钥（仅内存持有，不落盘）：解锁 keyfile 模式笔记本后
  /// 传入，使保存时可重加密最新内容（零知识架构）。
  final List<int>? sessionMasterKey;

  @override
  State<NotebookViewPage> createState() => _NotebookViewPageState();
}

class _NotebookViewPageState extends State<NotebookViewPage> {
  NotebookStorage? get storage => widget.storage;
  late Notebook _notebook;

  /// 状态刷新薄包装（供 extension 使用）：转发受保护的 [setState]。
  void _applyState(VoidCallback fn) => setState(fn);
  bool _saving = false;
  bool _saveQueued = false;
  Completer<void>? _saveCompletion;

  /// 标签筛选关键词（A2：输入标签后只显示带该标签的页面）。
  String _tagFilter = '';

  /// 会话内密码（设置密码时记录；保存加密笔记本时用于重加密最新内容）。
  String? _sessionPassword;

  /// 会话内 U盘主密钥（keyfile 模式解锁后记录，仅内存；保存时重加密）。
  List<int>? _sessionMasterKey;

  /// H-05 部分落地（专家审计 2026-08-15）：生命周期监听——后台/切出时
  /// 自动保存草稿（防丢失）。完整会话锁定（清密钥 + 重解锁状态机）评估
  /// 为后续专项（涉及解锁流程重构，拆分须简化）。
  AppLifecycleListener? _lifecycleListener;

  /// 当前生效的会话密码（优先用本页设置过的，其次用打开时传入的）。
  String? get _effectivePassword => _sessionPassword ?? widget.sessionPassword;

  /// 当前生效的 U盘主密钥（优先用本页设置/解锁的，其次用打开时传入的）。
  List<int>? get _effectiveMasterKey =>
      _sessionMasterKey ?? widget.sessionMasterKey;

  /// 会话守卫（专家审计最优先③——2026-08-16）：失去焦点立即锁定（保存 +
  /// 清除媒体密钥——private_notes_light 模式）；resume 已锁定则提示重新
  /// 解锁（文件选择器运行中豁免——防导入/导出误锁）。
  late final SessionGuard _sessionGuard = SessionGuard(
    onLock: () {
      _save();
      MediaCryptoService.instance.clearSessionKey();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会话已锁定，请重新解锁')),
        );
      }
    },
    onReauthenticateRequired: () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会话已过期，请重新解锁')),
        );
      }
    },
  );

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    // H-05 部分落地：后台/切出自动保存草稿（防数据丢失；_save 有
    // _saving 保护不会并发堆叠；onInactive 覆盖切后台/失去焦点场景）。
    _lifecycleListener = AppLifecycleListener(
      onInactive: () => _save(),
    );
    // 搜索高亮跳转：携带命中页 ID 时，首帧后直接打开该页。
    final jumpToPageId = widget.initialPageId;
    if (jumpToPageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NotebookPage? target;
        for (final page in _notebook.pages) {
          if (page.id == jumpToPageId) {
            target = page;
            break;
          }
        }
        if (target != null) _openPage(target);
      });
    }
  }

  /// 会话密钥内存清理（红蓝攻防 D-2 修复 2026-08-15）：
  /// Widget 销毁时显式清零堆内存中的主密钥/密码——Dart GC 不保证立即
  /// 回收，fillRange 主动擦除可防冷启动/内存转储（frida/proc mem）提取。
  @override
  void dispose() {
    final key = _sessionMasterKey;
    if (key != null) {
      key.fillRange(0, key.length, 0);
      _sessionMasterKey = null;
    }
    _sessionPassword = null;
    _sessionGuard.dispose();
    // H-03 密钥清理时机：页面退出清除媒体加密会话密钥（D-2 内存清理）。
    MediaCryptoService.instance.clearSessionKey();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  /// 保存笔记本到本地（每次变更后调用）。
  ///
  /// 版本历史（C1，对齐 nb"每次修改自动 commit"）：保存前为每个页面
  /// 记录当前内容快照（最多 [NotebookPage.maxHistoryVersions] 版），
  /// 供回溯恢复。
  Future<void> _save() async {
    if (_saving) {
      _saveQueued = true;
      return _saveCompletion?.future ?? Future<void>.value();
    }
    _saving = true;
    final completion = Completer<void>();
    _saveCompletion = completion;
    try {
      do {
        _saveQueued = false;
        _notebook.touch();
        // 自动记录版本快照（C1 + C2 diff 摘要）。
        for (final page in _notebook.pages) {
          if (page.cloneOf != null) continue; // 克隆页不存本地快照（内容在源）
          // 可用性修复：内容未变化时不记录快照（否则每次保存——包括
          // 新建空页面、打开未修改就返回——都会堆叠"内容微调"空白快照，
          // 污染版本历史）。比较笔画数 + 文字数 + 文本内容。
          if (_hasContentChanged(page)) {
            // C2：相对上一版计算变更 diff 摘要（笔画数/文字数）。
            final prev = page.history.isNotEmpty ? page.history.first : null;
            final summary = _diffSummary(page, prev);
            // 版本快照必须**深拷贝**（评审发现 P2）：page.document/textItems 是
            // 编辑器实时修改的同一对象，若存引用则所有版本都指向当前状态，
            // 无法回溯、diff 恒为 0、文件里重复序列化当前内容。
            page.history.insert(
              0,
              PageVersion(
                time: DateTime.now(),
                document: DrawingDocument.fromJson(page.document.toJson()),
                textItems: page.textItems
                    .map((t) => PageTextItem.fromJson(t.toJson()))
                    .toList(),
                imageItems: page.imageItems
                    .map((item) => PageImageItem.fromJson(item.toJson()))
                    .toList(),
                connectors: page.connectors
                    .map((item) => PageConnector.fromJson(item.toJson()))
                    .toList(),
                shapes: page.shapes
                    .map((item) => PageShapeItem.fromJson(item.toJson()))
                    .toList(),
                charts: page.charts
                    .map((item) => PageChartItem.fromJson(item.toJson()))
                    .toList(),
                summary: summary,
              ),
            );
            if (page.history.length > NotebookPage.maxHistoryVersions) {
              page.history.removeRange(
                NotebookPage.maxHistoryVersions,
                page.history.length,
              );
            }
          }
        }
        // 加密笔记本：用会话密钥重加密最新内容后保存（评审发现 P1 修复 +
        // 可用性修复：编辑后保存不再抛 StateError，内容不会丢失）。
        // 未加密：普通原子写入。
        if (_notebook.encrypted &&
            _notebook.encryptionMode == EncryptionMode.keyfile) {
          final mk = _effectiveMasterKey;
          if (mk != null) {
            await widget.storage.saveWithKey(_notebook, mk);
          } else {
            await widget.storage.save(_notebook);
          }
        } else {
          final pw = _effectivePassword;
          if (_notebook.encrypted && pw != null) {
            await widget.storage.encryptAndSave(_notebook, pw);
          } else {
            await widget.storage.save(_notebook);
          }
        }
        widget.onChanged?.call();
      } while (_saveQueued);
      completion.complete();
    } catch (e) {
      // M-04 修复（专家审计 2026-08-15）：异常完成 Completer——防调用方
      // await _saveCompletion.future 永久等待（保存失败挂起）。
      completion.completeError(e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：${e.runtimeType}')));
      }
    } finally {
      _saving = false;
      if (identical(_saveCompletion, completion)) _saveCompletion = null;
    }
  }

  /// 页面内容是否相比上一版本有变化。
  ///
  /// 版本回溯必须覆盖所有可编辑对象，不能只按笔画数与文字数量判断；
  /// 否则图片、形状、图表或连接线变更会被静默漏存，恢复会产生混合状态。
  bool _hasContentChanged(NotebookPage page) {
    final prev = page.history.isNotEmpty ? page.history.first : null;
    if (prev == null) return _pageHasContent(page);
    return _contentSignature(
          document: page.document,
          textItems: page.textItems,
          imageItems: page.imageItems,
          connectors: page.connectors,
          shapes: page.shapes,
          charts: page.charts,
        ) !=
        _contentSignature(
          document: prev.document,
          textItems: prev.textItems,
          imageItems: prev.imageItems,
          connectors: prev.connectors,
          shapes: prev.shapes,
          charts: prev.charts,
        );
  }

  bool _pageHasContent(NotebookPage page) =>
      page.document.layers.any((layer) => layer.strokes.isNotEmpty) ||
      page.textItems.isNotEmpty ||
      page.imageItems.isNotEmpty ||
      page.connectors.isNotEmpty ||
      page.shapes.isNotEmpty ||
      page.charts.isNotEmpty;

  String _contentSignature({
    required DrawingDocument document,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageConnector> connectors,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
  }) => jsonEncode({
    'document': document.toJson(),
    'textItems': textItems.map((item) => item.toJson()).toList(),
    'imageItems': imageItems.map((item) => item.toJson()).toList(),
    'connectors': connectors.map((item) => item.toJson()).toList(),
    'shapes': shapes.map((item) => item.toJson()).toList(),
    'charts': charts.map((item) => item.toJson()).toList(),
  });

  /// 计算页面相对上一版的变更 diff 摘要（C2，借鉴 GenOffice 快照 diff 思路）。
  String _diffSummary(NotebookPage page, PageVersion? prev) {
    if (prev == null) return '首次保存';
    final strokesNow = page.document.layers.fold<int>(
      0,
      (sum, l) => sum + l.strokes.length,
    );
    final strokesPrev = prev.document.layers.fold<int>(
      0,
      (sum, l) => sum + l.strokes.length,
    );
    final parts = <String>[];
    final ds = strokesNow - strokesPrev;
    if (ds != 0) parts.add('笔画${ds > 0 ? '+' : ''}$ds');
    if (page.textItems.length != prev.textItems.length) {
      parts.add(
        '文字${page.textItems.length > prev.textItems.length ? '+' : ''}'
        '${page.textItems.length - prev.textItems.length}',
      );
    }
    // 文字内容是否被修改（数量相同但文本有变化）。
    var textChanged = false;
    if (page.textItems.length == prev.textItems.length) {
      for (var i = 0; i < page.textItems.length; i++) {
        if (page.textItems[i].text != prev.textItems[i].text) {
          textChanged = true;
          break;
        }
      }
    }
    if (textChanged) parts.add('文字修改');
    final imageDiff = page.imageItems.length - prev.imageItems.length;
    final shapeDiff = page.shapes.length - prev.shapes.length;
    final chartDiff = page.charts.length - prev.charts.length;
    final connectorDiff = page.connectors.length - prev.connectors.length;
    if (imageDiff != 0) parts.add('图片${imageDiff > 0 ? '+' : ''}$imageDiff');
    if (shapeDiff != 0) parts.add('形状${shapeDiff > 0 ? '+' : ''}$shapeDiff');
    if (chartDiff != 0) parts.add('图表${chartDiff > 0 ? '+' : ''}$chartDiff');
    if (connectorDiff != 0) {
      parts.add('连线${connectorDiff > 0 ? '+' : ''}$connectorDiff');
    }
    return parts.isEmpty ? '内容微调' : parts.join(' · ');
  }

  /// 导入 Markdown/文本文件，按段落生成文字块（C4，借鉴 nb 导入）。

  /// 新建页面并进入编辑器。模板在创建时就决定纸张与初始结构，
  /// 避免用户先得到空白页、再手动寻找多项设置。

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _notebook.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: _createPage,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建页面'),
            ),
          ),
          PopupMenuButton<_NotebookMenuItem>(
            tooltip: AppLocalizations.of(context)?.noteActions ?? '笔记本操作',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _onNotebookMenuSelected,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _NotebookMenuItem.importPage,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded),
                  title: Text(AppLocalizations.of(context)?.noteImportPage ?? '从其他笔记本引入页面'),
                ),
              ),
              PopupMenuItem(
                value: _NotebookMenuItem.importText,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text(AppLocalizations.of(context)?.noteImportMarkdown ?? '导入 Markdown 或文本'),
                ),
              ),
              PopupMenuItem(
                value: _NotebookMenuItem.importPdf,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text(AppLocalizations.of(context)?.noteImportPdf ?? '导入 PDF 并逐页批注'),
                ),
              ),
              PopupMenuItem(
                value: _NotebookMenuItem.security,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _notebook.encrypted
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                  ),
                  title: Text(_notebook.encrypted ? '修改密码保护' : '设置密码保护'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _NotebookMenuItem.organize,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text(AppLocalizations.of(context)?.noteTidyPages ?? '批量整理页面'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AmbientBackground(
        child: Column(
          children: [
            // 标签筛选（A2：按标签过滤页面）
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.pagePadding,
                8,
                AppDesign.pagePadding,
                8,
              ),
              child: GlassSurface(
                borderRadius: BorderRadius.circular(14),
                sigma: 8,
                padding: const EdgeInsets.all(4),
                child: TextField(
                  onChanged: (v) => setState(() => _tagFilter = v.trim()),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)?.noteFilterHint ?? '筛选标签或关键词',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildPages()),
          ],
        ),
      ),
    );
  }

  Widget _buildPages() {
    // 标签筛选后的页面列表（A2）。
    final pages =
        (_tagFilter.isEmpty
                ? _notebook.pages
                : _notebook.pages
                      .where((p) => p.tags.any((t) => t.contains(_tagFilter)))
                      .toList())
            .toList()
          ..sort((a, b) {
            if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
            final aTime = a.lastOpenedAt ?? a.updatedAt;
            final bTime = b.lastOpenedAt ?? b.updatedAt;
            return bTime.compareTo(aTime);
          });
    if (_notebook.pages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_add_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('这个笔记本还没有页面，点击右上角新建'),
          ],
        ),
      );
    }
    if (pages.isEmpty) {
      return const Center(
        child: Text('没有匹配该标签的页面', style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.pagePadding,
        8,
        AppDesign.pagePadding,
        96,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 224,
        childAspectRatio: 0.74,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: pages.length,
      itemBuilder: (context, i) {
        final page = pages[i];
        return _PageCard(
          page: page,
          onTap: () => _openPage(page),
          onDelete: () => _deletePage(page),
          onHistory: () => _showHistory(page),
          onToggleFavorite: () => _toggleFavorite(page),
        );
      },
    );
  }
}
