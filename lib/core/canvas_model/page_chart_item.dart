import 'dart:ui';

import 'package:drawing_notes_app/core/utils/wire_enum.dart';

/// 图表类型。
enum ChartType implements WireEnum {
  bar,
  line;

  @override
  String get wireName => switch (this) {
    ChartType.bar => 'bar',
    ChartType.line => 'line',
  };
}

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

  /// 以同一对象标识的快照覆盖全部可变字段（[copy] 的逆，H-2 第二轮审计）。
  void restoreFrom(PageChartItem snapshot) {
    assert(snapshot.id == id, '只能恢复同一图表对象的状态');
    chartType = snapshot.chartType;
    data = List.of(snapshot.data);
    labels = List.of(snapshot.labels);
    x = snapshot.x;
    y = snapshot.y;
    width = snapshot.width;
    height = snapshot.height;
    color = snapshot.color;
    zOrder = snapshot.zOrder;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chartType': chartType.wireName,
    'data': data,
    'labels': labels,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'color': color,
    'zOrder': zOrder,
  };

  /// 为命令历史创建独立快照（与 PageShapeItem.copy 同纪律）：
  /// data/labels 是可变列表，必须复制列表本身。
  PageChartItem copy() => PageChartItem(
    id: id,
    chartType: chartType,
    data: List.of(data),
    labels: List.of(labels),
    x: x,
    y: y,
    width: width,
    height: height,
    color: color,
    zOrder: zOrder,
  );

  factory PageChartItem.fromJson(Map<String, dynamic> json) => PageChartItem(
    id: json['id'] as String,
    // 回落口径与改造前逐字相同：未知/缺失 → bar。
    chartType:
        wireEnumOf(ChartType.values, json['chartType'] as String?) ?? ChartType.bar,
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
