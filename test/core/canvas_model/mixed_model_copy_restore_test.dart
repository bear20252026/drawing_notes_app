// H-2（第二轮审计 2026-11-18）：copy/restoreFrom 字段集成对一致性门禁。
//
// 起因：_restoreFields 手抄清单漏 seed/_dashLegacy，注释谎称「toJson 往返
// 自动跟随」。修复收敛到模型 restoreFrom 单点后，本门禁钉住「copy 复制的
// 字段 == restoreFrom 恢复的字段」——模型加字段时只改 copy 不改 restoreFrom
// （或反之）当场红。
//
// 判据：对每类模型，构造一个**全字段非默认值**的实例 → copy() → 改原实例
// 全部可变字段为另一组值 → restoreFrom(copy) → 逐字段断言回到 copy 时的值。
// 任何漏恢复的字段都会停在「改后值」而非「copy 时值」→ 红。
//
// 局限（M-7 三轮审计 2026-11-18）：本测试是**手抄字段清单**——模型新增
// 字段而 copy+restoreFrom 双双漏跟时，本测试不红（新字段不在清单内）。
// 「字段集自动跟随模型」的机器判据由 AST 门禁承担：
// test/architecture/mixed_model_field_set_ast_gate_test.dart（解析源码可变
// 字段 vs copy/restoreFrom 覆盖集，差集非空即红）。本测试只钉**已列字段**
// 的恢复正确性，不声称自动跟随新增字段。
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';

void main() {
  test('PageTextItem：copy→改→restoreFrom 全字段回到快照值', () {
    final original = PageTextItem(
      id: 't1',
      x: 10,
      y: 20,
      text: '快照文本',
      fontSize: 18,
      color: 0xFF112233,
      isSticky: true,
      bold: true,
      italic: true,
      underline: true,
      strikethrough: true,
      isTodo: true,
      todoChecked: true,
      align: TextAlignType.center,
      zOrder: 5,
      width: 200,
      groupId: 'g1',
      href: 'https://example.com',
      fontFamily: 'serif',
      fractionalIndex: 'a0',
      runs: const [TextRun(text: '片段', bold: true, color: 0xFF445566)],
    );
    final snap = original.copy();
    // 改全部可变字段为另一组值。
    original
      ..x = 99
      ..y = 99
      ..text = '脏值'
      ..fontSize = 99
      ..color = 0xFF999999
      ..isSticky = false
      ..bold = false
      ..italic = false
      ..underline = false
      ..strikethrough = false
      ..isTodo = false
      ..todoChecked = false
      ..align = TextAlignType.right
      ..zOrder = 99
      ..width = 999
      ..groupId = 'dirty'
      ..href = 'dirty'
      ..fontFamily = 'dirty'
      ..fractionalIndex = 'dirty'
      ..runs = const [TextRun(text: '脏片段')];
    original.restoreFrom(snap);
    expect(original.x, 10);
    expect(original.y, 20);
    expect(original.text, '快照文本');
    expect(original.fontSize, 18);
    expect(original.color, 0xFF112233);
    expect(original.isSticky, isTrue);
    expect(original.bold, isTrue);
    expect(original.italic, isTrue);
    expect(original.underline, isTrue);
    expect(original.strikethrough, isTrue);
    expect(original.isTodo, isTrue);
    expect(original.todoChecked, isTrue);
    expect(original.align, TextAlignType.center);
    expect(original.zOrder, 5);
    expect(original.width, 200);
    expect(original.groupId, 'g1');
    expect(original.href, 'https://example.com');
    expect(original.fontFamily, 'serif');
    expect(original.fractionalIndex, 'a0');
    expect(original.runs!.single.text, '片段');
    expect(original.runs!.single.color, 0xFF445566);
  });

  test('PageImageItem：copy→改→restoreFrom 全字段回到快照值', () {
    final original = PageImageItem(
      id: 'i1',
      x: 10,
      y: 20,
      filePath: '/snap.png',
      width: 300,
      height: 200,
      zOrder: 3,
      groupId: 'g1',
      href: 'https://example.com',
      fractionalIndex: 'a0',
    );
    final snap = original.copy();
    original
      ..x = 99
      ..y = 99
      ..filePath = '/dirty.png'
      ..width = 999
      ..height = 999
      ..zOrder = 99
      ..groupId = 'dirty'
      ..href = 'dirty'
      ..fractionalIndex = 'dirty';
    original.restoreFrom(snap);
    expect(original.x, 10);
    expect(original.y, 20);
    expect(original.filePath, '/snap.png');
    expect(original.width, 300);
    expect(original.height, 200);
    expect(original.zOrder, 3);
    expect(original.groupId, 'g1');
    expect(original.href, 'https://example.com');
    expect(original.fractionalIndex, 'a0');
  });

  test('PageShapeItem：copy→改→restoreFrom 全字段回到快照值（含 seed/dash）', () {
    final original = PageShapeItem(
      id: 's1',
      shapeType: ShapeType.ellipse,
      x: 10,
      y: 20,
      width: 100,
      height: 80,
      color: 0xFF112233,
      fillColor: 0xFF445566,
      strokeWidth: 5,
      zOrder: 3,
      rotation: 0.5,
      dash: true,
      rough: true,
      elbow: true,
      strokeStyle: StrokeStyle.dotted,
      fillStyle: FillStyle.hachure,
      flipX: true,
      flipY: true,
      boundElementId: 'bound1',
      locked: true,
      groupId: 'g1',
      href: 'https://example.com',
      seed: 42,
      version: 7,
      versionNonce: 99,
      fractionalIndex: 'a0',
      lineStart: const Offset(1, 2),
      lineEnd: const Offset(3, 4),
    );
    final snap = original.copy();
    original
      ..shapeType = ShapeType.rect
      ..x = 99
      ..y = 99
      ..width = 999
      ..height = 999
      ..color = 0xFF999999
      ..fillColor = null
      ..strokeWidth = 99
      ..zOrder = 99
      ..rotation = 9.9
      ..dash = false
      ..rough = false
      ..elbow = false
      ..strokeStyle = null
      ..fillStyle = null
      ..flipX = false
      ..flipY = false
      ..boundElementId = null
      ..locked = false
      ..groupId = 'dirty'
      ..href = 'dirty'
      ..seed = 999
      ..version = 99
      ..versionNonce = 999
      ..fractionalIndex = 'dirty'
      ..lineStart = null
      ..lineEnd = null;
    original.restoreFrom(snap);
    expect(original.shapeType, ShapeType.ellipse);
    expect(original.x, 10);
    expect(original.y, 20);
    expect(original.width, 100);
    expect(original.height, 80);
    expect(original.color, 0xFF112233);
    expect(original.fillColor, 0xFF445566);
    expect(original.strokeWidth, 5);
    expect(original.zOrder, 3);
    expect(original.rotation, 0.5);
    expect(original.dash, isTrue, reason: 'dash getter 投影：strokeStyle=dotted → true');
    expect(original.rough, isTrue);
    expect(original.elbow, isTrue);
    expect(original.strokeStyle, StrokeStyle.dotted);
    expect(original.fillStyle, FillStyle.hachure);
    expect(original.flipX, isTrue);
    expect(original.flipY, isTrue);
    expect(original.boundElementId, 'bound1');
    expect(original.locked, isTrue);
    expect(original.groupId, 'g1');
    expect(original.href, 'https://example.com');
    expect(original.seed, 42, reason: 'H-2 核心：seed 此前漏恢复');
    expect(original.version, 7);
    expect(original.versionNonce, 99);
    expect(original.fractionalIndex, 'a0');
    expect(original.lineStart, const Offset(1, 2));
    expect(original.lineEnd, const Offset(3, 4));
  });

  test('PageShapeItem：strokeStyle=null 时 _dashLegacy 经 restoreFrom 恢复', () {
    // v3 遗留形状：strokeStyle=null，dash getter 以 _dashLegacy 为真相。
    final original = PageShapeItem(
      id: 's2',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      dash: true, // strokeStyle 默认 null → _dashLegacy=true
    );
    expect(original.strokeStyle, isNull);
    expect(original.dash, isTrue, reason: 'legacy 投影');
    final snap = original.copy();
    original.dash = false; // 改 legacy
    expect(original.dash, isFalse);
    original.restoreFrom(snap);
    expect(original.dash, isTrue, reason: 'H-2 核心：_dashLegacy 此前漏恢复');
    expect(original.strokeStyle, isNull);
  });

  test('PageChartItem：copy→改→restoreFrom 全字段回到快照值', () {
    final original = PageChartItem(
      id: 'c1',
      chartType: ChartType.line,
      data: const [1.0, 2.0, 3.0],
      labels: const ['A', 'B', 'C'],
      x: 10,
      y: 20,
      width: 400,
      height: 300,
      color: 0xFF112233,
      zOrder: 2,
    );
    final snap = original.copy();
    original
      ..chartType = ChartType.bar
      ..data = [9.9]
      ..labels = ['dirty']
      ..x = 99
      ..y = 99
      ..width = 999
      ..height = 999
      ..color = 0xFF999999
      ..zOrder = 99;
    original.restoreFrom(snap);
    expect(original.chartType, ChartType.line);
    expect(original.data, [1.0, 2.0, 3.0]);
    expect(original.labels, ['A', 'B', 'C']);
    expect(original.x, 10);
    expect(original.y, 20);
    expect(original.width, 400);
    expect(original.height, 300);
    expect(original.color, 0xFF112233);
    expect(original.zOrder, 2);
  });
}