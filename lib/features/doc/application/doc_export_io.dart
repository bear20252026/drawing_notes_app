import 'package:drawing_notes_app/core/utils/filename_sanitize.dart';
// 由 Claude 团队生成 | Drawing Notes App
// 文档导出落盘辅助（M12.5/6）：文件名安全化 + 写入系统文档目录。
// F10：规则收口到 core/utils/filename_sanitize.dart。

export 'package:drawing_notes_app/core/utils/filename_sanitize.dart'
    show sanitizeFileName, sanitizeExportFileName;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 导出扩展名白名单（未知格式拒绝——防调用方透传遍历/可执行扩展名）。
const _allowedExportExtensions = {
  'md',
  'markdown',
  'txt',
  'html',
  'htm',
  'pdf',
  'png',
  'json',
};

String _sanitizeExtension(String extension) {
  final ext = extension.trim().toLowerCase().replaceAll('.', '');
  if (!_allowedExportExtensions.contains(ext)) {
    throw ArgumentError('不支持的导出格式：$extension');
  }
  return ext;
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
  if (!dir.existsSync()) await dir.create(recursive: true);
  final base = sanitizeExportFileName(baseName);
  final ext = _sanitizeExtension(extension);
  var path = '${dir.path}${Platform.pathSeparator}$base.$ext';
  var n = 1;
  while (File(path).existsSync()) {
    path = '${dir.path}${Platform.pathSeparator}$base (${n++}).$ext';
  }
  return path;
}
