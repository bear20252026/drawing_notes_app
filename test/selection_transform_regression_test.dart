import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> addLine(
    DrawingController controller,
    Offset from,
    Offset to,
  ) async {
    controller.startStroke(from);
    controller.extendStroke(to);
    await controller.endStroke();
  }

  test('稀疏长笔画穿过矩形选区时也能被圈中', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'lasso-cross', title: '套索交叉'),
    );
    await addLine(controller, const Offset(-100, 0), const Offset(100, 0));

    controller.selectionTool = SelectionTool.rect;
    controller.beginSelection(const Offset(-10, -10));
    controller.extendSelection(const Offset(10, 10));
    controller.endSelection();

    expect(controller.hasSelectedStrokes, isTrue);
    controller.dispose();
  });

  test('缩放围绕实际选中笔画中心，不围绕大套索中心漂移', () async {
    final controller = DrawingController(
      DrawingDocument(id: 'lasso-center', title: '套索中心'),
    );
    await addLine(controller, const Offset(90, 100), const Offset(110, 100));

    controller.selectionTool = SelectionTool.rect;
    // 故意画出远大于内容的选区；旧实现会围绕 (0,0) 缩放。
    controller.beginSelection(const Offset(-1000, -1000));
    controller.extendSelection(const Offset(1000, 1000));
    controller.endSelection();
    controller.scaleSelectedStrokes(2);
    controller.endTransform();

    final points = controller.document.layers.single.strokes.single.points;
    expect(points.first.offset, const Offset(80, 100));
    expect(points.last.offset, const Offset(120, 100));
    controller.dispose();
  });

  // P-05（审计 2026-09-27）回归锁：变换撤销从整层双份快照改为窄命令
  // （TransformStrokesCommand，只记受影响笔画三元组）。锁三件事：
  // ①撤销按三元组恢复**原对象**（identity）——不是内容相等的副本；
  // ②与删除（整层快照命令）交错时 LIFO 仍精确还原（窄命令按索引覆写
  // 的前提是栈中上方命令忠实还原，快照命令满足）；
  // ③重做对称恢复变换后对象。
  test('P-05：变换撤销走窄命令，与快照命令交错时 LIFO 精确还原', () async {
    final controller = DrawingController(
      DrawingDocument(
        id: 'narrow-transform',
        title: '窄命令变换',
        layers: <Layer>[
          Layer(id: 'work', name: 'work'),
          Layer(id: 'other', name: 'other'),
        ],
      ),
    );
    await addLine(controller, const Offset(0, 0), const Offset(10, 0));
    await addLine(controller, const Offset(100, 0), const Offset(110, 0));
    final originals = List.of(controller.document.layers[0].strokes);
    expect(originals, hasLength(2));

    controller.selectionTool = SelectionTool.rect;
    controller.beginSelection(const Offset(-5, -5));
    controller.extendSelection(const Offset(115, 5));
    controller.endSelection();
    expect(controller.hasSelectedStrokes, isTrue);

    controller.moveSelectedStrokes(const Offset(30, 0));
    controller.endTransform();
    final transformed = List.of(controller.document.layers[0].strokes);
    expect(identical(transformed[0], originals[0]), isFalse,
        reason: '变换以新 Stroke 对象替换点列');

    // 紧接着删除（整层快照命令）——栈变为 [Add0, Add1, 变换, 删除]。
    controller.deleteSelectedStrokes();
    expect(controller.document.layers[0].strokes, isEmpty);

    // 撤销删除：快照按引用还原变换后对象。
    controller.undo();
    final afterUnDelete = controller.document.layers[0].strokes;
    expect(afterUnDelete, hasLength(2));
    expect(identical(afterUnDelete[0], transformed[0]), isTrue,
        reason: '快照命令按引用还原变换后对象');
    // 撤销变换：窄命令在其上按三元组精确覆写回原对象。
    controller.undo();
    final restored = controller.document.layers[0].strokes;
    expect(identical(restored[0], originals[0]), isTrue,
        reason: '窄命令 undo 必须放回变换前的原对象');
    expect(identical(restored[1], originals[1]), isTrue);
    expect(restored[0].points.first.offset, const Offset(0, 0));
    expect(restored[1].points.first.offset, const Offset(100, 0));

    // 重做对称：先变换后删除。
    controller.redo();
    expect(
      identical(controller.document.layers[0].strokes[0], transformed[0]),
      isTrue,
    );
    controller.redo();
    expect(controller.document.layers[0].strokes, isEmpty);
    controller.dispose();
  });
}