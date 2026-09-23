import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/apple_design.dart';
import '../../l10n/app_localizations.dart';

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

  // B3 键盘调色（审计 2026-09-07）：RGB 数字输入——键盘用户无法操作
  // 二维色域/色相条（指针手势专属），这三格是唯一全键盘取色通道。
  late final TextEditingController _rCtrl;
  late final TextEditingController _gCtrl;
  late final TextEditingController _bCtrl;
  final _rFocus = FocusNode();
  final _gFocus = FocusNode();
  final _bFocus = FocusNode();

  @override
  void dispose() {
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _rFocus.dispose();
    _gFocus.dispose();
    _bFocus.dispose();
    super.dispose();
  }

  /// 预设色板（12 种常用色）。
  static const List<Color> _presetColors = [
    Color(0xFF1A1A1A), // 黑
    Color(0xFF555555), // 深灰
    Color(0xFF8B8B8B), // 中灰
    AppleColor.surfaceWhite, // 白
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
    _rCtrl = TextEditingController(
      text: '${(widget.initialColor.r * 255).round()}',
    );
    _gCtrl = TextEditingController(
      text: '${(widget.initialColor.g * 255).round()}',
    );
    _bCtrl = TextEditingController(
      text: '${(widget.initialColor.b * 255).round()}',
    );
    // 失焦即提交（与 Enter 一致）。
    for (final f in [_rFocus, _gFocus, _bFocus]) {
      f.addListener(() {
        if (!f.hasFocus) _submitRgb();
      });
    }
    _selected = widget.initialColor;
  }

  void _apply(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _selected = hsv.toColor();
      _syncRgbFields(_selected);
    });
  }

  /// RGB 输入框随选中色同步（焦点内的格子不打扰正在输入的用户）。
  void _syncRgbFields(Color c) {
    void set(TextEditingController ctrl, double channel, FocusNode focus) {
      if (focus.hasFocus) return;
      final v = (channel * 255).round().clamp(0, 255);
      if (ctrl.text != '$v') ctrl.text = '$v';
    }

    set(_rCtrl, c.r, _rFocus);
    set(_gCtrl, c.g, _gFocus);
    set(_bCtrl, c.b, _bFocus);
  }

  /// 提交 RGB 输入（0–255；非法输入忽略保持原色）。
  void _submitRgb() {
    final r = int.tryParse(_rCtrl.text.trim());
    final g = int.tryParse(_gCtrl.text.trim());
    final b = int.tryParse(_bCtrl.text.trim());
    if (r == null || g == null || b == null) return;
    final c = Color.fromARGB(
      255,
      r.clamp(0, 255),
      g.clamp(0, 255),
      b.clamp(0, 255),
    );
    _apply(HSVColor.fromColor(c));
  }

  /// 单格 RGB 输入框（76px 宽 + 前缀标签；Enter/失焦提交）。
  Widget _rgbField(String label, TextEditingController ctrl, FocusNode focus) {
    // 合法圆角档位只有 0/5/8/11/18/pill——禁止 OutlineInputBorder 默认 4。
    const radius = BorderRadius.all(Radius.circular(AppleRadius.xs));
    return Semantics(
      // 读屏：避免只听到单字母前缀（审计 2026-09-18 P2-1）。
      label: '$label 通道',
      textField: true,
      child: SizedBox(
        width: 76,
        child: TextField(
          controller: ctrl,
          focusNode: focus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submitRgb(),
          style: AppleType.controlStyle(
            Theme.of(context).colorScheme.onSurface,
          ),
          maxLength: 3,
          decoration: InputDecoration(
            isDense: true,
            prefixText: '$label ',
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: AppleColor.focusBlue, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  /// 颜色近似相等（HSV 往返换算有极小分量误差，不能用 == 精确比较）。
  /// alpha 一并比较：initialColor 可能带透明度，否则选中态判定失真。
  static bool _sameColor(Color a, Color b) =>
      (a.r - b.r).abs() < 0.004 &&
      (a.g - b.g).abs() < 0.004 &&
      (a.b - b.b).abs() < 0.004 &&
      (a.a - b.a).abs() < 0.004;

  /// 色块的读屏标签：#RRGGBB（读屏用户需要可念出的颜色值）。
  static String _hexLabel(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)?.colorPickerTitle ?? '选择颜色'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 预设色板（选中态：外圈强调色描边 + 居中勾选，见 _Swatch）。
              // 三输入：44×44 透明热区（HIG/WCAG 最小触控）+ Semantics 标签。
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _presetColors)
                    Semantics(
                      button: true,
                      label: _hexLabel(c),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppleRadius.lg),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _apply(HSVColor.fromColor(c));
                          },
                          child: Center(
                            child: _Swatch(
                              color: c,
                              selected: _sameColor(c, _selected),
                            ),
                          ),
                        ),
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
                child: Semantics(
                  // 三输入：指针专属二维色域需读屏标签；键盘走 RGB 三格。
                  label:
                      AppLocalizations.of(context)?.colorPickerSvHint ??
                      '饱和度与明度（键盘请用下方 RGB 输入）',
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
              ),
              const SizedBox(height: 12),
              // 色相渐变条（横向彩虹，点击/拖动取色相）。
              // 视觉条 22px 居中、触控热区扩到 44px（HIG/WCAG 最小触控尺寸）；
              // 宽度显式 300，与 _pickHue 的换算宽度一致（修复 320/300 偏差）。
              SizedBox(
                width: 300,
                height: 44,
                child: Semantics(
                  label:
                      AppLocalizations.of(context)?.colorPickerHueHint ??
                      '色相（键盘请用下方 RGB 输入）',
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
                              borderRadius: BorderRadius.circular(
                                AppleRadius.xs,
                              ),
                              child: const CustomPaint(
                                painter: _HueBarPainter(),
                              ),
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
                              borderRadius: BorderRadius.circular(
                                AppleRadius.xs,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 同色系色阶（对齐 Excalidraw ShadeList）：当前色相的明度档位。
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (var i = 0; i <= 5; i++) _shadeDot(i)],
              ),
              // 最近使用色（对齐 Excalidraw CustomColorList）
              if (_recentColors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _recentColors.reversed.take(12))
                      Semantics(
                        button: true,
                        label: _hexLabel(c),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppleRadius.md),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _apply(HSVColor.fromColor(c));
                            },
                            child: Center(
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
                  // B3 键盘调色：RGB 数字输入（Enter 提交；0–255 钳制）。
                  // 焦点环：Focus Blue 2px（DESIGN.md:300、440）。
                  Row(
                    children: [
                      _rgbField('R', _rCtrl, _rFocus),
                      const SizedBox(width: 6),
                      _rgbField('G', _gCtrl, _gFocus),
                      const SizedBox(width: 6),
                      _rgbField('B', _bCtrl, _bFocus),
                    ],
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
          child: Text(AppLocalizations.of(context)?.cancel ?? '取消'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () {
            if (!_recentColors.contains(_selected)) {
              _recentColors.add(_selected);
            }
            Navigator.of(context).pop(_selected);
          },
          child: Text(AppLocalizations.of(context)?.commonConfirm ?? '确定'),
        ),
      ]),
    );
  }

  /// 同色系色阶单点（三输入：44×44 透明热区 + Semantics 颜色标签）。
  Widget _shadeDot(int i) {
    final shade = HSVColor.fromAHSV(
      1,
      _hsv.hue,
      _hsv.saturation,
      0.2 + 0.15 * i,
    );
    final color = shade.toColor();
    return Semantics(
      button: true,
      label: _hexLabel(color),
      child: SizedBox(
        width: 44,
        height: 44,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppleRadius.md),
          onTap: () {
            HapticFeedback.selectionClick();
            _apply(shade);
          },
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
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
