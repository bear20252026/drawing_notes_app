import 'package:drawing_notes_app/core/canvas_model/text_item.dart'
    show PageTextItem;
import 'package:drawing_notes_app/core/canvas_model/stroke.dart' show Stroke;

/// SVG 导出纯函数（从 editor_page 拆出的导出域第一步）。
///
/// 只依赖模型、不依赖任何 UI 状态，可独立测试与复用；
/// editor_page 的导出入口调用这些顶层函数，行为与原先内联一致。

/// 笔画 -> SVG path（用采样点折线 + 线宽 stroke，与画布视觉一致）。
///
/// 颜色格式：#RRGGBB，透明 alpha 用 stroke-opacity。
String strokeToSvgPath(Stroke stroke) {
  if (stroke.points.isEmpty) return '';
  final w = stroke.width.toDouble();
  final argb = stroke.color.toARGB32();
  final hex = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = ((argb >> 24) & 0xFF) / 255;
  final d = StringBuffer()
    ..write('M${stroke.points.first.x},${stroke.points.first.y}');
  for (final p in stroke.points.skip(1)) {
    d.write(' L${p.x},${p.y}');
  }
  return '<path d="$d" fill="none" stroke="#$hex" '
      'stroke-width="$w" stroke-linecap="round" stroke-linejoin="round" '
      'stroke-opacity="${alpha.toStringAsFixed(3)}"/>\n';
}

/// 文字块 -> SVG text（字号/颜色/粗斜体/对齐）。
String textToSvgText(PageTextItem t) {
  final hex = (t.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final bold = t.bold ? ' font-weight="bold"' : '';
  final italic = t.italic ? ' font-style="italic"' : '';
  // XML 转义，防止特殊字符破坏 SVG。
  final text = t.text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  return '<text x="${t.x}" y="${t.y + t.fontSize}" '
      'font-size="${t.fontSize}" fill="#$hex"$bold$italic '
      'font-family="sans-serif">$text</text>\n';
}

/// 构建完整 SVG 文档字符串（白纸底 + viewBox 自适应）。
///
/// [strokeSvg] 与 [textSvg] 为已生成的 SVG 片段（见 [strokeToSvgPath] /
/// [textToSvgText]）；本函数负责 XML 头与根元素封装。
String buildSvgDocument({
  required double width,
  required double height,
  required String body,
}) {
  final w = width.toStringAsFixed(2);
  final h = height.toStringAsFixed(2);
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" '
      'viewBox="0 0 $w $h">',
    )
    ..writeln('<rect width="$w" height="$h" fill="white"/>')
    ..write(body)
    ..writeln('</svg>');
  return buf.toString();
}

/// 导出失败时统一的错误提示文案（供 UI 层 snackbar 使用）。
String svgExportErrorMessage(Object error) => '导出失败：$error';
