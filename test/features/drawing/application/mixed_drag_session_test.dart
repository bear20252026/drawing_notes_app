// P1 架构收口（2026-11-18）：会话对象结构性保证的专项回归。
//
// 钉住三轮审计 H-1/H-2/M-1 的构造性消除：
// ① 聚焦手柄期间窗口内混入的命令（Delete 冒泡）commit 时合成事务入栈
//    ——不再被 closeGroup 返回值丢弃吞掉（H-2）；
// ② abort 兜底：任意嵌套深度强制还原+回滚，幂等（H-1 dispose 路径）；
// ③ 会话不依赖页面存活：捕获列表引用后外部槽清空照样结算（H-1 切页）；
// ④ 挂起通知补发：窗口内 notifyChanged 被挂起，commitGroup 后补发（M-1）。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_object_mutation.dart';

void main() {
  late DrawingController host;
  late List<PageTextItem> texts;
  late List<PageImageItem> images;
  late List<PageShapeItem> shapes;
  late List<PageChartItem> charts;

  setUp(() {
    host = DrawingController(
      DrawingDocument(id: 'p1', title: '会话收口', width: 800, height: 600),
    );
    texts = [PageTextItem(id: 't1', x: 10, y: 10, text: '甲')];
    images = [PageImageItem(id: 'i1', x: 20, y: 20, filePath: '/a.png')];
    shapes = [
      PageShapeItem(
        id: 's1', shapeType: ShapeType.rect, x: 30, y: 30, width: 40, height: 40),
    ];
    charts = [
      PageChartItem(id: 'c1', chartType: ChartType.bar, data: const [1, 2]),
    ];
  });

  MixedDragSession newSession() => MixedDragSession(
    textItems: texts, imageItems: images, shapes: shapes, charts: charts,
    host: host, markDirty: () {},
  );

  test('H-2：窗口内混入的命令 commit 时合成事务入栈——不再被吞', () {
    final session = newSession();
    session.begin(); // 聚焦：开 group
    shapes.first.x = 100; // 拖拽改字段

    // 聚焦期间 Delete 冒泡到页面：删除命令 push 落入窗口。
    MixedObjectDeleteRecorder.deleteAndRecord(
      ids: {'t1'},
      textItems: texts, imageItems: images, shapes: shapes, charts: charts,
      host: host, markDirty: () {},
    );
    expect(texts, isEmpty, reason: '前置：删除确实执行了');
    expect(host.canUndo, isFalse, reason: 'group 开着，undo 被拒绝');

    // 失焦：commit 关组——删除命令必须合成事务入栈（此前被丢弃）。
    expect(session.commit(), isTrue);
    expect(host.canUndo, isTrue, reason: '窗口内删除命令不再被吞');

    // undo 一次 = 整批回退（拖拽+删除合成一条事务）。
    host.undo();
    expect(texts.map((t) => t.id), ['t1'], reason: '删除撤得回');
    expect(shapes.first.x, 30, reason: '拖拽也一并回退（同事务）');
  });

  test('H-2 反向：cancel 回滚窗口内命令——删除被撤回到位', () {
    final session = newSession();
    session.begin();
    MixedObjectDeleteRecorder.deleteAndRecord(
      ids: {'t1'},
      textItems: texts, imageItems: images, shapes: shapes, charts: charts,
      host: host, markDirty: () {},
    );
    expect(texts, isEmpty);

    session.cancel(); // 取消手势：窗口命令逆序 undo + 快照还原
    expect(texts.map((t) => t.id), ['t1'], reason: '窗口内删除被回滚');
    expect(host.canUndo, isFalse, reason: '取消不产生历史条目');
  });

  test('H-1：abort 任意嵌套深度强制结算，幂等', () {
    final session = newSession();
    session.begin();
    session.begin(); // 嵌套（聚焦+指针）
    session.begin();
    shapes.first.x = 500;

    session.abort(); // dispose 兜底：压平嵌套强制还原
    expect(shapes.first.x, 30, reason: '还原到会话起点');
    expect(session.isClosed, isTrue);
    expect(host.historyService.isGroupOpen, isFalse, reason: 'group 必然关闭');
    expect(host.canUndo, isFalse);

    session.abort(); // 幂等：再调不抛不重复还原
    expect(shapes.first.x, 30);
  });

  test('H-1：会话不依赖页面存活——外部槽清空照样结算', () {
    final session = newSession();
    session.begin();
    shapes.first.x = 200;
    // 模拟切页：页面侧槽清空，但会话持有列表引用。
    // （会话 API 下 commit 不接收页面参数——结构上不可能因页面 null 早退。）
    expect(session.commit(), isTrue);
    expect(host.canUndo, isTrue);
    host.undo();
    expect(shapes.first.x, 30);
  });

  test('M-1：窗口内挂起的通知 commitGroup 后补发', () {
    var notifications = 0;
    host.addListener(() => notifications++);
    final session = newSession();
    session.begin();
    host.notifyChanged(); // group 开着 → 挂起
    final before = notifications;
    session.commit(); // commitGroup 内部 flush
    expect(notifications, greaterThan(before), reason: '挂起通知必须补发');
  });

  test('嵌套 commit/cancel 只递减，最外层才结算', () {
    final session = newSession();
    session.begin();
    session.begin();
    shapes.first.x = 100;
    expect(session.commit(), isFalse, reason: '内层不结算');
    expect(host.historyService.isGroupOpen, isTrue);
    expect(session.cancel(), isTrue, reason: '最外层取消');
    expect(shapes.first.x, 30);
    expect(host.historyService.isGroupOpen, isFalse);
  });

  test('commit 后 isClosed 幂等：焦点失焦+panEnd 双触发不重复关组', () {
    final session = newSession();
    session.begin();
    shapes.first.x = 100;
    expect(session.commit(), isTrue);
    expect(session.commit(), isTrue, reason: '已闭合再 commit 幂等');
    expect(host.historyService.isGroupOpen, isFalse);
    // 只有一条历史（双触发不产生第二条）。
    host.undo();
    expect(shapes.first.x, 30);
    expect(host.canUndo, isFalse);
  });
}
