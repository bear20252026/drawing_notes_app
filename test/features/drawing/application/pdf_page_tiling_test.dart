// v1.17.20 无限画布「按纸张分页」导出——切片纯函数回归测试。
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';

void main() {
  group('sliceContentIntoPages', () {
    test('单页内的小内容 → 恰好 1 页（整页世界尺寸）', () {
      // A4 pt 595.28×841.89，scale=1 → 页世界尺寸 = 纸张尺寸。
      final pages = sliceContentIntoPages(
        const Rect.fromLTWH(0, 0, 500, 700),
        pageSize: const Size(595.28, 841.89),
        scale: 1,
      );
      expect(pages, hasLength(1));
      expect(pages.first.left, 0);
      expect(pages.first.top, 0);
      expect(pages.first.width, closeTo(595.28, 1e-6));
      expect(pages.first.height, closeTo(841.89, 1e-6));
    });

    test('横向 2.5 页宽 → 3 列；纵向 1.2 页高 → 2 行（ceil 语义）', () {
      // 页世界尺寸 100×100，内容 250×120 → 3 列 × 2 行。
      final pages = sliceContentIntoPages(
        const Rect.fromLTWH(10, 20, 250, 120),
        pageSize: const Size(100, 100),
        scale: 1,
      );
      expect(pages, hasLength(6));
      // 行优先：第一行三页 top 相同，第二行 top +100。
      expect(pages[0].top, 20);
      expect(pages[3].top, 120);
      // 横向步进 = 页宽。
      expect(pages[1].left, 110);
      expect(pages[2].left, 210);
    });

    test('负坐标内容（无限画布左上方向）正确偏移', () {
      final pages = sliceContentIntoPages(
        const Rect.fromLTWH(-150, -50, 100, 100),
        pageSize: const Size(100, 100),
        scale: 1,
      );
      expect(pages, hasLength(1));
      expect(pages.first.left, -150);
      expect(pages.first.top, -50);
    });

    test('scale>1（内容放大进纸）时页世界尺寸 = 纸张/scale', () {
      // 纸张 200×200，scale=2 → 每页承载 100×100 世界单位。
      final pages = sliceContentIntoPages(
        const Rect.fromLTWH(0, 0, 150, 150),
        pageSize: const Size(200, 200),
        scale: 2,
      );
      expect(pages, hasLength(4));
      expect(pages[1].left, 100);
      expect(pages[2].top, 100);
    });

    test('空内容 / 非法参数 → 空表', () {
      expect(
        sliceContentIntoPages(
          Rect.zero,
          pageSize: const Size(100, 100),
          scale: 1,
        ),
        isEmpty,
      );
      expect(
        sliceContentIntoPages(
          const Rect.fromLTWH(0, 0, 100, 100),
          pageSize: Size.zero,
          scale: 1,
        ),
        isEmpty,
      );
      expect(
        sliceContentIntoPages(
          const Rect.fromLTWH(0, 0, 100, 100),
          pageSize: const Size(100, 100),
          scale: 0,
        ),
        isEmpty,
      );
    });
  });
}
