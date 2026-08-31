// 由 Claude 团队生成 | Drawing Notes App
// 文档导出落盘辅助（M12.5/6）：文件名安全化 + 写入系统文档目录。
// 转换逻辑在域层（note_block_doc_markdown.dart / doc_html_export.dart），
// 本文件只做 IO——单一职责，避免转换与落盘耦合。

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 文件名安全化：去除路径非法字符 + 尾点/尾空格（Windows 文件名禁尾点）。
String sanitizeFileName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return cleaned.isEmpty ? '未命名' : cleaned;
}

/// 把内容写入 `文档目录/绘图笔记导出/<name>.<ext>`，重名自动追加序号。
/// 返回最终写入的文件路径。
Future<String> writeExportFile({
  required String baseName,
  required String extension,
  required String content,
}) async {
  final path = await _resolveExportPath(
    baseName: baseName,
    extension: extension,
  );
  await File(path).writeAsString(content, flush: true);
  return path;
}

/// 二进制版导出（PDF 等格式必须走字节，避免文本编码破坏数据）。
Future<String> writeExportFileBytes({
  required String baseName,
  required String extension,
  required Uint8List bytes,
}) async {
  final path = await _resolveExportPath(
    baseName: baseName,
    extension: extension,
  );
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<String> _resolveExportPath({
  required String baseName,
  required String extension,
}) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${docsDir.path}${Platform.pathSeparator}绘图笔记导出');
  // P3：全部异步 IO——existsSync/createSync 在 UI isolate 会造成微卡顿。
  if (!await dir.exists()) await dir.create(recursive: true);
  final base = sanitizeFileName(baseName);
  var path = '${dir.path}${Platform.pathSeparator}$base.$extension';
  var n = 1;
  while (await File(path).exists()) {
    path = '${dir.path}${Platform.pathSeparator}$base (${n++}).$extension';
  }
  return path;
}
