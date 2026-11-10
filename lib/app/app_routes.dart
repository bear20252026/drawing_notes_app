// 跨 feature 路由契约层（2026-10-10 解耦批次）。
//
// 缘起：`features/notes` 的三个入口（home_page / search_page /
// notebook_view_page）此前直接 import `features/doc/presentation/doc_page.dart`
// 与 `features/security/presentation/*` 的具体页面来 push，构成跨 feature
// 反向依赖（违反本仓 `docs/ARCHITECTURE.md` 的 feature 分层：
// `features/*` 只能依赖 `core/`，不得横向 import 他 feature 的
// presentation 层）。
//
// 本文件是**纯契约**：只声明 typedef + 参数 DTO，不 import 任何
// `features/` 下的实现。实现由组合根 `app_shell_routes.dart` /
// `composition_root.dart` 注入，notes 侧因此只需依赖 `core/`（参数类型）
// 与 `app/`（本文件）。
//
// 设计要点：
// - 参数一律走**不可变 DTO**（[DocOpenArgs] / [NotebookOpenArgs] /
//   [NotebookPasswordResetRequest]），不直接传 doc 的 `NoteBlockDoc`
//   —— 否则本文件仍要 import doc 的 application 层。
// - 回调返回 `Future<bool>`（是否成功），与既有页面的 `EditorPageBuilder`
//   同构，保持宿主对「成功/失败」的分支语义。
// - 模板选择（[showTemplatePicker]）同样走契约：notes 只声明「我要一个
//   模板」，弹窗 UI 由组合根注入的实现拼装——避免 notes 反向 import
//   doc 的 presentation 层去自己拼模板选择器。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_templates.dart';

/// 打开「打字笔记」（块文档）页的入口描述。
///
/// 字段与 `features/doc/presentation/doc_page.dart` 的 `DocPage` 构造一一
/// 对应，但**只经 core 类型**表达：
/// - [id] / [title] / [body] / [createdAt] / [updatedAt] / [tags]
///   → 组成 `NoteBlockDoc`；
/// - [isFavorite] / [allowCopyPaste] → DocPage 的受控状态。
///
/// 新增字段时优先扩展本 DTO，而不是把 doc 的类型泄进契约层。
class DocOpenArgs {
  const DocOpenArgs({
    required this.id,
    required this.title,
    this.body = const <NoteBlock>[],
    this.createdAt,
    this.updatedAt,
    this.tags = const <String>[],
    this.isFavorite = false,
    this.allowCopyPaste = false,
    this.onSaved,
  });

  final String id;
  final String title;
  final List<NoteBlock> body;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final bool isFavorite;

  /// 是否以「复制/粘贴到画布」的暂存中转模式打开（宿主据此决定是否把
  /// DocPage 挂上剪贴板回调）。
  final bool allowCopyPaste;

  /// 保存后的钩子（可选）：在实现侧完成**默认持久化之后**调用。
  ///
  /// 存在的理由：笔记本页「以块文档打开」这条腿在保存后必须回写源页
  /// （`NotebookPage.title/updatedAt`）并走加密本的 `encryptAndSave` 分支
  /// —— 这是 notes 侧的领域逻辑，无法下沉到 app 层。经此钩子回注，
  /// notes 既不失去该行为，也不需知道 DocPage 的存在。
  ///
  /// 参数为**已保存后**的文档（标题/时间戳可能已变）。
  final void Function(NoteBlockDoc saved)? onSaved;
}

/// 打开分页画布（笔记本页）编辑器的入口描述。
///
/// 与 `NotebookViewPage` 的「打开某页」语义同构，用于宿主在只持有
/// id/title（例如搜索结果）时请求打开，而无需构造真实的
/// `NotebookPage`。
class NotebookOpenArgs {
  const NotebookOpenArgs({
    required this.pageId,
    required this.pageTitle,
    this.notebookId,
    this.sessionPassword,
  });

  final String pageId;
  final String pageTitle;

  /// 所属笔记本 id（用于打开整个笔记本视图）；可空。
  final String? notebookId;

  /// 会话内已解锁的笔记本密码（仅内存持有，不落盘）。
  ///
  /// 搜索结果页在解锁拦截后已拿到会话密码（加密本场景），打开编辑器时
  /// 必须一并传入，否则保存时无法重加密——这正是 `NotebookViewPage`
  /// `sessionPassword` 参数存在的理由（修复“编辑后无法保存”）。
  /// 非加密本为 null。
  final String? sessionPassword;
}

/// 笔记本「忘记密码」重置请求。
///
/// notes 只声明「请为这个笔记本启动重置流」，具体流程（USB 槽位校验 →
/// 密码重设 → 解锁）由 security 侧实现，经组合根注入
/// [AppRouteServices.startNotebookPasswordReset]。
class NotebookPasswordResetRequest {
  const NotebookPasswordResetRequest({
    required this.notebookId,
    required this.notebookTitle,
  });

  final String notebookId;
  final String notebookTitle;
}

/// 画布（独立密码）「忘记密码」重置请求。
///
/// 与 [NotebookPasswordResetRequest] 同构但**独立声明**：画布走
/// `FilePasswordResetFlow`、笔记本走 `NotebookPasswordResetFlow`，
/// 两者 storage 类型不同（`StorageService` vs `NotebookStorage`），
/// 合成一个 DTO 会迫使契约层依赖 notes 的 infrastructure 类型。
class FilePasswordResetRequest {
  const FilePasswordResetRequest({
    required this.docId,
    required this.docTitle,
  });

  final String docId;
  final String docTitle;
}

/// 跨 feature 路由服务契约（由组合根实现并注入）。
abstract interface class AppRouteServices {
  /// 打开打字笔记页（原 notes 直推 `DocPage`）。
  Future<bool> openNotePage(BuildContext context, DocOpenArgs args);

  /// 打开分页画布（原 notes 直推 `NotebookViewPage`）。
  Future<bool> openNotebookPage(BuildContext context, NotebookOpenArgs args);

  /// 启动笔记本密码重置流（原 notes 直推 security 的
  /// `NotebookPasswordResetFlow.show`）。
  Future<bool> startNotebookPasswordReset(
    BuildContext context,
    NotebookPasswordResetRequest request,
  );

  /// 启动画布独立密码重置流（原 notes 直推 security 的
  /// `FilePasswordResetFlow.show`）。
  Future<bool> startFilePasswordReset(
    BuildContext context,
    FilePasswordResetRequest request,
  );

  /// 弹出「选择笔记模板」选择器（原 notes 自拼的 GlassDialog）。
  ///
  /// 返回 null 表示用户取消。
  Future<DocTemplate?> showTemplatePicker(
    BuildContext context, {
    DocTemplate? selected,
  });
}

/// 由「已装配的实现」反查服务的便捷入口。
///
/// 用法（与 `SessionSecrets.instance` 同构，避免每个消费点都多接一个
/// required 参数——尤其是历史测试的大量直构点）：
///
/// ```dart
/// final routes = AppRouteServices.instance;
/// if (routes == null) { /* 未装配（独立页面直构） */ }
/// ```
///
/// 该实例由组合根 `CompositionRoot.build()` 写入；测试可注入假实现来
/// 断言「点击后走了路由」而不真的 push 页面。
AppRouteServices? get appRouteServices => _instance;
set appRouteServices(AppRouteServices? value) => _instance = value;

AppRouteServices? _instance;
