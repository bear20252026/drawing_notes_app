import 'dart:math' as math;

/// U2 图片降采样（2026-09-02，P1-13）。
///
/// 此前全库解码图片均无 cacheWidth/target 尺寸（审计 P1-13：原图全分辨率
/// 进内存，多图文档滚动时解码与内存峰值大，Android 有 OOM 风险）。本助手
/// 提供「长边上限」降采样策略的目标尺寸计算：调用方在解码阶段直接产出
/// 目标尺寸位图，超限原图不再整幅进内存。
class ImageDecodeCap {
  const ImageDecodeCap._();

  /// 显示类图片（缩略/阅读/演示）默认长边上限：2048px 在常见 DPI 与
  /// 展示尺寸下不可分辨差异，解码内存从动辄 100MB+ 封顶到 ≤16MB。
  static const int defaultMaxLongEdge = 2048;

  /// 画布编辑图片上限：画布可深度缩放，放宽到 4096 保缩放清晰度，
  /// 同时仍把极端照片（8000px+）的解码内存钳到 ≤64MB。
  static const int canvasMaxLongEdge = 4096;

  /// 纯函数：计算长边不超过 [maxLongEdge] 的目标尺寸（只缩不放大）。
  static ({int width, int height}) targetSize(
    int width,
    int height,
    int maxLongEdge,
  ) {
    if (width <= 0 || height <= 0) return (width: width, height: height);
    final longEdge = math.max(width, height);
    if (longEdge <= maxLongEdge) return (width: width, height: height);
    final scale = maxLongEdge / longEdge;
    return (
      width: (width * scale).round().clamp(1, width),
      height: (height * scale).round().clamp(1, height),
    );
  }

  /// 缩略图解码档位（审计四-2，2026-09-06）。
  ///
  /// 按布局宽 × dpr 逐像素算 cacheWidth 时，窗口连续 resize 会在图像
  /// 缓存里留下多档位图；把目标宽取整到 256/512/1024 档（超出取
  /// [defaultMaxLongEdge]，只升不降），相邻宽度共用同一位图。
  static int quantizedCacheWidth(double logicalWidth, double devicePixelRatio) {
    final target = logicalWidth * devicePixelRatio;
    if (!target.isFinite || target <= 0) return defaultMaxLongEdge;
    for (final tier in const [256, 512, 1024]) {
      if (target <= tier) return tier;
    }
    return defaultMaxLongEdge;
  }

  /// 导出/一次性解码档位：取**不小于**所需长边的最小档位，封顶
  /// [canvasMaxLongEdge]。
  ///
  /// 与 [quantizedCacheWidth] 的方向相反是有意的：缓存档位宁可略降一档换「相邻
  /// 尺寸复用同一位图」，导出则要保证完整性——欠一档就是往产物里塞一张比输出
  /// 分辨率还低的图（放大后发糊），那正是我们要修的「静默劣化」的另一半。
  static int exportTierFor(double requiredLongEdge) {
    // 退化尺寸（0 / 非有限）也留一档最低分辨率： dst 面积为零时 Skia 本来
    // 就不落任何像素，但解码尺寸不能算成 0（instantiateCodec 会拒）。
    if (!requiredLongEdge.isFinite || requiredLongEdge <= 0) return 256;
    for (final tier in const [256, 512, 1024, 2048]) {
      if (requiredLongEdge <= tier) return tier;
    }
    return canvasMaxLongEdge;
  }
}
