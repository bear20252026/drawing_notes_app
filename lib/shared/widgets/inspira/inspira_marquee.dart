// Inspira UI · Marquee —— 无缝循环滚动展示条。
//
// 灵感来自 Inspira UI 的 Marquee 组件（MIT），本项目以纯 Flutter 重写：
// - 内容沿水平方向无限循环滚动（内容取模平移，宽度不足视口时自动复制补齐）；
// - 鼠标悬停自动暂停（hoverPause），移开恢复；
// - 尊重系统「减弱动态效果」：静态展示、不启动 ticker；
// - 空内容安全退化为空组件。
//
// 典型用法（首页最近文件/画作横滚展示）：
//   InspiraMarquee(
//     items: [for (final f in recentFiles) FileThumb(file: f)],
//     velocity: 30,
//   )

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class InspiraMarquee extends StatefulWidget {
  const InspiraMarquee({
    super.key,
    required this.items,
    this.velocity = 32,
    this.gap = 28,
    this.hoverPause = true,
    this.height,
    this.padding = EdgeInsets.zero,
    this.fadeEdges = true,
    this.fadeWidth = 40,
  });

  /// 循环滚动的条目（调用方自行包 InkWell 处理点击）。
  final List<Widget> items;

  /// 滚动速度（逻辑像素/秒）；正值向左滚。
  final double velocity;

  /// 条目间距。
  final double gap;

  /// 鼠标悬停时是否暂停。
  final bool hoverPause;

  /// 视口高度；缺省由父级约束决定。
  final double? height;

  final EdgeInsetsGeometry padding;

  /// 两端渐隐遮罩（避免内容硬切边缘）。
  final bool fadeEdges;

  final double fadeWidth;

  @override
  State<InspiraMarquee> createState() => _InspiraMarqueeState();
}

class _InspiraMarqueeState extends State<InspiraMarquee>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _offset = 0;
  bool _hovering = false;
  Duration _lastTick = Duration.zero;

  /// 单份内容的实测宽度（含条目间 gap）；null 表示尚未测量完成。
  double? _contentWidth;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  void _maybeStartTicker(bool animationsEnabled) {
    final shouldRun = animationsEnabled &&
        widget.items.isNotEmpty &&
        !_hovering &&
        _contentWidth != null;
    if (shouldRun && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final w = _contentWidth;
    if (w == null || w <= 0) return;
    setState(() {
      // 取模防长时间运行后浮点精度劣化。
      _offset = (_offset + widget.velocity * dt) % w;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceEffects = MediaQuery.disableAnimationsOf(context);
    _maybeStartTicker(!reduceEffects);

    if (widget.items.isEmpty) return const SizedBox.shrink();

    Widget viewport = LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;

        // 第一帧先离屏测量单份内容宽度（UnconstrainedBox 去除视口宽度
        // 约束，超宽内容也不会触发 overflow）。
        if (_contentWidth == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final box =
                _measureKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize) return;
            final w = box.size.width;
            if (w <= 0) return;
            setState(() => _contentWidth = w);
          });
          return Offstage(
            offstage: true,
            child: UnconstrainedBox(
              child: Row(
                key: _measureKey,
                mainAxisSize: MainAxisSize.min,
                children: _singlePass(),
              ),
            ),
          );
        }

        // 内容比视口窄时复制补齐，保证取模平移后无缝衔接。
        // 每份拷贝包在独立 Row（唯一 key）里：调用方条目若自带 key，
        // 不同父级下互不为兄弟节点，不会触发重复 key 断言。
        final repeats =
            (viewW / _contentWidth!).ceil().clamp(1, 8) + 1;

        // 拷贝行总宽必然超过视口（repeats 设计如此）：
        // OverflowBox 解除宽度约束让行按内容自然排布（不触发 overflow），
        // 超出部分由上层 ClipRect 裁剪。
        Widget strip = Transform.translate(
          offset: Offset(-_offset, 0),
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < repeats; r++)
                  Row(
                    key: ValueKey('inspira-marquee-copy-$r'),
                    mainAxisSize: MainAxisSize.min,
                    children: _singlePass(),
                  ),
              ],
            ),
          ),
        );

        strip = MouseRegion(
          onEnter: widget.hoverPause
              ? (_) {
                  _hovering = true;
                  _maybeStartTicker(!reduceEffects);
                }
              : null,
          onExit: widget.hoverPause
              ? (_) {
                  _hovering = false;
                  _maybeStartTicker(!reduceEffects);
                }
              : null,
          child: strip,
        );

        Widget result = ClipRect(child: strip);
        if (widget.fadeEdges && viewW > 0) {
          result = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final w = bounds.width;
              if (w <= 0) return const LinearGradient(colors: [Colors.white, Colors.white]).createShader(bounds);
              final fade = widget.fadeWidth.clamp(0.0, w / 2);
              return LinearGradient(
                colors: const [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0, fade / w, 1 - fade / w, 1],
              ).createShader(bounds);
            },
            child: result,
          );
        }
        return result;
      },
    );

    return Padding(
      padding: widget.padding,
      child: SizedBox(
        height: widget.height,
        child: viewport,
      ),
    );
  }

  final GlobalKey _measureKey = GlobalKey();

  /// 一份完整内容（items + 间隔），末尾也带 gap 以保证循环接缝均匀。
  List<Widget> _singlePass() {
    final gap = SizedBox(width: widget.gap);
    return [
      for (final item in widget.items) ...[item, gap],
    ];
  }
}
