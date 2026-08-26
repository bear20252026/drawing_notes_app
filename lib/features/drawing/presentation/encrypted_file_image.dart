import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/security/media_crypto_service.dart';
import '../../../infrastructure/storage/vfs/vault_service.dart';

/// 加密媒体图片渲染（H-03 双端接入 2026-08-15）�?///
/// ImageProvider.loadBuffer 官方 API（PR #103496）：读取媒体文件字节 �?/// [MediaCryptoService.readMediaFile]（DAN 密文解密 / 明文兼容——旧数据
/// 与未加密笔记本）�?解码渲染。与 storeImage 加密写入成对（双端同步）�?@immutable
class EncryptedFileImage extends ImageProvider<EncryptedFileImage> {
  const EncryptedFileImage(this.file, {this.scale = 1.0});

  /// 媒体文件（可能为 DAN 密文或明文）�?  final File file;

  final double scale;

  @override
  Future<EncryptedFileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<EncryptedFileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    EncryptedFileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.file.path,
    );
  }

  Future<ui.Codec> _loadAsync(
    EncryptedFileImage key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    // 媒体 VFS 双轨�?026-08-16）：'vfs:' 前缀对象（新媒体——VaultService
    // 解密明文）→ 直接渲染；否则文件路径（旧媒体——DAN 检测兼容—�?    // s3-encryption-gateway 双读窗口模式）�?    final path = key.file.path;
    if (path.startsWith('vfs:')) {
      final clear = await VaultService.instance.getObject(path.substring(4));
      if (clear.isEmpty) {
        PaintingBinding.instance.imageCache.evict(key);
        throw StateError('$file 无法加载为图片（VFS 对象�?);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(clear);
      return decode(buffer);
    }
    final bytes = await key.file.readAsBytes();
    // DAN 密文 �?解密；明文（旧数�?未加密）�?原样返回�?    final clear = await MediaCryptoService.instance.readMediaFile(bytes);
    if (clear.isEmpty) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('$file 无法加载为图�?);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(clear);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is EncryptedFileImage &&
      other.file.path == file.path &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(file.path, scale);

  @override
  String toString() => 'EncryptedFileImage("${file.path}", scale: $scale)';
}
