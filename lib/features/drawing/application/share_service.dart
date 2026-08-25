import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 系统分享服务：对齐 Android Intent / Windows Share 体验。
///
/// 通过平台通道调用原生分享 API：
/// - Android: Intent.ACTION_SEND
/// - Windows: Share charm / shell API
/// - macOS: NSSharingService
class ShareService {
  static const MethodChannel _channel = MethodChannel(
    'gov.drawingnotes/share',
  );

  /// 分享文件到系统分享菜单。
  ///
  /// [filePath] 本地文件路径
  /// [mimeType] MIME 类型（如 'image/png', 'application/pdf'）
  /// [title] 分享对话框标题（可选）
  static Future<void> shareFile({
    required String filePath,
    required String mimeType,
    String? title,
  }) async {
    try {
      await _channel.invokeMethod('shareFile', {
        'filePath': filePath,
        'mimeType': mimeType,
        'title': title ?? '分享',
      });
    } on MissingPluginException {
      // 平台不支持分享，静默失败
      debugPrint('ShareService: 平台不支持分享功能');
    } catch (e) {
      debugPrint('ShareService: 分享失败 - $e');
      rethrow;
    }
  }

  /// 分享文本内容。
  static Future<void> shareText({
    required String text,
    String? title,
  }) async {
    try {
      await _channel.invokeMethod('shareText', {
        'text': text,
        'title': title ?? '分享',
      });
    } on MissingPluginException {
      debugPrint('ShareService: 平台不支持分享功能');
    } catch (e) {
      debugPrint('ShareService: 分享失败 - $e');
      rethrow;
    }
  }

  /// 分享图片数据。
  ///
  /// 将 RGBA 像素数据写入临时文件后分享。
  static Future<void> shareImage({
    required Uint8List pngData,
    String? title,
  }) async {
    try {
      // 写入临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngData, flush: true);

      // 分享临时文件
      await shareFile(
        filePath: tempFile.path,
        mimeType: 'image/png',
        title: title,
      );

      // 清理临时文件
      await tempFile.delete();
    } catch (e) {
      debugPrint('ShareService: 分享图片失败 - $e');
      rethrow;
    }
  }

  /// 分享 PDF 文件。
  static Future<void> sharePdf({
    required Uint8List pdfData,
    required String fileName,
    String? title,
  }) async {
    try {
      // 写入临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(pdfData, flush: true);

      // 分享临时文件
      await shareFile(
        filePath: tempFile.path,
        mimeType: 'application/pdf',
        title: title,
      );

      // 清理临时文件
      await tempFile.delete();
    } catch (e) {
      debugPrint('ShareService: 分享 PDF 失败 - $e');
      rethrow;
    }
  }

  /// 分享 SVG 文件。
  static Future<void> shareSvg({
    required String svgContent,
    required String fileName,
    String? title,
  }) async {
    try {
      // 写入临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(svgContent, flush: true);

      // 分享临时文件
      await shareFile(
        filePath: tempFile.path,
        mimeType: 'image/svg+xml',
        title: title,
      );

      // 清理临时文件
      await tempFile.delete();
    } catch (e) {
      debugPrint('ShareService: 分享 SVG 失败 - $e');
      rethrow;
    }
  }
}
