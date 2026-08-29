// M11 契约测试：EdgelessController 工具面板（画笔/形状/橡皮/便签）。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Offset, Size;

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_controller.dart';

void main() {
  late EdgelessController controller;
  const viewport = Size(800, 600);

  setUp(() {
    controller = EdgelessController(doc: EdgelessDoc.empty('edoc'));
  });

  test('默认工具为选择', () {
    expect(controller.tool, EdgelessTool.select);
  });

  test('画笔：手势生命周期提交笔迹到 doc', () {
    controller.setTool(EdgelessTool.brush);
    controller.beginGesture(
      controller.camera.worldToScreen(const Offset(0, 0), viewport),
      1,
      viewport,
    );
    controller.updateGesture(
      controller.camera.worldToScreen(const Offset(50, 0), viewport),
      1.0,
      1,
      viewport,
    );
    controller.updateGesture(
      controller.camera.worldToScreen(const Offset(100, 10), viewport),
      1.0,
      1,
      viewport,
    );
    controller.endGesture();
    expect(controller.doc.strokes.length, 1);
    expect(controller.doc.strokes.single.pointCount, 3);
    // 单点笔迹（未拖动）不提交。
    controller.beginGesture(
      controller.camera.worldToScreen(const Offset(0, 0), viewport),
      1,
      viewport,
    );
    controller.endGesture();
    expect(controller.doc.strokes.length, 1);
  });

  test('形状：拖出手势提交形状，过小忽略', () {
    controller.setTool(EdgelessTool.shape);
    Offset toScreen(Offset w) => controller.camera.worldToScreen(w, viewport);
    controller.beginGesture(toScreen(const Offset(0, 0)), 1, viewport);
    controller.updateGesture(
      toScreen(const Offset(200, 100)),
      1.0,
      1,
      viewport,
    );
    controller.endGesture(
      lastLocalFocal: toScreen(const Offset(200, 100)),
      viewport: viewport,
    );
    expect(controller.doc.shapes.length, 1);
    final shape = controller.doc.shapes.single;
    expect(shape.x, 0);
    expect(shape.y, 0);
    expect(shape.w, 200);
    expect(shape.h, 100);

    // 过小形状（<6 世界单位）不提交。
    controller.beginGesture(toScreen(const Offset(0, 0)), 1, viewport);
    controller.endGesture(
      lastLocalFocal: toScreen(const Offset(3, 3)),
      viewport: viewport,
    );
    expect(controller.doc.shapes.length, 1);
  });

  test('橡皮：点按擦除笔迹', () {
    controller.setTool(EdgelessTool.brush);
    Offset toScreen(Offset w) => controller.camera.worldToScreen(w, viewport);
    controller.beginGesture(toScreen(const Offset(0, 0)), 1, viewport);
    controller.updateGesture(toScreen(const Offset(100, 0)), 1.0, 1, viewport);
    controller.endGesture();
    expect(controller.doc.strokes.length, 1);

    controller.setTool(EdgelessTool.eraser);
    // 命中笔迹（世界点 (50,1)，笔迹沿 x 轴）。
    controller.eraseAt(toScreen(const Offset(50, 1)), viewport);
    expect(controller.doc.strokes, isEmpty);
  });

  test('便签：点按创建 220x220 帧', () {
    controller.setTool(EdgelessTool.sticky);
    final center = controller.camera.worldToScreen(
      const Offset(500, 500),
      viewport,
    );
    controller.stickyAt(center, viewport);
    expect(controller.doc.frames.length, 1);
    final frame = controller.doc.frames.single;
    expect(frame.w, 220);
    expect(frame.h, 220);
    expect(frame.doc.title, '便签');
  });

  test('select 工具：原有拖帧/平移行为不受影响', () {
    // 添加一个帧，单指按住帧拖动。
    final withFrame = controller.doc.addFrame(
      NoteBlockDoc.empty('frame-doc'),
      at: const Offset(0, 0),
    );
    controller = EdgelessController(doc: withFrame);
    final frameScreen = controller.camera.worldToScreen(
      controller.doc.frames.first.rect.center,
      viewport,
    );
    controller.beginGesture(frameScreen, 1, viewport);
    controller.updateGesture(
      frameScreen + const Offset(30, 0),
      1.0,
      1,
      viewport,
    );
    controller.endGesture();
    expect(controller.doc.frames.first.x, 30);
  });
}
