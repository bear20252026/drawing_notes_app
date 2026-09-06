import 'dart:async' show unawaited;
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
    // 打开已有文档的首次光栅化（2026-09-07 白纸缺陷）：CanvasPainter 对
    // 非无限画布只画位图（image==null 直接跳过该层），此前打开已含笔画
    // 的页面时无人触发光栅化——所有层位图为 null，已有内容整页不可见
    // （用户症状「只有一张白纸」的一半根因）。位图就绪前 painter 走
    // 矢量回退显示，就绪后自动切换位图路径。初始失败不致命：层保持
    // 脏标记，后续失效自愈（painter 矢量回退兜底显示）。
    unawaited(
      rebuildAll().catchError((_) {
        // 忽略：见上——脏标记保留，下次 invalidateLayer 重试。
      }),
    );
  }

  final DrawingDocument _document;
  final VoidCallback _onRenderUpdated;
  final bool Function() _isOwnerDisposed;
  final LayerCompositor _compositor;
  final Map<String, LayerRenderCache> _caches = <String, LayerRenderCache>{};

  bool _disposed = false;

  bool get _isInactive => _disposed || _isOwnerDisposed();

  /// 为绘制提供图层位图视图列表（自底向上）。
  List<LayerPaintView> get paintViews => <LayerPaintView>[
    for (final layer in _document.layers)
      LayerPaintView(
        image: _caches[layer.id]?.image,
        strokes: layer.strokes,
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
    // 任务链串行执行（见 _rebuildQueue）：本 await 覆盖此前飞行中的重建
    // 轮到并完成本次重建，无需旧实现的「跳过后补跑」兜底。
    await _rebuildLayer(layer);
  }

  /// 标记所有图层为脏并按顺序重建，供图层快照恢复等全量变更使用。
  ///
  /// 无限画布守卫（2026-09-07 内存修复）：与 [invalidateLayer] 同口径——
  /// 无限画布走矢量路径、不使用离屏位图（无需重建也无需通知重绘）。
  /// 此前本方法缺守卫，桌面端每次窗口切走再切回（onResume）都会把
  /// 无限画板每层光栅化成 painter 永远不会用的位图（每层 ~24MB 纯浪费，
  /// 随窗口切换反复发生）。
  Future<void> rebuildAll() async {
    if (_isInactive) return;
    if (_document.infinite) return;
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

  /// 串行化重建任务链（2026-09-07 重构）：此前用 `_rebuilding` 布尔守卫，
  /// 重建飞行中到来的失效请求会直接**跳过并提前返回**——构造器触发首次
  /// 光栅化后，紧跟的落笔失效就可能撞上飞行中的重建，调用方 await 返回
  /// 时位图尚未就绪；rebuildAll 在飞行中调用还会整批跳过其余图层。
  /// 改为把每次重建排到任务链末尾：天然串行，await 语义为
  /// 「轮到本任务且执行完毕」。
  Future<void> _rebuildQueue = Future<void>.value();

  Future<void> _rebuildLayer(Layer layer) {
    final task = _rebuildQueue.then((_) => _rebuildLayerNow(layer));
    // 队尾吞掉异常，保证后续任务不被前一个失败卡死；原异常仍由
    // 返回的 task 传给调用方（保持既有失败传播语义）。
    _rebuildQueue = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  Future<void> _rebuildLayerNow(Layer layer) async {
    final cache = _caches[layer.id];
    if (cache == null || _isInactive) return;
    // 空图层/隐藏图层不持有位图（2026-09-07 内存治理）：空层光栅化只会
    // 得到一张全透明位图（A4 封顶后仍 ~24MB）；隐藏层位图 painter 不会
    // 绘制。两者直接释放既有位图并清脏——内容出现（落笔）或图层重新
    // 显示（快照恢复路径会再走 rebuildAll）时按需重建。
    if (!layer.visible || layer.strokes.isEmpty) {
      cache.dirty = false;
      cache.dirtyRegion = null;
      if (cache.image != null) {
        cache.dispose();
        _notifyIfActive();
      }
      return;
    }
    while (cache.dirty && !_isInactive) {
      cache.dirty = false;
      final region = cache.image != null && cache.dirtyRegion != null
          ? cache.dirtyRegion
          : null;
      final base = region != null ? cache.image : null;
      cache.dirtyRegion = null;
      if (base == null) {
        // 全量重建（封顶画布每笔都是全量）：旧位图不会作为增量底图，
        // 在分配新位图**之前**释放——否则 toImage 期间新旧两张 ~24MB
        // 位图并存，每笔落笔的瞬时峰值翻倍（2026-09-07 内存治理）。
        // 重建期间 painter 走矢量回退，画面不会闪空。
        cache.image?.dispose();
        cache.image = null;
      }
      try {
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
      } catch (_) {
        // 光栅化失败（如系统内存不足）：标记脏，下次失效/重试自愈，
        // 期间 painter 矢量回退保证内容仍可见。
        cache.dirty = true;
        rethrow;
      }
      _notifyIfActive();
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
