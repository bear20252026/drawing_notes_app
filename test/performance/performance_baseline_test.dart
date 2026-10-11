// 内核 P0 第一步：性能基线（专家审计整改清单 §七，2026-10-10）。
//
// 目的：给后续 StrokeBuffer/空间索引/瓦片渲染等内核投资提供**量化决策依据**——
// 外部审计的多项建议（R-tree、存储反转）必须先被基线证实存在真实拐点才动工。
// 首批基线结论（2026-10-10，本机 Windows）：
//   - 对象级视口剔除已存在（InkLayerPainter.cullStrokes，O(1)/条 AABB + 多槽
//     渲染计划缓存），5 万笔剔除单帧毫秒级——R-tree 无动工依据；
//   - 命令式撤销 2000 条入栈/全量撤销/重做合计亚秒级——历史栈无压力。
//
// 断言纪律：**正确性硬断言，耗时只设极宽松天花板**（本机/CI 速度差数倍，
// 基线的价值在数字对比而非门禁）；所有耗时/规模数字打印到 stdout 留档。
// 跑法：
//   NO_PROXY=127.0.0.1,localhost flutter test test/performance/ --reporter expanded
import 'dart:convert';
import 'dart:ui' show Color, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_edit_history.dart';
import 'package:drawing_notes_app/features/drawing/rendering/ink_layer_painter.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';

Stroke _stroke(int seed, int pointCount) {
  final points = <StrokePoint>[];
  var x = (seed * 7) % 400;
  var y = (seed * 11) % 300;
  for (var i = 0; i < pointCount; i++) {
    x = (x + 7) % 400;
    y = (y + 11) % 300;
    points.add(StrokePoint(x.toDouble(), y.toDouble(), 0.5));
  }
  return Stroke(
    points: points,
    color: const Color.fromARGB(255, 26, 26, 26),
    width: 2,
    type: BrushType.pen,
  );
}

DrawingDocument _documentWith(int strokeCount, int pointsPerStroke) {
  final layer = Layer(id: 'l1', name: '');
  for (var i = 0; i < strokeCount; i++) {
    layer.strokes.add(_stroke(i, pointsPerStroke));
  }
  return DrawingDocument(id: 'perf_doc', title: 'baseline', layers: [layer]);
}

/// B-3 专用计数命令（DocumentEditHistory 只管栈，不关心命令语义）。
class _CountingCommand extends DocCommand {
  _CountingCommand(this.log);
  final List<String> log;
  @override
  void undo() => log.add('undo');
  @override
  void redo() => log.add('redo');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('性能基线（数字供对比，耗时上限仅防失控）', () {
    test('B-1 单笔画 10 万点：构建 / bounds 首算 / 剔除查询', () {
      final sw = Stopwatch()..start();
      final stroke = _stroke(1, 100000);
      sw.stop();
      // ignore: avoid_print
      print('基线[B-1] 10万点 Stroke 对象构建: ${sw.elapsedMilliseconds}ms');

      sw..reset()..start();
      final bounds = StrokeRenderer.strokeBounds(stroke);
      sw.stop();
      // ignore: avoid_print
      print('基线[B-1] strokeBounds 首算: ${sw.elapsedMilliseconds}ms');
      expect(bounds, isNotNull);

      sw..reset()..start();
      const clip = Rect.fromLTWH(0, 0, 200, 200);
      for (var i = 0; i < 100; i++) {
        InkLayerPainter.cullStrokes([stroke], clip);
      }
      sw.stop();
      // ignore: avoid_print
      print('基线[B-1] cullStrokes×100（缓存命中 O(1)/条 AABB）: ${sw.elapsedMilliseconds}ms');
      expect(sw.elapsedMilliseconds, lessThan(60000), reason: '天花板（防失控，非性能门禁）');
    });

    test('B-2 9000 笔×20 点文档：encode/decode 往返正确性 + 耗时', () {
      // 规模受 codec 防御上限约束（防 JSON 炸弹，DocumentCodec:172-181）：
      // 单层 ≤1 万笔、全局 ≤100 万点——「单文档百万点」按设计不可落盘，
      // 外部审计设想的规模只能以多文档/多页形态存在。基线取防御上限内的
      // 9000×20=18 万点。
      final doc = _documentWith(9000, 20);
      final totalPoints = doc.layers.fold<int>(
        0,
        (sum, l) => sum + l.strokes.fold(0, (s, st) => s + st.points.length),
      );
      // ignore: avoid_print
      print('基线[B-2] 规模: 9000 笔 / $totalPoints 点');

      const codec = DocumentCodec();
      final sw = Stopwatch()..start();
      final encoded = codec.encode(doc);
      sw.stop();
      final encodeMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('基线[B-2] encode: ${encodeMs}ms, ${encoded.length ~/ 1024} KiB');

      sw..reset()..start();
      final decoded = codec.decode(encoded);
      sw.stop();
      final decodeMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('基线[B-2] decode: ${decodeMs}ms');
      // ignore: avoid_print
      print('基线[B-2] 往返合计: ${encodeMs + decodeMs}ms');

      expect(decoded.id, doc.id);
      expect(decoded.layers.single.strokes, hasLength(9000));
      final first = decoded.layers.single.strokes.first;
      expect(first.points, hasLength(20));
      expect(first.points.first.x, _stroke(0, 20).points.first.x);
      expect(decoded.layers.single.strokes.last.points.last.pressure, 0.5);
      expect(utf8.decode(encoded, allowMalformed: true), isNot(contains('"x":')),
          reason: '扁平数组格式（无逐点键名）');
      expect(encodeMs + decodeMs, lessThan(120000), reason: '天花板（防失控）');
    });

    test('B-3 长会话撤销：2000 条命令入栈 + 全量撤销/重做', () {
      final history = DocumentEditHistory(maxEntries: 5000);
      final log = <String>[];
      final sw = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        history.push(_CountingCommand(log));
      }
      sw.stop();
      // ignore: avoid_print
      print('基线[B-3] 2000 条命令入栈: ${sw.elapsedMilliseconds}ms');

      sw..reset()..start();
      var undone = 0;
      while (history.undo()) {
        undone++;
      }
      // ignore: avoid_print
      print('基线[B-3] 全量撤销 $undone 条: ${sw.elapsedMilliseconds}ms');

      sw..reset()..start();
      var redone = 0;
      while (history.redo()) {
        redone++;
      }
      // ignore: avoid_print
      print('基线[B-3] 全量重做 $redone 条: ${sw.elapsedMilliseconds}ms');

      expect(undone, 2000);
      expect(redone, 2000);
      expect(log.length, 4000);
    });

    test('B-4 cullStrokes 线性剔除规模标定（R-tree 决策依据）', () {
      const clip = Rect.fromLTWH(0, 0, 400, 400);
      for (final count in const [10000, 50000]) {
        final strokes = List.generate(count, (i) => _stroke(i, 10));
        InkLayerPainter.cullStrokes(strokes, clip); // 预热 bounds 缓存
        final sw = Stopwatch()..start();
        InkLayerPainter.cullStrokes(strokes, clip);
        sw.stop();
        // ignore: avoid_print
        print('基线[B-4] $count 笔线性剔除（缓存命中后）: ${sw.elapsedMicroseconds}µs/帧');
        expect(sw.elapsedMilliseconds, lessThan(10000), reason: '天花板（防失控）');
      }
    });
  });
}
