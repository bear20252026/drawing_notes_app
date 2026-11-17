import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_interaction_controllers.dart';

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

  static PageTextItem? findById({
    required Iterable<PageTextItem> items,
    required String id,
  }) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 返回双击坐标命中的第一个文字块 ID；命中框沿用编辑器现有字号规则。
  static String? hitTextId({
    required Iterable<PageTextItem> items,
    required double x,
    required double y,
  }) {
    for (final item in items) {
      final width = item.fontSize * 2;
      if (x >= item.x &&
          x <= item.x + width &&
          y >= item.y &&
          y <= item.y + item.fontSize) {
        return item.id;
      }
    }
    return null;
  }

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

/// 混排对象删除的「成对登记」组合根（EUI-02，第四轮审计 2026-10-15）。
///
/// 审计说的是「删除没有确认」，追下去缺的是**撤销**：`_deleteSelectedItem`
/// 原先不 push 任何命令，而浮动选择条那条腿
/// （`selection_bar.dart:165` → `controller.deleteSelectedDocumentObjects`）
/// 会 push `DocumentObjectsSnapshotCommand`——同一个用户意图两套实现，只有
/// 一套撤得回。删完紧接着 `_notifyChanged()` 排自动保存 ⇒ 误删既撤不回又立刻
/// 落盘。
///
/// **处置选择（写下来免得下一轮再判一遍）**：不加模态确认。画布里删除是高频
/// 动作，正确的形状是「删得掉也撤得回」；每次按 Delete 弹一次窗是把撤销栈
/// healthy 的主链路训练成对话框依赖。
///
/// 为什么不复用 [DocumentObjectsSnapshotCommand]：那份快照只覆盖
/// `layers/shapes/images`，而这里删的是文字/图片/形状/图表四类，且分页宿主
/// 持有的是 `NotebookPage` 自己的四份列表引用。用那份撤销会把文字和图表留在
/// 删除后的状态——正是本条缺陷的形状。
///
/// 为什么是这个形状、落在这个文件：[EditorPageObjectMutation] 这个类的契约写明
/// 「不负责撤销/重做和持久化」，所以另立一个类；但**不再新开文件**——
/// `lib/features/drawing/presentation/` 受 `sloc-guard` 的 `max_files = 40`
/// 目录门禁（`.sloc-guard.toml` 里 P3-8 那条注释就是这条临界），第 41 个文件
/// 当场 FAILED。也不落在 `editor_page_editing.dart`：那条 part 所在库受行数棘轮
/// 约束（`test/editor_page_line_ratchet_test.dart`，当前 7127/7127，余量 0）。
class MixedObjectDeleteRecorder {
  const MixedObjectDeleteRecorder._();

  /// 删除命中的混排对象，并登记一条可撤销记录；返回实际删除数量。
  ///
  /// V-01 口径：独立画布模式没有其余三类集合，调用方必须给**可增长**空表——
  /// `const []` 会让 `removeWhere` 抛 `UnsupportedError`（删除路径对四类集合
  /// 一律调用它）。
  ///
  /// 一个也没删到时**不产生历史条目**，与 `pushTransaction` 的空集合口径一致：
  /// 否则用户按一次 Ctrl+Z 会白吃掉一步真操作。
  static int deleteAndRecord({
    required Set<String> ids,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
    required DrawingController host,
    required void Function() markDirty,
  }) {
    final before = MixedObjectCollections(
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );
    final removed = EditorPageObjectMutation.remove(
      ids: ids,
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );
    if (removed == 0) return removed;
    host.pushCommand(
      MixedObjectsSnapshotCommand(
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
        charts: charts,
        before: before,
        after: MixedObjectCollections(
          textItems: textItems,
          imageItems: imageItems,
          shapes: shapes,
          charts: charts,
        ),
        onRestored: () {
          // 与 `restoreDocumentObjectsSnapshot` 同口径：字节回来了还得失效
          // 渲染缓存、补一帧，并把这次撤销登记成待落盘改动——否则盘上留着的
          // 仍是「删掉之后」的那一版。
          host.invalidateLayer(host.currentLayer.id);
          host.tickFrame();
          markDirty();
        },
      ),
    );
    return removed;
  }
}

/// 混排对象**拖拽事务**的成对登记组合根（拖拽撤销专项 2026-11-17）。
///
/// 整域缺口：笔记模式的移动/旋转/缩放/文字宽度柄直改对象字段，结束只
/// `_notifyChanged`（排自动保存）不 push 任何命令——拖完既撤不回又立刻
/// 落盘，与删除（EUI-02 已修）是同一形状。独立画布模式的指针链路早已
/// 走 session 的 begin/end 事务（`endDocumentObjectsTransform` 等），
/// 本类把同一语义补给 overlay 手势链路，**不碰独立模式那条腿**（防双记）。
///
/// 事务形状（与 session 懒快照同构，但起点显式）：
/// - [begin]：手势起点拍一份四类集合**深快照**存进交互态槽；嵌套 begin
///   以首个为准（宽度柄聚焦+指针同会话不覆盖基准）。
/// - [commit]：手势终点再拍一份，与起始**逐字段比对**（toJson 串，与
///   DocumentObjectsSnapshot 同口径）；无变化不产生条目（空拖拽不白吃
///   一步撤销）；有变化 push 一条 [MixedObjectsSnapshotCommand]。
/// - [cancel]：还原起始快照、不入栈（与 session cancel* 同口径）。
///
/// 为什么落本文件不新开：presentation 目录 max_files=40 已满；本文件是
/// 独立库（不计 editor_page 行数棘轮），与 MixedObjectDeleteRecorder 同域。
class MixedObjectDragRecorder {
  const MixedObjectDragRecorder._();

  /// 手势起点：拍起始深快照。已有进行中事务时不覆盖（首个为准）。
  static void begin({
    required EditorCanvasInteractionState interaction,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
  }) {
    interaction.mixedDragBefore ??= MixedObjectCollections(
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );
  }

  /// 手势终点：有变化才登记一条撤销；返回是否产生了历史条目。
  static bool commit({
    required EditorCanvasInteractionState interaction,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
    required DrawingController host,
    required void Function() markDirty,
  }) {
    final before = interaction.mixedDragBefore;
    interaction.mixedDragBefore = null;
    if (before == null) return false;
    final after = MixedObjectCollections(
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
    );
    if (_same(before, after)) return false;
    host.pushCommand(
      MixedObjectsSnapshotCommand(
        textItems: textItems,
        imageItems: imageItems,
        shapes: shapes,
        charts: charts,
        before: before,
        after: after,
        onRestored: () {
          // 与删除记录器同口径：字节回来了还得失效渲染缓存、补一帧，
          // 并把这次撤销登记成待落盘改动。
          host.invalidateLayer(host.currentLayer.id);
          host.tickFrame();
          markDirty();
        },
      ),
    );
    return true;
  }

  /// 手势取消：还原起始快照，不写入历史（与 session cancel* 同口径）。
  static void cancel({
    required EditorCanvasInteractionState interaction,
    required List<PageTextItem> textItems,
    required List<PageImageItem> imageItems,
    required List<PageShapeItem> shapes,
    required List<PageChartItem> charts,
    required DrawingController host,
  }) {
    final before = interaction.mixedDragBefore;
    interaction.mixedDragBefore = null;
    if (before == null) return;
    _writeBack(textItems, before.textItems);
    _writeBack(imageItems, before.imageItems);
    _writeBack(shapes, before.shapes);
    _writeBack(charts, before.charts);
    host.invalidateLayer(host.currentLayer.id);
    host.tickFrame();
  }

  static void _writeBack<T>(List<T> live, List<T> snapshot) {
    live
      ..clear()
      ..addAll(snapshot);
  }

  /// 逐字段比对（toJson 串，与 DocumentObjectsSnapshot.isSame 同口径）。
  static bool _same(MixedObjectCollections a, MixedObjectCollections b) {
    bool sameList<T>(List<T> x, List<T> y, String Function(T) json) {
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (json(x[i]) != json(y[i])) return false;
      }
      return true;
    }

    String t(PageTextItem e) => e.toJson().toString();
    String i(PageImageItem e) => e.toJson().toString();
    String s(PageShapeItem e) => e.toJson().toString();
    String c(PageChartItem e) => e.toJson().toString();
    return sameList(a.textItems, b.textItems, t) &&
        sameList(a.imageItems, b.imageItems, i) &&
        sameList(a.shapes, b.shapes, s) &&
        sameList(a.charts, b.charts, c);
  }
}
