import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar_action_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _EditorToolbarActionsFixture buildFixture(_ActionLog log) =>
      _EditorToolbarActionsFixture(log);

  test('构建动作包不执行任一页面委托', () {
    final log = _ActionLog();

    buildFixture(log).actions;

    expect(log.events, isEmpty);
  });

  test('笔刷和视口动作保留无参数、布尔、数值和字符串委托', () {
    final log = _ActionLog();
    final actions = buildFixture(log).actions;

    actions.selectBrush();
    actions.selectEraser();
    actions.setPixelEraserMode(true);
    actions.setEraserCanEraseShapesStroke(false);
    actions.setEraserCanEraseShapesPixel(true);
    actions.setTemporaryMarkerEnabled(false);
    actions.showColorPicker();
    actions.onSizeChanged(12.5);
    actions.onBrushSelected('pen');
    actions.onToggleGrid();
    actions.onToggleSnap();
    actions.onFitToScreen();
    actions.onZoomIn();
    actions.onZoomOut();
    actions.onZoomReset();

    expect(log.events, [
      'brush.select',
      'brush.eraser',
      'brush.pixel:true',
      'brush.stroke-shapes:false',
      'brush.pixel-shapes:true',
      'brush.temporary:false',
      'brush.color',
      'brush.size:12.5',
      'brush.preset:pen',
      'viewport.grid',
      'viewport.snap',
      'viewport.fit',
      'viewport.in',
      'viewport.out',
      'viewport.reset',
    ]);
  });

  test('对象和形状动作保留页面命令与枚举、整数、浮点参数', () {
    final log = _ActionLog();
    final actions = buildFixture(log).actions;

    actions.selectEyedropper();
    actions.selectRect();
    actions.selectLasso();
    actions.selectText();
    actions.recolorAllText();
    actions.toggleLink();
    actions.showPagination();
    actions.addStickyNote();
    actions.cyclePaper();
    actions.insertImage();
    actions.onSelectedFontSize(18);
    actions.changeTextColor();
    actions.toggleBold();
    actions.toggleItalic();
    actions.toggleUnderline();
    actions.toggleStrikethrough();
    actions.cycleAlign();
    actions.editText();
    actions.deleteSelected();
    actions.onSelectShape(ShapeType.diamond);
    actions.setShapeFillEnabled(true);
    actions.onDistribute(false);
    actions.onShapeStrokeWidth(6);
    actions.onShapeOpacity(0.4);
    actions.onShapeFillColor();
    actions.onToggleMarquee();
    actions.onReorder(3);
    actions.onToggleDash();

    expect(log.events, [
      'object.eyedropper',
      'object.rect',
      'object.lasso',
      'object.text',
      'object.recolor',
      'object.link',
      'object.pagination',
      'object.sticky',
      'object.paper',
      'object.image',
      'object.font-size:18.0',
      'object.text-color',
      'object.bold',
      'object.italic',
      'object.underline',
      'object.strikethrough',
      'object.align',
      'object.edit',
      'object.delete',
      'shape.select:ShapeType.diamond',
      'shape.fill:true',
      'shape.distribute:false',
      'shape.stroke:6.0',
      'shape.opacity:0.4',
      'shape.fill-color',
      'shape.marquee',
      'shape.reorder:3',
      'shape.dash',
    ]);
  });
}

class _EditorToolbarActionsFixture {
  _EditorToolbarActionsFixture(_ActionLog log)
    : actions = EditorToolbarActionFactory.build(
        brush: EditorToolbarBrushActions(
          selectBrush: log.command('brush.select'),
          selectEraser: log.command('brush.eraser'),
          setPixelEraserMode: log.value('brush.pixel'),
          setEraserCanEraseShapesStroke: log.value('brush.stroke-shapes'),
          setEraserCanEraseShapesPixel: log.value('brush.pixel-shapes'),
          setTemporaryMarkerEnabled: log.value('brush.temporary'),
          showColorPicker: log.command('brush.color'),
          onSizeChanged: log.value('brush.size'),
          onBrushSelected: log.value('brush.preset'),
        ),
        object: EditorToolbarObjectActions(
          selectEyedropper: log.command('object.eyedropper'),
          selectRect: log.command('object.rect'),
          selectLasso: log.command('object.lasso'),
          selectText: log.command('object.text'),
          recolorAllText: log.command('object.recolor'),
          toggleLink: log.command('object.link'),
          showPagination: log.command('object.pagination'),
          addStickyNote: log.command('object.sticky'),
          cyclePaper: log.command('object.paper'),
          insertImage: log.command('object.image'),
          onSelectedFontSize: log.value('object.font-size'),
          changeTextColor: log.command('object.text-color'),
          toggleBold: log.command('object.bold'),
          toggleItalic: log.command('object.italic'),
          toggleUnderline: log.command('object.underline'),
          toggleStrikethrough: log.command('object.strikethrough'),
          cycleAlign: log.command('object.align'),
          editText: log.command('object.edit'),
          deleteSelected: log.command('object.delete'),
        ),
        shape: EditorToolbarShapeActions(
          onSelectShape: log.value('shape.select'),
          setShapeFillEnabled: log.value('shape.fill'),
          onDistribute: log.value('shape.distribute'),
          onShapeStrokeWidth: log.value('shape.stroke'),
          onShapeOpacity: log.value('shape.opacity'),
          onShapeFillColor: log.command('shape.fill-color'),
          onToggleMarquee: log.command('shape.marquee'),
          onReorder: log.value('shape.reorder'),
          onToggleDash: log.command('shape.dash'),
        ),
        viewport: EditorToolbarViewportActions(
          onToggleGrid: log.command('viewport.grid'),
          onToggleSnap: log.command('viewport.snap'),
          onFitToScreen: log.command('viewport.fit'),
          onZoomIn: log.command('viewport.in'),
          onZoomOut: log.command('viewport.out'),
          onZoomReset: log.command('viewport.reset'),
        ),
      );

  final EditorToolbarActions actions;
}

class _ActionLog {
  final List<String> events = [];

  VoidCallback command(String name) =>
      () => events.add(name);

  ValueChanged<T> value<T>(String name) =>
      (value) => events.add('$name:$value');
}
