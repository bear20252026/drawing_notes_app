import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';

/// 分页笔记的只读导出快照。
///
/// 该对象位于 drawing 应用层，作为 [EditorExporter] 的唯一笔记输入。编辑页
/// 在组合边界将可变的笔记页面投影到此快照；导出器随后只依赖绘图领域的文字
/// 类型和可序列化 JSON 负载，避免反向依赖 notes 的完整聚合根。
class PagedExportSnapshot {
  PagedExportSnapshot({
    required this.title,
    required Iterable<PageTextItem> textItems,
    required Iterable<Map<String, dynamic>> imageItems,
    required Iterable<Map<String, dynamic>> shapes,
  }) : textItems = List.unmodifiable(
         textItems.map(
           (item) =>
               PageTextItem.fromJson(Map<String, dynamic>.from(item.toJson())),
         ),
       ),
       imageItems = List.unmodifiable(
         imageItems.map(
           (item) => Map<String, dynamic>.unmodifiable(
             Map<String, dynamic>.from(item),
           ),
         ),
       ),
       shapes = List.unmodifiable(
         shapes.map(
           (item) => Map<String, dynamic>.unmodifiable(
             Map<String, dynamic>.from(item),
           ),
         ),
       );

  final String title;

  /// 复制后的绘图领域文字项，供 PDF、SVG、RTF 与文本导出读取。
  final List<PageTextItem> textItems;

  /// 笔记侧图片的 JSON 投影，仅用于导出工程 JSON。
  final List<Map<String, dynamic>> imageItems;

  /// 绘图形状的 JSON 投影，仅用于导出工程 JSON。
  final List<Map<String, dynamic>> shapes;
}
