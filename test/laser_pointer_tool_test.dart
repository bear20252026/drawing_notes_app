import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/temporary_ink_session.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
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
    // T-04（审计 2026-09-27）：注入假时钟——startedAt（起笔）与消退判定
    // 共用同一时钟源，时间显式推进，零真实延时且与机器快慢无关。
    var now = DateTime(2026, 1, 1, 12);
    final controller = DrawingController(
      DrawingDocument(id: 'laser_fade', title: '激光尾迹'),
      temporaryInkClock: () => now,
    );
    addTearDown(controller.dispose);

    controller.tool = BrushType.laser;
    controller.startStroke(const Offset(0, 0));
    controller.extendStroke(const Offset(30, 0));
    controller.extendStroke(const Offset(60, 0));
    controller.extendStroke(const Offset(90, 0));
    controller.extendStroke(const Offset(120, 0));
    await controller.endStroke();

    now = now.add(laserHoldDuration + const Duration(milliseconds: 950));
    expect(controller.temporaryLaserStrokes, hasLength(1));
    expect(
      controller.temporaryLaserStrokes.single.firstPointIndex,
      greaterThan(0),
      reason: '消退应从起笔端推进，而非整条线同时变淡',
    );

    now = now.add(
      laserSweepDuration +
          laserFinalFadeDuration +
          const Duration(milliseconds: 80),
    );
    expect(controller.temporaryLaserStrokes, isEmpty);
  });
}
