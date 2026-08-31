import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Rect;

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/shape_creation_geometry.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_binding_geometry.dart';
import 'package:drawing_notes_app/features/drawing/rendering/shape_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShapeCreationGeometry.fromDrag 线性元素方向', () {
    // 画布坐标系：x 向右，y 向下。
    test('左上→右下拖拽：start 在左上、end 在右下', () {
      final shape = ShapeCreationGeometry.fromDrag(
        const Offset(10, 20),
        const Offset(210, 120),
      ).createShape(
        id: 'a',
        shapeType: ShapeType.arrow,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      expect(shape.lineStart, const Offset(0, 0));
      expect(shape.lineEnd, const Offset(200, 100));
    });

    test('右上→左下拖拽：start 在右上、end 在左下（不被镜像）', () {
      final shape = ShapeCreationGeometry.fromDrag(
        const Offset(210, 20),
        const Offset(10, 120),
      ).createShape(
        id: 'a',
        shapeType: ShapeType.arrow,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      expect(shape.x, 10);
      expect(shape.y, 20);
      expect(shape.lineStart, const Offset(200, 0));
      expect(shape.lineEnd, const Offset(0, 100));
    });

    test('左下→右上拖拽：start 在左下、end 在右上', () {
      final shape = ShapeCreationGeometry.fromDrag(
        const Offset(10, 120),
        const Offset(210, 20),
      ).createShape(
        id: 'a',
        shapeType: ShapeType.arrow,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      expect(shape.lineStart, const Offset(0, 100));
      expect(shape.lineEnd, const Offset(200, 0));
    });

    test('右下→左上拖拽：start 在右下、end 在左上', () {
      final shape = ShapeCreationGeometry.fromDrag(
        const Offset(210, 120),
        const Offset(10, 20),
      ).createShape(
        id: 'a',
        shapeType: ShapeType.arrow,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      expect(shape.lineStart, const Offset(200, 100));
      expect(shape.lineEnd, const Offset(0, 0));
    });

    test('单击放置线性元素：端点置空回退默认对角线（不退化为零长度）', () {
      final geometry = ShapeCreationGeometry.fromDrag(
        const Offset(100, 80),
        const Offset(101, 81),
      );
      final arrow = geometry.createShape(
        id: 'a',
        shapeType: ShapeType.arrow,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      expect(arrow.lineStart, isNull);
      expect(arrow.lineEnd, isNull);

      final line = geometry.createShape(
        id: 'l',
        shapeType: ShapeType.line,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      expect(line.lineStart, isNull);
      expect(line.lineEnd, isNull);
    });
  });

  group('ShapeBindingGeometry.applyArrowEndpoints 端点规范', () {
    test('写入相对外接框的真实端点并归零 flip（方向单一来源）', () {
      final arrow = PageShapeItem(
        id: 'a',
        shapeType: ShapeType.arrow,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        color: 0xFF000000,
        strokeWidth: 2,
        flipX: true,
        flipY: true,
      );
      ShapeBindingGeometry.applyArrowEndpoints(
        arrow,
        start: const Offset(300, 50),
        end: const Offset(100, 250),
      );
      expect(arrow.x, 100);
      expect(arrow.y, 50);
      expect(arrow.width, 200);
      expect(arrow.height, 200);
      expect(arrow.flipX, isFalse);
      expect(arrow.flipY, isFalse);
      expect(arrow.lineStart, const Offset(200, 0));
      expect(arrow.lineEnd, const Offset(0, 200));
    });
  });

  group('ShapeRenderer.drawDocumentShape 方向渲染（像素级回归）', () {
    // 回归背景：渲染器曾对已保存真实端点的线性元素再施加 flipX/flipY
    // 镜像，导致四个对角方向全部坍缩为"左上→右下"（用户从右上往左下
    // 画箭头时方向被吞掉）。本用例渲染一个"右上→左下"的箭头，断言
    // 箭头头部（末端）确实落在左下角。
    Future<Map<String, int>> renderCornerInk(PageShapeItem shape) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        ui.Paint()..color = const Color(0xFFFFFFFF),
      );
      ShapeRenderer.drawDocumentShape(canvas, shape);
      final image = await recorder.endRecording().toImage(100, 100);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final bytes = data!.buffer.asUint8List();

      int inkInCorner(int x0, int y0) {
        var count = 0;
        for (var y = y0; y < y0 + 20; y++) {
          for (var x = x0; x < x0 + 20; x++) {
            final i = (y * 100 + x) * 4;
            // 非白色即视为墨迹（线/箭头为黑色）。
            if (bytes[i] < 128) count++;
          }
        }
        return count;
      }

      return {
        'topLeft': inkInCorner(0, 0),
        'topRight': inkInCorner(80, 0),
        'bottomLeft': inkInCorner(0, 80),
        'bottomRight': inkInCorner(80, 80),
      };
    }

    test('从右上画到左下的箭头：箭头头部在左下而非右下', () async {
      final shape = PageShapeItem(
        id: 'a',
        shapeType: ShapeType.arrow,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        color: 0xFF000000,
        strokeWidth: 2,
        // 模拟 fromDrag 保存的真实数据：端点为真实方向，flip 同时被
        // 记录——渲染端必须以端点为准，不能再镜像。
        flipX: true,
        flipY: true,
        lineStart: const Offset(100, 0),
        lineEnd: const Offset(0, 100),
      );
      final ink = await renderCornerInk(shape);
      // 修复前：双重翻转把线画成左上→右下，右上角完全无墨、箭头头部
      // 错误地落在右下角。修复后：起点(右上)有线经过，头部(左下)墨迹
      // 明显多于终点对角与起点。
      expect(ink['topRight']!, greaterThan(0), reason: '起点(右上)应有线段经过');
      expect(ink['bottomLeft']!, greaterThan(ink['topRight']!),
          reason: '末端(左下)应比起点有更多墨迹（箭头头部）');
      expect(ink['bottomRight']! * 2, lessThan(ink['bottomLeft']!),
          reason: '修复前箭头头部错误地出现在右下角');
    });

    test('无端点旧文档回退对角线仍可渲染（向后兼容）', () async {
      final shape = PageShapeItem(
        id: 'a',
        shapeType: ShapeType.line,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        color: 0xFF000000,
        strokeWidth: 2,
      );
      final ink = await renderCornerInk(shape);
      // 默认对角线为左下→右上，四个角附近的对角区域都应有墨迹。
      expect(ink['topRight']!, greaterThan(0));
      expect(ink['bottomLeft']!, greaterThan(0));
    });
  });
}
