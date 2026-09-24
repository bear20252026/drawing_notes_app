// 绘图展示层小组件集合（F9 自 editor_components.dart 拆出，2026-09-24）：
// 快捷键行/番茄钟/分页预览/线性读数气泡。使用方继续 import
// editor_components.dart（export 桶兼容）或直接本文件。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';


/// 编辑器纯展示组件集（架构重构 R1：从 editor_page 外移的零耦合组件）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 本文件内组件**不持有编辑器状态**，全部通过构造参数传入；
/// - 不读写文件、不调用存储层——纯展示/渲染职责；
/// - 每个组件 ≤100 行，职责单一，可独立测试。

/// 快捷键帮助条目（键位 + 说明）。
class ShortcutRow extends StatelessWidget {
  const ShortcutRow({super.key, required this.shortcut, required this.action});

  final String shortcut;
  final String action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppleRadius.xs),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              shortcut,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}


/// 番茄钟专注计时浮层（D2，借鉴 Relatum 学习工具）。
///
/// 默认 25 分钟专注计时，支持开始/暂停/重置；到时触发 [onFinished]。
class PomodoroTimer extends StatefulWidget {
  const PomodoroTimer({super.key, this.onFinished});

  final VoidCallback? onFinished;

  /// 默认专注时长：25 分钟。
  static const Duration defaultDuration = Duration(minutes: 25);

  @override
  State<PomodoroTimer> createState() => _PomodoroTimerState();
}


class _PomodoroTimerState extends State<PomodoroTimer> {
  late Duration _remaining = PomodoroTimer.defaultDuration;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _remaining -= const Duration(seconds: 1);
          if (_remaining <= Duration.zero) {
            _remaining = Duration.zero;
            _timer!.cancel();
            _timer = null;
            widget.onFinished?.call();
          }
        });
      });
    }
    setState(() {});
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    setState(() => _remaining = PomodoroTimer.defaultDuration);
  }

  @override
  Widget build(BuildContext context) {
    final mins = _remaining.inMinutes.toString().padLeft(2, '0');
    final secs = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    final running = _timer != null;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(AppleRadius.lg),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.87),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, size: 16),
            const SizedBox(width: 4),
            Text(
              '$mins:$secs',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: running
                  ? AppLocalizations.of(context)?.pomodoroPause ?? '暂停'
                  : AppLocalizations.of(context)?.pomodoroStart ?? '开始',
              icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: _toggle,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context)?.pomodoroReset ?? '重置',
              icon: const Icon(Icons.refresh, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }
}


/// 分页预览组件（D3：长笔记多页预览，借鉴 Umo Editor 分页模式）。
///
/// 把文字块按 A4 页面高度（逻辑像素）分页渲染，
/// 每页显示页眉（标题+页码）与内容，超出页高的内容流到下一页。
class PaginationPreview extends StatefulWidget {
  const PaginationPreview({super.key, required this.textItems});

  final List<PageTextItem> textItems;

  @override
  State<PaginationPreview> createState() => _PaginationPreviewState();
}


class _PaginationPreviewState extends State<PaginationPreview> {
  /// A4 页面逻辑高度（对应画布 2480x3508 的近似高度）。
  static const double _pageHeight = 800;

  /// 单行文字估算高度。
  static const double _lineHeight = 28;

  /// 分页结果 memo（渲染性能 2026-09-07）：此前每次 build 都重跑分页
  /// 算法。输入未变（同一 textItems 引用 + 长度一致；PageTextItem 无
  /// revision 字段，调用方以 page.textItems 整列表传入，增删必改变
  /// 长度）则复用上次结果。
  List<List<PageTextItem>>? _pages;

  @override
  void didUpdateWidget(PaginationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.textItems, widget.textItems) ||
        oldWidget.textItems.length != widget.textItems.length) {
      _pages = null;
    }
  }

  List<List<PageTextItem>> _computePages() {
    // 分页：按估算行数把文字块分配到多页。
    final pages = <List<PageTextItem>>[];
    var current = <PageTextItem>[];
    var used = 60.0; // 页顶留白
    for (final t in widget.textItems) {
      final lines = (t.text.length / 18).ceil().clamp(1, 20);
      final h = _lineHeight * lines + 12;
      if (used + h > _pageHeight && current.isNotEmpty) {
        pages.add(current);
        current = <PageTextItem>[];
        used = 60.0;
      }
      current.add(t);
      used += h;
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages ??= _computePages();

    return ListView.builder(
      itemCount: pages.length,
      itemBuilder: (context, i) {
        final items = pages[i];
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppleColor.hairline),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(
                            context,
                          )?.pageIndicator(i + 1, pages.length) ??
                          '第 ${i + 1} 页 / 共 ${pages.length} 页',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    t.text,
                    // 文档列表条目：control 13 + 块级富文本修饰。
                    style: AppleType.controlStyle(
                      Color(t.color),
                      weight: t.bold ? FontWeight.bold : FontWeight.normal,
                    ).copyWith(
                      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
                      decoration: t.underline
                          ? TextDecoration.underline
                          : (t.strikethrough
                                ? TextDecoration.lineThrough
                                : TextDecoration.none),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}


/// 线性元素拖拽读数气泡（审计二-6，2026-09-06）。
///
/// 创建/编辑直线与箭头时显示「长度 px · 角度°」：触屏手指遮挡落点时，
/// 用户至少「看得见」自己在画什么。浮层材质（玻璃胶囊），不拦截指针。
class LinearReadoutBubble extends StatelessWidget {
  const LinearReadoutBubble({
    super.key,
    required this.length,
    required this.angleDeg,
  });

  /// 长度（画布坐标 px）。
  final double length;

  /// 与水平方向的夹角（度，0~360）。
  final double angleDeg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppleRadius.pill),
      sigma: 8,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        '${length.round()}px · ${angleDeg.round()}°',
        style: AppleType.captionStyle(scheme.onSurface),
      ),
    );
  }
}
