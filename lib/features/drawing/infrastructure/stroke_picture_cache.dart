import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/core/rendering/stroke_renderer.dart';

/// 已完成笔画集合的预渲染 Picture 缓存（借鉴 scribe_canvas
/// `ScribePainter.cachedPicture` 的 O(1) 重绘思想，见
/// docs/SOURCE_READ_ADAPTATION_REPORT.md）。
///
/// 设计要点（逻辑缜密、结构清晰）：
/// - **预渲染**：一笔提交后把所有已完成笔画录制为一张 [ui.Picture]，
///   重绘时 `canvas.drawPicture` 替代逐 path 绘制 → 重绘与笔画数无关。
/// - **指纹判定**：命中判定用"引用 + geometryRevision + 尺寸 + 参数"
///   组合指纹（O(n) 轻量扫描），**不重算几何**；点列替换/对象替换后
///   指纹变化自动重建（与 Expando Path 缓存的 revision 校验一致）。
/// - **可选组件**：不改变现有渲染路径；override（颜色/透明度）场景直接
///   现画不缓存，保证与 [StrokeRenderer.drawStroke] 语义完全一致。
/// - **回滚安全**：调用方随时 [invalidate] 或弃用实例即回退旧路径。
class StrokePictureCache {
  StrokePictureCache({this.maxCacheCount = 4});

  /// 最大缓存条数（LRU 上限，防长期驻留内存膨胀）。
  final int maxCacheCount;

  final List<_PictureEntry> _entries = [];

  /// 用 [strokes]（已完成）录制一张预渲染 Picture 并缓存。
  ///
  /// [size] 为画布尺寸；[usePressure] 与 [isComplete] 透传给
  /// [StrokeRenderer.drawStroke]。命中指纹直接返回缓存，未命中重建。
  /// override 参数（颜色/透明度）非空时不缓存、直接现画（语义等价旧路径）。
  ui.Picture? pictureFor(
    List<Stroke> strokes, {
    required ui.Size size,
    bool usePressure = true,
    ui.Color? colorOverride,
    double? opacityOverride,
  }) {
    if (strokes.isEmpty || size.isEmpty) return null;
    // override 场景不缓存：与 drawStroke 语义保持完全一致。
    if (colorOverride != null || opacityOverride != null) {
      return _renderNow(strokes, size, usePressure, colorOverride, opacityOverride);
    }

    final fingerprint = _Fingerprint(strokes, size, usePressure);
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].fingerprint == fingerprint) {
        // LRU 提升：命中条目移到末尾。
        final hit = _entries.removeAt(i);
        _entries.add(hit);
        return hit.picture;
      }
    }

    final picture = _renderNow(strokes, size, usePressure, null, null);
    if (picture != null) {
      _entries.add(_PictureEntry(fingerprint, picture));
      if (_entries.length > maxCacheCount) {
        _entries.removeAt(0); // 淘汰最久未用
      }
    }
    return picture;
  }

  /// 清空缓存（回滚/失效率）。
  void invalidate() {
    for (final e in _entries) {
      e.picture.dispose();
    }
    _entries.clear();
  }

  /// 当前缓存条目数（测试/审计）。
  int get cacheCount => _entries.length;

  /// 当前指纹集合（测试辅助）。
  @visibleForTesting
  List<String> get fingerprints => _entries
      .map((e) => e.fingerprint.toString())
      .toList(growable: false);

  ui.Picture? _renderNow(
    List<Stroke> strokes,
    ui.Size size,
    bool usePressure,
    ui.Color? colorOverride,
    double? opacityOverride,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final stroke in strokes) {
      StrokeRenderer.drawStroke(
        canvas,
        stroke,
        colorOverride: colorOverride,
        opacityOverride: opacityOverride,
        usePressure: usePressure,
        isComplete: true,
      );
    }
    return recorder.endRecording();
  }
}

/// 缓存指纹：笔画集合的引用 + 各笔画几何版本 + 画布尺寸 + 压感开关。
///
/// 值语义（==）比较：任一笔画被替换（identity 变化）或点列变化
/// （geometryRevision 变化）或尺寸/压感变化 → 指纹不等 → 重建。
class _Fingerprint {
  _Fingerprint(List<Stroke> strokes, ui.Size size, bool usePressure)
      : _ids = List.unmodifiable(strokes.map(identityHashCode)),
        _revisions = List.unmodifiable(strokes.map((s) => s.geometryRevision)),
        _width = size.width,
        _height = size.height,
        _usePressure = usePressure;

  final List<int> _ids;
  final List<int> _revisions;
  final double _width;
  final double _height;
  final bool _usePressure;

  @override
  bool operator ==(Object other) {
    if (other is! _Fingerprint) return false;
    if (_width != other._width ||
        _height != other._height ||
        _usePressure != other._usePressure ||
        _ids.length != other._ids.length) {
      return false;
    }
    for (var i = 0; i < _ids.length; i++) {
      if (_ids[i] != other._ids[i] || _revisions[i] != other._revisions[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    Object.hashAll(_ids),
    Object.hashAll(_revisions),
    _width,
    _height,
    _usePressure,
  ]);

  @override
  String toString() =>
      'StrokePictureCache#${_ids.length} rev=$_revisions '
      '(${_width.toInt()}x${_height.toInt()}, pressure=$_usePressure)';
}

/// 缓存条目：指纹 + 预渲染 Picture。
class _PictureEntry {
  _PictureEntry(this.fingerprint, this.picture);

  final _Fingerprint fingerprint;
  final ui.Picture picture;
}
