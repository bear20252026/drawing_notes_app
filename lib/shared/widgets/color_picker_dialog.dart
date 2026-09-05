import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/apple_design.dart';

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

  /// 颜色近似相等（HSV 往返换算有极小分量误差，不能用 == 精确比较）。
  /// alpha 一并比较：initialColor 可能带透明度，否则选中态判定失真。
  static bool _sameColor(Color a, Color b) =>
      (a.r - b.r).abs() < 0.004 &&
      (a.g - b.g).abs() < 0.004 &&
      (a.b - b.b).abs() < 0.004 &&
      (a.a - b.a).abs() < 0.004;

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
              // 预设色板（选中态：外圈强调色描边 + 居中勾选，见 _Swatch）。
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _presetColors)
                    InkWell(
                      borderRadius: BorderRadius.circular(AppleRadius.lg),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _apply(HSVColor.fromColor(c));
                      },
                      child: _Swatch(
                        color: c,
                        selected: _sameColor(c, _selected),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // 二维色域框（Saturation × Value，对齐 Excalidraw ColorPicker Picker）：
              // 横向 = 饱和度 0→1，纵向 = 明度 1→0，底色随当前色相变化。
              Container(
                width: 300,
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppleRadius.sm),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _pickSv(d.localPosition),
                  onPanUpdate: (d) => _pickSv(d.localPosition),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppleRadius.sm),
                          child: CustomPaint(
                            painter: _SvSquarePainter(hue: _hsv.hue),
                          ),
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
              // 视觉条 22px 居中、触控热区扩到 44px（HIG/WCAG 最小触控尺寸）；
              // 宽度显式 300，与 _pickHue 的换算宽度一致（修复 320/300 偏差）。
              SizedBox(
                width: 300,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _pickHue(d.localPosition),
                  onPanUpdate: (d) => _pickHue(d.localPosition),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppleRadius.xs),
                            child: const CustomPaint(painter: _HueBarPainter()),
                          ),
                        ),
                      ),
                      // 当前色相指示。
                      Positioned(
                        left: _hsv.hue / 360 * 300 - 4,
                        top: 11,
                        child: Container(
                          width: 8,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black38),
                            borderRadius: BorderRadius.circular(AppleRadius.xs),
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
                      borderRadius: BorderRadius.circular(AppleRadius.md),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _apply(
                          HSVColor.fromAHSV(
                            1,
                            _hsv.hue,
                            _hsv.saturation,
                            0.2 + 0.15 * i,
                          ),
                        );
                      },
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
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
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
                        borderRadius: BorderRadius.circular(AppleRadius.md),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _apply(HSVColor.fromColor(c));
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
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
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    // r/g/b 为 0–1 的 double，需 ×255 还原为常规 RGB 读数。
                    'RGB(${(_selected.r * 255).round()}, ${(_selected.g * 255).round()}, ${(_selected.b * 255).round()})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: AppleDialog.actions([
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
      ]),
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
    // 覆盖：横向饱和度叠加——左侧白色（s=0 去饱和）、右侧透明（s=1 全饱和），
    // 与 _pickSv 的取色映射（左 s=0 → 右 s=1）一致；对齐 Excalidraw
    // S 方块「左白右饱和」方向（原方向镜像颠倒，点饱和处取到 s=0）。
    final sGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Colors.white, Colors.transparent],
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

/// 预设色板单元格：圆形色块 + 选中态（外圈强调色描边 + 居中勾选标记）。
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected});

  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 浅色块给浅描边、深色块给深描边，保证任意底色上边界可辨。
    final hairline = color.computeLuminance() > 0.5
        ? scheme.outlineVariant
        : scheme.outline.withValues(alpha: 0.4);
    return Container(
      width: 34,
      height: 34,
      padding: EdgeInsets.all(selected ? 2 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: hairline),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 16,
                color: color.computeLuminance() > 0.5
                    ? Colors.black.withValues(alpha: 0.7)
                    : Colors.white,
              )
            : null,
      ),
    );
  }
}
