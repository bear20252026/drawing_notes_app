// drawing_controller_notifiers_test.dart — P2 #22 Phase 3 Notifier 单元测试。
import 'package:drawing_notes_app/features/drawing/application/layers_notifier.dart';
import 'package:drawing_notes_app/features/drawing/application/strokes_notifier.dart';
import 'package:drawing_notes_app/features/drawing/application/tools_notifier.dart';
import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── ToolsNotifier ──────────────────────────────────

  group('ToolsNotifier', () {
    late ToolsNotifier notifier;
    int notifyCount = 0;

    setUp(() {
      notifier = ToolsNotifier();
      notifyCount = 0;
      notifier.addListener(() => notifyCount++);
    });

    tearDown(() => notifier.dispose());

    test('默认值正确', () {
      expect(notifier.tool, BrushType.pen);
      expect(notifier.color, const Color(0xFF1A1A1A));
      expect(notifier.brushSize, 6.0);
      expect(notifier.eraserMode, EraserMode.stroke);
      expect(notifier.currentToolOpacity, 1.0);
      expect(notifier.isLaserMode, false);
    });

    test('tool setter 通知', () {
      notifier.tool = BrushType.eraser;
      expect(notifier.tool, BrushType.eraser);
      expect(notifyCount, 1);
    });

    test('tool setter 相同值不通知', () {
      notifier.tool = BrushType.pen; // 同值
      expect(notifyCount, 0);
    });

    test('color setter 通知', () {
      notifier.color = Colors.red;
      expect(notifier.color, Colors.red);
      expect(notifyCount, 1);
    });

    test('brushSize setter 通知', () {
      notifier.brushSize = 12.0;
      expect(notifier.brushSize, 12.0);
      expect(notifyCount, 1);
    });

    test('brushSize 相同值不通知', () {
      notifier.brushSize = 6.0;
      expect(notifyCount, 0);
    });

    test('eraserMode setter 通知', () {
      notifier.eraserMode = EraserMode.pixel;
      expect(notifier.eraserMode, EraserMode.pixel);
      expect(notifyCount, 1);
    });

    test('currentToolOpacity clamp', () {
      notifier.currentToolOpacity = 1.5;
      expect(notifier.currentToolOpacity, 1.0);
      notifier.currentToolOpacity = -0.5;
      expect(notifier.currentToolOpacity, 0.0);
    });

    test('isLaserMode setter 通知', () {
      notifier.isLaserMode = true;
      expect(notifier.isLaserMode, true);
      expect(notifyCount, 1);
    });

    test('eraserSize setter 不通知', () {
      notifier.eraserSize = 48.0;
      expect(notifier.eraserSize, 48.0);
      expect(notifyCount, 0);
    });

    test('批量修改触发多次通知', () {
      notifier.tool = BrushType.eraser;
      notifier.color = Colors.blue;
      notifier.brushSize = 3.0;
      expect(notifyCount, 3);
    });
  });

  // ── StrokesNotifier ──────────────────────────────────

  group('StrokesNotifier', () {
    late StrokesNotifier notifier;
    int notifyCount = 0;

    setUp(() {
      notifier = StrokesNotifier();
      notifyCount = 0;
      notifier.addListener(() => notifyCount++);
    });

    tearDown(() => notifier.dispose());

    test('默认空笔画', () {
      expect(notifier.strokes, isEmpty);
      expect(notifier.strokeCount, 0);
      expect(notifier.currentStroke, isNull);
    });

    test('bindStrokes 绑定笔画', () {
      final strokes = [
        Stroke(
          points: [const StrokePoint(0, 0, 1.0)],
          color: Colors.black,
          width: 6.0,
          type: BrushType.pen,
        ),
      ];
      notifier.bindStrokes(strokes);
      expect(notifier.strokeCount, 1);
    });

    test('onStrokeAdded 通知', () {
      notifier.onStrokeAdded();
      expect(notifyCount, 1);
    });

    test('onStrokeRemoved 通知', () {
      notifier.onStrokeRemoved();
      expect(notifyCount, 1);
    });

    test('onHistoryChanged 通知', () {
      notifier.onHistoryChanged();
      expect(notifyCount, 1);
    });

    test('onCurrentStrokeUpdated 不通知（高频）', () {
      final stroke = Stroke(
        points: [const StrokePoint(0, 0, 1.0)],
        color: Colors.black,
        width: 6.0,
        type: BrushType.pen,
      );
      notifier.onCurrentStrokeUpdated(stroke);
      expect(notifier.currentStroke, isNotNull);
      expect(notifyCount, 0); // 不触发通知。
    });

    test('onCurrentStrokeCommitted 通知', () {
      notifier.onCurrentStrokeUpdated(Stroke(
        points: [],
        color: Colors.black,
        width: 6.0,
        type: BrushType.pen,
      ));
      notifier.onCurrentStrokeCommitted();
      expect(notifier.currentStroke, isNull);
      expect(notifyCount, 1);
    });
  });

  // ── LayersNotifier ──────────────────────────────────

  group('LayersNotifier', () {
    late LayersNotifier notifier;
    int notifyCount = 0;

    setUp(() {
      notifier = LayersNotifier();
      notifyCount = 0;
      notifier.addListener(() => notifyCount++);
    });

    tearDown(() => notifier.dispose());

    test('默认值正确', () {
      expect(notifier.currentLayerIndex, 0);
      expect(notifier.layerOpacity, 1.0);
    });

    test('currentLayerIndex setter 通知', () {
      notifier.currentLayerIndex = 2;
      expect(notifier.currentLayerIndex, 2);
      expect(notifyCount, 1);
    });

    test('layerOpacity setter 通知并 clamp', () {
      notifier.layerOpacity = 0.5;
      expect(notifier.layerOpacity, 0.5);
      expect(notifyCount, 1);

      notifier.layerOpacity = 1.5;
      expect(notifier.layerOpacity, 1.0);
    });

    test('isStrokeVisible 默认可见', () {
      expect(notifier.isStrokeVisible('stroke-1'), true);
    });

    test('setStrokeVisibility 通知', () {
      notifier.setStrokeVisibility('stroke-1', false);
      expect(notifier.isStrokeVisible('stroke-1'), false);
      expect(notifyCount, 1);
    });

    test('setStrokeVisibility 相同值不通知', () {
      // 先设置一次。
      notifier.setStrokeVisibility('stroke-1', false);
      expect(notifyCount, 1);
      // 再设置相同值——不触发通知。
      notifier.setStrokeVisibility('stroke-1', false);
      expect(notifyCount, 1); // 仍然是 1。
    });

    test('onLayerAdded 通知', () {
      notifier.onLayerAdded();
      expect(notifyCount, 1);
    });

    test('onLayerRemoved 通知并递减索引', () {
      notifier.currentLayerIndex = 2;
      notifyCount = 0;
      notifier.onLayerRemoved();
      expect(notifier.currentLayerIndex, 1);
      expect(notifyCount, 1);
    });

    test('onLayerRemoved 索引为 0 不递减', () {
      notifier.onLayerRemoved();
      expect(notifier.currentLayerIndex, 0);
    });

    test('onLayersReordered 通知', () {
      notifier.onLayersReordered();
      expect(notifyCount, 1);
    });
  });
}
