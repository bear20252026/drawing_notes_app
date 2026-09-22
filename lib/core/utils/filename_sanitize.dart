// 文件名 / 远端路径段清洗——单一事实来源（F10，2026-09-21）。
//
// 此前导出落盘（doc_export_io.sanitizeFileName）与 WebDAV 远端路径段
// （webdav_sync_client）各有一套规则，语义不同却分散。本文件把两者
// 收口到 core/utils，调用方只依赖本库。

import 'package:drawing_notes_app/core/utils/domain_display_labels.dart';

/// Windows 保留设备名（不区分大小写）。
const kReservedDeviceNames = {
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

/// 远端路径段安全字符（WebDAV / 同步）：字母数字与 `_.~-`。
final RegExp kSafeRemotePathSegment = RegExp(r'^[A-Za-z0-9_.~\-]+$');

/// 控制字符（C0 + DEL）——源码用转义，避免字面量污染。
final RegExp _controlChars = RegExp('[\u0000-\u001f\u007f]');

/// 导出文件名安全化：路径非法字符、控制字符、尾点/尾空格。
String sanitizeExportFileName(String raw) {
  var cleaned = raw
      .replaceAll(_controlChars, '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return DomainDisplayLabels.filesystemUntitled;
  if (cleaned.length > 200) cleaned = cleaned.substring(0, 200);
  final stem = cleaned.split('.').first.toLowerCase();
  if (kReservedDeviceNames.contains(stem)) cleaned = '_$cleaned';
  return cleaned;
}

/// 单段远端路径是否合法。
bool isSafeRemotePathSegment(String segment) {
  if (segment.isEmpty) return false;
  if (segment == '.' || segment == '..') return false;
  return kSafeRemotePathSegment.hasMatch(segment);
}

/// 校验整条相对远端路径（`/` 分隔多段）。
bool isSafeRemoteRelativePath(String relativePath) {
  for (final seg in relativePath.split('/')) {
    if (seg.isEmpty) continue;
    if (!isSafeRemotePathSegment(seg)) return false;
  }
  return true;
}

/// 历史 API 名（导出/测试）：与 [sanitizeExportFileName] 等价。
String sanitizeFileName(String raw) => sanitizeExportFileName(raw);
