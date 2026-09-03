// 由 Claude 团队生成 | Drawing Notes App
// 文档导出落盘辅助（M12.5/6）：文件名安全化 + 写入系统文档目录。
// 转换逻辑在域层（note_block_doc_markdown.dart / doc_html_export.dart），
// 本文件只做 IO——单一职责，避免转换与落盘耦合。

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Windows 保留设备名（不区分大小写、忽略尾点尾空格）。
const _reservedDeviceNames = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// 文件名安全化：去除路径非法字符 + 尾点/尾空格（Windows 文件名禁尾点）。
/// P2 加固：控制字符剥离 + 200 字上限（超长写失败 DoS）+ 保留设备名
/// （CON/NUL 写失败/误操作）+ 扩展名白名单化（调用方透传 `../../exe`
/// 即遍历/双扩展名欺骗）。
String sanitizeFileName(String raw) {
  var cleaned = raw
      // ignore: control_character_in_regex
      .replaceAll(RegExp('[\u0000-\u001f\u007f]'), '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return '未命名';
  if (cleaned.length > 200) cleaned = cleaned.substring(0, 200);
  final stem = cleaned.split('.').first.toLowerCase();
  if (_reservedDeviceNames.contains(stem)) cleaned = '_$cleaned';
  return cleaned;
}

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
  if (!await dir.exists()) await dir.create(recursive: true);
  final base = sanitizeFileName(baseName);
  final ext = _sanitizeExtension(extension);
  var path = '${dir.path}${Platform.pathSeparator}$base.$ext';
  var n = 1;
  while (await File(path).exists()) {
    path = '${dir.path}${Platform.pathSeparator}$base (${n++}).$ext';
  }
  return path;
}
