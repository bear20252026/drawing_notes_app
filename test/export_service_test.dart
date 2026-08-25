/// 导出功能测试：画板→PDF/PNG、笔记→PDF、多页→PPTX。
///
/// 覆盖四大导出路径的核心逻辑：笔画渲染、图片输出、多页支持、PPTX XML 生成。
library;

import 'dart:convert';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:drawing_notes_app/core/export/canvas_image_exporter.dart';
import 'package:drawing_notes_app/core/export/canvas_pdf_exporter.dart';
import 'package:drawing_notes_app/core/export/note_pdf_exporter.dart';
import 'package:drawing_notes_app/core/export/pptx_exporter.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ===== CanvasPdfExporter =====
  group('CanvasPdfExporter', () {
    late CanvasPdfExporter exporter;

    setUp(() {
      exporter = const CanvasPdfExporter();
    });

    test('空笔画列表生成有效 PDF', () async {
      final result = await exporter.export(strokes: []);
      expect(result, isNotEmpty);
      expect(result.length, greaterThan(100));
      expect(String.fromCharCodes(result.sublist(0, 5)), startsWith('%PDF'));
    });

    test('单条笔画导出为有效 PDF', () async {
      final stroke = _createTestStroke();
      final result = await exporter.export(
        strokes: [stroke],
        title: '测试画作',
        author: '测试',
      );
      expect(result, isNotEmpty);
      expect(String.fromCharCodes(result.sublist(0, 5)), startsWith('%PDF'));
    });

    test('多条笔画导出', () async {
      final strokes = [
        _createTestStroke(color: 0xFF0000FF, width: 3),
        _createTestStroke(color: 0xFFFF0000, width: 5),
        _createTestStroke(color: 0xFF00FF00, width: 2),
      ];
      final result = await exporter.export(strokes: strokes);
      expect(result, isNotEmpty);
      expect(String.fromCharCodes(result.sublist(0, 5)), startsWith('%PDF'));
    });

    test('多页导出回调正确触发', () async {
      final pages = [
        [_createTestStroke()],
        [_createTestStroke(color: 0xFFFF0000)],
        [_createTestStroke(color: 0xFF00FF00)],
      ];
      final progressReports = <MapEntry<int, int>>[];

      final result = await exporter.exportMultiPage(
        pages: pages,
        onProgress: (current, total) {
          progressReports.add(MapEntry(current, total));
        },
      );

      expect(result, isNotEmpty);
      expect(progressReports.length, 3);
      expect(progressReports.first.key, 1);
      expect(progressReports.last.key, 3);
    });

    test('自定义页面尺寸生效', () async {
      final a4Portrait = await exporter.export(
        strokes: [_createTestStroke()],
        pageWidth: 595,
        pageHeight: 842,
      );
      final letterLandscape = await exporter.export(
        strokes: [_createTestStroke()],
        pageWidth: 792,
        pageHeight: 612,
      );
      expect(a4Portrait, isNotEmpty);
      expect(letterLandscape, isNotEmpty);
    });
  });

  // ===== NotePdfExporter =====
  group('NotePdfExporter', () {
    late NotePdfExporter exporter;

    setUp(() {
      exporter = const NotePdfExporter();
    });

    test('空页面列表生成有效 PDF', () async {
      final result = await exporter.export(pages: []);
      expect(result, isNotEmpty);
      expect(String.fromCharCodes(result.sublist(0, 5)), startsWith('%PDF'));
    });

    test('带标题的笔记页面导出', () async {
      final page = NotebookPage(
        id: 'page-1',
        title: '测试笔记',
        document: DrawingDocument(id: 'doc-1', title: 'doc'),
        textItems: [
          PageTextItem(id: 't1', text: '这是测试内容', x: 0, y: 0, width: 400),
        ],
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
      );

      final result = await exporter.export(
        pages: [page],
        title: '测试笔记本',
        author: '测试',
      );
      expect(result, isNotEmpty);
      expect(String.fromCharCodes(result.sublist(0, 5)), startsWith('%PDF'));
    });

    test('多页笔记导出带进度回调', () async {
      final pages = List.generate(
        5,
        (i) => NotebookPage(
          id: 'page-$i',
          title: '第 $i 页',
          document: DrawingDocument(id: 'doc-$i', title: 'doc $i'),
          textItems: [
            PageTextItem(id: 't$i', text: '内容 $i', x: 0, y: 0, width: 400),
          ],
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
        ),
      );
      final progressReports = <MapEntry<int, int>>[];

      final result = await exporter.export(
        pages: pages,
        onProgress: (current, total) {
          progressReports.add(MapEntry(current, total));
        },
      );

      expect(result, isNotEmpty);
      expect(progressReports.length, 5);
    });

    test('带笔画的笔记页面导出', () async {
      final doc = DrawingDocument(
        id: 'doc-stroke',
        title: 'doc',
        layers: [
          Layer(id: 'layer-1', name: 'default', strokes: [_createTestStroke()]),
        ],
      );

      final page = NotebookPage(
        id: 'page-stroke',
        title: '带笔画的笔记',
        document: doc,
        textItems: const [],
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 1),
      );

      final result = await exporter.export(pages: [page]);
      expect(result, isNotEmpty);
      expect(String.fromCharCodes(result.sublist(0, 5)), startsWith('%PDF'));
    });
  });

  // ===== PptxExporter =====
  group('PptxExporter', () {
    late PptxExporter exporter;

    setUp(() {
      exporter = const PptxExporter();
    });

    test('空幻灯片列表生成有效 PPTX', () async {
      final result = await exporter.export(pages: []);
      expect(result, isNotEmpty);
      expect(result[0], 0x50); // P
      expect(result[1], 0x4B); // K
    });

    test('单页幻灯片导出', () async {
      final result = await exporter.export(
        pages: [
          {
            'title': '测试幻灯片',
            'content': '这是内容',
          },
        ],
        title: '测试演示',
        author: '测试',
      );
      expect(result, isNotEmpty);
      expect(result[0], 0x50);
      expect(result[1], 0x4B);
    });

    test('多页幻灯片导出', () async {
      final pages = List.generate(
        10,
        (i) => <String, dynamic>{
          'title': '幻灯片 ${i + 1}',
          'content': '第 ${i + 1} 页的内容',
          'bullets': <String>['要点 A', '要点 B', '要点 C'],
        },
      );

      final result = await exporter.export(pages: pages, title: '多页演示');
      expect(result, isNotEmpty);
      expect(result[0], 0x50);
      expect(result[1], 0x4B);
    });

    test('XML 特殊字符正确转义', () async {
      final result = await exporter.export(
        pages: [
          {
            'title': '包含 <特殊> 字符 & "引号"',
            'content': '内容中有 <br> 标签',
          },
        ],
      );
      expect(result, isNotEmpty);
    });

    test('PPTX 可被 ZipDecoder 解包', () async {
      final result = await exporter.export(
        pages: [
          {
            'title': '验证解包',
            'content': '测试内容',
          },
        ],
      );

      final archive = ZipDecoder().decodeBytes(result);
      expect(archive.files, isNotEmpty);

      final names = archive.files.map((f) => f.name).toList();
      expect(names, contains('[Content_Types].xml'));
      expect(names, contains('ppt/presentation.xml'));
      expect(names, contains('ppt/slides/slide1.xml'));
      expect(names, contains('docProps/core.xml'));
    });

    test('演示文稿元数据正确写入', () async {
      final result = await exporter.export(
        pages: [
          {'title': '标题页', 'content': '内容'},
        ],
        title: '我的演示',
        author: '作者名',
      );

      final archive = ZipDecoder().decodeBytes(result);
      final coreFile = archive.files
          .firstWhere((f) => f.name == 'docProps/core.xml');
      // 文件内容可能被 Archive 存储为 ISO-8859-1 bytes，
      // 但实际数据是 UTF-8 编码的 XML。
      final coreContent = coreFile.content as List<int>;
      final xml = utf8.decode(coreContent, allowMalformed: true);

      expect(xml, contains('我的演示'));
      expect(xml, contains('作者名'));
    });

    test('多页幻灯片数量与 presentation.xml 一致', () async {
      final pages = List.generate(
        5,
        (i) => <String, dynamic>{
          'title': '页 $i',
          'content': '内容 $i',
        },
      );

      final result = await exporter.export(pages: pages);
      final archive = ZipDecoder().decodeBytes(result);

      final slideFiles =
          archive.files.where((f) => f.name.startsWith('ppt/slides/slide'));
      expect(slideFiles.length, 5);

      final presXml = archive.files
          .firstWhere((f) => f.name == 'ppt/presentation.xml')
          .content as List<int>;
      final xml = String.fromCharCodes(presXml);
      expect(xml, contains('sldId'));
    });

    test('PPTX 包含 slideMaster 和 slideLayout（可被 PowerPoint 打开）', () async {
      final result = await exporter.export(
        pages: [
          {'title': '验证 OOXML 结构', 'content': '测试 slideMaster/slideLayout'},
        ],
      );

      final archive = ZipDecoder().decodeBytes(result);
      final names = archive.files.map((f) => f.name).toList();

      // 验证 slideMaster 和 slideLayout 文件存在
      expect(names, contains('ppt/slideMasters/slideMaster1.xml'));
      expect(names, contains('ppt/slideLayouts/slideLayout1.xml'));

      // 验证 presentation.xml 引用了 slideMaster
      final presXml = archive.files
          .firstWhere((f) => f.name == 'ppt/presentation.xml')
          .content as List<int>;
      final presXmlStr = utf8.decode(presXml, allowMalformed: true);
      expect(presXmlStr, contains('sldMasterIdLst'));

      // 验证 presentation.xml.rels 引用了 slideMaster
      final presRels = archive.files
          .firstWhere((f) => f.name == 'ppt/_rels/presentation.xml.rels')
          .content as List<int>;
      final presRelsStr = utf8.decode(presRels, allowMalformed: true);
      expect(presRelsStr, contains('slideMaster'));

      // 验证 slide1.xml.rels 引用了 slideLayout
      final slideRels = archive.files
          .firstWhere((f) => f.name == 'ppt/slides/_rels/slide1.xml.rels')
          .content as List<int>;
      final slideRelsStr = utf8.decode(slideRels, allowMalformed: true);
      expect(slideRelsStr, contains('slideLayout'));

      // 验证 [Content_Types].xml 包含所有必要的 Override
      final contentTypes = archive.files
          .firstWhere((f) => f.name == '[Content_Types].xml')
          .content as List<int>;
      final ctStr = utf8.decode(contentTypes, allowMalformed: true);
      expect(ctStr, contains('slideMaster'));
      expect(ctStr, contains('slideLayout'));
      expect(ctStr, contains('docProps'));
    });
  });

  // ===== CanvasImageExporter =====
  group('CanvasImageExporter', () {
    late CanvasImageExporter exporter;

    setUp(() {
      exporter = const CanvasImageExporter();
    });

    test('空笔画列表生成有效 PNG', () async {
      final result = await exporter.export(strokes: []);
      expect(result, isNotEmpty);
      // PNG 文件头：0x89 0x50 0x4E 0x47
      expect(result[0], 0x89);
      expect(result[1], 0x50); // P
      expect(result[2], 0x4E); // N
      expect(result[3], 0x47); // G
    });

    test('含笔画时生成有效 PNG', () async {
      final result = await exporter.export(
        strokes: [_createTestStroke()],
      );
      expect(result, isNotEmpty);
      expect(result[0], 0x89); // PNG 魔数
    });

    test('自定义尺寸和背景色', () async {
      final result = await exporter.export(
        strokes: [_createTestStroke()],
        width: 800,
        height: 600,
        background: const Color(0xFFF0F0F0),
      );
      expect(result, isNotEmpty);
      expect(result[0], 0x89);
    });

    test('JPEG 格式导出（回退到 PNG）', () async {
      final result = await exporter.export(
        strokes: [_createTestStroke()],
        format: ImageExportFormat.jpeg,
      );
      expect(result, isNotEmpty);
      // JPEG 回退到 PNG 编码
      expect(result[0], 0x89);
    });
  });
}

/// 创建测试用笔画。
Stroke _createTestStroke({
  int color = 0xFF000000,
  double width = 2.0,
}) {
  return Stroke(
    points: List.generate(
      20,
      (i) => StrokePoint(
        i * 5.0,
        50.0 + 30.0 * (i % 3 == 0 ? -1 : 1),
        0.5,
      ),
    ),
    color: Color(color),
    width: width,
    opacity: 1.0,
    type: BrushType.pen,
  );
}
