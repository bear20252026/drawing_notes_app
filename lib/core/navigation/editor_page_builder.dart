import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/rendering/notebook_print_page_data.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';

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

      /// 同本全部会话（笔记本范围=全部页用；独立画布为 null）。
      /// 类型保持 core 契约（notes 聚合不泄漏进组合签名）。
      List<EditorPageSession> Function()? allSessions,

      /// 多页 PDF 合成引擎（C-01 解环，审计 2026-09-27）：core 只读页
      /// 契约入参，实现由组合根绑定（notes 的 NotebookPdfExporter）。
      Future<Uint8List> Function(
        List<NotebookPrintPageData> pages, {
        int? jpegQuality,
      })?
      multipageComposer,

      INotebookAccessor? notebookAccessor,
      StorageService? documentStorage,
      VoidCallback? onChanged,

      /// 媒体会话解密服务（C-06，审计 2026-09-27）：编辑器内嵌图片
      /// （EncryptedFileImage）的解密依赖由组合根传线——编辑器不再直取
      /// 全局单例；可空（测试直构 EditorPage 未注入时按既有「会话密钥
      /// 未注入」语义 fail-closed）。
      MediaCryptoService? mediaCrypto,
      Future<void> Function(BuildContext context)? openPresentation,
    });
