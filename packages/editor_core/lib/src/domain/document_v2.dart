// editor_core——不可变文档状态（专家 I-006——2026-08-16——批次 A）。
//
// 按专家目标架构（ADR-001）：Document 的唯一可信来源——不可变数据
// 模型（copyWith——禁止 UI 直接修改字段）。纯 Dart——禁 Flutter/dart:io。
// 最小引导：DocumentV2 骨架（页码/图层/修改版本）——后续批次 C 迁移
// AddStroke/CreateShape/CreateText/MoveItem 命令。

import 'line_item.dart';

/// V2 不可变文档（最小引导——I-006 immutable_document_state_exists）。
///
/// 不可变约定：所有字段 final；修改通过 [copyWith]（返回新实例——
/// 原实例不变——历史/撤销基于不可变快照）。
class DocumentV2 {
  const DocumentV2({
    required this.id,
    required this.pageCount,
    this.revision = 0,
    this.layers = const [],
  });

  final String id;
  final int pageCount;

  /// 修改版本号（每次变更递增——审计/同步版本策略）。
  final int revision;

  /// 文档包含的图层列表（不可变）。
  final List<LayerV2> layers;

  /// 不可变拷贝：仅更新指定字段——原实例不变。
  DocumentV2 copyWith({
    int? pageCount,
    int? revision,
    List<LayerV2>? layers,
  }) => DocumentV2(
    id: id,
    pageCount: pageCount ?? this.pageCount,
    revision: revision ?? this.revision,
    layers: layers ?? this.layers,
  );

  /// 序列化为 JSON 映射（持久化存储）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'pageCount': pageCount,
        'revision': revision,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  /// 从 JSON 映射反序列化。
  static DocumentV2 fromJson(Map<String, dynamic> json) => DocumentV2(
        id: json['id'] as String,
        pageCount: json['pageCount'] as int,
        revision: (json['revision'] as int?) ?? 0,
        layers: (json['layers'] as List<dynamic>)
            .map((e) => LayerV2.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is DocumentV2 &&
      other.id == id &&
      other.pageCount == pageCount &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(id, pageCount, revision);
}
