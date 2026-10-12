// v4 样式循环的回归锁（2026-10-13）。
//
// 钉三件容易在后续改动里悄悄坏掉的事：
// ① 工具条按钮的四档/三档循环顺序与「回到起点」的闭合性；
// ② `dash` 作为 `strokeStyle` 投影的一致性（否则旧版本读到的观感会与新键分裂）；
// ③ 循环写出的形状经 codec 落盘再读回，样式不衰减（未知值只降级不报错）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';

PageShapeItem _rect({bool dash = false, bool rough = false, int? fillColor}) => PageShapeItem(
  id: 'sh_cycle',
  shapeType: ShapeType.rect,
  x: 0,
  y: 0,
  width: 100,
  height: 60,
  dash: dash,
  rough: rough,
  fillColor: fillColor,
);

void main() {
  group('线型循环', () {
    test('实线 → 虚线 → 点线 → 实线，且 dash 始终跟随', () {
      final s = _rect();
      expect(s.effectiveStrokeStyle, StrokeStyle.solid);

      s.cycleStrokeStyle();
      expect(s.effectiveStrokeStyle, StrokeStyle.dashed);
      expect(s.dash, isTrue, reason: 'dash 是 strokeStyle 的投影');

      s.cycleStrokeStyle();
      expect(s.effectiveStrokeStyle, StrokeStyle.dotted, reason: 'dash 表达不了的第三档');
      expect(
        s.dash,
        isTrue,
        reason: '布尔只答「是不是实线」：点线也必须 true，否则旧版本把点线画成实线',
      );

      s.cycleStrokeStyle();
      expect(s.effectiveStrokeStyle, StrokeStyle.solid);
      expect(s.dash, isFalse);
    });

    test('旧文件（无 strokeStyle）第一次循环前观感不变', () {
      final legacyDashed = _rect(dash: true);
      expect(legacyDashed.effectiveStrokeStyle, StrokeStyle.dashed);
      expect(legacyDashed.toJson().containsKey('strokeStyle'), isFalse);
      // 显式回到 solid 后，与旧推导一致 ⇒ 依然不落新键（旧文件重存不长键）。
      legacyDashed.cycleStrokeStyle(); // dashed → dotted
      legacyDashed.cycleStrokeStyle(); // dotted → solid
      expect(legacyDashed.toJson().containsKey('strokeStyle'), isFalse);
      expect(legacyDashed.dash, isFalse);
    });
  });

  group('填充循环', () {
    test('无 → 实心 → 斜线 → 交叉 → 无', () {
      final s = _rect();
      expect(s.effectiveFillStyle, isNull);

      s.cycleFillStyle(0x66A5D6A7);
      expect(s.fillColor, 0x66A5D6A7, reason: '从无到有要给用户一个可见的起色');
      expect(s.effectiveFillStyle, FillStyle.solid);

      s.cycleFillStyle(0x66A5D6A7);
      expect(s.effectiveFillStyle, FillStyle.hachure);

      s.cycleFillStyle(0x66A5D6A7);
      expect(s.effectiveFillStyle, FillStyle.crossHatch);

      s.cycleFillStyle(0x66A5D6A7);
      expect(s.fillColor, isNull);
      expect(s.effectiveFillStyle, isNull);
      expect(s.fillStyle, isNull, reason: '关掉填充时样式也要撤回，别留悬空键');
    });

    test('手绘形状可显式关掉斜线（v4 的新能力）', () {
      final roughFilled = _rect(rough: true, fillColor: 0x330066CC);
      expect(roughFilled.effectiveFillStyle, FillStyle.hachure, reason: '缺省仍是升级前的手绘斜线');
      roughFilled.fillStyle = FillStyle.solid;
      expect(roughFilled.effectiveFillStyle, FillStyle.solid);
      expect(roughFilled.toJson()['fillStyle'], 'solid', reason: '偏离旧推导，必须落盘');
      expect(roughFilled.rough, isTrue, reason: '描边抖动不受填充样式影响');
    });
  });

  group('经落盘回读', () {
    test('点线 + 交叉线在 codec 往返后原样存活', () {
      final s = _rect();
      s.cycleStrokeStyle();
      s.cycleStrokeStyle(); // dotted
      s.cycleFillStyle(0x66A5D6A7);
      s.cycleFillStyle(0x66A5D6A7);
      s.cycleFillStyle(0x66A5D6A7); // crossHatch
      final doc = DrawingDocument(
        id: 'doc_cycle',
        title: '样式循环',
        shapes: [s],
      );
      final bytes = const DocumentCodec().encode(doc);
      final back = const DocumentCodec().decode(bytes);
      final shape = back.shapes.single;
      expect(shape.effectiveStrokeStyle, StrokeStyle.dotted);
      expect(shape.effectiveFillStyle, FillStyle.crossHatch);
      expect(jsonDecode(utf8.decode(bytes))['version'], DocumentCodec.latestVersion);
      // 幂等：再编码一次字节完全一致。
      expect(const DocumentCodec().encode(back), bytes);
    });

    test('非法样式值降级为旧推导，不抛异常', () {
      final envelope = {
        'version': DocumentCodec.latestVersion,
        'document': {
          'id': 'doc_bogus',
          'title': '非法样式',
          'layers': [
            {'id': 'layer_1', 'name': '', 'visible': true, 'opacity': 1.0, 'strokes': <dynamic>[]},
          ],
          'shapes': [
            {
              'id': 'sh_bogus',
              'shapeType': 'rect',
              'x': 0.0,
              'y': 0.0,
              'width': 10.0,
              'height': 10.0,
              'color': 0xFF000000,
              'strokeWidth': 2.0,
              'zOrder': 0,
              'rotation': 0.0,
              'dash': true,
              'rough': false,
              'elbow': false,
              'strokeStyle': 'squiggly',
              'flipX': false,
              'flipY': false,
              'locked': false,
              'seed': 1,
              'version': 0,
              'versionNonce': 0,
            },
          ],
          'imageItems': <dynamic>[],
          'textItems': <dynamic>[],
        },
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
      final doc = const DocumentCodec().decode(bytes);
      final shape = doc.shapes.single;
      expect(shape.effectiveStrokeStyle, StrokeStyle.dashed, reason: '非法值按 dash 推导');
      expect(utf8.decode(const DocumentCodec().encode(doc)), isNot(contains('squiggly')));
    });
  });
}
