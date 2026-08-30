import 'dart:ui';

/// 图表类型。
enum ChartType { bar, line }

/// 分页画布上的图表元素。
///
/// 图表是可定位、可缩放的绘图画布元素；笔记页面可持有它，但模型本身不依赖
/// notes 聚合根，从而允许绘图展示组件直接消费该类型。
class PageChartItem {
  PageChartItem({
    required this.id,
    required this.chartType,
    required this.data,
    this.labels = const [],
    this.x = 100,
    this.y = 100,
    this.width = 320,
    this.height = 200,
    this.color = 0xFF3A6EA5,
    this.zOrder = 0,
  });

  final String id;
  ChartType chartType;
  List<double> data;
  List<String> labels;
  double x;
  double y;
  double width;
  double height;
  int color;
  int zOrder;

  Offset get position => Offset(x, y);

  Map<String, dynamic> toJson() => {
    'id': id,
    'chartType': chartType.name,
    'data': data,
    'labels': labels,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'color': color,
    'zOrder': zOrder,
  };

  factory PageChartItem.fromJson(Map<String, dynamic> json) => PageChartItem(
    id: json['id'] as String,
    chartType: ChartType.values.firstWhere(
      (chartType) => chartType.name == json['chartType'],
      orElse: () => ChartType.bar,
    ),
    data: (json['data'] as List? ?? const [])
        .map((value) => (value as num).toDouble())
        .toList(),
    labels: (json['labels'] as List? ?? const [])
        .map((value) => value as String)
        .toList(),
    x: (json['x'] as num?)?.toDouble() ?? 100,
    y: (json['y'] as num?)?.toDouble() ?? 100,
    width: (json['width'] as num?)?.toDouble() ?? 320,
    height: (json['height'] as num?)?.toDouble() ?? 200,
    color: (json['color'] as num?)?.toInt() ?? 0xFF3A6EA5,
    zOrder: (json['zOrder'] as num?)?.toInt() ?? 0,
  );
}
