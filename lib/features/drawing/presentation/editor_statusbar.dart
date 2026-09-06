import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_motion.dart';
import 'package:drawing_notes_app/features/drawing/application/di_providers.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/application/stylus_input.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 编辑器状态栏（审计三-2 改版，2026-09-06）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：纯展示组件——只监听
/// [controller] 与 [hoverPos] 渲染，操作经回调返回，不读写文件与存储。
/// 改版内容：
/// - 缩放百分比 → 胶囊按钮，点开 50/100/200/适应画布 菜单；
/// - 保存状态 → 图标 + 文本色芯片，状态切换带 toastIn 微动效；
/// - 画布坐标读数 → 仅桌面平台可见、默认收起（坐标是调试器审美），
///   需要时点右侧按钮展开；
/// - 图标统一 rounded 系。
class EditorStatusBar extends ConsumerStatefulWidget {
  const EditorStatusBar({
    super.key,
    required this.document,
    required this.hoverPos,
    required this.inkPressureSample,
    required this.saving,
    required this.lastSavedAt,
    required this.onZoomTo,
    required this.onZoomFit,
  });

  /// 文档（family provider 参数；controller 经 Riverpod 派生获取）。
  final DrawingDocument document;

  /// 鼠标悬停/移动时的画布坐标（状态栏显示）。
  final ValueListenable<Offset?> hoverPos;

  /// 最近一次墨迹输入的压力来源。为空表示尚未开始书写。
  final ValueListenable<InkPressureSample?> inkPressureSample;

  /// 自动保存进行中（编辑器状态传入，非本组件自行推断）。
  final bool saving;

  /// 最近一次保存完成时间（null = 本次会话尚未保存过）。
  final DateTime? lastSavedAt;

  /// 缩放菜单动作：缩放到指定倍率（宿主保证视口中心不漂移）。
  final ValueChanged<double> onZoomTo;

  /// 缩放菜单动作：按视口适应整页并居中。
  final VoidCallback onZoomFit;

  @override
  ConsumerState<EditorStatusBar> createState() => _EditorStatusBarState();
}

class _EditorStatusBarState extends ConsumerState<EditorStatusBar> {
  /// 画布坐标读数开关：默认关（审计三-2），仅桌面平台提供。
  bool _coordsVisible = false;

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  String _saveLabel(bool dirty) {
    if (widget.saving) return '保存中…';
    final t = widget.lastSavedAt;
    if (t == null || dirty) return '未保存';
    return '已保存 '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  Color _saveColor(ThemeData theme, bool dirty) {
    final blue = theme.brightness == Brightness.dark
        ? AppleColor.actionBlueOnDark
        : AppleColor.actionBlue;
    if (widget.saving) return blue;
    if (dirty) return AppleColor.favourite;
    return AppleColor.noteGreen;
  }

  IconData get _saveIcon {
    if (widget.saving) return Icons.sync_rounded;
    if (widget.lastSavedAt == null) return Icons.cloud_upload_rounded;
    return Icons.check_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(drawingControllerProvider(widget.document));
    final theme = Theme.of(context);
    return Material(
      elevation: 2,
      color: theme.colorScheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final isEraser = controller.tool == BrushType.eraser;
          final activeSize = isEraser
              ? controller.eraserSize
              : controller.brushSize;
          return ValueListenableBuilder<Offset?>(
            valueListenable: widget.hoverPos,
            builder: (context, pos, _) =>
                ValueListenableBuilder<InkPressureSample?>(
                  valueListenable: widget.inkPressureSample,
                  builder: (context, pressure, _) {
                    final scalePercent = (controller.viewScale * 100).round();
                    final pressureLabel = pressure?.diagnostics;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isEraser
                                ? Icons.auto_fix_high_rounded
                                : Icons.brush_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isEraser ? '橡皮擦' : '画笔',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${activeSize.round()}px',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (pressureLabel != null) ...[
                            const SizedBox(width: 12),
                            Tooltip(
                              message: pressure!.hasHardwarePressure
                                  ? '正在使用设备上报的真实压力范围'
                                  : '当前设备未报告可用压感，正在使用稳定的回退策略',
                              child: Text(
                                pressureLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: pressure.hasHardwarePressure
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          // 保存状态芯片：状态切换带 toastIn 微动效
                          //（频率闸门：偶发档，标准动画合规）。
                          _buildSaveChip(theme, controller.isDirty),
                          const SizedBox(width: 12),
                          // 缩放胶囊：点开 50/100/200/适应画布。
                          _buildZoomPill(theme, scalePercent),
                          // 画布坐标读数：仅桌面 + 默认关（审计三-2）。
                          if (_isDesktop) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: _coordsVisible ? '隐藏坐标' : '显示画布坐标',
                              visualDensity: VisualDensity.compact,
                              isSelected: _coordsVisible,
                              icon: Icon(Icons.my_location_rounded, size: 16),
                              onPressed: () => setState(
                                () => _coordsVisible = !_coordsVisible,
                              ),
                            ),
                            if (_coordsVisible)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Text(
                                  pos != null
                                      ? 'x:${pos.dx.round()} y:${pos.dy.round()}'
                                      : 'x:- y:-',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
          );
        },
      ),
    );
  }

  Widget _buildSaveChip(ThemeData theme, bool dirty) {
    final color = _saveColor(theme, dirty);
    final label = _saveLabel(dirty);
    final row = Row(
      key: ValueKey<String>(label),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_saveIcon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
    if (AppleMotion.reduceMotionOf(context)) {
      // 减弱动效：更轻——只做交叉淡入，去掉缩放。
      return AnimatedSwitcher(duration: AppleMotion.toastIn, child: row);
    }
    return AnimatedSwitcher(
      duration: AppleMotion.toastIn,
      switchInCurve: AppleMotion.easeOut,
      switchOutCurve: AppleMotion.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: AppleMotion.enterScale, end: 1).animate(
            CurvedAnimation(parent: animation, curve: AppleMotion.easeOut),
          ),
          child: child,
        ),
      ),
      child: row,
    );
  }

  Widget _buildZoomPill(ThemeData theme, int scalePercent) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppleRadius.pill),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: PopupMenuButton<_ZoomChoice>(
        tooltip: '缩放画布',
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppleRadius.md)),
        ),
        initialValue: switch (scalePercent) {
          50 => _ZoomChoice.z50,
          100 => _ZoomChoice.z100,
          200 => _ZoomChoice.z200,
          _ => null,
        },
        onSelected: (choice) {
          switch (choice) {
            case _ZoomChoice.z50:
              widget.onZoomTo(0.5);
            case _ZoomChoice.z100:
              widget.onZoomTo(1.0);
            case _ZoomChoice.z200:
              widget.onZoomTo(2.0);
            case _ZoomChoice.fit:
              widget.onZoomFit();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _ZoomChoice.z50, child: Text('50%')),
          PopupMenuItem(value: _ZoomChoice.z100, child: Text('100%')),
          PopupMenuItem(value: _ZoomChoice.z200, child: Text('200%')),
          PopupMenuItem(value: _ZoomChoice.fit, child: Text('适应画布')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.zoom_out_map_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text('$scalePercent%', style: theme.textTheme.bodySmall),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ZoomChoice { z50, z100, z200, fit }
