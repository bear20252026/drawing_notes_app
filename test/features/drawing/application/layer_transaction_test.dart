// 图层事务（交接文档 2026-10-05 第三优先）。
//
// `LayerService.beginLayerTransaction()` 原先是空方法——只有名字没有语义。
// 本文件把交接文档要求逐条钉成断言：开始 / 提交 / 失败回滚 / 嵌套 /
// 通知合并 / 一批操作如何形成一次撤销，以及「窗口内不得撤销」。

import 'dart:convert';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/operation/document_operation.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_transaction.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/services/history_service.dart';
import 'package:drawing_notes_app/features/drawing/application/services/layer_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 图层结构指纹：顺序 + 每层的身份、显隐、不透明度与笔画数。
String signature(DrawingDocument d) => jsonEncode([
  for (final l in d.layers)
    {
      'id': l.id,
      'name': l.name,
      'visible': l.visible,
      'opacity': l.opacity,
      'strokes': l.strokes.length,
    },
]);

DrawingController controller(String id) => DrawingController(
  DrawingDocument(id: id, title: '事务', width: 200, height: 200),
);

/// 一批图层操作：新建 + 显隐 + 相邻换位 + 删除（四步各自都会写一条历史）。
void runLayerOps(DrawingController c) {
  c.addLayer(name: 'tmp');
  c.toggleLayerVisibility(0);
  c.moveLayerUp(1);
  c.removeLayer(c.document.layers.length - 1);
}

void main() {
  test('空事务（begin 后什么都没做）不产生历史条目', () {
    final c = controller('empty');
    addTearDown(c.dispose);
    final before = c.historyService.entryCount;
    c.layerService.beginLayerTransaction();
    c.layerService.commitLayerTransaction();
    expect(c.historyService.entryCount, before);
    expect(c.layerService.hasOpenLayerTransaction, isFalse);
  });

  test('一批图层操作提交后=一条撤销条目，undo/redo 整批同进同退', () {
    final c = controller('commit');
    addTearDown(c.dispose);
    c.addLayer(name: 'keep'); // 事务外的一条，作为参照
    c.markSaved();
    final entriesBefore = c.historyService.entryCount;
    final before = signature(c.document);

    c.layerService.beginLayerTransaction();
    runLayerOps(c);
    final committed = signature(c.document);
    expect(
      c.historyService.entryCount,
      entriesBefore,
      reason: '窗口内的命令只累积，不写历史',
    );
    expect(
      c.isDirty,
      isTrue,
      reason: '窗口内必须当场置脏，否则自动保存会漏掉这批编辑',
    );
    c.layerService.commitLayerTransaction();

    expect(
      c.historyService.entryCount,
      entriesBefore + 1,
      reason: '四步操作合并成恰好一条撤销条目',
    );

    c.undo();
    expect(signature(c.document), before, reason: '一次撤销整批回到 begin 之前');
    c.redo();
    expect(signature(c.document), committed, reason: '一次重做整批回到提交时');
  });

  test('事务窗口内挂起逐次刷新，提交时合并补发', () {
    final control = controller('control');
    addTearDown(control.dispose);
    control.addLayer(name: 'keep');
    var controlNotifications = 0;
    control.addListener(() => controlNotifications++);
    runLayerOps(control); // 不开事务：逐次通知的既有行为
    expect(
      controlNotifications,
      greaterThan(1),
      reason: '对照组应每步都通知，否则「合并」这条断言是空的',
    );

    final c = controller('merged');
    addTearDown(c.dispose);
    c.addLayer(name: 'keep');
    var notifications = 0;
    c.addListener(() => notifications++);

    c.layerService.beginLayerTransaction();
    runLayerOps(c);
    expect(notifications, 0, reason: '窗口内一次都不该刷 UI');
    c.layerService.commitLayerTransaction();

    expect(notifications, greaterThan(0), reason: '提交时必须补发通知');
    expect(
      notifications,
      lessThan(controlNotifications),
      reason: '通知合并：同一批操作刷新次数必须少于逐次通知',
    );
  });

  test('回滚：整批撤销回去且历史条目零增长', () {
    final c = controller('rollback');
    addTearDown(c.dispose);
    c.addLayer(name: 'keep');
    final entriesBefore = c.historyService.entryCount;
    final before = signature(c.document);

    c.layerService.beginLayerTransaction();
    runLayerOps(c);
    expect(signature(c.document), isNot(before), reason: '回滚前必须真的改过');
    c.layerService.rollbackLayerTransaction();

    expect(
      signature(c.document),
      before,
      reason: '回滚要逐步撤销窗口内的每条命令，文档回到 begin 之前',
    );
    expect(c.historyService.entryCount, entriesBefore, reason: '回滚不留历史条目');
    expect(c.layerService.hasOpenLayerTransaction, isFalse);
  });

  test('嵌套：内层并入外层，只有最外层闭合才提交', () {
    final c = controller('nested');
    addTearDown(c.dispose);
    final entriesBefore = c.historyService.entryCount;

    c.layerService.beginLayerTransaction();
    c.layerService.beginLayerTransaction();
    c.addLayer(name: 'inner');
    c.layerService.commitLayerTransaction(); // 内层：只减一层计数
    expect(
      c.historyService.entryCount,
      entriesBefore,
      reason: '内层提交不得产出条目，事务仍未闭合',
    );
    expect(c.layerService.hasOpenLayerTransaction, isTrue);

    c.addLayer(name: 'outer');
    c.layerService.commitLayerTransaction(); // 外层：整体提交
    expect(
      c.historyService.entryCount,
      entriesBefore + 1,
      reason: '两层里的两次新建图层合并为一条撤销',
    );
    c.undo();
    expect(c.document.layers.length, 1);
  });

  test('窗口内拒绝撤销/重做，闭合后恢复可用', () {
    final c = controller('gate');
    addTearDown(c.dispose);
    c.addLayer(name: 'before');
    final before = signature(c.document);

    c.layerService.beginLayerTransaction();
    c.addLayer(name: 'during');
    expect(c.historyService.canUndo, isFalse, reason: '分组开着时不得暴露撤销');
    c.undo();
    expect(signature(c.document), isNot(before), reason: 'undo 被拒绝，不得撕半批');
    expect(c.historyService.canUndo, isFalse);
    c.layerService.commitLayerTransaction();

    expect(c.historyService.canUndo, isTrue);
    c.undo();
    expect(signature(c.document), before);
  });

  test('未配对与未绑定都当场报错，不静默放过', () {
    final c = controller('unpaired');
    addTearDown(c.dispose);
    expect(
      c.layerService.commitLayerTransaction,
      throwsStateError,
      reason: '没开事务就提交 = 调用方逻辑错了，必须响',
    );
    expect(c.layerService.rollbackLayerTransaction, throwsStateError);

    final unbound = LayerService();
    addTearDown(unbound.dispose);
    expect(unbound.beginLayerTransaction, throwsStateError);
  });

  test('HistoryService 分组：窗口内只累积、当场置脏、按序取出', () {
    final events = <String>[];
    final history = HistoryService();
    addTearDown(history.dispose);
    history.push(_Command('outside', events));
    history.markSaved();
    expect(history.entryCount, 1);
    expect(history.isDirty, isFalse);

    history.beginGroup();
    history.push(_Command('a', events));
    history.push(_Command('b', events));
    expect(history.entryCount, 1, reason: '分组内不写栈');
    expect(history.groupedCommandCount, 2);
    expect(history.isDirty, isTrue, reason: '分组内必须当场置脏');
    expect(history.isGroupOpen, isTrue);
    expect(history.undo(), isFalse, reason: '分组开着时拒绝撤销');

    final commands = history.closeGroup();
    expect(commands, hasLength(2));
    expect(history.isGroupOpen, isFalse);
    history.push(DocumentTransaction(commands!));
    expect(history.entryCount, 2);
    expect(history.undo(), isTrue);
    expect(history.undo(), isTrue);
    expect(events, ['undo:b', 'undo:a', 'undo:outside']);
  });

  // ---------------- DRW-08：分组窗口与会话操作日志（第四轮台账 §25） ----------------
  //
  // 旧写法每条子命令在窗口内就记一次 op，最外层提交时 `DocumentTransaction.operation`
  // 又把同一批聚成 `OpBatch` 记第二次 ⇒ 一次事务落**两遍**；回滚那条腿更糟：
  // `command.undo()` 撤得掉文档改动，撤不掉已经写进日志的 op，而 A2 那条腿会把
  // 「水位线之后」的日志写进磁盘侧车给将来的重放/增量同步用——等于留下一段从没生效过的操作。
  // 下面刻意用**两步都可表达**的图层操作（显隐 + 换位）；新建/删除图层那两条命令本来
  // 就不进操作流（`operation` 为 null），混进它们整批都不记，见最后一条。

  test('分组提交：日志里恰好一条 OpBatch，不是「两单条 + 一批」三条', () {
    final c = controller('oplog-commit');
    addTearDown(c.dispose);
    c.addLayer(name: 'keep'); // 事务外的参照（这条命令本身不进操作流）
    c.layerService.beginLayerTransaction();
    c.toggleLayerVisibility(0);
    c.moveLayerUp(0);
    expect(c.operationLog.length, 0, reason: '窗口内一条都不该记——提交时整批记一次');
    final serialBefore = c.operationLog.lastSerial;
    c.layerService.commitLayerTransaction();

    expect(c.operationLog.length, 1, reason: '一批操作 = 一条日志记录');
    expect(
      c.operationLog.lastSerial - serialBefore,
      1,
      reason: '水位线只前进一格：A2 侧靠它决定「哪些操作还没落盘」',
    );
    final op = c.operationLog.records.single;
    expect(op, isA<OpBatch>());
    expect((op as OpBatch).ops, hasLength(2), reason: '两步操作聚成一批，成员数要真对得上');
  });

  test('分组回滚：日志里不留那段从没生效过的操作', () {
    final c = controller('oplog-rollback');
    addTearDown(c.dispose);
    c.addLayer(name: 'keep');
    final logBefore = c.operationLog.length;

    c.layerService.beginLayerTransaction();
    c.toggleLayerVisibility(0);
    c.moveLayerUp(0);
    expect(c.operationLog.length, logBefore, reason: '窗口内不记');
    c.layerService.rollbackLayerTransaction();

    expect(
      c.operationLog.length,
      logBefore,
      reason: '回滚撤掉了文档改动就必须也撤得掉日志——写进侧车会被将来重放',
    );
  });

  test('反向锁：事务外的命令照旧逐条记录（不许把正常记录一起吞掉）', () {
    final c = controller('oplog-outside');
    addTearDown(c.dispose);
    c.addLayer(name: 'second'); // 只有一层时 moveLayerUp 是空操作，会少记一条
    c.toggleLayerVisibility(0);
    c.moveLayerUp(0);
    expect(c.operationLog.length, 2, reason: '不开事务时两步各记一条——延迟记录不能顺手把这条路也关掉');
    expect(c.operationLog.records.whereType<OpBatch>(), isEmpty);
  });

  test('嵌套：内层提交不产出记录，最外层整批记一次', () {
    final c = controller('oplog-nested');
    addTearDown(c.dispose);
    c.addLayer(name: 'second');
    c.layerService.beginLayerTransaction();
    c.layerService.beginLayerTransaction();
    c.toggleLayerVisibility(0);
    c.layerService.commitLayerTransaction(); // 内层：事务仍未闭合
    expect(c.operationLog.length, 0, reason: '内层提交不该产出记录');
    c.moveLayerUp(0);
    c.layerService.commitLayerTransaction(); // 外层：整批落地一次
    expect(c.operationLog.length, 1);
    expect((c.operationLog.records.single as OpBatch).ops, hasLength(2));
  });

  test('整批里混进不可表达的命令 ⇒ 一批都不记，而不是留下半批', () {
    final c = controller('oplog-mixed');
    addTearDown(c.dispose);
    c.layerService.beginLayerTransaction();
    c.addLayer(name: 'structural'); // 新建图层这类命令本来没有 op 表达
    c.toggleLayerVisibility(0);
    c.layerService.commitLayerTransaction();
    expect(
      c.operationLog.length,
      0,
      reason:
          '`DocumentTransaction.operation` 的口径是「部分记录无法完整回放」——'
          '窗口内逐条记会绕过这个口径，留下回放不了的前半批',
    );
  });
}

class _Command extends DocCommand {
  _Command(this.name, this.events);
  final String name;
  final List<String> events;
  @override
  void undo() => events.add('undo:$name');
  @override
  void redo() => events.add('redo:$name');
}
