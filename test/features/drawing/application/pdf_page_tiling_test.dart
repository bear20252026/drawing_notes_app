// v1.17.20 无限画布「按纸张分页」导出——切片纯函数回归测试。
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/drawing/application/pdf_export_options.dart';

void main() {
  group('sliceContentIntoPages', () {
    test('单页内的小内容 → 恰好 1 页（整页世界尺寸，内容居中）', () {
      // A4 pt 595.28×841.89，scale=1 → 页世界尺寸 = 纸张尺寸。
      // 审计 #28：单页 tile 内容居中（与单页大图档成页观感一致）。
      final pages = sliceContentIntoPages(
        const Rect.fromLTWH(0, 0, 500, 700),
        pageSize: const Size(595.28, 841.89),
        scale: 1,
      );
      expect(pages, hasLength(1));
      expect(pages.first.width, closeTo(595.28, 1e-6));
      expect(pages.first.height, closeTo(841.89, 1e-6));
      // 内容中心 = 页中心。
      expect(pages.first.center.dx, closeTo(250, 1e-6));
      expect(pages.first.center.dy, closeTo(350, 1e-6));
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

    // v1.17.22 页序档位：columnMajor（先纵后横）。
    group('columnMajor 页序', () {
      List<Rect> slice({required bool columnMajor}) => sliceContentIntoPages(
        const Rect.fromLTWH(10, 20, 250, 120),
        pageSize: const Size(100, 100),
        scale: 1,
        columnMajor: columnMajor,
      );

      test('先纵后横：页序按列推进（纵向长内容书写方向）', () {
        final pages = slice(columnMajor: true);
        expect(pages, hasLength(6)); // 3 列 × 2 行，总数不变。
        // 第 1 页 = (列0,行0)。
        expect(pages[0].left, 10);
        expect(pages[0].top, 20);
        // 第 2 页 = (列0,行1)——纵向下移一页。
        expect(pages[1].left, 10);
        expect(pages[1].top, 120);
        // 第 3 页 = (列1,行0)——回顶部、右移一列。
        expect(pages[2].left, 110);
        expect(pages[2].top, 20);
        // 末页 = (列2,行1)。
        expect(pages[5].left, 210);
        expect(pages[5].top, 120);
      });

      test('与默认行优先逐页集合相同（仅顺序不同）', () {
        final rowMajor = slice(columnMajor: false);
        final columnMajor = slice(columnMajor: true);
        expect(columnMajor, hasLength(rowMajor.length));
        // 同一集合：任意页在两个序里都存在且位置一致。
        for (final tile in rowMajor) {
          expect(columnMajor.contains(tile), isTrue);
        }
      });

      test('单列内容：两种页序等价', () {
        final a = sliceContentIntoPages(
          const Rect.fromLTWH(0, 0, 100, 250),
          pageSize: const Size(100, 100),
          scale: 1,
          columnMajor: true,
        );
        final b = sliceContentIntoPages(
          const Rect.fromLTWH(0, 0, 100, 250),
          pageSize: const Size(100, 100),
          scale: 1,
        );
        expect(a, b);
      });
    });

    // v1.17.23 审计修复 #27：maxPages 上限前置——超限在网格物化前拦截，
    // 防固定输出 scale 下超大包围盒生成海量 Rect 卡主 isolate。
    group('maxPages 上限前置', () {
      test('rows×cols 超限 → 空表（不物化网格）', () {
        // 内容 250×120 → 3 列 × 2 行 = 6 页；上限 5 页 → 空表。
        final pages = sliceContentIntoPages(
          const Rect.fromLTWH(10, 20, 250, 120),
          pageSize: const Size(100, 100),
          scale: 1,
          maxPages: 5,
        );
        expect(pages, isEmpty);
      });

      test('恰好等于上限 → 正常返回全表', () {
        final pages = sliceContentIntoPages(
          const Rect.fromLTWH(10, 20, 250, 120),
          pageSize: const Size(100, 100),
          scale: 1,
          maxPages: 6,
        );
        expect(pages, hasLength(6));
      });

      test('null 上限 = 不限制（既有行为）', () {
        final pages = sliceContentIntoPages(
          const Rect.fromLTWH(10, 20, 250, 120),
          pageSize: const Size(100, 100),
          scale: 1,
        );
        expect(pages, hasLength(6));
      });

      test('kPdfTiledOutputScale = 1.0（审计 #1 回归锁）：分页输出口径', () {
        // 固定输出 scale——历史上此口径曾错用 fitContentOnPaper（保证
        // 整幅内容放进一张纸 → 切片恒 1×1 单页，页序/页脚/进度全链路
        // 不可达多页）。锁死常量防回潮。
        expect(kPdfTiledOutputScale, 1.0);
        // 生产等价输入：A4 纸 + 固定 scale，横向 2 页宽内容 → 2 页。
        final pages = sliceContentIntoPages(
          const Rect.fromLTWH(0, 0, 800, 700),
          pageSize: const Size(595.28, 841.89),
          scale: kPdfTiledOutputScale,
        );
        expect(pages, hasLength(2));
        expect(pages[1].left, closeTo(595.28, 1e-6));
      });
    });
  });
}
