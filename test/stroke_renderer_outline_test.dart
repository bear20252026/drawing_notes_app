import 'dart:ui';

import 'package:drawing_notes_app/infrastructure/rendering/stroke_renderer.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke _thickStroke() => Stroke(
  type: BrushType.pen,
  color: 0xFF1A1A1A,
  width: 32,
  points: [
    const StrokePoint(10, 50, 0.25),
    const StrokePoint(28, 46, 0.95),
    const StrokePoint(48, 55, 0.30),
    const StrokePoint(72, 44, 0.88),
    const StrokePoint(100, 50, 0.55),
  ],
);

void main() {
  test('粗笔压感输入生成连续的闭合填充轮廓', () {
    final outline = StrokeRenderer.strokeOutline(_thickStroke());

    expect(outline, isNotNull);
    final metrics = outline!.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.single.length, greaterThan(150));

    final bounds = outline.getBounds();
    expect(bounds.left, lessThan(10));
    expect(bounds.right, greaterThan(100));
    expect(bounds.height, greaterThan(20));
  });

  test('书写中的预览轮廓同样可连贯覆盖整个笔迹范围', () {
    final complete = StrokeRenderer.strokeOutline(_thickStroke());
    final preview = StrokeRenderer.strokeOutline(
      _thickStroke(),
      isComplete: false,
    );

    expect(preview, isNotNull);
    expect(preview!.getBounds().left, lessThanOrEqualTo(10));
    expect(preview.getBounds().right, greaterThan(70));
    expect(complete!.getBounds().width, greaterThan(preview.getBounds().width));
  });

  test('固定宽度高亮笔不读取压感，生成稳定轮廓', () {
    final marker = Stroke(
      type: BrushType.marker,
      color: 0xFFFFD54F,
      width: 24,
      points: [const StrokePoint(0, 0, 0.1), const StrokePoint(100, 0, 0.9)],
    );

    final outline = StrokeRenderer.strokeOutline(marker, usePressure: false);

    expect(outline, isNotNull);
    expect(outline!.getBounds().height, closeTo(24, 3));
  });

  test('完成笔画的轮廓被惰性缓存，点列替换后失效重建', () {
    final stroke = _thickStroke();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // 首次绘制前无缓存。
    expect(StrokeRenderer.cachedOutlineFor(stroke, usePressure: true), isNull);

    // 首次绘制计算并缓存，压感/非压感槽位独立。
    StrokeRenderer.drawStroke(canvas, stroke);
    final cached = StrokeRenderer.cachedOutlineFor(stroke, usePressure: true);
    expect(cached, isNotNull);
    expect(
      StrokeRenderer.cachedOutlineFor(stroke, usePressure: false),
      isNull,
      reason: '非压感槽位不应被压感绘制污染',
    );

    // 再次绘制命中同一 Path 实例，避免重复计算。
    StrokeRenderer.drawStroke(canvas, stroke);
    expect(
      StrokeRenderer.cachedOutlineFor(stroke, usePressure: true),
      same(cached),
    );

    // 预览（未完成）笔画不缓存。
    expect(
      StrokeRenderer.cachedOutlineFor(stroke, usePressure: true),
      isNotNull,
    );

    // 点列替换（收笔/编辑）使缓存失效，下次绘制重建。
    stroke.replacePoints([
      ...stroke.points,
      const StrokePoint(120, 60, 0.5),
    ]);
    expect(StrokeRenderer.cachedOutlineFor(stroke, usePressure: true), isNull);
    StrokeRenderer.drawStroke(canvas, stroke);
    expect(StrokeRenderer.cachedOutlineFor(stroke, usePressure: true), isNotNull);
  });
}
