import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/presentation/canvas_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('三种纸张模板（网格/横线/点阵）均可无异常绘制', () {
    for (final type in [PaperType.grid, PaperType.lined, PaperType.dot]) {
      final document = DrawingDocument(
        id: 'paper_${type.name}',
        title: '纸张 ${type.name}',
        paperType: type,
      );
      final controller = DrawingController(document);
      addTearDown(controller.dispose);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      const size = ui.Size(400, 300);

      // paint 内部会调用 _paintPaperTemplate（非 infinite 文档），
      // 三种模板都应正常渲染而不抛异常。
      CanvasPainter(controller: controller).paint(canvas, size);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);
      picture.dispose();
    }
  });

  test('空白模板跳过背景绘制，不产生异常', () {
    final document = DrawingDocument(
      id: 'paper_blank',
      title: '空白',
      paperType: PaperType.blank,
    );
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    CanvasPainter(controller: controller).paint(
      canvas,
      const ui.Size(400, 300),
    );
    recorder.endRecording().dispose();
  });
}
