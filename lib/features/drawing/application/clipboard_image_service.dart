import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 剪贴板图片导入服务：支持从剪贴板读取图片数据。
///
/// 通过平台通道获取剪贴板中的图片数据（RGBA 格式），
/// 支持 Windows (CF_DIB) 和 Android (Bitmap) 剪贴板格式。
class ClipboardImageService {
  static const MethodChannel _channel = MethodChannel(
    'gov.drawingnotes/clipboard',
  );

  /// 检查剪贴板中是否有图片数据。
  static Future<bool> hasImage() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasImage');
      return result ?? false;
    } on MissingPluginException {
      // 平台不支持，返回 false
      return false;
    } catch (e) {
      debugPrint('ClipboardImageService: 检查图片失败 - $e');
      return false;
    }
  }

  /// 从剪贴板获取图片数据。
  ///
  /// 返回 RGBA 像素数据和尺寸信息，失败返回 null。
  static Future<ClipboardImageData?> getImage() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getImage',
      );
      if (result == null) return null;

      final width = result['width'] as int;
      final height = result['height'] as int;
      final rgba = result['rgba'] as Uint8List;

      return ClipboardImageData(
        width: width,
        height: height,
        rgba: rgba,
      );
    } on MissingPluginException {
      // 平台不支持
      return null;
    } catch (e) {
      debugPrint('ClipboardImageService: 获取图片失败 - $e');
      return null;
    }
  }

  /// 将剪贴板图片数据转换为 Flutter ui.Image。
  static Future<ui.Image?> getImageAsUiImage() async {
    final data = await getImage();
    if (data == null) return null;

    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(data.rgba.buffer.asUint8List(), (image) {
      completer.complete(image);
    });

    return completer.future;
  }

  /// 将剪贴板图片数据转换为 PNG 字节。
  static Future<Uint8List?> getImageAsPng() async {
    try {
      final data = await Clipboard.getData('image/png');
      return data?.bytes;
    } catch (e) {
      debugPrint('ClipboardImageService: 获取PNG失败 - $e');
      return null;
    }
  }
}

/// 剪贴板图片数据。
class ClipboardImageData {
  const ClipboardImageData({
    required this.width,
    required this.height,
    required this.rgba,
  });

  /// 图片宽度（像素）。
  final int width;

  /// 图片高度（像素）。
  final int height;

  /// RGBA 像素数据。
  final Uint8List rgba;

  /// 图片尺寸。
  Size get size => Size(width.toDouble(), height.toDouble());
}
