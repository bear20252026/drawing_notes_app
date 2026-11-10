// 组合根对 `AppRouteServices` 的默认实现（2026-10-10 解耦批次）。
//
// 本文件是**唯一**允许 import `features/doc/presentation` 与
// `features/security/presentation` 的位置之一（另一个是 app_shell_routes）——
// 契约 `app/app_routes.dart` 不含任何 feature 实现，notes 侧因此无需反向
// 依赖 doc/security。
//
// 三条腿的语义与迁移前**逐条一致**：
// 1. [openNotePage] ← 原 notes 三处 push 块文档页的调用；
//    含 N2 受密解锁拦截（`_ensureUnlocked` 与 notes 侧原口径相同：
//    未受密/已解锁直接过，受密弹 `UnlockFlow`，忘记密码走重置流）。
// 2. [openNotebookPage] ← 原 notes 两处 `Navigator.push(NotebookViewPage(...))`。
// 3. [startNotebookPasswordReset] ← 原 notes 直推
//    `NotebookPasswordResetFlow.show`。
// 4. [showTemplatePicker] ← 原 notes 自拼的模板选择 `GlassDialog`。
library;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/app/app_routes.dart';
import 'package:drawing_notes_app/app/app_services.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/documents/note_templates.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_builder.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart'
    show VaultFileLockException;
import 'package:drawing_notes_app/features/doc/application/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_page.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/security/presentation/block_doc_password_reset_flow.dart';
import 'package:drawing_notes_app/features/security/presentation/file_password_reset_flow.dart';
import 'package:drawing_notes_app/features/security/presentation/notebook_password_reset_flow.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/glass_dialog.dart';
import 'package:drawing_notes_app/shared/widgets/unlock_sheets.dart';

/// 组合根默认路由服务。
///
/// 持有 [_services]（数据/存储）与 [_shellContext]（提供 `context` 与
/// `editorPageBuilder`）——后者是 `AppShell` 的弱引用，避免循环持有。
class DefaultRouteServices implements AppRouteServices {
  DefaultRouteServices({
    required AppServices services,
    EditorPageBuilder? Function()? editorPageBuilderProvider,
    NotebookStorage? Function()? notebookStorageProvider,
    StorageService? documentStorage,
  }) : _services = services, // ignore: prefer_initializing_formals -- 保留公共命名参数
       _editorPageBuilderProvider = editorPageBuilderProvider, // ignore: prefer_initializing_formals
       _notebookStorageProvider = notebookStorageProvider, // ignore: prefer_initializing_formals
       _documentStorage = documentStorage; // ignore: prefer_initializing_formals

  final AppServices _services;
  final EditorPageBuilder? Function()? _editorPageBuilderProvider;
  final NotebookStorage? Function()? _notebookStorageProvider;

  /// 无限画布/文档存储（画布独立密码重置流用；笔记不持有该实例）。
  ///
  /// 可空：notes 侧不持有文档存储（它只读 `AllDoc` 元信息）；独立直构
  /// `AppShell` 且未注入 documentStorage 时，画布重置流不可用。
  final StorageService? _documentStorage;

  EditorPageBuilder? get _editorPageBuilder =>
      _editorPageBuilderProvider?.call();
  NotebookStorage? get _notebookStorage => _notebookStorageProvider?.call();

  /// 块文档存储（N2 拦截与 DocPage 共用同一实例——缓存失效口径一致）。
  NoteBlockDocStore get _blockDocStore => _services.blockDocStore;

  @override
  Future<bool> openNotePage(BuildContext context, DocOpenArgs args) async {
    final store = _blockDocStore;
    // N2：受密未解锁先解锁（与 notes 侧原口径逐条一致：锁定异常折叠为
    // null → fail-closed，但补捕 FormatException/TypeError 给出损坏反馈）。
    if (await store.isBlockDocPasswordProtected(args.id) &&
        !store.isBlockDocUnlocked(args.id)) {
      if (!context.mounted) return false;
      final pin = await UnlockFlow.show(
        context,
        title:
            AppLocalizations.of(context)?.docUnlockTitle ??
            '该笔记已加密，输入密码',
        flexible: true,
        onVerify: (p) => store.verifyBlockDocPassword(args.id, p),
        footerLabel:
            AppLocalizations.of(context)?.docForgotPassword ?? '忘记密码？',
        onFooter: () {
          BlockDocPasswordResetFlow.show(
            context,
            store: store,
            docId: args.id,
            docTitle: args.title,
          );
        },
      );
      if (pin == null && !store.isBlockDocUnlocked(args.id)) return false;
    }
    if (!context.mounted) return false;

    final NoteBlockDoc? loaded;
    try {
      final result = await store.loadDocument(args.id);
      if (!context.mounted) return false;
      loaded = result;
    } on BlockDocLockedException {
      return false; // 会话 DEK 已被清——不暴露内容
    } on FormatException {
      _showCorruptFeedback(context);
      return false;
    } on TypeError {
      _showCorruptFeedback(context);
      return false;
    }
    if (loaded == null || !context.mounted) return false;
    // 局部非空副本：既满足提升，又不被下方闭包捕获（闭包内捕获的变量
    // 不参与类型提升）。
    final noteDoc = loaded;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocPage(
          document: noteDoc,
          blockDocStore: store,
          controller: DocController(
            onSave: (updated) async {
              await store.saveDocument(updated);
              // 调用方钩子（如笔记本页回写源页 + 加密本重加密）在默认
              // 持久化**之后**执行——与迁移前 `onSave` 内的书写顺序一致。
              args.onSaved?.call(updated);
            },
          ),
          resetBlockDocPassword: BlockDocPasswordResetFlow.show,
        ),
      ),
    );
    return true;
  }

  void _showCorruptFeedback(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n?.homeDocCorrupt ?? '笔记数据损坏，无法打开')),
    );
  }

  @override
  Future<bool> openNotebookPage(
    BuildContext context,
    NotebookOpenArgs args,
  ) async {
    final storage = _notebookStorage;
    if (storage == null) return false;

    // 加密本：调用方已解锁时会话密码非空，需解密后再交给页面（与
    // app_shell 的 NotebookViewPage 装配同口径——否则页面拿到密文态）。
    final Notebook? loaded;
    try {
      final result = await storage.load(args.notebookId ?? args.pageId);
      if (!context.mounted) return false;
      loaded = result;
    } on VaultFileLockException {
      return false; // 保险库已锁定——fail-closed
    }
    if (loaded == null || !context.mounted) return false;
    // 局部非空副本（闭包内捕获的变量不参与类型提升）。
    final notebook = loaded;

    final sessionPw = args.sessionPassword;
    if (sessionPw != null) {
      try {
        final ok = await storage.decryptNotebook(loaded, sessionPw);
        if (!ok || !context.mounted) return false;
        final mediaSalt = await storage.ensureMediaSalt();
        await _services.mediaCrypto.setSessionPassword(sessionPw, mediaSalt);
      } on FormatException {
        return false; // 密码失效（缓存过期/重置竞态）——fail-closed
      }
    }
    if (!context.mounted) return false;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotebookViewPage(
          notebook: notebook,
          storage: storage,
          blockDocStore: _blockDocStore,
          editorPageBuilder: _editorPageBuilder,
          mediaCrypto: _services.mediaCrypto,
          sessionPassword: sessionPw,
        ),
      ),
    );
    return true;
  }

  @override
  Future<bool> startNotebookPasswordReset(
    BuildContext context,
    NotebookPasswordResetRequest request,
  ) async {
    final storage = _notebookStorage;
    if (storage == null) return false;
    return NotebookPasswordResetFlow.show(
      context,
      storage: storage,
      notebookId: request.notebookId,
      notebookTitle: request.notebookTitle,
    );
  }

  @override
  Future<bool> startFilePasswordReset(
    BuildContext context,
    FilePasswordResetRequest request,
  ) async {
    final storage = _documentStorage;
    if (storage == null || !context.mounted) return false;
    return FilePasswordResetFlow.show(
      context,
      storage: storage,
      docId: request.docId,
      docTitle: request.docTitle,
    );
  }

  @override
  Future<DocTemplate?> showTemplatePicker(
    BuildContext context, {
    DocTemplate? selected,
  }) {
    final l10n = AppLocalizations.of(context);
    return GlassDialog.show<DocTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n?.homeSelectTemplate ?? '选择笔记模板'),
        children: [
          for (final t in DocTemplate.values)
            // 键盘可达：首个模板选项初始聚焦。
            Focus(
              autofocus: t == DocTemplate.values.first,
              child: SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(t),
                child: ListTile(
                  leading: Icon(_templateIcon(t)),
                  title: Text(_templateNameOf(ctx, t) ?? t.label),
                  subtitle: Text(_templateDescOf(ctx, t)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 模板 → 图标（展示层映射；模板本体在 core，不含 material 依赖）。
  static IconData _templateIcon(DocTemplate t) {
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

  /// i18n（E1 批 4）：模板名（domain 的 label 为 zh 兜底）。
  static String? _templateNameOf(BuildContext context, DocTemplate t) {
    final l10n = AppLocalizations.of(context);
    switch (t) {
      case DocTemplate.blank:
        return l10n?.tplBlankName ?? '空白笔记';
      case DocTemplate.meeting:
        return l10n?.tplMeetingName ?? '会议纪要';
      case DocTemplate.daily:
        return l10n?.tplDailyName ?? '每日日志';
      case DocTemplate.todoList:
        return l10n?.tplTodoName ?? '待办清单';
    }
  }

  /// i18n（E1 批 4）：模板说明。
  static String _templateDescOf(BuildContext context, DocTemplate t) {
    final l10n = AppLocalizations.of(context);
    switch (t) {
      case DocTemplate.blank:
        return l10n?.tplBlankDesc ?? '从零开始';
      case DocTemplate.meeting:
        return l10n?.tplMeetingDesc ?? '议题 · 决议 · 行动项';
      case DocTemplate.daily:
        return l10n?.tplDailyDesc ?? '今日完成 · 明日计划';
      case DocTemplate.todoList:
        return l10n?.tplTodoDesc ?? '预置待办块';
    }
  }
}
