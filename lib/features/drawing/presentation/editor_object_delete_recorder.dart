import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';

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
/// 为什么不塞进 [EditorPageObjectMutation]：那个类的契约写明「不负责撤销/重做
/// 和持久化」，命令登记属于宿主时序。为什么不塞进 `editor_page_editing.dart`：
/// 那条 part 所在库受行数棘轮约束（`test/editor_page_line_ratchet_test.dart`），
/// 而这是一次纯新增的收口。
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
