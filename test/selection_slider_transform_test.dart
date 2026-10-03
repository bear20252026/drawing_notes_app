import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/drawing/presentation/selection_bar.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 选区栏缩放/旋转滑块的笔画提交与锚点归属回归（2026-10-03 复核 P1）。
///
/// - `editor_page_body.dart` 的 `onTransformEnd` 原只有「笔记本混合 / 形状 /
///   图片」三个分支，缺笔画分支 ⇒ 滑块改了笔画坐标（也存盘），窄命令从未
///   提交，Ctrl+Z 撤不回。
/// - 锚点 `transformBefore` 原用 `??=` 且从不清空 ⇒ 残留锚点会被下一次手势
///   当作起点，按旧图层/旧位置组装三元组，撤销错位、越界项被静默丢弃。
void main() {
  Stroke strokeAt(double y) => Stroke(
    points: <StrokePoint>[StrokePoint(10, y, 1), StrokePoint(60, y, 1)],
    color: const Color(0xFF111111),
    width: 2,
    type: BrushType.pen,
  );

  DrawingController controllerWith({
    required List<List<Stroke>> layerStrokes,
  }) {
    final layers = <Layer>[
      for (var index = 0; index < layerStrokes.length; index++)
        Layer(
          id: 'layer-$index',
          name: '图层 $index',
          strokes: layerStrokes[index],
        ),
    ];
    return DrawingController(
      DrawingDocument(
        id: 'slider-transform',
        title: '选区滑块变换',
        width: 400,
        height: 400,
        layers: layers,
      ),
    );
  }

  /// 在当前图层用矩形草稿框选 [rect] 覆盖到的笔画。
  void selectRect(DrawingController c, Rect rect) {
    c.selectionTool = SelectionTool.rect;
    c.beginSelection(rect.topLeft);
    c.extendSelection(rect.bottomRight);
    c.endSelection();
  }

  Offset firstPoint(Stroke stroke) => stroke.points.first.offset;

  group('选区栏滑块笔画提交', () {
    testWidgets('滑块缩放后松手必须提交窄命令：Ctrl+Z 能还原笔画坐标', (
      tester,
    ) async {
      final a = strokeAt(10);
      final doc = DrawingDocument(
        id: 'slider-widget',
        title: '选区滑块',
        width: 400,
        height: 400,
        layers: <Layer>[Layer(id: 'layer_1', name: '图层 1', strokes: <Stroke>[a])],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: EditorPage(document: doc)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final bar = tester.widget<SelectionBar>(find.byType(SelectionBar));
      final controller = bar.controller;
      selectRect(controller, const Rect.fromLTRB(0, 0, 80, 30));
      expect(controller.hasSelectedStrokes, isTrue);

      bar.onScaleChanged(1.5);
      final scaled = doc.layers.first.strokes.first;
      expect(identical(scaled, a), isFalse, reason: '缩放会替换为新 Stroke 对象');
      expect(firstPoint(scaled), isNot(firstPoint(a)));

      // 松手（Slider.onChangeEnd）：必须产生一条可撤销记录。
      bar.onTransformEnd();
      await tester.pump();
      expect(controller.canUndo, isTrue, reason: '滑块笔画变换必须入栈');

      controller.undo();
      expect(
        firstPoint(doc.layers.first.strokes.first),
        firstPoint(a),
        reason: '撤销还原滑块改掉的笔画坐标',
      );

      controller.redo();
      expect(firstPoint(doc.layers.first.strokes.first), firstPoint(scaled));
    });
  });

  group('变换锚点归属', () {
    test('残留锚点不得跨手势：换选区后的第一次 undo 只还原第二次手势', () {
      final a = strokeAt(10);
      final b = strokeAt(60);
      final c = controllerWith(layerStrokes: <List<Stroke>>[<Stroke>[a, b]]);
      final strokes = c.document.layers.single.strokes;

      // 手势 1：只选中 A 缩放——滑块路径此前不调 endTransform，锚点会残留。
      selectRect(c, const Rect.fromLTRB(0, 0, 80, 30));
      c.scaleSelectedStrokes(2);
      final afterFirst = <Offset>[
        firstPoint(strokes[0]),
        firstPoint(strokes[1]),
      ];
      expect(firstPoint(strokes[0]), isNot(firstPoint(a)));

      // 手势 2：重新框选 A+B 缩放并提交（换选区即手势边界）。
      selectRect(c, const Rect.fromLTRB(0, 0, 80, 80));
      c.scaleSelectedStrokes(3);
      c.endTransform();

      c.undo();
      expect(
        <Offset>[firstPoint(strokes[0]), firstPoint(strokes[1])],
        afterFirst,
        reason: '第一次撤销必须精确回到手势 1 结束时的状态',
      );

      c.undo();
      expect(firstPoint(strokes[0]), firstPoint(a));
      expect(firstPoint(strokes[1]), firstPoint(b));
    });

    test('切层后锚点作废：撤销只影响新图层，不串改旧图层笔画', () {
      final layer0Stroke = strokeAt(10);
      final layer1Stroke = strokeAt(20);
      final c = controllerWith(layerStrokes: <List<Stroke>>[
        <Stroke>[layer0Stroke],
        <Stroke>[layer1Stroke],
      ]);
      final layer0 = c.document.layers[0].strokes;
      final layer1 = c.document.layers[1].strokes;

      selectRect(c, const Rect.fromLTRB(0, 0, 80, 30));
      c.scaleSelectedStrokes(2); // 未提交的旧图层变换 + 残留锚点

      c.currentLayerIndex = 1;
      selectRect(c, const Rect.fromLTRB(0, 0, 80, 40));
      c.scaleSelectedStrokes(4);
      c.endTransform();

      final layer0After = firstPoint(layer0.first);
      c.undo();
      expect(
        firstPoint(layer1.first),
        firstPoint(layer1Stroke),
        reason: '撤销只回退当前图层的手势',
      );
      expect(firstPoint(layer0.first), layer0After, reason: '旧图层不被串改');
    });

    test('清除选区后锚点作废：下一次变换不会用旧锚点组装三元组', () {
      final a = strokeAt(10);
      final b = strokeAt(60);
      final c = controllerWith(layerStrokes: <List<Stroke>>[<Stroke>[a, b]]);
      final strokes = c.document.layers.single.strokes;

      selectRect(c, const Rect.fromLTRB(0, 0, 80, 30));
      c.scaleSelectedStrokes(2);
      c.clearSelection();

      selectRect(c, const Rect.fromLTRB(0, 0, 80, 80));
      c.scaleSelectedStrokes(5);
      c.endTransform();

      final gestureStart = <Offset>[
        firstPoint(strokes[0]),
        firstPoint(strokes[1]),
      ];
      c.undo();
      expect(
        <Offset>[firstPoint(strokes[0]), firstPoint(strokes[1])],
        gestureStart,
        reason: '换选区前的变换不能混进这次的撤销记录',
      );
      expect(c.canUndo, isFalse, reason: '清除选区后无遗留历史条目');
    });
  });
}
