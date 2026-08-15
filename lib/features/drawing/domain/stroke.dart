import 'dart:math';
import 'dart:ui';

/// 笔画类型（笔刷类型）
///
/// marker 为半透明高亮笔；
/// laser 仅表示运行时的临时激光指示器，绝不写入工程文件；
/// eraser 表示橡皮擦笔画，渲染时以“透明擦除”方式生效。
enum BrushType {
  pen, // 钢笔：压感纯色线条
  pencil, // 铅笔：低透明度石墨笔触
  marker, // 高亮笔：不叠色局部合成
  laser, // 激光指示器：瞬时尾迹，不持久化
  eraser, // 橡皮擦：透明擦除
}

/// 笔画上的一个采样点。
///
/// 记录画布坐标系下的坐标与笔压（0.0~1.0）。
/// 笔压用于 Phase 2 的压感粗细控制；鼠标/普通手指无压感时压力恒为 1.0。
class StrokePoint {
  const StrokePoint(this.x, this.y, this.pressure);

  final double x;
  final double y;
  final double pressure;

  Offset get offset => Offset(x, y);

  // ---- 序列化（供本地文件存储使用，见 storage/document_codec.dart）----

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'p': pressure};

  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
    (json['p'] as num?)?.toDouble() ?? 1.0,
  );
}

/// 一条完整的笔画：由连续的采样点 + 笔刷参数组成。
///
/// 设计说明：笔画以"矢量点列"方式存储（而非直接写死在位图上），
/// 这样撤销/重做、图层合并、任意分辨率导出都能无损进行，
/// 也是后续云同步（更换存储层）的基础。
class Stroke {
  Stroke({
    required this.points,
    required this.color,
    required this.width,
    required this.type,
    this.opacity = 1.0,
    int? seed,
    this.version = 0,
    this.versionNonce = 0,
  }) : seed = seed ?? _newSeed();

  /// 随机种子：手绘风格/抖动生成的稳定随机源（对齐 Excalidraw 元素模型），
  /// 同一元素重复渲染时使用同一 seed 保证质感一致。
  int seed;

  /// 元素版本号：每次内容变更单调递增，供协作/增量同步的冲突检测。
  int version;

  /// 每次编辑递增的快速变化指示器；比 [version] 更细粒度。
  int versionNonce;

  static int _newSeed() => Random.secure().nextInt(0x7FFFFFFF);

  /// 几何版本号：点列被替换时递增，用于使渲染 Path 缓存失效。
  /// 移动/缩放/旋转会重建新 Stroke 对象（新 identity），无需手动递增。
  int _geometryRevision = 0;

  /// 当前点列版本（配合 StrokeRenderer 的 Path 惰性缓存使用）。
  int get geometryRevision => _geometryRevision;

  /// 收笔时以最终优化点列替换实时预览点列。
  ///
  /// 替换会使 StrokeRenderer 持有的几何缓存失效，下次绘制重新生成轮廓。
  void replacePoints(List<StrokePoint> newPoints) {
    _geometryRevision++;
    version++;
    versionNonce++;
    points
      ..clear()
      ..addAll(newPoints);
  }

  final List<StrokePoint> points;
  final Color color;

  /// 基础线宽（画布逻辑像素），实际渲染宽度 = base * 压感系数。
  final double width;
  final BrushType type;

  /// 笔画自身不透明度（0~1），默认 1.0。
  final double opacity;

  // ---- 序列化 ----

  /// 点列压缩编码（落地 Saber SBN v13 的二进制点列压缩思想，独立实现）：
  /// 把 `[{x,y,p}, ...]` 对象数组压扁为 `[x0,y0,p0, x1,y1,p1, ...]`
  /// 数值数组，消除每个点的键名开销（约省一半体积）；读取端双向兼容
  /// 旧对象数组格式。
  static List<num> _encodePoints(List<StrokePoint> points) => [
    for (final p in points) ...[p.x, p.y, p.pressure],
  ];

  static List<StrokePoint> _decodePoints(Object? raw) {
    final list = raw as List? ?? const [];
    if (list.isEmpty) return const [];
    // 旧格式：元素为 Map（对象数组）；新格式：元素为 num（扁平数组）。
    final first = list.first;
    if (first is Map) {
      return [
        for (final e in list)
          StrokePoint.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    }
    final flat = list.cast<num>();
    return [
      for (var i = 0; i + 2 < flat.length || i < flat.length; i += 3)
        if (i + 2 < flat.length)
          StrokePoint(
            flat[i].toDouble(),
            flat[i + 1].toDouble(),
            flat[i + 2].toDouble(),
          )
        else
          StrokePoint(flat[i].toDouble(), 0, 1),
    ];
  }

  Map<String, dynamic> toJson() => {
    'points': _encodePoints(points),
    'color': color.toARGB32(),
    'width': width,
    'type': type.name,
    'opacity': opacity,
    'seed': seed,
    'version': version,
    'versionNonce': versionNonce,
  };

  factory Stroke.fromJson(Map<String, dynamic> json) => Stroke(
    points: _decodePoints(json['points']),
    color: Color((json['color'] as num).toInt()),
    width: (json['width'] as num).toDouble(),
    type: BrushType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => BrushType.pen,
    ),
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    seed: (json['seed'] as num?)?.toInt(),
    version: (json['version'] as num?)?.toInt() ?? 0,
    versionNonce: (json['versionNonce'] as num?)?.toInt() ?? 0,
  );
}
