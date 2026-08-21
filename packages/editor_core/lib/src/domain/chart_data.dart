// editor_core——ChartData 图表（Excalidraw charts/ 借鉴——2026-08-21）。
//
// Excalidraw charts/ 本地化——柱状图/折线图/饼图数据模型。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - charts/ 目录——数据可视化图表（柱状图/折线图/饼图）
// - ChartData 数据点 + 标签 + 类型
// - 渲染由 CanvasPainterV2 负责（数据与渲染分离——积木式）
library;

/// 图表类型（Excalidraw charts/ 借鉴）。
enum ChartType {
  /// 柱状图（竖柱）。
  bar,

  /// 折线图。
  line,

  /// 饼图。
  pie,
}

/// 图表数据点（不可变——Excalidraw ChartData 本地化）。
class ChartDataPoint {
  const ChartDataPoint({
    required this.label,
    required this.value,
    this.color = '#000000',
  });

  final String label;
  final double value;
  final String color;

  ChartDataPoint copyWith({String? label, double? value, String? color}) {
    return ChartDataPoint(
      label: label ?? this.label,
      value: value ?? this.value,
      color: color ?? this.color,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartDataPoint && label == other.label && value == other.value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// 图表数据集（不可变——Excalidraw ChartDataset 本地化）。
class ChartDataset {
  const ChartDataset({
    required this.name,
    required this.points,
    this.color = '#0000FF',
  });

  final String name;
  final List<ChartDataPoint> points;
  final String color;

  /// 数据集总值（饼图百分比计算用）。
  double get total => points.fold(0.0, (sum, p) => sum + p.value);

  /// 最大值（柱状图/折线图 Y 轴缩放用）。
  double get maxValue =>
      points.isEmpty ? 0 : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

  /// 最小值。
  double get minValue =>
      points.isEmpty ? 0 : points.map((p) => p.value).reduce((a, b) => a < b ? a : b);

  /// 平均值。
  double get average => points.isEmpty ? 0 : total / points.length;

  ChartDataset copyWith({String? name, List<ChartDataPoint>? points, String? color}) {
    return ChartDataset(
      name: name ?? this.name,
      points: points ?? this.points,
      color: color ?? this.color,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartDataset && name == other.name && points.length == other.points.length;

  @override
  int get hashCode => Object.hash(name, points.length);
}

/// 图表数据（Excalidraw charts/ 本地化——不可变）。
///
/// 包含图表类型 + 数据集 + 配置——数据与渲染分离（积木式）。
/// 渲染由 CanvasPainterV2 负责——此模型只存数据。
class ChartData {
  const ChartData({
    required this.id,
    required this.type,
    required this.datasets,
    this.title = '',
    this.xLabel = '',
    this.yLabel = '',
    this.showLegend = true,
    this.showValues = false,
    this.x = 0,
    this.y = 0,
    this.width = 400,
    this.height = 300,
  });

  final String id;
  final ChartType type;
  final List<ChartDataset> datasets;
  final String title;
  final String xLabel;
  final String yLabel;
  final bool showLegend;
  final bool showValues;
  final double x;
  final double y;
  final double width;
  final double height;

  /// 是否为空（无数据集）。
  bool get isEmpty => datasets.isEmpty || datasets.every((d) => d.points.isEmpty);

  /// 所有数据点数量。
  int get pointCount => datasets.fold(0, (sum, d) => sum + d.points.length);

  /// 全局最大值（所有数据集）。
  double get globalMax =>
      datasets.isEmpty ? 0 : datasets.map((d) => d.maxValue).reduce((a, b) => a > b ? a : b);

  /// 饼图百分比（指定数据集——仅 pie 类型）。
  List<double> piePercentages(int datasetIndex) {
    if (type != ChartType.pie || datasetIndex >= datasets.length) return [];
    final dataset = datasets[datasetIndex];
    if (dataset.total == 0) return [];
    return dataset.points.map((p) => p.value / dataset.total * 100).toList();
  }

  ChartData copyWith({
    ChartType? type,
    List<ChartDataset>? datasets,
    String? title,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return ChartData(
      id: id,
      type: type ?? this.type,
      datasets: datasets ?? this.datasets,
      title: title ?? this.title,
      xLabel: xLabel,
      yLabel: yLabel,
      showLegend: showLegend,
      showValues: showValues,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartData && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);
}
