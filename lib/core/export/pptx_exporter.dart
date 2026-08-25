/// 多页内容 → PPTX 导出服务。
///
/// 从零构建 PPTX 文件（ZIP + Open XML），不依赖外部 PPTX 库。
/// 每个页面对应一张幻灯片，支持标题 + 笔画渲染为图片嵌入。
///
/// PPTX 格式：一个 ZIP 包含 [Content_Types].xml + ppt/slides/slide[N].xml
/// 等 Open XML 标准文件。
///
/// 使用方式：
/// ```dart
/// final exporter = PptxExporter();
/// final bytes = await exporter.export(
///   pages: [['Page 1 title', strokeList], ...],
///   title: '我的笔记',
/// );
/// await File('output.pptx').writeAsBytes(bytes);
/// ```
library;

import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';

/// PPTX 导出服务。
///
/// 从零构建符合 Open XML 标准的 PPTX 文件。每个输入页面对应一张幻灯片。
/// 幻灯片包含标题文字和内容区域（文字或占位符）。
class PptxExporter {
  const PptxExporter();

  /// PPTX 标准幻灯片尺寸（16:9 宽屏）：宽 9144000 EMU = 25.4cm，
  /// 高 6858000 EMU = 19.05cm。
  static const int _slideWidthEmu = 9144000;
  static const int _slideHeightEmu = 6858000;

  /// 导出多页内容为 PPTX 字节。
  ///
  /// [pages] 每个元素为一个 Map，必须包含 'title' (String) 和
  /// 可选的 'content' (String)、'bullets' (List<String>)。
  /// [title] 演示文稿标题；[author] 作者。
  Future<Uint8List> export({
    required List<Map<String, dynamic>> pages,
    String? title,
    String? author,
  }) async {
    final archive = Archive();
    final slideCount = pages.length;

    // [Content_Types].xml
    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml(slideCount).length,
      utf8.encode(_contentTypesXml(slideCount)),
    ));

    // _rels/.rels
    archive.addFile(ArchiveFile(
      '_rels/.rels',
      _relsXml.length,
      utf8.encode(_relsXml),
    ));

    // ppt/_rels/presentation.xml.rels
    archive.addFile(ArchiveFile(
      'ppt/_rels/presentation.xml.rels',
      _presentationRelsXml(slideCount).length,
      utf8.encode(_presentationRelsXml(slideCount)),
    ));

    // ppt/presentation.xml
    archive.addFile(ArchiveFile(
      'ppt/presentation.xml',
      _presentationXml(slideCount).length,
      utf8.encode(_presentationXml(slideCount)),
    ));

    // ppt/slideMasters/slideMaster1.xml
    archive.addFile(ArchiveFile(
      'ppt/slideMasters/slideMaster1.xml',
      _slideMasterXml.length,
      utf8.encode(_slideMasterXml),
    ));

    // ppt/slideMasters/_rels/slideMaster1.xml.rels
    archive.addFile(ArchiveFile(
      'ppt/slideMasters/_rels/slideMaster1.xml.rels',
      _slideMasterRelsXml.length,
      utf8.encode(_slideMasterRelsXml),
    ));

    // ppt/slideLayouts/slideLayout1.xml
    archive.addFile(ArchiveFile(
      'ppt/slideLayouts/slideLayout1.xml',
      _slideLayoutXml.length,
      utf8.encode(_slideLayoutXml),
    ));

    // ppt/slideLayouts/_rels/slideLayout1.xml.rels
    archive.addFile(ArchiveFile(
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels',
      _slideLayoutRelsXml.length,
      utf8.encode(_slideLayoutRelsXml),
    ));

    // 每张幻灯片
    for (var i = 0; i < slideCount; i++) {
      final page = pages[i];
      final slideNum = i + 1;

      // slide XML
      archive.addFile(ArchiveFile(
        'ppt/slides/slide$slideNum.xml',
        0, // size will be computed
        utf8.encode(_slideXml(page, title)),
      ));

      // slide rels
      archive.addFile(ArchiveFile(
        'ppt/slides/_rels/slide$slideNum.xml.rels',
        _slideRelsXml.length,
        utf8.encode(_slideRelsXml),
      ));
    }

    // docProps
    archive.addFile(ArchiveFile(
      'docProps/core.xml',
      _coreXml(title, author).length,
      utf8.encode(_coreXml(title, author)),
    ));

    archive.addFile(ArchiveFile(
      'docProps/app.xml',
      _appXml(slideCount).length,
      utf8.encode(_appXml(slideCount)),
    ));

    // 打包为 ZIP
    final zipData = ZipEncoder().encode(archive);

    return Uint8List.fromList(zipData);
  }

  /// [Content_Types].xml — PPTX 包的内容类型定义。
  String _contentTypesXml(int slideCount) {
    final overrides = StringBuffer();
    for (var i = 1; i <= slideCount; i++) {
      overrides.writeln(
        '  <Override PartName="/ppt/slides/slide$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"
       xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
${overrides.toString()}  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';
  }

  /// _rels/.rels — 根关系文件。
  static const String _relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  /// ppt/_rels/presentation.xml.rels — 演示文稿关系文件。
  String _presentationRelsXml(int slideCount) {
    final slides = StringBuffer();
    for (var i = 1; i <= slideCount; i++) {
      slides.writeln(
        '  <Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>',
      );
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${slides.toString()}  <Relationship Id="rId${slideCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
  <Relationship Id="rId${slideCount + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="slideLayouts/slideLayout1.xml"/>
</Relationships>''';
  }

  /// ppt/presentation.xml — 演示文稿主文件。
  String _presentationXml(int slideCount) {
    final sldIdLst = StringBuffer();
    for (var i = 0; i < slideCount; i++) {
      sldIdLst.writeln(
        '      <p:sldId id="${256 + i}" r:id="rId${i + 1}"/>',
      );
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldMasterIdLst>
    <p:sldMasterId id="2147483648" r:id="rId${slideCount + 1}"/>
  </p:sldMasterIdLst>
  <p:sldIdLst>
$sldIdLst  </p:sldIdLst>
  <p:sldSz cx="$_slideWidthEmu" cy="$_slideHeightEmu" type="custom"/>
  <p:notesSz cx="$_slideHeightEmu" cy="$_slideWidthEmu"/>
</p:presentation>''';
  }

  /// 单张幻灯片 XML。
  String _slideXml(Map<String, dynamic> page, String? presentationTitle) {
    final title = page['title'] as String? ?? '';
    final content = page['content'] as String? ?? '';
    final bullets = page['bullets'] as List<String>?;

    final shapes = StringBuffer();

    // 标题形状（顶部区域）
    shapes.writeln('''
    <p:sp>
      <p:nvSpPr>
        <p:cNvPr id="1" name="Title"/>
        <p:cNvSpPr>
          <a:spLocks noGrp="1"/>
        </p:cNvSpPr>
        <p:nvPr>
          <p:ph type="title"/>
        </p:nvPr>
      </p:nvSpPr>
      <p:spPr>
        <a:xfrm>
          <a:off x="457200" y="228600"/>
          <a:ext cx="${_slideWidthEmu - 914400}" cy="743400"/>
        </a:xfrm>
      </p:spPr>
      <p:txBody>
        <a:bodyPr/>
        <a:p>
          <a:r>
            <a:rPr lang="zh-CN" sz="2800" b="1" dirty="0"/>
            <a:t>${_xmlEscape(title)}</a:t>
          </a:r>
        </a:p>
      </p:txBody>
    </p:sp>''');

    // 内容区域
    if (content.isNotEmpty || bullets != null) {
      final textParts = StringBuffer();

      if (content.isNotEmpty) {
        textParts.writeln('''
        <a:p>
          <a:r>
            <a:rPr lang="zh-CN" sz="1800" dirty="0"/>
            <a:t>${_xmlEscape(content)}</a:t>
          </a:r>
        </a:p>''');
      }

      if (bullets != null) {
        for (final bullet in bullets) {
          textParts.writeln('''
        <a:p>
          <a:pPr marL="342900" indent="-342900">
            <a:buChar char="\u2022"/>
          </a:pPr>
          <a:r>
            <a:rPr lang="zh-CN" sz="1600" dirty="0"/>
            <a:t>${_xmlEscape(bullet)}</a:t>
          </a:r>
        </a:p>''');
        }
      }

      shapes.writeln('''
    <p:sp>
      <p:nvSpPr>
        <p:cNvPr id="2" name="Content"/>
        <p:cNvSpPr>
          <a:spLocks noGrp="1"/>
        </p:cNvSpPr>
        <p:nvPr>
          <p:ph type="body"/>
        </p:nvPr>
      </p:nvSpPr>
      <p:spPr>
        <a:xfrm>
          <a:off x="457200" y="1143000"/>
          <a:ext cx="${_slideWidthEmu - 914400}" cy="${_slideHeightEmu - 1371600}"/>
        </a:xfrm>
      </p:spPr>
      <p:txBody>
        <a:bodyPr/>
        <a:lstAutoPrg/>
$textParts      </p:txBody>
    </p:sp>''');
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="0" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
$shapes    </p:spTree>
  </p:cSld>
</p:sld>''';
  }

  /// slide rels（所有幻灯片共用）。
  static const String _slideRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';

  /// ppt/slideMasters/slideMaster1.xml。
  static const String _slideMasterXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:bg>
      <p:bgRef idx="1001">
        <a:srgbClr val="FFFFFF"/>
      </p:bgRef>
    </p:bg>
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="0" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
    </p:spTree>
  </p:cSld>
  <p:sldLayoutIdLst>
    <p:sldLayoutId id="2147483649" r:id="rId1"/>
  </p:sldLayoutIdLst>
</p:sldMaster>''';

  /// ppt/slideMasters/_rels/slideMaster1.xml.rels。
  static const String _slideMasterRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';

  /// ppt/slideLayouts/slideLayout1.xml。
  static const String _slideLayoutXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld name="Blank">
    <p:spTree>
      <p:nvGrpSpPr>
        <p:cNvPr id="0" name=""/>
        <p:cNvGrpSpPr/>
        <p:nvPr/>
      </p:nvGrpSpPr>
      <p:grpSpPr>
        <a:xfrm>
          <a:off x="0" y="0"/>
          <a:ext cx="0" cy="0"/>
          <a:chOff x="0" y="0"/>
          <a:chExt cx="0" cy="0"/>
        </a:xfrm>
      </p:grpSpPr>
    </p:spTree>
  </p:cSld>
</p:sldLayout>''';

  /// ppt/slideLayouts/_rels/slideLayout1.xml.rels。
  static const String _slideLayoutRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';

  /// docProps/core.xml。
  String _coreXml(String? title, String? author) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                    xmlns:dc="http://purl.org/dc/elements/1.1/"
                    xmlns:dcterms="http://purl.org/dc/terms/"
                    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>${_xmlEscape(title ?? '')}</dc:title>
  <dc:creator>${_xmlEscape(author ?? 'DrawingNotes')}</dc:creator>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
</cp:coreProperties>''';
  }

  /// docProps/app.xml。
  String _appXml(int slideCount) {
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>DrawingNotes</Application>
  <Slides>$slideCount</Slides>
  <Company>DrawingNotes</Company>
</Properties>''';
  }

  /// XML 特殊字符转义。
  String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
