import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';

/// 文档图片的运行时解码缓存。
///
/// 图片字节只保存在离线文件中，文档 JSON 仅持久化文件路径。本协作者负责把
/// 路径按需解码为 [ui.Image]、复用进行中的同一加载任务、以有限并发预载导出
/// 所需资源，并在替换或销毁时释放 GPU/Skia 图像资源。
typedef DocumentImageDecoder = Future<ui.Image> Function(String filePath);

class DocumentImageCache {
  DocumentImageCache({
    required this._onImageAvailable,
    required this._isOwnerDisposed,
    this._decoder = _decodeImageFile,
  });

  final VoidCallback _onImageAvailable;
  final bool Function() _isOwnerDisposed;
  final DocumentImageDecoder _decoder;
  final Map<String, ui.Image> _images = <String, ui.Image>{};
  final Map<String, Future<void>> _loads = <String, Future<void>>{};

  bool _disposed = false;

  bool get _isInactive => _disposed || _isOwnerDisposed();

  /// 返回已解码图片；首次访问会在后台启动加载并在完成后请求宿主刷新。
  ui.Image? imageFor(DocumentImageItem item) {
    final cached = _images[item.id];
    if (cached != null) return cached;
    unawaited(_load(item));
    return null;
  }

  /// 在渲染或导出前确保一组图片已完成加载。
  ///
  /// 每批最多四张，避免大量高分辨率图片同时解码造成瞬时内存峰值。
  Future<void> ensureLoaded(Iterable<DocumentImageItem> items) async {
    final pending = <DocumentImageItem>[
      for (final item in items)
        if (!_images.containsKey(item.id)) item,
    ];
    const batchSize = 4;
    for (var index = 0; index < pending.length; index += batchSize) {
      if (_isInactive) return;
      final batch = pending.skip(index).take(batchSize);
      await Future.wait(<Future<void>>[for (final item in batch) _load(item)]);
    }
  }

  Future<void> _load(DocumentImageItem item) {
    if (_isInactive || _images.containsKey(item.id)) {
      return Future<void>.value();
    }
    final ongoing = _loads[item.id];
    if (ongoing != null) return ongoing;
    final task = _decodeAndStore(item);
    _loads[item.id] = task;
    return task;
  }

  Future<void> _decodeAndStore(DocumentImageItem item) async {
    ui.Image? image;
    try {
      image = await _decoder(item.filePath);
      if (_isInactive) return;
      final previous = _images[item.id];
      _images[item.id] = image;
      image = null;
      previous?.dispose();
      _onImageAvailable();
    } catch (_) {
      // 图片缺失或损坏时保留其余文档内容的可编辑性；下次按需访问可重试。
    } finally {
      image?.dispose();
      _loads.remove(item.id);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _loads.clear();
  }
}

Future<ui.Image> _decodeImageFile(String filePath) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(filePath);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
