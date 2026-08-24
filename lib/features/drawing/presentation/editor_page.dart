import 'dart:async';

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/features/drawing/application/brush_preset_store.dart';
import 'package:drawing_notes_app/features/drawing/application/command_registry.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_input_arbiter.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode_store.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_exporter.dart';
import 'package:drawing_notes_app/features/drawing/domain/fractional_index.dart';
import 'package:drawing_notes_app/features/drawing/application/gesture_math.dart';
import 'package:drawing_notes_app/core/rendering/pencil_shader.dart';
import 'package:drawing_notes_app/core/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/shape_creation_geometry.dart';
import 'package:drawing_notes_app/features/drawing/presentation/shape_library.dart';
import 'package:drawing_notes_app/core/utils/safe_url.dart';
import 'package:drawing_notes_app/features/drawing/application/stylus_input.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/view_transform_cache.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/core/notes_accessor.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/presentation/canvas_painter.dart';
import 'package:drawing_notes_app/features/drawing/presentation/encrypted_file_image.dart';
import 'package:drawing_notes_app/shared/widgets/color_picker_dialog.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_components.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_context_bar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_left_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_statusbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_viewmodel.dart';
import 'package:drawing_notes_app/features/drawing/presentation/layer_panel.dart';
import 'package:drawing_notes_app/features/drawing/presentation/properties_panel.dart';
import 'package:drawing_notes_app/features/drawing/presentation/resize_handles.dart';
import 'package:drawing_notes_app/features/drawing/presentation/selection_bar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/toolbar_state_mapper.dart';

part 'editor_page_dialogs.dart';
part 'editor_page_overlays.dart';
part 'editor_page_drag_ops.dart';
part 'editor_page_input.dart';
part 'editor_page_input_gestures.dart';
part 'editor_page_editing.dart';
part 'editor_page_actions.dart';
part 'editor_page_tools.dart';
part 'editor_page_commands.dart';
part 'editor_page_shortcuts.dart';
part 'editor_page_persistence.dart';
part 'editor_page_appbar.dart';
part 'editor_page_body.dart';
part 'editor_page_pinch.dart';
part 'editor_page_fields.dart';

/// 编辑器页面。
///
/// 两种使用场景：
/// 1. 独立画作模式：仅传 [document]（Phase 1-4，画布功能）；
/// 2. 笔记本页面模式：传 [notebook]/[page]/[storage]/[onChanged]，
///    在画布之上叠加文字块与图片块（Phase 5 混排）。
///
/// 职责：
/// - 手势采集：笔画 / 选区 / 吸管 / 文字与图片放置
/// - 工具面板：撤销、重做、清空、画笔/橡皮擦/吸管/选区/文字/图片
/// - 保存回调：任何变更后调用 [onChanged]（由上级页面负责落盘）
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({
    super.key,
    DrawingDocument? document,
    this.notebook,
    this.page,
    this.storage,
    this.docStorage,
    this.onChanged,
    this.openPresentation,
  }) : _initialDocument = document;

  /// 独立画作模式：初始文档（为空时创建默认空白文档）。
  final DrawingDocument? _initialDocument;

  /// 笔记本页面模式：所属笔记本与当前页面。
  final Notebook? notebook;
  final NotebookPage? page;

  /// 笔记侧存储契约（插入图片时复制图片副本用）。
  final INotebookAccessor? storage;

  /// 独立画作存储（Phase 6 自动保存用）。
  final StorageService? docStorage;

  /// 打开放映页的回调（跨 feature 页面跳转契约，S4b 接口化）：
  /// 由笔记侧注入实现（跳转 PresentationPage），drawing 不直接依赖
  /// notes 的 presentation UI；null 时演示功能提示不可用。
  final Future<void> Function(BuildContext context, NotebookPage page)?
      openPresentation;

  /// 内容变更回调（自动保存由上级页面实现）。
  final VoidCallback? onChanged;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with _EditorPageStateFields {
  /// 指针落下：跟踪指针，必要时进入绘制/选区流程。

  // ---------------- 文字 / 图片混排（Phase 5） ----------------

  /// 文字工具：点击画布后在该位置直接就地输入文字（借鉴 OneNote/Word，
  /// 不再弹窗输入）。文字块先创建为空文本并进入编辑状态，回车/失焦提交。

  /// 处理键盘动作。
  ///
  /// 借鉴 Excalidraw ActionManager：快捷键只负责匹配和分发，真正的
  /// 可用性与副作用始终收敛在 [_commands]。这样当同一动作在菜单或
  /// 命令面板中呈现时，不会出现“快捷键能用但按钮不可用”的分叉。
  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _allowPopAfterSave,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _allowPopAfterSave) return;
        final navigator = Navigator.of(context);
        await _flushBeforePop();
        if (!mounted) return;
        setState(() => _allowPopAfterSave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) navigator.pop(result);
        });
      },
      child: KeyboardListener(
        focusNode: _shortcutFocus,
        autofocus: true,
        onKeyEvent: _onShortcutKey,
        child: Scaffold(
          appBar: _buildAppBar(context),
          body: _fullscreen
              ? _buildCanvasArea()
              : _buildBody(context),
          bottomNavigationBar: _buildStatusBar(),
        ),
      ),
    );
  }

  /// 底部状态栏：缩放比例、当前工具粗细、鼠标画布坐标。
}