import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/document_codec.dart';

/// 大文档性能基准（专家审查建议补充 2026-08-15）：
/// 1000+ 笔画大文档的序列化/反序列化耗时基线——宽松上限防 CI 环境
/// 抖动误报，主要防严重性能退化回归（如 O(N²) 重构）。
void main() {
  test('1200 笔画大文档：编解码耗时基线（防严重退化）', () {
    final document = DrawingDocument(id: 'perf_1200', title: '性能基准');
    final rng = Random(42);
    for (var i = 0; i < 1200; i++) {
      final points = List.generate(
        20,
        (j) => StrokePoint(
          rng.nextDouble() * 800,
          rng.nextDouble() * 600,
          0.5,
        ),
      );
      document.layers.single.strokes.add(
        Stroke(
          points: points,
          color: const Color(0xFF000000),
          width: 2,
          type: BrushType.pen,
        ),
      );
    }
    expect(document.layers.single.strokes.length, 1200);

    final codec = DocumentCodec();
    final encodeWatch = Stopwatch()..start();
    final bytes = codec.encode(document);
    encodeWatch.stop();

    final decodeWatch = Stopwatch()..start();
    final decoded = codec.decode(bytes);
    decodeWatch.stop();

    // 内容保真（防"为快而丢"）。
    expect(decoded.layers.single.strokes.length, 1200);
    // 宽松基线：1200 笔画（24000 点）序列化/反序列化应在秒级完成。
    // CI 慢机留 10 倍余量，仅拦严重性能退化（如意外 O(N²)）。
    expect(
      encodeWatch.elapsedMilliseconds,
      lessThan(5000),
      reason: '序列化耗时基线（1200 笔画）：${encodeWatch.elapsedMilliseconds}ms',
    );
    expect(
      decodeWatch.elapsedMilliseconds,
      lessThan(10000),
      reason: '反序列化耗时基线（1200 笔画）：${decodeWatch.elapsedMilliseconds}ms',
    );
  });
}
