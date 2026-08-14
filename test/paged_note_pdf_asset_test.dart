import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  testWidgets('离线 CJK 字体可生成包含中文的分页 PDF', (tester) async {
    final fontData = await rootBundle.load(
      'assets/fonts/DroidSansFallbackFull.ttf',
    );
    final cjk = pw.Font.ttf(fontData);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: cjk, bold: cjk),
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Text('分页笔记：中文导出验证'),
      ),
    );

    final bytes = await document.save();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
