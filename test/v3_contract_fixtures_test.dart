// v3 工程文件契约夹具（桌面端一侧）。
//
// 与网页版 `drawing_notes_web/tools/interop/` 跑同一批文件与同一份
// `manifest.json` 期望值：任一侧改坏格式（字段名、预算数值、宽容回读口径、
// 拒绝条件）都会在这里变红。清单副本两处各一份，sha256 必须相同
// （网页侧 runner 会在能看到本仓路径时做跨目录比对）。
//
// 刻意的不对称写在清单 notes 里：加密信封 DNV 的识别层次不同——桌面端在存储层
// （VaultFileCodec）识别，codec 层只会报「JSON 格式无效」，因此 reject 用例按
// `dartMessage` 断言消息片段，而不是要求两端给出同一个错误类。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const String _dir = 'test/fixtures/v3';
const DocumentCodec _codec = DocumentCodec();

Map<String, dynamic> _json(String relative) =>
    jsonDecode(utf8.decode(File('$_dir/$relative').readAsBytesSync())) as Map<String, dynamic>;

int _totalStrokes(DrawingDocument doc) =>
    doc.layers.fold<int>(0, (sum, Layer layer) => sum + layer.strokes.length);

int _totalPoints(DrawingDocument doc) => doc.layers.fold<int>(
  0,
  (int sum, Layer layer) =>
      sum + layer.strokes.fold<int>(0, (int acc, Stroke k) => acc + k.points.length),
);

int _invalidDropped(DocumentDecodeReport r) =>
    r.invalidLayersDropped +
    r.invalidStrokesDropped +
    r.invalidPointsDropped +
    r.invalidShapesDropped +
    r.invalidImagesDropped +
    r.invalidTextItemsDropped;

/// 与网页侧 buildOverBudget 同构：超 maxStrokesPerLayer 一条，现场生成不入库。
String _overBudgetJson(int strokes) {
  final buffer = StringBuffer()
    ..write('{"version":3,"document":{"id":"fx_over_budget","title":"超预算","width":2048,')
    ..write('"height":1536,"infinite":true,"paperType":"blank","folder":"",')
    ..write('"createdAt":"2026-10-12T00:00:00.000Z","updatedAt":"2026-10-12T00:00:00.000Z",')
    ..write('"layers":[{"id":"layer_1","name":"","visible":true,"opacity":1,"strokes":[');
  for (var i = 0; i < strokes; i++) {
    if (i > 0) buffer.write(',');
    buffer.write(
      '{"id":"stroke_$i","points":[$i,$i,1,${i + 1},${i + 1},1],'
      '"color":4278190080,"width":2,"type":"pen","opacity":1,"seed":${i + 1},"version":0,"versionNonce":0}',
    );
  }
  buffer.write(']}],"shapes":[],"imageItems":[],"textItems":[]}}');
  return buffer.toString();
}

void main() {
  final manifest = _json('manifest.json');
  final budgets = manifest['budgets'] as Map<String, dynamic>;
  final cases = (manifest['cases'] as List).cast<Map<String, dynamic>>();

  test('防御预算数值与清单逐条一致', () {
    expect(DocumentBudgets.maxFileBytes, budgets['maxFileBytes']);
    expect(DocumentBudgets.maxLayerCount, budgets['maxLayerCount']);
    expect(DocumentBudgets.maxStrokesPerLayer, budgets['maxStrokesPerLayer']);
    expect(DocumentBudgets.maxPointsPerStroke, budgets['maxPointsPerStroke']);
    expect(DocumentBudgets.maxTotalStrokes, budgets['maxTotalStrokes']);
    expect(DocumentBudgets.maxTotalPoints, budgets['maxTotalPoints']);
    expect(DocumentBudgets.maxShapeCount, budgets['maxShapeCount']);
    expect(DocumentBudgets.maxImageCount, budgets['maxImageCount']);
    expect(DocumentBudgets.maxTextCount, budgets['maxTextCount']);
    expect(DocumentBudgets.maxCoordinateMagnitude, (budgets['maxCoordinateMagnitude'] as num).toDouble());
    expect(DocumentBudgets.maxObjectExtent, (budgets['maxObjectExtent'] as num).toDouble());
    expect(DocumentBudgets.maxStrokeWidth, (budgets['maxStrokeWidth'] as num).toDouble());
    expect(DocumentBudgets.maxFontSize, (budgets['maxFontSize'] as num).toDouble());
    expect(DocumentCodec.latestVersion, budgets['formatVersion']);
  });

  for (final entry in cases) {
    final expect_ = entry['expect'] as Map<String, dynamic>;
    final name = (entry['file'] ?? entry['generate']) as String;

    if (expect_['reject'] != null) {
      test('拒绝 $name（${expect_['reject']}）', () {
        final bytes = utf8.encode(File('$_dir/$name').readAsStringSync(encoding: latin1));
        expect(
          () => _codec.decode(Uint8List.fromList(bytes)),
          throwsA(
            isA<FormatException>().having(
              (FormatException e) => e.message,
              'message',
              contains(expect_['dartMessage'] as String),
            ),
          ),
        );
      });
      continue;
    }

    test('解码 $name', () {
      final text = entry['generate'] != null
          ? _overBudgetJson(entry['strokes'] as int)
          : File('$_dir/$name').readAsStringSync();
      final decoded = _codec.decodeDetailed(
        Uint8List.fromList(utf8.encode(text)),
      );
      final doc = decoded.document;
      final report = decoded.report;

      void count(String key, int actual) {
        if (expect_[key] == null) return;
        expect(actual, expect_[key], reason: '$name.$key');
      }

      count('layers', doc.layers.length);
      count('strokes', _totalStrokes(doc));
      count('shapes', doc.shapes.length);
      count('textItems', doc.textItems.length);
      count('imageItems', doc.imageItems.length);
      expect(report.isBudgetTruncated, expect_['truncated'], reason: '$name.truncated');

      if (expect_['invalidDropped'] != null) {
        expect(_invalidDropped(report), expect_['invalidDropped'], reason: '$name.invalidDropped');
      }
      if (expect_['invalidShapesDroppedMin'] != null) {
        final minShapes = expect_['invalidShapesDroppedMin'] as int;
        expect(
          report.invalidShapesDropped >= minShapes,
          isTrue,
          reason: '$name.invalidShapesDropped=${report.invalidShapesDropped}',
        );
      }
      if (expect_['invalidStrokesDroppedMin'] != null) {
        final minStrokes = expect_['invalidStrokesDroppedMin'] as int;
        expect(
          report.invalidStrokesDropped >= minStrokes,
          isTrue,
          reason: '$name.invalidStrokesDropped=${report.invalidStrokesDropped}',
        );
      }

      // 笔画 type 序列必须原样读回：像素橡皮的轨迹就活在这个键上（BrushType.eraser），
      // 解码时丢掉它等于把用户擦过的地方重新画回来。
      final strokeTypes = expect_['strokeTypes'];
      if (strokeTypes is List) {
        final got = doc.layers
            .expand((Layer layer) => layer.strokes.map((Stroke k) => k.type.name))
            .toList();
        expect(got, strokeTypes, reason: '$name.strokeTypes');
      }

      // v4 样式键的三条规则（显式优先 / 缺省推导 / 未知降级）两端必须同解。
      final shapeStyles = expect_['shapeStyles'];
      if (shapeStyles is List) {
        for (final raw in shapeStyles) {
          final want = raw as Map<String, dynamic>;
          final matches = doc.shapes.where((s) => s.id == want['id']).toList();
          expect(matches.length, 1, reason: '$name 形状 ${want['id']} 应恰好存在一个');
          if (matches.isEmpty) continue;
          expect(matches.single.effectiveStrokeStyle.name, want['strokeStyle'], reason: '${want['id']} 线型');
          expect(matches.single.effectiveFillStyle?.name, want['fillStyle'], reason: '${want['id']} 填充样式');
        }
      }

      // 幂等：编码→解码再编码，字节必须一致（两端互导不能每次往返都变）。
      final once = _codec.encode(doc);
      final again = _codec.decodeDetailed(once);
      final twice = _codec.encode(again.document);
      expect(
        utf8.decode(twice),
        utf8.decode(once),
        reason: '$name encode→decode→encode 不幂等',
      );
      expect(_totalStrokes(again.document), _totalStrokes(doc), reason: '$name 重读后笔画数变化');
      expect(_totalPoints(again.document), _totalPoints(doc), reason: '$name 重读后采样点数变化');

      // 抖动种子与版本必须存活：丢了就是「同一张画重开后画面自己变」。
      for (var l = 0; l < doc.layers.length; l++) {
        final layer = doc.layers[l];
        final roundLayer = again.document.layers[l];
        for (var s = 0; s < layer.strokes.length; s++) {
          final stroke = layer.strokes[s];
          final round = roundLayer.strokes[s];
          expect(round.seed, stroke.seed, reason: '第 $l 层第 $s 笔 seed 变化');
          expect(round.version, stroke.version, reason: '第 $l 层第 $s 笔 version 变化');
          expect(round.versionNonce, stroke.versionNonce, reason: '第 $l 层第 $s 笔 versionNonce 变化');
        }
      }
    });
  }

  test('编码侧对超预算直接拒绝（读写对称）', () {
    // 必须现场构造：走解码路径会被截断到上限，就测不到编码侧那道门了。
    final strokes = List<Stroke>.generate(
      DocumentBudgets.maxStrokesPerLayer + 1,
      (int i) => Stroke(
        points: const [StrokePoint(0, 0, 1), StrokePoint(1, 1, 1)],
        color: const Color(0xFF000000),
        width: 2,
        type: BrushType.pen,
      ),
    );
    final doc = DrawingDocument(
      id: 'fx_encode_guard',
      title: '编码侧越界',
      layers: [Layer(id: 'layer_1', name: '', strokes: strokes)],
    );
    expect(() => _codec.encode(doc), throwsA(isA<DocumentBudgetException>()));
  });

  test('Color 与 ARGB 整数互转不留符号歧义', () {
    expect(const Color(0xFF0066CC).toARGB32(), 0xFF0066CC);
    expect(const Color(0x330066CC).toARGB32(), 0x330066CC);
  });
}
