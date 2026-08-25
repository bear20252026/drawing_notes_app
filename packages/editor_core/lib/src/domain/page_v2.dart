// editor_core——PageV2 分页模型（批次 F-1——2026-08-21）。
//
// 多页画布领域模型——每页独立 DocumentV2 + 独立撤销/重做栈。
// 纯 Dart——禁 Flutter/dart:io（R-02）。
library;

import 'document_v2.dart';

/// 分页模型（多页画布——每页独立 DocumentV2）。
///
/// 遵循专家方案批次 F：
/// - 每页独立 DocumentV2（不可变）
/// - 每页独立撤销/重做栈
/// - 支持新建/插入/删除/重排
class PageV2 {
  const PageV2({
    required this.id,
    required this.document,
    required this.index,
  });

  final String id;
  final DocumentV2 document;
  final int index;

  PageV2 copyWith({
    String? id,
    DocumentV2? document,
    int? index,
  }) {
    return PageV2(
      id: id ?? this.id,
      document: document ?? this.document,
      index: index ?? this.index,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageV2 &&
          id == other.id &&
          document == other.document &&
          index == other.index;

  @override
  int get hashCode => Object.hash(id, document, index);
}
