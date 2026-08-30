import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';

/// 由应用组合根提供的编辑器页面构建契约。
///
/// notes 与 drawing 均可依赖此契约，但只有 app 层知道具体的
/// [EditorPage] 实现。这样笔记页不必直接 import 绘图的 presentation，
/// 同时保留独立画布和笔记页混排两种编辑会话的既有参数语义；笔记页
/// 在 notes 内部先适配为 [EditorPageSession]，避免把 notes 聚合泄漏到
/// drawing presentation。
typedef EditorPageBuilder =
    Widget Function({
      DrawingDocument? document,
      EditorPageSession? session,
      INotebookAccessor? notebookAccessor,
      StorageService? documentStorage,
      VoidCallback? onChanged,
      Future<void> Function(BuildContext context)? openPresentation,
    });
