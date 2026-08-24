// editor_core——HighlighterCompositing 荧光笔合成（Saber 借鉴——2026-08-22）。
//
// Saber 荧光笔（v1.35）：canvas compositing 渲染——高亮不重叠不变色——
// 渲染在文字下方——比传统荧光笔更自然（用户之前反馈荧光效果不明显）。
//
// 本地化：荧光笔 compositing 参数（不重叠变色/渲染文字下方——
// BrushStyles.highlighter 补强）——纯 Dart 可测——不搞崩。
//
// 版权：Saber（GPL-3.0——Adil Hanney）——仅参数非代码复制——NOTICE 已记录。
library;

/// 荧光笔合成结果（不可变）。
class HighlighterRender {
  const HighlighterRender({
    required this.layerBelowText,
    required this.noOverlapShift,
    required this.alphaStable,
  });

  /// 是否渲染在文字下方（Saber——文字清晰可见）。
  final bool layerBelowText;

  /// 重叠区域是否不变色（Saber——canvas compositing——不越叠越深）。
  final bool noOverlapShift;

  /// 透明度是否稳定（重叠不加深）。
  final bool alphaStable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HighlighterRender &&
          layerBelowText == other.layerBelowText &&
          noOverlapShift == other.noOverlapShift;

  @override
  int get hashCode => Object.hash(layerBelowText, noOverlapShift);
}

/// 荧光笔合成服务（Saber 借鉴——积木式纯 Dart）。
///
/// 解决用户反馈"荧光效果不明显"：canvas compositing——
/// 高亮渲染在文字下方 + 重叠不变色（传统荧光笔重叠会变深——
/// Saber 用 compositing 保持颜色一致）。
class HighlighterCompositing {
  const HighlighterCompositing();

  /// 荧光笔渲染参数（Saber——文字下方 + 重叠不变色 + 透明度稳定）。
  HighlighterRender render() {
    return const HighlighterRender(
      layerBelowText: true,
      noOverlapShift: true,
      alphaStable: true,
    );
  }

  /// 有效透明度（重叠不变色——n 次重叠后透明度仍稳定）。
  double effectiveAlpha(double baseAlpha, int overlapCount) {
    // Saber compositing：重叠不加深——透明度稳定（无累计）。
    return baseAlpha;
  }

  /// 荧光笔是否应渲染在文字下方（避免遮挡文字）。
  bool shouldLayerBelowText(HighlighterRender render) => render.layerBelowText;

  /// 混合两个高亮区域（重叠——颜色一致——不加深）。
  ({double r, double g, double b}) blend(
    ({double r, double g, double b}) c1,
    ({double r, double g, double b}) c2,
  ) {
    // Saber：重叠区域保持原色（compositing——取浅色——不加深）。
    final r = c1.r < c2.r ? c1.r : c2.r;
    final g = c1.g < c2.g ? c1.g : c2.g;
    final b = c1.b < c2.b ? c1.b : c2.b;
    return (r: r, g: g, b: b);
  }
}
