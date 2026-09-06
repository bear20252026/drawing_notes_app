// M12 回归测试：橡皮擦渲染语义。
//
// 背景：像素橡皮擦以 BlendMode.clear 提交；此前 opacity=1 的图层在
// 主画布上直接渲染，clear 会把纸面背景一并清穿，露出底层黑色——
// 表现为"橡皮擦画出黑色线条"。修复后每层统一 saveLayer 隔离。
//
// 本测试在离屏 Picture 上复现"纸面 + 墨迹 + 橡皮擦"的组合，
// 逐像素验证：擦除区域应露出纸面（白），而非黑色。
import 'dart:ui' as ui;
import 'package:flutter/painting.dart' show Paint;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

void main() {
  test('BlendMode.clear 橡皮擦在隔离层内只清除墨迹，不产生黑色痕迹', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // 纸面（白）。
    canvas.drawRect(
      const Offset(0, 0) & const ui.Size(200, 200),
      Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    // 图层隔离（与 paintVectorLayers 修复后的结构一致）。
    canvas.saveLayer(const Offset(0, 0) & const ui.Size(200, 200), Paint());

    // 一条黑色墨迹（y=50 横线）。
    StrokeRenderer.drawStroke(
      canvas,
      Stroke(
        points: _points(20, 50, 180, 50),
        color: const ui.Color(0xFF000000),
        width: 6,
        type: BrushType.pen,
      ),
    );

    // 橡皮擦横穿墨迹（y=50，x=60..140）。
    StrokeRenderer.drawStroke(
      canvas,
      Stroke(
        points: _points(60, 50, 140, 50),
        color: const ui.Color(0x00000000),
        width: 12,
        type: BrushType.eraser,
      ),
    );

    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 200);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = bytes!.buffer.asUint8List();

    ui.Color pixelAt(double x, double y) {
      final offset = (y.toInt() * 200 + x.toInt()) * 4;
      return ui.Color.fromARGB(
        pixels[offset + 3],
        pixels[offset],
        pixels[offset + 1],
        pixels[offset + 2],
      );
    }

    // 未擦除区域：仍是黑墨。
    expect(pixelAt(30, 50), const ui.Color(0xFF000000));
    // 擦除中心：露出纸面（白），绝不能是黑色。
    final erased = pixelAt(100, 50);
    expect(
      erased,
      isNot(const ui.Color(0xFF000000)),
      reason: '擦除区域出现黑色 = clear 穿透到了纸面之下',
    );
    expect(erased.r * 255.0, greaterThan(200), reason: '擦除后应露出白色纸面');
  });
}

List<StrokePoint> _points(double x1, double y1, double x2, double y2) {
  final pts = <StrokePoint>[];
  for (var i = 0; i <= 20; i++) {
    final t = i / 20;
    pts.add(StrokePoint(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, 1.0));
  }
  return pts;
}
