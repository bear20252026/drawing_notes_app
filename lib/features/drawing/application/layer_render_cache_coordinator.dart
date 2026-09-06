import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/features/drawing/rendering/layer_compositor.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';

/// 协调文档图层的离屏位图缓存。
///
/// 缓存索引、脏区域、异步串行重建和位图资源释放均属于运行时渲染会话，
/// 与 DrawingController 的工具、手势、选区和历史职责无关。该协作者通过
/// [onRenderUpdated] 仅在缓存可视状态变化时请求宿主刷新。
class LayerRenderCacheCoordinator {
  LayerRenderCacheCoordinator({
    required this._document,
    required this._onRenderUpdated,
    required this._isOwnerDisposed,
    this._compositor = const LayerCompositor(),
  }) {
    rebuildCacheMap();
  }

  final DrawingDocument _document;
  final VoidCallback _onRenderUpdated;
  final bool Function() _isOwnerDisposed;
  final LayerCompositor _compositor;
  final Map<String, LayerRenderCache> _caches = <String, LayerRenderCache>{};

  bool _rebuilding = false;
  bool _disposed = false;

  bool get _isInactive => _disposed || _isOwnerDisposed();

  /// 为绘制提供图层位图视图列表（自底向上）。
  List<LayerPaintView> get paintViews => <LayerPaintView>[
    for (final layer in _document.layers)
      LayerPaintView(
        image: _caches[layer.id]?.image,
        visible: layer.visible,
        opacity: layer.opacity,
      ),
  ];

  /// 新建图层后预先注册空缓存，避免首次失效时遗漏索引。
  void addLayer(Layer layer) {
    if (_isInactive) return;
    _caches.putIfAbsent(layer.id, LayerRenderCache.new);
  }

  /// 删除图层时释放其位图，防止运行时图像资源泄漏。
  void removeLayer(String layerId) {
    _caches.remove(layerId)?.dispose();
  }

  /// 根据当前文档图层同步缓存索引，并释放已删除图层的位图。
  void rebuildCacheMap() {
    if (_isInactive) return;
    final layerIds = _document.layers.map((layer) => layer.id).toSet();
    final removedCaches = <LayerRenderCache>[];
    _caches.removeWhere((layerId, cache) {
      if (layerIds.contains(layerId)) return false;
      removedCaches.add(cache);
      return true;
    });
    for (final cache in removedCaches) {
      cache.dispose();
    }
    for (final layer in _document.layers) {
      _caches.putIfAbsent(layer.id, LayerRenderCache.new);
    }
  }

  /// 标记图层内容或属性变化，并在非无限画布上异步重建离屏缓存。
  Future<void> invalidateLayer(String layerId, {Rect? region}) async {
    if (_isInactive) return;
    // 无限画布不使用固定宽高的离屏位图缓存；直接绘制可见区域矢量点列。
    if (_document.infinite) {
      _notifyIfActive();
      return;
    }
    final cache = _caches[layerId];
    final layer = _document.layers
        .where((candidate) => candidate.id == layerId)
        .firstOrNull;
    if (cache == null || layer == null) return;
    cache
      ..dirty = true
      ..dirtyRegion = region;
    await _rebuildLayer(layer);
    // 若本次调用在既有重建循环运行时被跳过，循环结束后补一次，保证缓存最终一致。
    if (cache.dirty && !_isInactive) {
      await _rebuildLayer(layer);
    }
  }

  /// 标记所有图层为脏并按顺序重建，供图层快照恢复等全量变更使用。
  Future<void> rebuildAll() async {
    if (_isInactive) return;
    for (final layer in _document.layers) {
      _caches[layer.id]?.dirty = true;
    }
    for (final layer in List<Layer>.of(_document.layers)) {
      if (_isInactive) return;
      await _rebuildLayer(layer);
    }
    _notifyIfActive();
  }

  /// 释放所有图层离屏位图（App 后台/最小化时调用，P1 修复 2026-09-06 外部
  /// 专家审计 #1）。
  ///
  /// 只释放位图资源并标记脏，**保留缓存索引**；返回前台后下一次重建按当前
  /// 笔画重新光栅化（懒重建）。这能显著降低空载/切后台时的常驻内存——
  /// 巨大画布（如 A4 分页）的图层位图只在真正绘画时占用。
  void releaseForBackground() {
    if (_isInactive) return;
    for (final cache in _caches.values) {
      cache.dispose();
      cache.dirty = true;
    }
  }

  Future<void> _rebuildLayer(Layer layer) async {
    final cache = _caches[layer.id];
    if (cache == null || _isInactive || _rebuilding) return;
    _rebuilding = true;
    try {
      while (cache.dirty && !_isInactive) {
        cache.dirty = false;
        final region = cache.image != null && cache.dirtyRegion != null
            ? cache.dirtyRegion
            : null;
        final base = region != null ? cache.image : null;
        cache.dirtyRegion = null;
        final nextImage = await _compositor.rasterize(
          layer,
          _document.width,
          _document.height,
          region: region,
          base: base,
        );
        if (_isInactive) {
          nextImage.dispose();
          return;
        }
        final previousImage = cache.image;
        cache.image = nextImage;
        previousImage?.dispose();
        _notifyIfActive();
      }
    } finally {
      _rebuilding = false;
    }
  }

  void _notifyIfActive() {
    if (!_isInactive) _onRenderUpdated();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final cache in _caches.values) {
      cache.dispose();
    }
    _caches.clear();
  }
}
