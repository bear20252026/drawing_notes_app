// editor_core——不可变文档状态（专家 I-006——2026-08-16——批次 A）。
//
// 按专家目标架构（ADR-001）：Document 的唯一可信来源——不可变数据
// 模型（copyWith——禁止 UI 直接修改字段）。纯 Dart——禁 Flutter/dart:io。
// 最小引导：DocumentV2 骨架（页码/图层/修改版本）——后续批次 C 迁移
// AddStroke/CreateShape/CreateText/MoveItem 命令。

/// V2 不可变文档（最小引导——I-006 immutable_document_state_exists）。
///
/// 不可变约定：所有字段 final；修改通过 [copyWith]（返回新实例——
/// 原实例不变——历史/撤销基于不可变快照）。
class DocumentV2 {
  const DocumentV2({
    required this.id,
    required this.pageCount,
    this.revision = 0,
  });

  final String id;
  final int pageCount;

  /// 修改版本号（每次变更递增——审计/同步版本策略）。
  final int revision;

  /// 不可变拷贝：仅更新指定字段——原实例不变。
  DocumentV2 copyWith({int? pageCount, int? revision}) => DocumentV2(
    id: id,
    pageCount: pageCount ?? this.pageCount,
    revision: revision ?? this.revision,
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
