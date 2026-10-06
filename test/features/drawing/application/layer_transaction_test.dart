// 图层事务（交接文档 2026-10-05 第三优先）。
//
// `LayerService.beginLayerTransaction()` 原先是空方法——只有名字没有语义。
// 本文件把交接文档要求逐条钉成断言：开始 / 提交 / 失败回滚 / 嵌套 /
// 通知合并 / 一批操作如何形成一次撤销，以及「窗口内不得撤销」。

import 'dart:convert';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
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
