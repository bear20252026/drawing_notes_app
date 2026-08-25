// layers_notifier.dart — 图层状态 ChangeNotifier（P2 #22 Phase 3 拆分）。
//
// 从 DrawingController 提取的图层管理：
// - 图层透明度、当前图层索引、笔画可见性、图层排序
// - 通知图层面板等低频 UI

import 'package:flutter/material.dart';

/// 图层状态 ChangeNotifier。
///
/// 图层操作完成后通知（添加/删除/排序/透明度变更）。
class LayersNotifier extends ChangeNotifier {
  /// 当前活跃图层索引。
  int _currentLayerIndex = 0;
  int get currentLayerIndex => _currentLayerIndex;
  set currentLayerIndex(int value) {
    if (_currentLayerIndex == value) return;
    _currentLayerIndex = value;
    notifyListeners();
  }

  /// 图层全局不透明度 (0.0–1.0)。
  double _layerOpacity = 1.0;
  double get layerOpacity => _layerOpacity;
  set layerOpacity(double value) {
    if (_layerOpacity == value) return;
    _layerOpacity = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 笔画可见性映射（key: 笔画 ID）。
  final Map<String, bool> _strokeVisibility = {};

  /// 获取笔画可见性。
  bool isStrokeVisible(String strokeId) {
    return _strokeVisibility[strokeId] ?? true;
  }

  /// 设置笔画可见性。
  void setStrokeVisibility(String strokeId, bool visible) {
    if (_strokeVisibility[strokeId] == visible) return;
    _strokeVisibility[strokeId] = visible;
    notifyListeners();
  }

  /// 图层已添加。
  void onLayerAdded() {
    notifyListeners();
  }

  /// 图层已删除。
  void onLayerRemoved() {
    if (_currentLayerIndex > 0) {
      _currentLayerIndex--;
    }
    notifyListeners();
  }

  /// 图层已重排。
  void onLayersReordered() {
    notifyListeners();
  }
}
