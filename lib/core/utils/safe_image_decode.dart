import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 超时保护的图片解码工具。
///
/// 为 `ui.instantiateImageCodec` 提供超时保护和错误处理，
/// 防止损坏图片或超大图片阻塞主线程。
///
/// 注：`ui.instantiateImageCodec` 必须在主线程执行（ui.Image 无法跨 Isolate 传递），
/// 但通过超时机制可以避免无限期阻塞。字节读取等 IO 操作已在各调用处使用 Isolate。
class SafeImageDecode {
  SafeImageDecode._();

  /// 默认超时时间
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// 安全解码图片字节为 [ui.Image]。
  ///
  /// 超时后自动取消并返回错误，不会阻塞主线程。
  ///
  /// [bytes] 图片原始字节，不能为空。
  /// [timeout] 超时时间，默认 30 秒。
  static Future<DecodeResult> decode(
    Uint8List bytes, {
    Duration timeout = defaultTimeout,
  }) async {
    if (bytes.isEmpty) {
      return DecodeResult.error('图片数据为空');
    }

    try {
      final codec = await ui
          .instantiateImageCodec(bytes)
          .timeout(timeout, onTimeout: () {
        throw TimeoutException(
          '图片解码超时（${timeout.inSeconds}秒），可能文件过大或已损坏',
        );
      });
      final frame = await codec.getNextFrame();
      return DecodeResult.success(frame.image);
    } on TimeoutException {
      return DecodeResult.error(
        '图片解码超时（${timeout.inSeconds}秒），文件可能过大或已损坏',
      );
    } catch (e) {
      return DecodeResult.error('图片解码失败：$e');
    }
  }
}

/// 图片解码结果。
class DecodeResult {
  final ui.Image? image;
  final String? errorMessage;

  DecodeResult.success(this.image) : errorMessage = null;
  DecodeResult.error(this.errorMessage) : image = null;

  bool get isSuccess => image != null;
  bool get isError => errorMessage != null;
}
