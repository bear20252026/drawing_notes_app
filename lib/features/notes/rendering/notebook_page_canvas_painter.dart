import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/canvas_model/text_item.dart'
    show PageTextItem, TextAlignType;
import 'package:drawing_notes_app/features/drawing/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/pdf_hybrid_exporter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_renderer.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook_page.dart';

/// 分页画布整页忠实渲染器（W2 翻页阅读 + 整本 PDF 导出共用）。
///
/// 与 [_PageThumbnailPainter]（占位缩略图）不同，这里按页面真实坐标
/// 渲染全部内容：手写笔画（复用 [InkLayerPainter]，含高亮笔合成）、
/// 形状（[ShapeRenderer]）、文字块（TextPainter 真实排版）、图片
/// （已解码位图直绘；未解码时退化为缩略图同款占位块）。
///
/// 双出口共用同一绘制入口 [paintContent]，保证"所见即所得"：
/// - 翻页阅读模式：widget 层 CustomPaint 直接调用；
/// - 整本 PDF 导出：离屏 PictureRecorder 光栅化（钢笔笔画走矢量通道，
///   传 [excludePenStrokes] = true 排除，避免双重绘制）。
class NotebookPageCanvasPainter extends CustomPainter {
  const NotebookPageCanvasPainter({
    required this.page,
    this.images = const <String, ui.Image>{},
    this.excludePenStrokes = false,
  });

  final NotebookPage page;

  /// 已解码图片（键 = imageItems.filePath，含 'vfs:' 对象路径）。
  final Map<String, ui.Image> images;

  /// PDF 矢量通道：排除钢笔笔画（钢笔由 StrokeRenderer 转 SVG path 写入）。
  final bool excludePenStrokes;

  /// 文字块 TextPainter 缓存（性能热点：paintContent 每次重绘都为每个
  /// 文字块新建 TextPainter + TextStyle + layout，翻页/导出时逐块全量排版）。
  ///
  /// 键 = [PageTextItem] 对象本身（Expando identity）：条目被替换/回收时
  /// 缓存随 GC 释放，不长期驻留（与 StrokeRenderer._outlineCache 同模式）。
  /// PageTextItem 无几何版本号且样式字段可变，故用「文本引用 + 影响排版
  /// 的全部样式字段」组合校验失效：文本用 identical（String 不可变，
  /// 重新赋值必换引用），其余为标量 ==，成本远低于一次 layout。
  /// 缓存的 TextPainter 跨 paint 复用，不 dispose 正在复用的实例。
  static final Expando<_TextItemPainterEntry> _textPainterCache = Expando(
    'notebookTextPainterCache',
  );

  static TextPainter _textPainterFor(PageTextItem text) {
    var entry = _textPainterCache[text];
    if (entry == null || !entry.matches(text)) {
      entry = _TextItemPainterEntry(text);
      _textPainterCache[text] = entry;
    }
    return entry.painter;
  }

  /// 页面内容绘制入口（widget 与离屏光栅共用；size 应为页面逻辑尺寸）。
  void paintContent(ui.Canvas canvas, ui.Size size) {
    final doc = page.document;
    final bounds = Offset.zero & size;

    // 白纸底（页面模式固定尺寸，非无限画布）。
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFFFFFFF));

    // 手写图层：可见性 + 不透明度语义与编辑器一致。
    for (final layer in doc.layers) {
      if (!layer.visible || layer.opacity <= 0) continue;
      final strokes = excludePenStrokes
          ? layer.strokes
                .where(PdfHybridExporter.shouldRasterize)
                .toList(growable: false)
          : layer.strokes;
      if (strokes.isEmpty) continue;
      if (layer.opacity < 1) {
        canvas.saveLayer(
          bounds,
          Paint()..color = Color.fromRGBO(0, 0, 0, layer.opacity),
        );
        InkLayerPainter.paintStrokes(canvas, bounds, strokes);
        canvas.restore();
      } else {
        InkLayerPainter.paintStrokes(canvas, bounds, strokes);
      }
    }

    // 形状。
    for (final shape in page.shapes) {
      ShapeRenderer.drawDocumentShape(canvas, shape);
    }

    // 图片：已解码直绘；未解码（无会话密钥/加载失败）时按缩略图同款
    // 占位块表达，保持布局真实。
    for (final image in page.imageItems) {
      final rect = Rect.fromLTWH(image.x, image.y, image.width, image.height);
      final decoded = images[image.filePath];
      if (decoded != null) {
        canvas.drawImageRect(
          decoded,
          Rect.fromLTWH(
            0,
            0,
            decoded.width.toDouble(),
            decoded.height.toDouble(),
          ),
          rect,
          Paint(),
        );
      } else {
        canvas.drawRect(rect, Paint()..color = const Color(0xFFCFD8DC));
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF607D8B),
        );
        canvas.drawLine(
          rect.topLeft,
          rect.bottomRight,
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0x66546E7A),
        );
      }
    }

    // 文字块：真实排版（字体样式与导出语义一致：待办勾选前缀/粗斜体/
    // 下划线/删除线/对齐；width 非 null 时按框宽换行）。
    // TextPainter 按条目缓存（见 _textPainterCache）：重绘只复用排版结果。
    for (final text in page.textItems) {
      _textPainterFor(text).paint(canvas, Offset(text.x, text.y));
    }
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) => paintContent(canvas, size);

  @override
  bool shouldRepaint(NotebookPageCanvasPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.page.updatedAt != page.updatedAt ||
      !identical(oldDelegate.images, images) ||
      oldDelegate.excludePenStrokes != excludePenStrokes;
}

/// [NotebookPageCanvasPainter] 文字块缓存的单个条目：持有跨 paint 复用的
/// [TextPainter]，并记录创建时的全部排版输入用于失效校验。
///
/// [PageTextItem] 字段可变且无版本号，任一影响排版的字段变化都必须重建
/// （见 [matches]）；位置 x/y 不参与排版，绘制时实时取值，故不缓存。
class _TextItemPainterEntry {
  _TextItemPainterEntry(PageTextItem text)
    : painter = TextPainter(
        text: TextSpan(
          text: text.isTodo
              ? '${text.todoChecked ? '☑' : '☐'} ${text.text}'
              : text.text,
          style: TextStyle(
            fontSize: text.fontSize,
            color: Color(text.color),
            fontWeight: text.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: text.italic ? FontStyle.italic : FontStyle.normal,
            decoration: text.strikethrough
                ? TextDecoration.lineThrough
                : (text.underline ? TextDecoration.underline : null),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: switch (text.align) {
          TextAlignType.left => TextAlign.left,
          TextAlignType.center => TextAlign.center,
          TextAlignType.right => TextAlign.right,
        },
      )..layout(maxWidth: text.width ?? double.infinity),
      _text = text.text,
      _fontSize = text.fontSize,
      _color = text.color,
      _width = text.width,
      _bold = text.bold,
      _italic = text.italic,
      _underline = text.underline,
      _strikethrough = text.strikethrough,
      _isTodo = text.isTodo,
      _todoChecked = text.todoChecked,
      _align = text.align;

  final TextPainter painter;

  final String _text;
  final double _fontSize;
  final int _color;
  final double? _width;
  final bool _bold;
  final bool _italic;
  final bool _underline;
  final bool _strikethrough;
  final bool _isTodo;
  final bool _todoChecked;
  final TextAlignType _align;

  /// 校验缓存条目对 [text] 是否仍然有效：文本用 identical（String 不可变，
  /// 重新赋值必换引用——同值不同对象时误判失效是安全方向），其余标量 ==。
  bool matches(PageTextItem text) =>
      identical(_text, text.text) &&
      _fontSize == text.fontSize &&
      _color == text.color &&
      _width == text.width &&
      _bold == text.bold &&
      _italic == text.italic &&
      _underline == text.underline &&
      _strikethrough == text.strikethrough &&
      _isTodo == text.isTodo &&
      _todoChecked == text.todoChecked &&
      _align == text.align;
}
