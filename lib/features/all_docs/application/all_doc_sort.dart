// M11 All Docs 排序：排序模式 + 展平排序纯函数。
// 纯 Dart，无 flutter/io 依赖，可单测锁定。
//
// 默认模式（timeGrouped）保留 AFFiNE 式「今天/本周/更早/从未更新」分组；
// 其余模式渲染为扁平列表（分组头无意义）。

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';

/// 排序模式。
enum AllDocSort {
  /// 默认：按更新时间分组（今天/本周/更早/从未更新），组内按更新时间倒序。
  timeGrouped,

  /// 按更新时间倒序（扁平）。
  updatedAtDesc,

  /// 按创建时间倒序（扁平）。
  createdAtDesc,

  /// 按标题升序（不区分大小写，扁平）。
  titleAsc,
}

/// 把分组结果展平并按 [sort] 排序。
/// [sort] 为 timeGrouped 时返回 null（调用方保持分组渲染）。
List<AllDoc>? flattenSorted(List<AllDocSection> sections, AllDocSort sort) {
  switch (sort) {
    case AllDocSort.timeGrouped:
      return null;
    case AllDocSort.updatedAtDesc:
      final docs = sections.expand((s) => s.docs).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return docs;
    case AllDocSort.createdAtDesc:
      final docs = sections.expand((s) => s.docs).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return docs;
    case AllDocSort.titleAsc:
      final docs = sections.expand((s) => s.docs).toList()
        ..sort((a, b) {
          final ta = a.title.toLowerCase();
          final tb = b.title.toLowerCase();
          return ta.compareTo(tb);
        });
      return docs;
  }
}
