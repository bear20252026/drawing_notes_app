import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 玻璃材质的弹窗外壳（**材质域**；排布与平台按钮顺序仍归 `AppleDialog`）。
///
/// 依赖方向：本文件在 `shared/`，依赖 `core/`，符合 shared → core 的单向规则；
/// `core/` 反向拿不到玻璃，因此由 [GlassDialog.surface] 作为注入点交回
/// [AppleDialog.confirm]，全库弹窗的排布逻辑因此仍是单一事实来源。
///
/// 与屏幕边缘的间距（inset）由**本外壳**负责——玻璃层必须贴合内容边界，
/// 若让内部 `AlertDialog` 保留默认 `insetPadding`，玻璃会被撑成全屏大板。
///
/// **不算玻璃叠玻璃**：模态弹窗与下方页面之间有 barrier（black54）隔开，
/// 且二者不同时可见于同一层级；总纲红线针对的是内容层内直接叠加。
class GlassDialog {
  GlassDialog._();

  /// 弹窗专用配方——与导航 / 工具条（sigma 12 / 基底 0.62）刻意不同：
  ///
  /// - `blur 16`：Apple HIG regular 变体 20–40 的下沿、clear 变体 10–20 的上沿。
  ///   弹窗面积远大于工具条，模糊不足会让背景细节顶到正文底下；
  /// - `基底 0.72`：regular 区间（0.6–0.8）中位。弹窗正文密集，
  ///   对比度优先于通透，故不取导航条用的 0.62（regular 下限偏通透）；
  /// - 饱和度沿用全库默认 1.4（[LiquidGlassRecipe.kDefaultSaturation]），
  ///   不额外堆叠色偏——弹窗背后是 barrier 变暗后的页面，饱和提升观感有限。
  static const double kSigma = 16;
  static const double kSurfaceOpacity = 0.72;

  /// 与 M3 `AlertDialog` 的默认圆角对齐；玻璃裁剪圆角必须与之相同，
  /// 否则内容四角会被裁掉。
  static const double kRadius = 28;

  /// 与屏幕边缘的留白（M3 `AlertDialog` 默认 horizontal 40 / vertical 24）。
  static const double insetHorizontal = 40;
  static const double insetVertical = 24;

  /// 传给 [AppleDialog.confirm] 的材质外壳。
  static AppleDialogSurface get surface => _buildSurface;

  /// [AppleDialog.confirm] 的玻璃版本（其余签名与语义完全一致）。
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '确定',
    String cancelText = '取消',
    bool dangerous = false,
  }) {
    return AppleDialog.confirm(
      context,
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: cancelText,
      dangerous: dangerous,
      surface: surface,
    );
  }

  static Widget _buildSurface({
    required Widget? title,
    required Widget? content,
    required List<Widget> actions,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 保证 AlertDialog 的最小宽度 280 装得下：inset ≤ (可用宽 - 280) / 2。
        final insetH = math.max(
          8.0,
          math.min(insetHorizontal, (constraints.maxWidth - 280) / 2),
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: insetH,
            vertical: insetVertical,
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(kRadius),
            sigma: kSigma,
            surfaceOpacity: kSurfaceOpacity,
            child: AlertDialog(
              // inset 已由外层 Padding 承担，此处必须置零，
              // 否则玻璃层尺寸 = 全屏，中间只留一小块内容。
              insetPadding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              title: title,
              content: content,
              actions: actions,
            ),
          ),
        );
      },
    );
  }
}
