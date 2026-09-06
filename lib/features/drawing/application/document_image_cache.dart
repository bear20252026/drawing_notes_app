import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/shared/utils/image_decode_cap.dart';

/// 文档图片的运行时解码缓存。
///
/// 图片字节只保存在离线文件中，文档 JSON 仅持久化文件路径。本协作者负责把
/// 路径按需解码为 [ui.Image]、复用进行中的同一加载任务、以有限并发预载导出
/// 所需资源，并在替换或销毁时释放 GPU/Skia 图像资源。
///
/// 内存上限（P0 修复，2026-09-06 外部专家审计 #2）：此前的 `_images` 是
/// 无任何淘汰的 `Map`，解码上限 4096 长边（单张极端照片可达 ~64MB），多图
/// 笔记累积很快到几百 MB。现加入 **LRU + 字节预算**：超 [maxCacheBytes]
/// 时按最近未用顺序淘汰并 `dispose`（近期渲染过=可见性高，近似专家建议的
/// 「按可见性优先保活，离屏图片先 dispose」）。
typedef DocumentImageDecoder = Future<ui.Image> Function(String filePath);

class DocumentImageCache {
  DocumentImageCache({
    required this._onImageAvailable,
    required this._isOwnerDisposed,
    DocumentImageDecoder? decoder,
    this.maxCacheBytes = maxCacheBytesDefault,
  }) : _decoder = decoder ?? _decodeImageFile;

  /// 文档图片解码缓存字节预算。单张 RGBA 上限 4096²×4 ≈ 64MB，预算 96MB
  /// 可容纳约 1.5 张超清大图或十几张常规图，超限即淘汰最久未用。
  static const int maxCacheBytesDefault = 96 << 20; // 96 MiB

  final VoidCallback _onImageAvailable;
  final bool Function() _isOwnerDisposed;
  final DocumentImageDecoder _decoder;
  final Map<String, ui.Image> _images = <String, ui.Image>{};
  final Map<String, Future<void>> _loads = <String, Future<void>>{};

  /// LRU 访问序（索引 0 = 最久未用）。
  final List<String> _lru = [];

  late final int maxCacheBytes;
  int _cachedBytes = 0;
  bool _disposed = false;

  bool get _isInactive => _disposed || _isOwnerDisposed();

  int _sizeOf(ui.Image image) => image.width * image.height * 4;

  /// 返回已解码图片；首次访问会在后台启动加载并在完成后请求宿主刷新。
  /// 命中时刷新 LRU 近序（最近渲染作为保活优先级依据）。
  ui.Image? imageFor(DocumentImageItem item) {
    final cached = _images[item.id];
    if (cached != null) {
      _touch(item.id);
      return cached;
    }
    unawaited(_load(item));
    return null;
  }

  void _touch(String id) {
    _lru
      ..remove(id)
      ..add(id);
  }

  /// 超出字节预算时按最久未用淘汰并释放其图像资源（P0 修复）。
  void _evictIfOverBudget() {
    while (_cachedBytes > maxCacheBytes && _lru.isNotEmpty) {
      final oldestId = _lru.removeAt(0);
      final evicted = _images.remove(oldestId);
      if (evicted != null) {
        _cachedBytes -= _sizeOf(evicted);
        evicted.dispose();
      }
    }
  }

  /// 在渲染或导出前确保一组图片已完成加载。
  ///
  /// 并发随剩余预算动态收缩（审计 P2-4）：预算充裕时批量 4 张并行；
  /// 已用字节超过预算一半后改为逐张串行——极端 4096 长边单张 ~64MB，
  /// 避免 4 张并行在淘汰介入前出现 150MB+ 的瞬时解码峰值。
  Future<void> ensureLoaded(Iterable<DocumentImageItem> items) async {
    final pending = <DocumentImageItem>[
      for (final item in items)
        if (!_images.containsKey(item.id)) item,
    ];
    for (var index = 0; index < pending.length; ) {
      if (_isInactive) return;
      final overHalfBudget = _cachedBytes > maxCacheBytes ~/ 2;
      final batchSize = overHalfBudget ? 1 : 4;
      final batch = pending.skip(index).take(batchSize);
      index += batchSize;
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
      _touch(item.id);
      final previousSize = previous == null ? 0 : _sizeOf(previous);
      _cachedBytes = _cachedBytes - previousSize + _sizeOf(image);
      image = null;
      previous?.dispose();
      _evictIfOverBudget();
      _onImageAvailable();
    } catch (_) {
      // 图片缺失或损坏时保留其余文档内容的可编辑性；下次按需访问可重试。
    } finally {
      image?.dispose();
      _loads.remove(item.id);
    }
  }

  /// 使单个图片的缓存位图失效并释放（裁剪重写文件后调用）。
  ///
  /// 下一次 `imageFor` 会按需重新解码磁盘上的新内容（P0 审计修复补充：
  /// 此前无单条失效 API，裁剪后画布仍显示裁剪前的旧全尺寸位图）。
  void invalidate(String imageId) {
    final removed = _images.remove(imageId);
    if (removed == null) return;
    _lru.remove(imageId);
    _cachedBytes -= _sizeOf(removed);
    removed.dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _lru.clear();
    _cachedBytes = 0;
    _loads.clear();
  }
}

/// 批次①c：先经 DNV 嗅探读字节（保险库密文解密 / 锁定抛
/// [VaultFileLockException]——由 [_decodeAndStore] 吞掉保留可编辑性），
/// 明文/DAN 由 readImageBytes 原样返回，再走既有 descriptor 解码。
///
/// U2 降采样（2026-09-02，P1-13）：长边超过 [ImageDecodeCap.canvasMaxLongEdge]
/// 时解码阶段直接缩图——画布可深度缩放故上限放宽到 4096，极端照片
/// （8000px+）的解码内存仍被钳制。
Future<ui.Image> _decodeImageFile(String filePath) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    final bytes = await VaultFileCodec.readImageBytes(File(filePath));
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final target = ImageDecodeCap.targetSize(
      descriptor.width,
      descriptor.height,
      ImageDecodeCap.canvasMaxLongEdge,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: target.width,
      targetHeight: target.height,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
