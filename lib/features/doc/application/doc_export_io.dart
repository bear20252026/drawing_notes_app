// 由 Claude 团队生成 | Drawing Notes App
// 文档导出落盘辅助（M12.5/6）：文件名安全化 + 写入系统文档目录。
// 转换逻辑在域层（note_block_doc_markdown.dart / doc_html_export.dart），
// 本文件只做 IO——单一职责，避免转换与落盘耦合。

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 文件名安全化：去除路径非法字符。
String sanitizeFileName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? '未命名' : cleaned;
}

/// 把内容写入 `文档目录/绘图笔记导出/<name>.<ext>`，重名自动追加序号。
/// 返回最终写入的文件路径。
Future<String> writeExportFile({
  required String baseName,
  required String extension,
  required String content,
}) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${docsDir.path}${Platform.pathSeparator}绘图笔记导出');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final base = sanitizeFileName(baseName);
  var path = '${dir.path}${Platform.pathSeparator}$base.$extension';
  var n = 1;
  while (File(path).existsSync()) {
    path = '${dir.path}${Platform.pathSeparator}$base (${n++}).$extension';
  }
  await File(path).writeAsString(content, flush: true);
  return path;
}
