// M11 产品清晰化：All Docs 搜索过滤纯函数。
// 纯 Dart，无 flutter/io 依赖，可单测锁定。

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';

/// 按关键词过滤文档区段（大小写不敏感的包含匹配）。
///
/// 规则（确定性）：
/// - [query] 去除首尾空白后为空 → 原样返回 [sections]；
/// - 命中文档：title 或 description 任一包含关键词（toLowerCase 比较）；
/// - 过滤后某区段无文档 → 该区段被剔除；
/// - 不改变区段顺序与组内文档顺序。
List<AllDocSection> filterSections(
  List<AllDocSection> sections,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sections;
  final out = <AllDocSection>[];
  for (final section in sections) {
    final hits = section.docs
        .where((d) =>
            d.title.toLowerCase().contains(q) ||
            d.description.toLowerCase().contains(q))
        .toList(growable: false);
    if (hits.isNotEmpty) {
      out.add(
        AllDocSection(
          group: section.group,
          label: section.label,
          docs: hits,
        ),
      );
    }
  }
  return out;
}
