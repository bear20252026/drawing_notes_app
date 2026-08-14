import 'package:flutter/material.dart';

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
  }

  void _apply(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _selected = hsv.toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择颜色'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
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
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _apply(HSVColor.fromColor(c)),
                      child: Container(
                        width: 34,
                        height: 34,
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
                ],
              ),
              const SizedBox(height: 16),
              // 二维色域框（Saturation × Value，对齐 Excalidraw ColorPicker Picker）：
              // 横向 = 饱和度 0→1，纵向 = 明度 1→0，底色随当前色相变化。
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
                      // 当前 S/V 位置指示圆点。
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
              // 色相渐变条（横向彩虹，点击/拖动取色相）。
              SizedBox(
                height: 22,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _pickHue(d.localPosition),
                  onPanUpdate: (d) => _pickHue(d.localPosition),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: const _HueBarPainter()),
                      ),
                      // 当前色相指示。
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
              // 同色系色阶（对齐 Excalidraw ShadeList）：当前色相的明度档位。
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i <= 5; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _apply(
                        HSVColor.fromAHSV(
                          1,
                          _hsv.hue,
                          _hsv.saturation,
                          0.2 + 0.15 * i,
                        ),
                      ),
                      child: Container(
                        width: 28,
                        height: 28,
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
                ],
              ),
              // 最近使用色（对齐 Excalidraw CustomColorList）
              if (_recentColors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _recentColors.reversed.take(12))
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _apply(HSVColor.fromColor(c)),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black26),
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!_recentColors.contains(_selected)) {
              _recentColors.add(_selected);
            }
            Navigator.of(context).pop(_selected);
          },
          child: const Text('确定'),
        ),
      ],
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
    final sGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
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
