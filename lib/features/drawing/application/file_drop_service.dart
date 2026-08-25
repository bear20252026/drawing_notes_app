import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 文件拖放导入服务：支持从文件系统拖放图片和文档。
///
/// 通过 file_selector 或拖放 API 获取文件路径，
/// 读取并验证文件格式，返回可导入的文件数据。
class FileDropService {
  /// 支持的图片格式。
  static const Set<String> supportedImageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
    'webp',
  };

  /// 支持的文档格式。
  static const Set<String> supportedDocumentExtensions = {
    'json', // Excalidraw 格式
    'svg',
    'pdf',
  };

  /// 检查文件是否为支持的图片格式。
  static bool isSupportedImage(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return supportedImageExtensions.contains(ext);
  }

  /// 检查文件是否为支持的文档格式。
  static bool isSupportedDocument(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return supportedDocumentExtensions.contains(ext);
  }

  /// 检查文件是否为支持的导入格式。
  static bool isSupportedFile(String filePath) {
    return isSupportedImage(filePath) || isSupportedDocument(filePath);
  }

  /// 读取图片文件数据。
  static Future<Uint8List?> readImageFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('FileDropService: 文件不存在 - $filePath');
        return null;
      }

      if (!isSupportedImage(filePath)) {
        debugPrint('FileDropService: 不支持的图片格式 - $filePath');
        return null;
      }

      return await file.readAsBytes();
    } catch (e) {
      debugPrint('FileDropService: 读取图片失败 - $e');
      return null;
    }
  }

  /// 读取 SVG 文件内容。
  static Future<String?> readSvgFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('FileDropService: 文件不存在 - $filePath');
        return null;
      }

      if (!isSupportedDocument(filePath) ||
          !filePath.toLowerCase().endsWith('.svg')) {
        debugPrint('FileDropService: 不是 SVG 文件 - $filePath');
        return null;
      }

      return await file.readAsString();
    } catch (e) {
      debugPrint('FileDropService: 读取 SVG 失败 - $e');
      return null;
    }
  }

  /// 读取 JSON 文件内容（Excalidraw 格式）。
  static Future<Map<String, dynamic>?> readJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('FileDropService: 文件不存在 - $filePath');
        return null;
      }

      if (!filePath.toLowerCase().endsWith('.json')) {
        debugPrint('FileDropService: 不是 JSON 文件 - $filePath');
        return null;
      }

      final content = await file.readAsString();
      return Map<String, dynamic>.from(
        jsonDecode(content) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('FileDropService: 读取 JSON 失败 - $e');
      return null;
    }
  }

  /// 获取文件的 MIME 类型。
  static String getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  /// 验证文件是否可导入（文件存在且格式支持）。
  static Future<FileDropValidation> validateFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return FileDropValidation(
        isValid: false,
        error: '文件不存在',
      );
    }

    if (!isSupportedFile(filePath)) {
      return FileDropValidation(
        isValid: false,
        error: '不支持的文件格式',
      );
    }

    final stat = await file.stat();
    if (stat.size == 0) {
      return FileDropValidation(
        isValid: false,
        error: '文件为空',
      );
    }

    // 限制文件大小（最大 50MB）
    const maxSize = 50 * 1024 * 1024;
    if (stat.size > maxSize) {
      return FileDropValidation(
        isValid: false,
        error: '文件太大（最大 50MB）',
      );
    }

    return FileDropValidation(
      isValid: true,
      fileSize: stat.size,
      mimeType: getMimeType(filePath),
    );
  }
}

/// 文件拖放验证结果。
class FileDropValidation {
  const FileDropValidation({
    required this.isValid,
    this.error,
    this.fileSize,
    this.mimeType,
  });

  final bool isValid;
  final String? error;
  final int? fileSize;
  final String? mimeType;

  /// 文件大小（MB）。
  double? get fileSizeMB =>
      fileSize != null ? (fileSize! / 1024 / 1024) : null;
}
