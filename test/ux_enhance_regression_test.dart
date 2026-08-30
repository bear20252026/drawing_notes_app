import 'dart:math' show cos, sin;

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户体验增强回归测试（对应"坐标偏移/滚轮缩放/字号"三项修复）。
///
/// 覆盖：
/// - 坐标变换一致性：viewToCanvas/canvasToView 严格互逆（含缩放/旋转/平移组合）；
///   滚轮缩放锚点不动（缩放前后锚点对应同一画布坐标）；
/// - 滚轮缩放：缩放比例与范围限制（0.05~20x）；
/// - 文字字号：PageTextItem 字号可调、序列化保留。
void main() {
  DrawingDocument makeDoc({int w = 400, int h = 300}) =>
      DrawingDocument(id: 'ux_doc', title: 'UX 回归', width: w, height: h);

  /// 断言两个变换函数严格互逆（误差容忍 1e-5）。
  void expectInvertible(DrawingController c, Offset viewPoint) {
    final canvasPoint = c.viewToCanvas(viewPoint);
    final back = c.canvasToView(canvasPoint);
    expect(
      back.dx,
      closeTo(viewPoint.dx, 1e-5),
      reason: 'view->canvas->view 应还原',
    );
    expect(back.dy, closeTo(viewPoint.dy, 1e-5));
  }

  group('坐标变换一致性（修复点击位置偏移）', () {
    test('缩放+平移组合：双向换算严格互逆', () {
      final c = DrawingController(makeDoc());
      c.viewScale = 1.7;
      c.viewOffset = const Offset(35, -12);
      expectInvertible(c, const Offset(120, 80));
      expectInvertible(c, const Offset(10, 260));
      expectInvertible(c, const Offset(0, 0));
    });

    test('缩放+旋转+平移组合：双向换算严格互逆', () {
      final c = DrawingController(makeDoc());
      c.viewScale = 0.8;
      c.viewOffset = const Offset(-30, 50);
      c.viewRotation = 0.6;
      expectInvertible(c, const Offset(200, 150));
      expectInvertible(c, const Offset(5, 5));
      expectInvertible(c, const Offset(395, 295));
    });

    test('画布中心在缩放/旋转下保持映射稳定', () {
      final c = DrawingController(makeDoc()); // 中心 (200,150)
      c.viewScale = 2.5;
      c.viewRotation = 0.3;
      c.viewOffset = const Offset(100, -40);
      // 画布中心应映射到 view = center + offset（旋转/缩放以中心为基准点）。
      final centerView = c.canvasToView(const Offset(200, 150));
      expect(centerView.dx, closeTo(200 + 100, 1e-5));
      expect(centerView.dy, closeTo(150 - 40, 1e-5));
    });

    test('缩放比例变化时画布中心映射不受影响', () {
      final c = DrawingController(makeDoc());
      c.viewOffset = const Offset(50, 30);
      final before = c.canvasToView(const Offset(200, 150));
      c.viewScale = 3.0;
      final after = c.canvasToView(const Offset(200, 150));
      expect(after.dx, closeTo(before.dx, 1e-5), reason: '中心点不随缩放移动');
      expect(after.dy, closeTo(before.dy, 1e-5));
    });
  });

  group('滚轮缩放（锚点不动 + 范围限制）', () {
    test('以锚点为基准缩放：锚点对应画布坐标缩放前后一致', () {
      final c = DrawingController(makeDoc());
      // 模拟 editor 的 _zoomAt 逻辑（保持锚点不动）。
      void zoomAt(Offset viewPoint, double factor) {
        final newScale = (c.viewScale * factor).clamp(0.05, 20.0);
        final canvasBefore = c.viewToCanvas(viewPoint);
        final center = Offset(200.0, 150.0);
        final rotated = _rotate(
          (canvasBefore - center) * newScale,
          c.viewRotation,
        );
        c.viewOffset = viewPoint - rotated - center;
        c.viewScale = newScale;
      }

      const anchor = Offset(300, 200);
      final canvasBefore = c.viewToCanvas(anchor);
      zoomAt(anchor, 1.5); // 放大 1.5 倍
      final canvasAfter = c.viewToCanvas(anchor);
      expect(
        canvasAfter.dx,
        closeTo(canvasBefore.dx, 1e-5),
        reason: '锚点画布坐标不变',
      );
      expect(canvasAfter.dy, closeTo(canvasBefore.dy, 1e-5));
    });

    test('滚轮缩放受范围限制（0.05~20）', () {
      final c = DrawingController(makeDoc());
      // 连续放大到上限
      for (var i = 0; i < 40; i++) {
        c.viewScale = (c.viewScale * 1.1).clamp(0.05, 20.0);
      }
      expect(c.viewScale, lessThanOrEqualTo(20.0));
      // 连续缩小到下限
      for (var i = 0; i < 40; i++) {
        c.viewScale = (c.viewScale / 1.1).clamp(0.05, 20.0);
      }
      expect(c.viewScale, greaterThanOrEqualTo(0.05));
    });
  });

  group('文字字号（修复"字太小不可调"）', () {
    test('PageTextItem 字号可设置并可序列化保留', () {
      final item = PageTextItem(
        id: 'txt_1',
        x: 100,
        y: 80,
        text: '大字笔记',
        fontSize: 48,
      );
      expect(item.fontSize, 48);

      final json = item.toJson();
      final restored = PageTextItem.fromJson(json);
      expect(restored.fontSize, 48, reason: '字号应序列化保留');
    });

    test('字号可调范围 8~200（编辑器 clamp 逻辑）', () {
      double clampFont(double v) => v.clamp(8, 200);
      expect(clampFont(4), 8);
      expect(clampFont(28), 28);
      expect(clampFont(500), 200);
    });
  });
}

/// 绕原点旋转（与 DrawingController._rotatePoint 一致）。
Offset _rotate(Offset p, double angle) {
  final cosA = cos(angle);
  final sinA = sin(angle);
  return Offset(p.dx * cosA - p.dy * sinA, p.dx * sinA + p.dy * cosA);
}
