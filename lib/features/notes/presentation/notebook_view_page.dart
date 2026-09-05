import 'dart:async';

import 'package:drawing_notes_app/shared/widgets/apple_empty_state.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_renderer.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/security/session_guard.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/pdf_import_service.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
// 批次②：笔记本设密 ≠开屏密码强制（verify 探测法检测同码）。
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
// N4 批 3：重置密码盘绑定（设密后询问 + 菜单入口）。
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';
import 'package:drawing_notes_app/shared/widgets/ambient_background.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
// U3 P1-12：标签筛选输入防抖（250ms 合帧）。
import 'package:drawing_notes_app/shared/utils/search_debouncer.dart';
import 'package:drawing_notes_app/features/notes/presentation/presentation_page.dart';
// W2：翻页阅读模式（上下滑动切页）+ 整本多页 PDF 导出。
import 'package:drawing_notes_app/features/notes/presentation/notebook_reader_page.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_pdf_exporter.dart';
// N2：笔记（块文档）文件密码——分页画布内打开受密块文档副本的解锁拦截。
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart'
    show UnlockFlow;
import 'package:drawing_notes_app/features/security/block_doc_password_reset_flow.dart';
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';

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
    this.editorPageBuilder,
    this.blockDocStore,
    this.sessionPassword,
  });

  final Notebook notebook;

  /// 块文档存储（R2 列表同步：shell 注入同一实例）。
  final NoteBlockDocStore? blockDocStore;
  final NotebookStorage storage;
  final VoidCallback? onChanged;

  /// 编辑器页面由应用组合根注入，避免 notes 直接依赖 drawing UI。
  final EditorPageBuilder? editorPageBuilder;

  /// 会话内密码（仅内存持有，不落盘）：解密密码模式笔记本后传入，
  /// 使保存时可重加密最新内容（修复"编辑后无法保存"的致命问题）。
  final String? sessionPassword;

  @override
  State<NotebookViewPage> createState() => _NotebookViewPageState();
}

class _NotebookViewPageState extends State<NotebookViewPage> {
  NotebookStorage? get storage => widget.storage;
  late Notebook _notebook;

  /// M4：块文档存储门面（延迟创建，避免在 widget 构造时调用 path_provider）。
  /// R2 列表同步：优先用注入实例（shell 同一 store）——自建实例会使
  /// shell 的 listDocHeaders 缓存不失效（新笔记在 AllDocs 不显示）。
  NoteBlockDocStore? _injectedBlockDocStore;

  /// M4：获取或创建块文档存储门面。
  NoteBlockDocStore get blockDocStore {
    if (_injectedBlockDocStore != null) return _injectedBlockDocStore!;
    return _injectedBlockDocStore ??=
        widget.blockDocStore ?? NoteBlockDocStore();
  }

  /// 状态刷新薄包装（供 extension 使用）：转发受保护的 [setState]。
  void _applyState(VoidCallback fn) => setState(fn);
  bool _saving = false;
  bool _saveQueued = false;
  Completer<void>? _saveCompletion;

  /// 标签筛选关键词（A2：输入标签后只显示带该标签的页面）。
  String _tagFilter = '';

  /// U3 P1-12：标签筛选防抖（每键 setState 会整页重建 GridView）。
  final SearchDebouncer _tagFilterDebouncer = SearchDebouncer();

  /// 会话内密码（设置密码时记录；保存加密笔记本时用于重加密最新内容）。
  String? _sessionPassword;

  /// H-05 部分落地（专家审计 2026-08-15）：生命周期监听——后台/切出时
  /// 自动保存草稿（防丢失）。完整会话锁定（清密钥 + 重解锁状态机）评估
  /// 为后续专项（涉及解锁流程重构，拆分须简化）。
  AppLifecycleListener? _lifecycleListener;

  /// 当前生效的会话密码（优先用本页设置过的，其次用打开时传入的）。
  String? get _effectivePassword => _sessionPassword ?? widget.sessionPassword;

  /// 会话守卫（专家审计最优先③——2026-08-16）：失去焦点立即锁定（保存 +
  /// 清除媒体密钥——private_notes_light 模式）；resume 已锁定则恢复会话。
  ///
  /// U1 修复（2026-09-02）：此前 onReauthenticateRequired 仅弹提示，
  /// 媒体密钥清了永不恢复 → 加密笔记本图片全部 StateError（"经常
  /// 退出"最大元凶）。恢复路径：密码仍在页内存（_sessionPassword 语义
  /// 即本页会话内有效），用其重派生媒体密钥注入后复位锁定态。
  ///
  /// U3 P0-7（2026-09-02）：锁定保存改走 [_saveIfChanged]——仅当页面
  /// 内容确有未落盘变更时才整本重加密；密钥清理与提示保持原即时语义。
  late final SessionGuard _sessionGuard = SessionGuard(
    onLock: () {
      _saveIfChanged();
      MediaCryptoService.instance.clearSessionKey();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('会话已锁定，请重新解锁')));
      }
    },
    onReauthenticateRequired: () {
      _restoreSessionAfterReauth();
    },
  );

  /// 再认证后恢复会话：重派生媒体密钥 + 复位锁定态 + 刷新 UI。
  ///
  /// 派生失败保持 fail-closed（密钥不注入），仅提示重新打开笔记本。
  Future<void> _restoreSessionAfterReauth() async {
    if (!mounted) return;
    final pw = _effectivePassword;
    if (_notebook.encrypted && pw != null && pw.isNotEmpty) {
      try {
        final mediaSalt = await widget.storage.ensureMediaSalt();
        await MediaCryptoService.instance.setSessionPassword(pw, mediaSalt);
      } catch (_) {
        _sessionGuard.unlock();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('会话已过期，请重新打开该分页画布')));
        return;
      }
    }
    _sessionGuard.unlock();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('会话已恢复')));
  }

  @override
  void initState() {
    super.initState();
    _notebook = widget.notebook;
    // H-05 部分落地：后台/切出自动保存草稿（防数据丢失；_save 有
    // _saving 保护不会并发堆叠；onInactive 覆盖切后台/失去焦点场景）。
    // U3 P0-7：改走 _saveIfChanged，无变更不再全量重加密。
    _lifecycleListener = AppLifecycleListener(onInactive: _saveIfChanged);
  }

  /// 会话密钥内存清理（红蓝攻防 D-2 修复 2026-08-15）：
  /// Widget 销毁时显式清零堆内存中的主密钥/密码——Dart GC 不保证立即
  /// 回收，fillRange 主动擦除可防冷启动/内存转储（frida/proc mem）提取。
  @override
  void dispose() {
    _sessionPassword = null;
    _sessionGuard.dispose();
    // H-03 密钥清理时机：页面退出清除媒体加密会话密钥（D-2 内存清理）。
    MediaCryptoService.instance.clearSessionKey();
    _tagFilterDebouncer.dispose();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  /// 保存笔记本到本地（每次变更后调用）。
  ///
  /// 版本历史（C1，对齐 nb"每次修改自动 commit"）：保存前为每个页面
  /// 记录当前内容快照（最多 [NotebookPage.maxHistoryVersions] 版），
  /// 供回溯恢复。
  ///
  /// 设计说明（P0-3b）：本方法**有意不**套用
  /// `core/saving/save_scheduler.dart` 的
  /// `SaveScheduler`。两者是语义不同的两类保存模型：
  ///  - 编辑器 `SaveScheduler`：面向"逐笔打字/落笔"的**防抖自动保存**，
  ///    失败时由调度器内部按退避/放弃策略自愈，对外 fire-and-forget；
  ///  - 笔记本 `_save()`：面向"离散动作边界"的**整本重写保存**（含每页
  ///    版本快照 + 重加密），调用方（导入/移动/删除）需要 `await` 且
  ///    必须**感知失败**以正确回滚或提示——因此这里保留自己的
  ///    `_saving/_saveQueued/_saveCompletion` 串行化，并把异常
  ///    `completeError` 抛给调用方。强行套用会吞掉失败信号，导致
  ///    "导入已成功" 的误导提示。
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
          // 内容未变化时不记录快照，避免打开未修改页面或新建空页造成无意义
          // 历史记录。完整载荷的比较、深拷贝和版本上限均由页面聚合保持。
          if (page.hasChangedSinceLatestVersion) {
            page.addVersion(
              time: DateTime.now(),
              summary: page.changeSummarySinceLatestVersion,
            );
          }
        }
        // 加密笔记本：用会话密码重加密最新内容后保存（评审发现 P1 修复 +
        // 可用性修复：编辑后保存不再抛 StateError，内容不会丢失）。
        // 未加密：普通原子写入。
        final pw = _effectivePassword;
        if (_notebook.encrypted && pw != null) {
          await widget.storage.encryptAndSave(_notebook, pw);
        } else {
          await widget.storage.save(_notebook);
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
        ).showSnackBar(SnackBar(content: Text('保存失败，请重试')));
      }
    } finally {
      _saving = false;
      if (identical(_saveCompletion, completion)) _saveCompletion = null;
    }
  }

  /// U3 P0-7：是否存在未落盘的页面内容变更。
  ///
  /// 页面内容快照机制（[NotebookPage.hasChangedSinceLatestVersion]）天然
  /// 反映"上次 addVersion 之后内容是否再变过"；克隆页（cloneOf != null）
  /// 内容在源页，本页保存不写其快照，故排除。元数据类变更（改名/加密/
  /// 重排）本就走同步 _save 调用方路径，不经此守卫。
  bool get _hasUnpersistedPageContent => _notebook.pages.any(
    (p) => p.cloneOf == null && p.hasChangedSinceLatestVersion,
  );

  /// 仅当有未落盘内容变更时才保存（onLock / onInactive 热路径专用）。
  ///
  /// 锁门即时性不变：媒体密钥清理与提示在 onLock 内同步执行，此方法
  /// 只是跳过"无变更 → 全量重加密 + 历史快照"的浪费；此前保存失败过的
  /// 页面 hasChangedSinceLatestVersion 仍为 true，下轮自愈重试。
  void _saveIfChanged() {
    if (!_hasUnpersistedPageContent) return;
    _save();
  }

  /// 导入 Markdown/文本文件，按段落生成文字块（C4，借鉴 nb 导入）。

  /// 新建页面并进入编辑器。模板在创建时就决定纸张与初始结构，
  /// 避免用户先得到空白页、再手动寻找多项设置。

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 让内容延伸到顶栏之后——玻璃才有东西可模糊（背后是 AmbientBackground）。
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(
          _notebook.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // W2：翻页阅读（上下滑动逐页切换，像翻 PDF）。
          IconButton(
            tooltip: '翻页阅读',
            icon: const Icon(Icons.auto_stories_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotebookReaderPage(
                  notebook: _notebook,
                  onEditPage: _openPage,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: _createPage,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建页面'),
            ),
          ),
          PopupMenuButton<_NotebookMenuItem>(
            tooltip: AppLocalizations.of(context)?.noteActions ?? '分页画布操作',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _onNotebookMenuSelected,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _NotebookMenuItem.importPage,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded),
                  title: Text(
                    AppLocalizations.of(context)?.noteImportPage ??
                        '从其他分页画布引入页面',
                  ),
                ),
              ),
              PopupMenuItem(
                value: _NotebookMenuItem.importText,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_rounded),
                  title: Text(
                    AppLocalizations.of(context)?.noteImportMarkdown ??
                        '导入 Markdown 或文本',
                  ),
                ),
              ),
              PopupMenuItem(
                value: _NotebookMenuItem.importPdf,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text(
                    AppLocalizations.of(context)?.noteImportPdf ??
                        '导入 PDF 并逐页批注',
                  ),
                ),
              ),
              // W2：整本导出——每个画布页对应 PDF 一页，合成单个文件。
              PopupMenuItem(
                value: _NotebookMenuItem.exportWholePdf,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_rounded),
                  title: const Text('导出整本 PDF'),
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
              // N4 批 3：已加密时提供重置密码盘绑定入口（忘记密码可重置）。
              if (_notebook.encrypted)
                PopupMenuItem(
                  value: _NotebookMenuItem.bindUsb,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.usb_rounded),
                    title: const Text('绑定重置密码盘'),
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _NotebookMenuItem.organize,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text(
                    AppLocalizations.of(context)?.noteTidyPages ?? '批量整理页面',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AmbientBackground(
        child: Padding(
          // 让位给玻璃顶栏。筛选框因此不会与顶栏重叠——否则筛选框自带的
          // GlassSurface 会和顶栏的玻璃叠在一起（红线）。
          padding: EdgeInsets.only(top: GlassAppBar.bodyTopPadding(context)),
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
                  borderRadius: BorderRadius.circular(AppleRadius.md),
                  sigma: 8,
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    // U3 P1-12：防抖 250ms，避免每键 setState 整页重建。
                    onChanged: (v) => _tagFilterDebouncer.run(
                      () => setState(() => _tagFilter = v.trim()),
                    ),
                    decoration: InputDecoration(
                      hintText:
                          AppLocalizations.of(context)?.noteFilterHint ??
                          '筛选标签或关键词',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildPages()),
            ],
          ),
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
      // 空态统一（审计二-4）：收编到共享 AppleEmptyState。
      return const AppleEmptyState(
        icon: Icons.note_add_outlined,
        title: '这个分页画布还没有页面',
        tip: '点击右上角新建',
      );
    }
    if (pages.isEmpty) {
      // 空态统一（审计二-4）：收编到共享 AppleEmptyState。
      return const AppleEmptyState(
        icon: Icons.label_outline_rounded,
        title: '没有匹配该标签的页面',
        tip: '试试选择其他标签',
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
          onOpenAsBlockDoc: () => _openBlockDocFromPage(page),
        );
      },
    );
  }
}
