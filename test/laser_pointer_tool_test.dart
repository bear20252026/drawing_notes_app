import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/temporary_markers.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('激光工具仅生成运行时尾迹，不写入图层或撤销历史', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'laser_transient', title: '激光临时墨迹'),
    );
    addTearDown(controller.dispose);

    controller.tool = BrushType.laser;
    controller.startStroke(const Offset(10, 20));
    controller.extendStroke(const Offset(50, 20));
    controller.extendStroke(const Offset(90, 30));
    await controller.endStroke();

    expect(controller.document.layers.single.strokes, isEmpty);
    expect(controller.canUndo, isFalse);
    expect(controller.temporaryLaserStrokes, hasLength(1));
    expect(
      controller.temporaryLaserStrokes.single.stroke.type,
      BrushType.laser,
    );
    expect(controller.temporaryLaserStrokes.single.firstPointIndex, 0);
  });

  test('激光尾迹在停留后从起笔端逐段消退并自动移除', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'laser_fade', title: '激光尾迹'),
    );
    addTearDown(controller.dispose);

    controller.tool = BrushType.laser;
    controller.startStroke(const Offset(0, 0));
    controller.extendStroke(const Offset(30, 0));
    controller.extendStroke(const Offset(60, 0));
    controller.extendStroke(const Offset(90, 0));
    controller.extendStroke(const Offset(120, 0));
    await controller.endStroke();

    await Future<void>.delayed(
      laserHoldDuration + const Duration(milliseconds: 950),
    );
    expect(controller.temporaryLaserStrokes, hasLength(1));
    expect(
      controller.temporaryLaserStrokes.single.firstPointIndex,
      greaterThan(0),
      reason: '消退应从起笔端推进，而非整条线同时变淡',
    );

    await Future<void>.delayed(
      laserSweepDuration +
          laserFinalFadeDuration +
          const Duration(milliseconds: 80),
    );
    expect(controller.temporaryLaserStrokes, isEmpty);
  });
}
