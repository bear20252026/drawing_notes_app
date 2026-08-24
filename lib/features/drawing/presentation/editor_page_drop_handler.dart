/// 拖放导入域（借鉴 Excalidraw 拖放导入）：支持从文件管理器拖入图片/文件。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 拖放文件类型。
enum DropFileType { image, unknown }

/// 拖放文件信息。
class DropFile {
  const DropFile({
    required this.name,
    required this.type,
    required this.bytes,
    this.mimeType,
  });

  final String name;
  final DropFileType type;
  final Uint8List bytes;
  final String? mimeType;

  bool get isImage => type == DropFileType.image;
}

/// 拖放处理器。
class DropHandler {
  /// 根据文件扩展名判断类型。
  static DropFileType detectType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp')) {
      return DropFileType.image;
    }
    return DropFileType.unknown;
  }

  /// 从文件路径列表异步读取字节。
  static Future<List<DropFile>> readFiles(List<String> paths) async {
    final files = <DropFile>[];
    for (final path in paths) {
      try {
        // 注意：实际文件读取由调用方通过 platform channel 或 dart:io 完成。
        // 这里仅做类型检测，字节数据由 EditorPage 通过 _readDroppedFile 读取。
        final name = path.split(RegExp(r'[/\\]')).last;
        files.add(DropFile(
          name: name,
          type: detectType(name),
          bytes: Uint8List(0), // 占位，实际字节由调用方填充
        ));
      } catch (_) {
        // 跳过无法读取的文件。
      }
    }
    return files;
  }
}

/// 拖放状态跟踪（用于 UI 反馈）。
class DropRegionState extends ChangeNotifier {
  bool _isDragging = false;
  bool get isDragging => _isDragging;

  void setDragging(bool value) {
    if (_isDragging != value) {
      _isDragging = value;
      notifyListeners();
    }
  }
}

/// 处理拖放的文件路径。
///
/// 读取文件字节并回调到 EditorPage 处理。
Future<void> handleDroppedFile(
  String path,
  void Function(Uint8List bytes, String name) onImageFile,
  void Function(String message) onError,
) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      onError('文件不存在: $path');
      return;
    }
    final bytes = await file.readAsBytes();
    final name = path.split(RegExp(r'[/\\]')).last;
    final type = DropHandler.detectType(name);
    if (type == DropFileType.image) {
      onImageFile(bytes, name);
    } else {
      onError('不支持的文件类型: $name');
    }
  } catch (e) {
    onError('读取文件失败: $e');
  }
}
