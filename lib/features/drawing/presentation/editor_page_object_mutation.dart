import 'package:drawing_notes_app/features/drawing/domain/page_chart_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_connector.dart';
import 'package:drawing_notes_app/features/drawing/domain/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/text_item.dart';

/// 混合画布对象的无状态突变协作者。
///
/// 只负责对调用方提供的对象集合执行确定性的分组标记和删除操作；不读取
/// Widget、控制器或 BuildContext，也不负责选择解析、动画、通知、撤销/重做
/// 和持久化。页面组合根仍负责这些时序与生命周期。
class EditorPageObjectMutation {
  const EditorPageObjectMutation._();

  /// 为选中的文字、图片和形状统一设置分组标识。
  ///
  /// 返回实际变更的对象数量，便于页面层生成既有提示文本而无需重复遍历。
  static int setGroupId({
    required Set<String> ids,
    required String? groupId,
    required Iterable<PageTextItem> textItems,
    required Iterable<PageImageItem> imageItems,
    required Iterable<PageShapeItem> shapes,
  }) {
    var changed = 0;
    for (final item in textItems) {
      if (ids.contains(item.id)) {
        item.groupId = groupId;
        changed++;
      }
    }
    for (final item in imageItems) {
      if (ids.contains(item.id)) {
        item.groupId = groupId;
        changed++;
      }
    }
    for (final item in shapes) {
      if (ids.contains(item.id)) {
        item.groupId = groupId;
        changed++;
      }
    }
    return changed;
  }

  /// 从混合对象集合中删除指定 id，返回实际删除的对象数量。
  ///
  /// 图表没有 groupId，但属于页面可删除对象，因此和其他三类对象一起处理。
  static int remove({
    required Set<String> ids,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
  }) {
    var removed = 0;
    removed += _removeWhere(textItems, ids, (item) => item.id);
    removed += _removeWhere(imageItems, ids, (item) => item.id);
    removed += _removeWhere(shapes, ids, (item) => item.id);
    removed += _removeWhere(charts, ids, (item) => item.id);
    return removed;
  }

  static int _removeWhere<T>(
    List<T> items,
    Set<String> ids,
    String Function(T item) idOf,
  ) {
    final before = items.length;
    items.removeWhere((item) => ids.contains(idOf(item)));
    return before - items.length;
  }
}

/// 连线端点合法性与 PageConnector 构造的无状态协作者。
class EditorLinkMutation {
  const EditorLinkMutation._();

  /// 为两个不同的画布对象创建连接；相同端点不产生连接。
  static PageConnector? createConnector({
    required String? sourceId,
    required String targetId,
    required String connectorId,
  }) {
    if (sourceId == null || sourceId.isEmpty || sourceId == targetId) {
      return null;
    }
    if (targetId.isEmpty || connectorId.isEmpty) return null;

    return PageConnector(
      id: connectorId,
      fromItemId: sourceId,
      toItemId: targetId,
    );
  }
}

/// 就地文字提交的确定性无状态协作者；UI 状态和持久化通知仍由页面组合根负责。
class EditorTextMutation {
  const EditorTextMutation._();

  /// 创建进入就地编辑的临时文字块；提交前不加入任何页面集合。
  static PageTextItem createDraft({
    required String id,
    required double x,
    required double y,
  }) {
    return PageTextItem(id: id, x: x, y: y, text: '');
  }

  /// 提交文字内容并确保同一文字块不会被重复加入目标集合。
  ///
  /// 返回 false 表示输入为空，调用方应保持原有“丢弃临时项”语义。
  static bool commit({
    required PageTextItem pending,
    required String rawText,
    required List<PageTextItem> items,
  }) {
    final text = rawText.trim();
    if (text.isEmpty) return false;

    pending.text = text;
    if (!items.any((item) => item.id == pending.id)) {
      items.add(pending);
    }
    return true;
  }
}

/// 文字样式变更的无状态协作者；对话框、通知和持久化时序仍由页面层负责。
class EditorTextStyleMutation {
  const EditorTextStyleMutation._();

  static double clampFontSize(double size) => size.clamp(8, 200).toDouble();

  static void setFontSize({required PageTextItem item, required double size}) {
    item.fontSize = clampFontSize(size);
  }

  static void setColor({required PageTextItem item, required int color}) {
    item.color = color;
  }

  static int recolorAll({
    required Iterable<PageTextItem> items,
    required int color,
  }) {
    var changed = 0;
    for (final item in items) {
      item.color = color;
      changed++;
    }
    return changed;
  }
}

/// 图片元素构造的无状态协作者；存储复制仍由页面组合根负责.
class EditorImageMutation {
  const EditorImageMutation._();

  static ({double x, double y}) pageImagePosition({
    required double centerX,
    required double centerY,
  }) {
    return (x: centerX, y: centerY);
  }

  static ({double x, double y}) documentImagePosition({
    required double centerX,
    required double centerY,
  }) {
    return (x: centerX - 100, y: centerY - 75);
  }

  static PageImageItem createPageImage({
    required String id,
    required double x,
    required double y,
    required String filePath,
  }) {
    return PageImageItem(id: id, x: x, y: y, filePath: filePath);
  }

  static DocumentImageItem createDocumentImage({
    required String id,
    required double x,
    required double y,
    required String filePath,
  }) {
    return DocumentImageItem(id: id, x: x, y: y, filePath: filePath);
  }
}

/// 混合对象超链接读写的无状态协作者。
class EditorHyperlinkMutation {
  const EditorHyperlinkMutation._();

  static String? hrefOf({
    required String id,
    required Iterable<PageTextItem> textItems,
    required Iterable<PageImageItem> imageItems,
    required Iterable<PageShapeItem> shapes,
  }) {
    for (final item in textItems) {
      if (item.id == id) return item.href;
    }
    for (final item in imageItems) {
      if (item.id == id) return item.href;
    }
    for (final item in shapes) {
      if (item.id == id) return item.href;
    }
    return null;
  }

  static bool setHref({
    required String id,
    required String? href,
    required Iterable<PageTextItem> textItems,
    required Iterable<PageImageItem> imageItems,
    required Iterable<PageShapeItem> shapes,
  }) {
    for (final item in textItems) {
      if (item.id == id) {
        item.href = href;
        return true;
      }
    }
    for (final item in imageItems) {
      if (item.id == id) {
        item.href = href;
        return true;
      }
    }
    for (final item in shapes) {
      if (item.id == id) {
        item.href = href;
        return true;
      }
    }
    return false;
  }
}
