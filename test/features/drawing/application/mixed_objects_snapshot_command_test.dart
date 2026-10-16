// EUI-02 的撤销记录本体：四类混排集合的成对恢复。
//
// 键盘链路（Delete → Ctrl+Z）由
// `test/features/drawing/presentation/editor_object_delete_undo_test.dart` 钉；
// 那里只能选中文字块（独立画布模式的可选集与 `EditorOverlayItemPlan.forCanvas`
// 同源），所以图片/形状/图表的恢复形状在这里单独钉——否则「四类都撤得回」这句
// 话只有一半有证据。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<PageTextItem> textItems;
  late List<PageImageItem> imageItems;
  late List<PageShapeItem> shapes;
  late List<PageChartItem> charts;

  setUp(() {
    textItems = [
      PageTextItem(id: 't1', x: 0, y: 0, text: '一'),
      PageTextItem(id: 't2', x: 0, y: 0, text: '二'),
    ];
    imageItems = [PageImageItem(id: 'i1', filePath: '/a.png', x: 0, y: 0)];
    shapes = [
      PageShapeItem(
        id: 's1',
        shapeType: ShapeType.rect,
        x: 0,
        y: 0,
        width: 40,
        height: 40,
      ),
    ];
    charts = [
      PageChartItem(id: 'c1', chartType: ChartType.bar, data: const [1, 2]),
    ];
  });

  MixedObjectsSnapshotCommand commandFrom(
    List<PageTextItem> t,
    List<PageImageItem> i,
    List<PageShapeItem> s,
    List<PageChartItem> c, {
    void Function()? onRestored,
  }) {
    final before = MixedObjectCollections(
      textItems: t,
      imageItems: i,
      shapes: s,
      charts: c,
    );
    t.removeWhere((e) => e.id == 't1');
    i.removeWhere((e) => e.id == 'i1');
    s.removeWhere((e) => e.id == 's1');
    c.removeWhere((e) => e.id == 'c1');
    final after = MixedObjectCollections(
      textItems: t,
      imageItems: i,
      shapes: s,
      charts: c,
    );
    return MixedObjectsSnapshotCommand(
      textItems: t,
      imageItems: i,
      shapes: s,
      charts: c,
      before: before,
      after: after,
      onRestored: onRestored,
    );
  }

  group('MixedObjectsSnapshotCommand 成对恢复', () {
    test('undo 按原下标放回四类对象，redo 再移除', () {
      final command = commandFrom(textItems, imageItems, shapes, charts);
      expect(textItems.map((t) => t.id), ['t2']);
      expect(imageItems, isEmpty);
      expect(shapes, isEmpty);
      expect(charts, isEmpty);

      command.undo();
      expect(textItems.map((t) => t.id), ['t1', 't2'], reason: '原下标必须还原');
      expect(imageItems.map((e) => e.id), ['i1']);
      expect(shapes.map((e) => e.id), ['s1']);
      expect(charts.map((e) => e.id), ['c1']);
      expect(
        identical(textItems.first, command.before.textItems.first),
        isTrue,
        reason: '放回的是同一实例：撤销不能把对象换成新身份',
      );

      command.redo();
      expect(textItems.map((t) => t.id), ['t2']);
      expect(imageItems, isEmpty);
      expect(shapes, isEmpty);
      expect(charts, isEmpty);
    });

    test('恢复走原地写回：宿主列表引用不换', () {
      final liveText = textItems;
      final command = commandFrom(textItems, imageItems, shapes, charts);
      command.undo();
      expect(
        identical(liveText, textItems),
        isTrue,
        reason: '撤销不得把宿主列表换成新实例（分页宿主持有的是同一份引用）',
      );
      expect(liveText.map((t) => t.id), ['t1', 't2']);
    });

    test('onRestored 在撤销与重做两条腿各触发一次', () {
      var restored = 0;
      final command = commandFrom(
        textItems,
        imageItems,
        shapes,
        charts,
        onRestored: () => restored++,
      );
      command.undo();
      expect(restored, 1, reason: '字节回来了却没补帧 = 撤销在屏上不成立');
      command.redo();
      expect(restored, 2);
    });

    test('没接 onRestored 也不抛（命令可独立于宿主使用）', () {
      commandFrom(textItems, imageItems, shapes, charts).undo();
      expect(textItems.map((t) => t.id), ['t1', 't2']);
    });
  });

  group('MixedObjectDeleteRecorder 接进真实撤销栈', () {
    late DrawingController host;
    late int dirtyCalls;

    setUp(() {
      host = DrawingController(
        DrawingDocument(id: 'rec1', title: '登记', width: 400, height: 300),
      );
      dirtyCalls = 0;
    });

    int record(Set<String> ids) => MixedObjectDeleteRecorder.deleteAndRecord(
      ids: ids,
      textItems: textItems,
      imageItems: imageItems,
      shapes: shapes,
      charts: charts,
      host: host,
      markDirty: () => dirtyCalls++,
    );

    test('删到东西 ⇒ 历史里真有一条，controller.undo() 撤得回', () {
      expect(record({'t1', 'i1', 's1', 'c1'}), 4);
      expect(host.canUndo, isTrue);
      expect(textItems.map((t) => t.id), ['t2']);

      host.undo();
      expect(textItems.map((t) => t.id), ['t1', 't2']);
      expect(imageItems.map((e) => e.id), ['i1']);
      expect(shapes.map((e) => e.id), ['s1']);
      expect(charts.map((e) => e.id), ['c1']);
      expect(dirtyCalls, 1, reason: '撤销必须登记成待落盘改动，否则盘上留的还是「删掉之后」的版本');

      host.redo();
      expect(textItems.map((t) => t.id), ['t2']);
      expect(dirtyCalls, 2);
    });

    test('一个也没删到 ⇒ 不产生历史条目', () {
      expect(record({'missing'}), 0);
      expect(host.canUndo, isFalse, reason: '空删除进撤销栈 = 用户按一次 Ctrl+Z 白吃掉一步真操作');
      expect(dirtyCalls, 0);
      expect(textItems.length, 2);
    });
  });
}
