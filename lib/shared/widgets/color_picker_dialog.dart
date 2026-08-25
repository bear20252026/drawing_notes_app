import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';

/// 颜色选择对话框（Phase 2 验收：色板 + 自由调色）。
///
/// 提供两种取色方式：
/// 1. 预设色板：12 种常用色，单击即选中；
/// 2. 自由调色：色相(H)/饱和度(S)/明度(V) 三个滑块，实时预览。
///
/// 使用方式：
/// ```dart
/// final color = await showDialog<Color>(
///   context: context,
///   builder: (_) => ColorPickerDialog(initialColor: currentColor),
/// );
/// if (color != null) controller.color = color;
/// ```
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key, required this.initialColor});

  final Color initialColor;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  /// 最近使用的自定义色（会话内，借鉴 Excalidraw CustomColorList）。
  static final List<Color> _recentColors = [];

  /// 当前选择的颜色（HSV 模型便于滑块调节）。
  late HSVColor _hsv;
  late Color _selected;

  /// 取色超时计时器（#38 修复——5 秒自动关闭——2026-08-24）。
  Timer? _timeoutTimer;

  /// 预设色板（12 种常用色）。
  static const List<Color> _presetColors = [
    Color(0xFF1A1A1A), // 黑
    Color(0xFF555555), // 深灰
    Color(0xFF8B8B8B), // 中灰
    Color(0xFFFFFFFF), // 白
    Color(0xFFD32F2F), // 红
    Color(0xFFFF7043), // 橙
    Color(0xFFFBC02D), // 黄
    Color(0xFF388E3C), // 绿
    Color(0xFF00897B), // 青
    Color(0xFF1976D2), // 蓝
    Color(0xFF7B1FA2), // 紫
    Color(0xFFC2185B), // 粉
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _selected = widget.initialColor;
    _startTimeout();
  }

  /// 启动 5 秒超时计时器（#38——2026-08-24）。
  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pop(_selected);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _apply(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _selected = hsv.toColor();
    });
    _startTimeout(); // 用户交互——重置超时。
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final subTextColor = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF6E6E73);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                AppLocalizations.of(context)?.selectColor ?? '选择颜色',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 预设色板
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final c in _presetColors)
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: GestureDetector(
                                onTap: () => _apply(HSVColor.fromColor(c)),
                                child: Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: c.computeLuminance() > 0.5
                                            ? Colors.black26
                                            : Colors.white24,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 二维色域框
                      SizedBox(
                        width: 300,
                        height: 170,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanDown: (d) => _pickSv(d.localPosition),
                          onPanUpdate: (d) => _pickSv(d.localPosition),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _SvSquarePainter(hue: _hsv.hue),
                                ),
                              ),
                              Positioned(
                                left: _hsv.saturation * 300 - 7,
                                top: (1 - _hsv.value) * 170 - 7,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _selected,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black26, blurRadius: 2),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 色相渐变条
                      SizedBox(
                        height: 22,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanDown: (d) => _pickHue(d.localPosition),
                          onPanUpdate: (d) => _pickHue(d.localPosition),
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: CustomPaint(painter: _HueBarPainter()),
                              ),
                              Positioned(
                                left: _hsv.hue / 360 * 300 - 4,
                                top: 0,
                                child: Container(
                                  width: 8,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.black38),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 同色系色阶
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i <= 5; i++)
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: GestureDetector(
                                onTap: () => _apply(
                                  HSVColor.fromAHSV(
                                    1,
                                    _hsv.hue,
                                    _hsv.saturation,
                                    0.2 + 0.15 * i,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: HSVColor.fromAHSV(
                                        1,
                                        _hsv.hue,
                                        _hsv.saturation,
                                        0.2 + 0.15 * i,
                                      ).toColor(),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.black26),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      // 最近使用色
                      if (_recentColors.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in _recentColors.reversed.take(12))
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: GestureDetector(
                                  onTap: () => _apply(HSVColor.fromColor(c)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: c,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black26),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      // 当前颜色预览
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _selected,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'RGB(${_selected.r.round()}, ${_selected.g.round()}, ${_selected.b.round()})',
                            style: TextStyle(
                              fontSize: 13,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Divider
            Container(height: 0.5, color: dividerColor),
            // Actions
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0066CC),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 17),
                      ),
                      child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
                    ),
                  ),
                ),
                Container(width: 0.5, height: 44, color: dividerColor),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextButton(
                      onPressed: () {
                        if (!_recentColors.contains(_selected)) {
                          _recentColors.add(_selected);
                        }
                        Navigator.of(context).pop(_selected);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0066CC),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      child: Text(AppLocalizations.of(context)?.confirm ?? '确定'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 二维色域框取色：位置 -> 饱和度/明度。
  void _pickSv(Offset local) {
    final s = (local.dx / 300).clamp(0.0, 1.0);
    final v = (1 - local.dy / 170).clamp(0.0, 1.0);
    _apply(_hsv.withSaturation(s).withValue(v));
  }

  /// 色相条取色：位置 -> 色相。
  void _pickHue(Offset local) {
    final h = (local.dx / 300 * 360).clamp(0.0, 360.0);
    _apply(_hsv.withHue(h));
  }
}

/// 二维色域框绘制器：横向 = 饱和度 0→1，纵向 = 明度 1→0，
/// 底色由当前色相决定（对齐 Excalidraw ColorPicker Picker 的 S/V 方块）。
class _SvSquarePainter extends CustomPainter {
  const _SvSquarePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    // 从左到右：饱和度渐变（当前色相 -> 同色相高饱和）；
    // 从上到下：明度渐变（白 -> 纯色 -> 黑）。
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final svGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, hueColor, Colors.black],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = svGradient);
    // 覆盖：横向饱和度叠加（右侧饱和、左侧去饱和）。
    final sGradient = const LinearGradient(
      colors: [Colors.transparent, Colors.white],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = sGradient);
  }

  @override
  bool shouldRepaint(_SvSquarePainter oldDelegate) => oldDelegate.hue != hue;
}

/// 色相渐变条绘制器（横向彩虹，点击/拖动取色相）。
class _HueBarPainter extends CustomPainter {
  const _HueBarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueGradient = LinearGradient(
      colors: [
        for (var h = 0; h <= 360; h += 60)
          HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = hueGradient);
  }

  @override
  bool shouldRepaint(_HueBarPainter oldDelegate) => false;
}
