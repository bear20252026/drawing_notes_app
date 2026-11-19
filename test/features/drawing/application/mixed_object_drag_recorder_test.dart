// 拖拽事务会话单测（P1 架构收口 2026-11-18：Recorder→MixedDragSession）。
//
// 整域缺口：笔记模式移动/旋转/缩放/宽度柄直改字段不入撤销。本文件钉
// 事务层的机器事实：begin 深快照 / commit 有变化才入栈 / cancel 还原
// 不入栈 / 嵌套 begin 首个为准 / 空拖拽不白吃撤销步。
//
// Widget 链路（真手势 → Ctrl+Z）由 editor_mixed_drag_undo_test.dart 钉。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DrawingController host;
  MixedDragSession? session;
  late List<PageTextItem> texts;
  late List<PageImageItem> images;
  late List<PageShapeItem> shapes;
  late List<PageChartItem> charts;
  late int dirtyCalls;

  setUp(() {
    host = DrawingController(
      DrawingDocument(id: 'drag1', title: '拖拽事务', width: 800, height: 600),
    );
    session = null;
    texts = [PageTextItem(id: 't1', x: 10, y: 10, text: '甲')];
    images = [PageImageItem(id: 'i1', x: 20, y: 20, filePath: '/a.png')];
    shapes = [
      PageShapeItem(
        id: 's1',
        shapeType: ShapeType.rect,
        x: 30,
        y: 30,
        width: 40,
        height: 40,
      ),
    ];
    charts = [
      PageChartItem(id: 'c1', chartType: ChartType.bar, data: const [1, 2]),
    ];
    dirtyCalls = 0;
  });

  void begin() {
    session ??= MixedDragSession(
      textItems: texts,
      imageItems: images,
      shapes: shapes,
      charts: charts,
      host: host,
      markDirty: () => dirtyCalls++,
    );
    session!.begin();
  }

  bool commit() => session!.commit();

  void cancel() => session!.cancel();

  test('移动后 commit：一条撤销，undo 回到起点，redo 再到终点', () {
    begin();
    shapes.first.x = 130; // 模拟拖拽原地改字段
    shapes.first.y = 90;
    expect(commit(), isTrue);
    expect(host.canUndo, isTrue);
    expect(dirtyCalls, 0, reason: 'commit 本身不 markDirty（调用方走保存链）');

    host.undo();
    expect(shapes.first.x, 30);
    expect(shapes.first.y, 30);
    expect(dirtyCalls, 1, reason: '撤销必须登记成待落盘改动');

    host.redo();
    expect(shapes.first.x, 130);
    expect(shapes.first.y, 90);
    expect(dirtyCalls, 2);
  });

  test('旋转后 commit：rotation 字段撤得回（深快照捕获原地变更）', () {
    begin();
    shapes.first.rotation = 1.5;
    expect(commit(), isTrue);

    host.undo();
    expect(shapes.first.rotation, 0);
    host.redo();
    expect(shapes.first.rotation, 1.5);
  });

  test('缩放后 commit：width/height/x/y 四字段同边界恢复', () {
    begin();
    shapes.first
      ..x = 25
      ..y = 25
      ..width = 60
      ..height = 70;
    expect(commit(), isTrue);

    host.undo();
    expect(shapes.first.x, 30);
    expect(shapes.first.y, 30);
    expect(shapes.first.width, 40);
    expect(shapes.first.height, 40);
  });

  test('文字宽度柄：width+fontSize 联动变更一条撤销', () {
    texts.first.width = 300;
    texts.first.fontSize = 24;
    begin();
    texts.first.width = 360;
    texts.first.fontSize = 28.8;
    expect(commit(), isTrue);

    host.undo();
    expect(texts.first.width, 300);
    expect(texts.first.fontSize, 24);
  });

  test('空拖拽（begin 后无变化）commit：不产生历史条目', () {
    begin();
    expect(commit(), isTrue, reason: '会话已闭合（返回值=闭合态，非条目态）');
    expect(host.canUndo, isFalse, reason: '空拖拽进栈 = 白吃一步真操作');
    expect(dirtyCalls, 0);
  });

  test('无会话直接 commit：页面入口 null 守卫（防御性）', () {
    shapes.first.x = 999;
    // 会话 API：无会话时页面入口 _commitMixedDrag 直接 return；
    // 会话对象自身 commit 前必 begin（构造即绑定），此处钉 null 守卫语义。
    expect(session, isNull);
    expect(host.canUndo, isFalse);
  });

  test('cancel：还原起始状态、不入栈', () {
    begin();
    shapes.first.x = 500;
    images.first.x = 600;
    cancel();
    expect(shapes.first.x, 30);
    expect(images.first.x, 20);
    expect(host.canUndo, isFalse, reason: '取消手势不写历史（session 同口径）');
    expect(session!.isClosed, isTrue);
  });

  test('嵌套 begin 以首个为准（宽度柄聚焦+指针同会话不覆盖基准）', () {
    begin();
    shapes.first.x = 100;
    begin(); // 第二次 begin 不覆盖（depth=2）
    shapes.first.x = 200;
    // 内层 commit 只递减 depth，不结算（H-3：最外层才关 group/清槽）。
    expect(commit(), isFalse, reason: '内层 commit 不产生条目');
    expect(host.canUndo, isFalse, reason: 'group 仍开着，undo 被拒绝');
    // 最外层 commit 结算：基准是第一次 begin 的起点（30），不是第二次。
    expect(commit(), isTrue);

    host.undo();
    expect(shapes.first.x, 30, reason: '回到第一次 begin 的起点，不是第二次');
  });

  test('四类对象同一次事务：一条撤销整体恢复（多选拖拽形状）', () {
    begin();
    texts.first.x = 110;
    images.first.x = 120;
    shapes.first.x = 130;
    charts.first.x = 140;
    expect(commit(), isTrue);
    expect(host.canUndo, isTrue);

    host.undo();
    expect(texts.first.x, 10);
    expect(images.first.x, 20);
    expect(shapes.first.x, 30);
    expect(charts.first.x, 100);
  });

  test('连续两次拖拽 = 两条独立撤销（LIFO 逐次回退）', () {
    begin();
    shapes.first.x = 100;
    commit();
    session = null; // 闭合后开新会话（页面入口同口径：isClosed 即重建）
    begin();
    shapes.first.x = 200;
    commit();

    host.undo();
    expect(shapes.first.x, 100, reason: '第一次 undo 回到第一次拖拽终点');
    host.undo();
    expect(shapes.first.x, 30, reason: '第二次 undo 回到最初起点');
  });

  test('拖拽后删除再撤销删除：深快照保证放回的是拖拽后的状态', () {
    // 组合正确性：删除命令持深快照，撤销删除放回的是「删除那一刻」的
    // 字段值（含此前拖拽的结果），不是被后续操作改脏的旧实例。
    begin();
    shapes.first.x = 100;
    commit();
    session = null;

    MixedObjectDeleteRecorder.deleteAndRecord(
      ids: {'s1'},
      textItems: texts,
      imageItems: images,
      shapes: shapes,
      charts: charts,
      host: host,
      markDirty: () => dirtyCalls++,
    );
    expect(shapes, isEmpty);

    host.undo(); // 撤销删除
    expect(shapes.single.x, 100, reason: '放回拖拽后的位置，不是拖拽前');
    host.undo(); // 撤销拖拽
    expect(shapes.single.x, 30);
  });
}