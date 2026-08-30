import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7 验收测试：体验打磨（引擎层可测部分）。
///
/// 验收标准（来自开发计划 4.3 Phase 7）：
/// - 深色模式（UI 部分，见 app/theme 实现）
/// - 手势：双指缩放画布、双指旋转画布（控制器视口变换，本文件验证）
/// - 全屏模式（UI 部分）
/// - 简单的首次启动引导提示（UI 部分）
/// - 整体操作顺手，没有明显卡顿，UI 在深色/浅色模式下都正常显示
///
/// 说明：双指手势的"视口变换"逻辑在 [DrawingController] 中，
/// 可独立单元测试；UI 层交互（深色切换按钮/全屏按钮/引导对话框）
/// 通过代码评审与双端构建验证。
void main() {
  DrawingDocument makeDoc() =>
      DrawingDocument(id: 't7', title: '测试画布', width: 400, height: 300);

  group('Phase 7 体验打磨（视口变换）', () {
    test('画布缩放：viewScale 围绕画布中心生效于坐标换算', () {
      final c = DrawingController(makeDoc()); // 400x300，中心 (200,150)
      c.viewScale = 2.0;
      c.viewOffset = Offset.zero;

      // 新变换模型：view = R·(scale·(p - center)) + center + offset
      // 视图坐标 (100,100) -> 画布坐标 (150,125)：
      //   ((100,100)-(200,150))/2 + (200,150) = (-50,-25)+(200,150) = (150,125)
      final canvasPoint = c.viewToCanvas(const Offset(100, 100));
      expect(canvasPoint.dx, closeTo(150, 1e-6));
      expect(canvasPoint.dy, closeTo(125, 1e-6));

      // 画布中心 (200,150) 映射到视图中心（scale=2 时 offset=0 居中）。
      final centerView = c.canvasToView(const Offset(200, 150));
      expect(centerView.dx, closeTo(200, 1e-6));
      expect(centerView.dy, closeTo(150, 1e-6));

      // 反向换算一致。
      final back = c.canvasToView(canvasPoint);
      expect(back.dx, closeTo(100, 1e-6));
      expect(back.dy, closeTo(100, 1e-6));
    });

    test('画布平移：viewOffset 参与坐标换算', () {
      final c = DrawingController(makeDoc()); // 400x300，中心 (200,150)
      c.viewScale = 1.0;
      c.viewOffset = const Offset(20, -10);

      // view = (p - center) + center + offset = p + offset
      final canvasPoint = c.viewToCanvas(const Offset(100, 100));
      expect(canvasPoint.dx, closeTo(80, 1e-6));
      expect(canvasPoint.dy, closeTo(110, 1e-6));

      // 反向一致。
      final back = c.canvasToView(canvasPoint);
      expect(back.dx, closeTo(100, 1e-6));
      expect(back.dy, closeTo(100, 1e-6));
    });

    test('画布旋转：viewRotation 参与坐标换算且可逆', () {
      final c = DrawingController(makeDoc());
      c.viewScale = 1.0;
      c.viewRotation = 0.5; // 约 28.6°

      const viewPoint = Offset(120, 80);
      final canvasPoint = c.viewToCanvas(viewPoint);
      final back = c.canvasToView(canvasPoint);
      expect(back.dx, closeTo(viewPoint.dx, 1e-6));
      expect(back.dy, closeTo(viewPoint.dy, 1e-6));
    });

    test('缩放+平移+旋转组合变换可逆', () {
      final c = DrawingController(makeDoc());
      c.viewScale = 1.7;
      c.viewOffset = const Offset(35, -12);
      c.viewRotation = -0.8;

      const viewPoint = Offset(200, 150);
      final canvasPoint = c.viewToCanvas(viewPoint);
      final back = c.canvasToView(canvasPoint);
      expect(back.dx, closeTo(viewPoint.dx, 1e-5));
      expect(back.dy, closeTo(viewPoint.dy, 1e-5));
    });

    test('视口变换不影响笔画数据（只影响显示）', () async {
      final c = DrawingController(makeDoc());
      c.viewScale = 3.0;
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      await c.endStroke();

      final stroke = c.document.layers.first.strokes.first;
      expect(stroke.points.first.offset.dx, 10, reason: '笔画坐标仍为画布坐标');
      expect(stroke.points.last.offset.dx, 20);
    });
  });
}
