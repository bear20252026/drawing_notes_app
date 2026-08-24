// ColorMagnifier —— 放大镜取色器模型（P2 #30）。
//
// 长按画布取色时，显示放大环跟随手指/笔尖，实时采样像素颜色。
// 模型与 UI 分离——纯数据 + 计算——可独立单测。
library;

import 'package:flutter/material.dart';

/// 放大镜取色器状态。
///
/// 包含：是否激活、指针位置、采样颜色、放大倍率。
class ColorMagnifierState {
  const ColorMagnifierState({
    this.isActive = false,
    this.position = Offset.zero,
    this.color,
    this.zoomLevel = 4.0,
  });

  /// 是否正在取色（长按中）。
  final bool isActive;

  /// 指针在画布上的位置（屏幕坐标）。
  final Offset position;

  /// 当前采样到的颜色（null 表示尚未采样）。
  final Color? color;

  /// 放大倍率（默认 4×）。
  final double zoomLevel;

  ColorMagnifierState copyWith({
    bool? isActive,
    Offset? position,
    Color? color,
    double? zoomLevel,
    bool clearColor = false,
  }) {
    return ColorMagnifierState(
      isActive: isActive ?? this.isActive,
      position: position ?? this.position,
      color: clearColor ? null : (color ?? this.color),
      zoomLevel: zoomLevel ?? this.zoomLevel,
    );
  }

  /// 格式化颜色为十六进制字符串（用于 UI 显示）。
  String get colorHex {
    if (color == null) return '#------';
    final r = color!.red.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = color!.green.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = color!.blue.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#$r$g$b';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorMagnifierState &&
          isActive == other.isActive &&
          position == other.position &&
          color == other.color &&
          zoomLevel == other.zoomLevel;

  @override
  int get hashCode => Object.hash(isActive, position, color, zoomLevel);
}
