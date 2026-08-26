// core/abstractions — 导出器抽象接口
// 遵循 Clean Architecture：定义抽象契约，实现由 Infrastructure 层提供

import 'dart:typed_data';

/// PDF 混合导出器抽象接口
///
/// 将文档导出为 PDF 格式（混合矢量+栅格）
abstract class PdfHybridExporter {
  /// 导出文档为 PDF
  Future<Uint8List> exportPdf(dynamic document);

  /// 导出页面为 PDF
  Future<Uint8List> exportPage(dynamic page);
}

/// SVG 导出器抽象接口
///
/// 将文档导出为 SVG 矢量格式
abstract class SvgExporter {
  /// 导出文档为 SVG
  Future<String> exportSvg(dynamic document);

  /// 导出页面为 SVG
  Future<String> exportPage(dynamic page);
}
