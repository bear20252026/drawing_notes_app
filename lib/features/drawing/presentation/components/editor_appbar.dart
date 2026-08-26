/// 编辑器顶部栏 — 独立 Widget。
///
/// 从 editor_page_appbar.dart 拆分出的独立组件。
/// 负责：
/// - 顶部工具栏按钮（撤销/重做/分享/关闭）
/// - 标题显示
/// - 全屏切换
///
/// 通过回调向上传递用户操作。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_design.dart';
import '../controllers/editor_state.dart';

/// 编辑器顶部栏。
class EditorAppBar extends StatelessWidget {
  const EditorAppBar({
    super.key,
    required this.editorState,
    required this.title,
    this.onClose,
    this.onUndo,
    this.onRedo,
    this.onShare,
    this.onToggleFullscreen,
    this.canUndo = false,
    this.canRedo = false,
  });

  /// 编辑器状态。
  final EditorState editorState;

  /// 标题文本。
  final String title;

  /// 关闭回调。
  final VoidCallback? onClose;

  /// 撤销回调。
  final VoidCallback? onUndo;

  /// 重做回调。
  final VoidCallback? onRedo;

  /// 分享回调。
  final VoidCallback? onShare;

  /// 全屏切换回调。
  final VoidCallback? onToggleFullscreen;

  /// 是否可以撤销。
  final bool canUndo;

  /// 是否可以重做。
  final bool canRedo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppDesign.surfaceBlack : AppDesign.canvasParchment;
    final textColor = isDark ? AppDesign.bodyOnDark : AppDesign.ink;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: editorState.fullscreen ? 0 : 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppDesign.bodyMuted.withValues(alpha: 0.2)
                : AppDesign.dividerSoft,
            width: 0.5,
          ),
        ),
      ),
      child: editorState.fullscreen
          ? const SizedBox.shrink()
          : Row(
              children: [
                // 关闭按钮
                _ToolbarButton(
                  icon: Icons.close_rounded,
                  onPressed: onClose,
                  tooltip: '关闭',
                ),
                const Spacer(),
                // 标题
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                // 撤销
                _ToolbarButton(
                  icon: Icons.undo_rounded,
                  onPressed: canUndo ? onUndo : null,
                  tooltip: '撤销',
                ),
                // 重做
                _ToolbarButton(
                  icon: Icons.redo_rounded,
                  onPressed: canRedo ? onRedo : null,
                  tooltip: '重做',
                ),
                // 分享
                _ToolbarButton(
                  icon: Icons.ios_share_rounded,
                  onPressed: onShare,
                  tooltip: '分享',
                ),
                // 全屏
                _ToolbarButton(
                  icon: editorState.fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onPressed: onToggleFullscreen,
                  tooltip: editorState.fullscreen ? '退出全屏' : '全屏',
                ),
              ],
            ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = onPressed != null
        ? (isDark ? AppDesign.bodyOnDark : AppDesign.ink)
        : (isDark ? AppDesign.bodyMuted : AppDesign.inkMuted48);

    return Semantics(
      button: true,
      label: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppDesign.roundedSm),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}
