import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:drawing_notes_app/core/canvas_model/document.dart'
    show DrawingDocument;
import 'package:drawing_notes_app/features/drawing/application/paged_export_snapshot.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart'
    show BrushType, Stroke;
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/core/rtf_exporter.dart';
import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';
import 'package:drawing_notes_app/features/drawing/rendering/pdf_hybrid_exporter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/svg_exporter.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_pdf_exporter.dart';

/// 画布导出域（参考 Saber 的 editor_exporter 模块化设计）。
///
/// 独立成类后，editor_page 只负责调用，导出细节（文件选择、平台通道、
/// 格式打包）集中在单一职责模块，便于独立测试与复用。
class EditorExporter {
  EditorExporter({
    required this.controller,
    required this.pageProvider,
    required this.showSnack,
    this.allPagesProvider,
  });

  final DrawingController controller;
  final PagedExportSnapshot? Function() pageProvider;

  /// 整本全部页数据源（笔记本模式由编辑器注入多会话快照；独立画布为 null）。
  /// 类型为 notes 侧打印页数据（架构门禁允许 drawing→notes/application）。
  final List<NotebookPrintPageData> Function()? allPagesProvider;

  final void Function(String message) showSnack;

  PagedExportSnapshot? get _page => pageProvider();

  /// 会话 → 整本打印页数据（二级面板范围=全部页的组合边界映射；
  /// notes 聚合不泄漏，drawing 侧只读 core 契约字段）。
  static NotebookPrintPageData printDataOf(EditorPageSession s) =>
      NotebookPrintPageData(
        id: s.id,
        title: s.title,
        document: s.document,
        textItems: s.textItems,
        imageItems: s.imageItems,
        shapes: s.shapes,
      );

  /// 复制 PNG 到剪贴板（对齐 Excalidraw 剪贴板复制，平台通道）。
  ///
  /// 流程：渲染 PNG -> 解码为 RGBA 像素 -> 平台通道传给 C++/Android，
  /// 由平台写入剪贴板（Windows 用 CF_DIB 位图格式）。
  Future<void> copyPngToClipboard() async {
    try {
      final png = await controller.renderToPng();
      if (png == null) {
        showSnack('复制失败：无法渲染画布');
        return;
      }
      // 解码 PNG 为 RGBA 像素（供平台构造 DIB 位图）。
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        showSnack('复制失败：像素解码失败');
        return;
      }
      const channel = MethodChannel('gov.drawingnotes/clipboard');
      await channel.invokeMethod('copyPng', {
        'width': image.width,
        'height': image.height,
        'rgba': data.buffer.asUint8List(),
      });
      image.dispose();
      showSnack('已复制 PNG 到剪贴板');
    } catch (e) {
      showSnack('复制 PNG 需平台支持：$e');
    }
  }

  /// 导出当前画布为 PNG（用户选择保存位置）。
  Future<void> exportPng() async {
    try {
      final png = await controller.renderToPng();
      if (png == null) {
        showSnack('导出失败：无法渲染画布');
        return;
      }
      final suggested = '${controller.document.title}.png';
      final location = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PNG 图片', extensions: ['png']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(png, flush: true);
      showSnack('已导出到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }

  /// 导出当前画布为 PDF（D4，借鉴 ONLYOFFICE 保真打印与 Saber 混合导出）。
  ///
  /// 钢笔笔画以矢量路径写入（任意缩放清晰）；高亮笔/铅笔/图片/形状以
  /// 光栅位图嵌入，页面尺寸与画布导出区域一致，保证矢量与位图精确对齐。
  Future<void> exportPdf() async {
    final page = _page;
    if (page != null) {
      await exportNotebookPdf(page);
      return;
    }
    try {
      final bounds = controller.document.infinite
          ? controller.contentBounds()
          : Rect.fromLTWH(
              0,
              0,
              controller.document.width.toDouble(),
              controller.document.height.toDouble(),
            );
      final vectorStrokes = <Stroke>[
        for (final layer in controller.document.layers)
          for (final stroke in layer.strokes)
            if (!PdfHybridExporter.shouldRasterize(stroke)) stroke,
      ];
      final png = await controller.renderToPng(
        excludedTypes: const {BrushType.pen},
      );
      if (png == null) {
        showSnack('导出失败：无法渲染画布');
        return;
      }
      final bytes = await PdfHybridExporter.export(
        bounds: bounds,
        rasterPng: png,
        vectorStrokes: vectorStrokes,
      );
      final location = await getSaveLocation(
        suggestedName: '${controller.document.title}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF 文档', extensions: ['pdf']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
      showSnack('已导出到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }

  /// 二级面板导出入口（M12.5）：按纸张/范围/质量三档位分发。
  ///
  /// - 笔记本模式：范围 当前页 → [exportNotebookPdf]；全部页 →
  ///   [NotebookPdfExporter.exportPages]（多会话快照经 [allPagesProvider]）；
  /// - 独立画布：单页 hybrid 导出（纸张适配 + 质量透传）。
  Future<void> exportPdfWithOptions({
    required PdfPaper paper,
    required PdfQuality quality,
    PdfRange range = PdfRange.currentPage,
  }) async {
    final page = _page;
    if (page != null) {
      if (range == PdfRange.allPages) {
        final all = allPagesProvider?.call();
        if (all == null || all.isEmpty) {
          showSnack('没有可导出的页面');
          return;
        }
        await _exportNotebookPages(
          all,
          quality: quality,
          baseName: '${page.title}-全本',
        );
        return;
      }
      await exportNotebookPdf(page, paper: paper, quality: quality);
      return;
    }
    await _exportCanvasPdf(paper: paper, quality: quality);
  }

  /// 整本多页导出（笔记本范围=全部页）：多会话快照已有墨迹光栅由引擎
  /// 离屏管线渲染（与整本导出同一管线），此处只负责落盘与提示。
  Future<void> _exportNotebookPages(
    List<NotebookPrintPageData> pages, {
    required PdfQuality quality,
    required String baseName,
  }) async {
    try {
      final bytes = await NotebookPdfExporter.exportPages(
        pages,
        jpegQuality: quality.jpegQuality,
      );
      final location = await getSaveLocation(
        suggestedName: '$baseName.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF 文档', extensions: ['pdf']),
        ],
      );
      if (location == null) return; // 用户取消
      await File(location.path).writeAsBytes(bytes, flush: true);
      showSnack('已导出整本 ${pages.length} 页 PDF：${location.path}');
    } catch (e) {
      showSnack('导出整本 PDF 失败：$e');
    }
  }

  /// 独立画布单页导出（纸张适配 + 质量透传；跟随画布 = 既有行为零变化）。
  Future<void> _exportCanvasPdf({
    required PdfPaper paper,
    required PdfQuality quality,
  }) async {
    try {
      final content = controller.document.infinite
          ? controller.contentBounds()
          : Rect.fromLTWH(
              0,
              0,
              controller.document.width.toDouble(),
              controller.document.height.toDouble(),
            );
      if (content.width <= 0 || content.height <= 0) {
        showSnack('导出失败：画布内容为空');
        return;
      }
      // 纸张适配：内容等比放入纸张并居中；跟随画布则 scale=1/offset=0。
      final fit = fitContentOnPaper(paper, content: content);
      final s = fit.scale;
      final o = fit.offset;
      final pageSize =
          paper.pageSize ?? ui.Size(content.width, content.height);
      final vectorStrokes = <Stroke>[
        for (final layer in controller.document.layers)
          for (final stroke in layer.strokes)
            if (!PdfHybridExporter.shouldRasterize(stroke)) stroke,
      ];
      final png = await controller.renderToPng(
        scale: s,
        excludedTypes: const {BrushType.pen},
      );
      if (png == null) {
        showSnack('导出失败：无法渲染画布');
        return;
      }
      final bytes = await PdfHybridExporter.export(
        bounds: ui.Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
        rasterPng: png,
        vectorStrokes: [
          for (final st in vectorStrokes) scaleStrokeForPaper(st, s, o),
        ],
        jpegQuality: quality.jpegQuality,
        contentRect: paper == PdfPaper.canvas
            ? null
            : ui.Rect.fromLTWH(
                o.dx,
                o.dy,
                content.width * s,
                content.height * s,
              ),
      );
      final location = await getSaveLocation(
        suggestedName: '${controller.document.title}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF 文档', extensions: ['pdf']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
      showSnack('已导出到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }

  /// 导出分页笔记为 A4 PDF：结构化文字以可检索 CJK 字体排版；同时附加
  /// 手写墨迹图层页，避免只导出文字而丢失原始书写内容。
  ///
  /// 二级面板参数：[paper] 作用于文字页版式（A4/Letter；跟随画布回落 A4，
  /// 文字重排无“画布尺寸”概念）；[quality] 作用于墨迹页光栅压缩。
  Future<void> exportNotebookPdf(
    PagedExportSnapshot page, {
    PdfPaper paper = PdfPaper.a4,
    PdfQuality quality = PdfQuality.lossless,
  }) async {
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/DroidSansFallbackFull.ttf',
      );
      final cjk = pw.Font.ttf(fontData);
      final theme = pw.ThemeData.withFont(
        base: cjk,
        bold: cjk,
        italic: cjk,
        boldItalic: cjk,
      );
      final ordered = page.textItems.toList()
        ..sort((a, b) {
          final byY = a.y.compareTo(b.y);
          return byY == 0 ? a.x.compareTo(b.x) : byY;
        });
      // 二级面板纸张：文字页版式跟纸张档位（跟随画布无意义，回落 A4）。
      final textFormat =
          paper == PdfPaper.letter ? PdfPageFormat.letter : PdfPageFormat.a4;
      final document = pw.Document(theme: theme);
      document.addPage(
        pw.MultiPage(
          pageFormat: textFormat,
          margin: const pw.EdgeInsets.fromLTRB(52, 56, 52, 56),
          build: (context) => [
            pw.Text(
              page.title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 18),
            for (final item in ordered)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(
                  '${item.isTodo ? (item.todoChecked ? '[x] ' : '[ ] ') : ''}${item.text}',
                  style: pw.TextStyle(
                    fontSize: (item.fontSize * 0.72).clamp(10, 28),
                    fontWeight: item.bold
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    fontStyle: item.italic
                        ? pw.FontStyle.italic
                        : pw.FontStyle.normal,
                    decoration: item.strikethrough
                        ? pw.TextDecoration.lineThrough
                        : (item.underline
                              ? pw.TextDecoration.underline
                              : pw.TextDecoration.none),
                  ),
                ),
              ),
          ],
        ),
      );

      final inkPng = await controller.renderToPng();
      if (inkPng != null) {
        // 二级面板质量：墨迹页光栅按档位压缩（无损 = PNG 原样）。
        final inkBytes = quality.jpegQuality == null
            ? inkPng
            : PdfHybridExporter.encodeJpeg(inkPng, quality.jpegQuality!);
        document.addPage(
          pw.Page(
            pageFormat: textFormat,
            margin: const pw.EdgeInsets.all(24),
            build: (context) => pw.Center(
              child: pw.Image(pw.MemoryImage(inkBytes), fit: pw.BoxFit.contain),
            ),
          ),
        );
      }

      final location = await getSaveLocation(
        suggestedName: '${page.title}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF 文档', extensions: ['pdf']),
        ],
      );
      if (location == null) return;
      await File(
        location.path,
      ).writeAsBytes(await document.save(), flush: true);
      showSnack('已导出分页笔记 PDF：${location.path}');
    } catch (e) {
      showSnack('导出分页笔记 PDF 失败：$e');
    }
  }

  /// 导出画布为 SVG（借鉴 Excalidraw 开放矢量格式）。
  ///
  /// 矢量导出：笔画转 SVG path 元素，文字块转 SVG text 元素，
  /// 白纸底 + viewBox 自适应；SVG 可无损缩放、供政府公文/网页嵌入。
  Future<void> exportSvg() async {
    try {
      final doc = controller.document;
      final w = doc.width.toDouble();
      final h = doc.height.toDouble();
      final body = StringBuffer();

      // 各图层笔画（可见层，按顺序绘制）。
      for (final layer in doc.layers) {
        if (!layer.visible || layer.opacity <= 0) continue;
        for (final stroke in layer.strokes) {
          body.write(strokeToSvgPath(stroke));
        }
      }
      // 文字块（笔记本模式）。
      final page = _page;
      if (page != null) {
        for (final t in page.textItems) {
          body.write(textToSvgText(t));
        }
      }

      final svg = buildSvgDocument(width: w, height: h, body: body.toString());
      final location = await getSaveLocation(
        suggestedName: '${doc.title}.svg',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SVG 矢量图', extensions: ['svg']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsString(svg, flush: true);
      showSnack('已导出 SVG 到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }

  /// 导出分页笔记为可由 Microsoft Word、WPS 等直接打开的 RTF 文档。
  ///
  /// 手写、图片和形状属于版面内容，推荐以 PDF/PNG/SVG 导出保真；此处导出
  /// 的是可继续编辑的结构化文字流，按页面坐标从上到下排序。
  Future<void> exportWordCompatibleRtf() async {
    final page = _page;
    if (page == null) {
      showSnack('仅分页笔记支持导出 Word 兼容文档');
      return;
    }
    if (page.textItems.isEmpty) {
      showSnack('本页还没有可导出的文字内容');
      return;
    }
    try {
      final rtf = PagedNoteRtfExporter.build(
        title: page.title,
        textItems: page.textItems,
      );
      final location = await getSaveLocation(
        suggestedName: '${page.title}.rtf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Word 兼容文档', extensions: ['rtf']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsString(rtf, flush: true);
      showSnack('已导出 Word 兼容文档：${location.path}');
    } catch (e) {
      showSnack('导出 Word 兼容文档失败：$e');
    }
  }

  /// 导出页面文字块内容为 Markdown/TXT（借鉴 nb/Joplin）。
  ///
  /// 样式映射：待办 -> `- [ ]/[x]`；粗体 -> `**`；斜体 -> `*`；
  /// 便利贴 -> 引用块 `>`；其余为纯文本行。
  Future<void> exportText() async {
    final page = _page;
    if (page == null) {
      showSnack('仅分页画布页面支持导出文本');
      return;
    }
    if (page.textItems.isEmpty) {
      showSnack('本页还没有文字内容');
      return;
    }

    final lines = <String>[];
    for (final t in page.textItems) {
      var text = t.text;
      if (t.bold) text = '**$text**';
      if (t.italic) text = '*$text*';
      if (t.isTodo) text = '- [${t.todoChecked ? 'x' : ' '}] $text';
      if (t.isSticky) text = '> $text';
      lines.add(text);
    }
    final content = '# ${page.title}\n\n${lines.join('\n\n')}\n';

    try {
      final location = await getSaveLocation(
        suggestedName: '${page.title}.md',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Markdown / 文本', extensions: ['md', 'txt']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsString(content, flush: true);
      showSnack('已导出文本到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }

  /// 导出画布为 PPTX（对齐 Excalidraw PPTX 导出）。
  ///
  /// 用 archive 包手动构造最小 OOXML PPTX：一张幻灯片嵌入画布 PNG 图片，
  /// 可在 PowerPoint/WPS 中打开编辑。
  Future<void> exportPptx() async {
    try {
      final png = await controller.renderToPng();
      if (png == null) {
        showSnack('导出失败：无法渲染画布');
        return;
      }
      final doc = controller.document;
      final w = doc.width.toDouble();
      final h = doc.height.toDouble();

      // OOXML PPTX 文件结构（最小可打开）。
      final files = <String, List<int>>{
        '[Content_Types].xml': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
</Types>''',
        ),
        '_rels/.rels': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''',
        ),
        'ppt/presentation.xml': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
<p:sldSz cx="${(w * 9525).round()}" cy="${(h * 9525).round()}"/>
</p:presentation>''',
        ),
        'ppt/_rels/presentation.xml.rels': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
</Relationships>''',
        ),
        'ppt/slides/slide1.xml': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
<p:pic>
<p:nvPicPr><p:cNvPr id="2" name="Canvas"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>
<p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${(w * 9525).round()}" cy="${(h * 9525).round()}"/></a:xfrm>
<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
</p:pic>
</p:spTree></p:cSld>
</p:sld>''',
        ),
        'ppt/slides/_rels/slide1.xml.rels': utf8.encode(
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
</Relationships>''',
        ),
        'ppt/media/image1.png': png,
      };

      // 打包 ZIP（PPTX = OOXML ZIP 容器）。
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final bytes = ZipEncoder().encode(archive);
      if (bytes.isEmpty) {
        showSnack('导出失败：PPTX 打包失败');
        return;
      }

      final location = await getSaveLocation(
        suggestedName: '${doc.title}.pptx',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PPTX 演示文稿', extensions: ['pptx']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
      showSnack('已导出 PPTX 到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }

  /// 导出画布为 JSON（Excalidraw 开放格式对齐：.excalidraw 语义）。
  Future<void> exportJson() async {
    try {
      final data = buildExportPayload(controller.document, page: _page);
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final location = await getSaveLocation(
        suggestedName: '${controller.document.title}.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON 工程文件', extensions: ['json']),
        ],
      );
      if (location == null) return; // 用户取消
      final file = File(location.path);
      await file.writeAsString(json, flush: true);
      showSnack('已导出 JSON 到：${location.path}');
    } catch (e) {
      showSnack('导出失败：$e');
    }
  }
}

/// 导出数据净化（落地 Excalidraw cleanAppStateForExport 的三态分离思路）。
///
/// 导出/存储/本地三个出口各自剥离运行时状态：
/// - 导出：只含文档域数据（图层/文字/图片/形状），**绝不携带**选区、
///   视图变换（缩放/平移）、当前工具等 UI 状态，避免污染工程文件；
/// - 存储：由 [DrawingDocument.toJson] 负责（仅文档域）；
/// - 本地：编辑器内部状态不落盘。
/// 独立静态方法便于单元测试断言净化边界。
Map<String, dynamic> buildExportPayload(
  DrawingDocument doc, {
  PagedExportSnapshot? page,
}) => {
  'type': 'drawing-notes',
  'version': 1,
  'title': doc.title,
  'width': doc.width,
  'height': doc.height,
  'layers': doc.layers.map((l) => l.toJson()).toList(),
  if (page != null) 'textItems': page.textItems.map((t) => t.toJson()).toList(),
  if (page != null) 'imageItems': page.imageItems,
  if (page != null) 'shapes': page.shapes,
};
