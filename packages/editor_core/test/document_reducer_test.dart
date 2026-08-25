import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 专家 I-006（2026-08-18——批次 C）：DocumentReducer 测试——
/// 命令模式（state + command → new state + inverse command）+ 撤销/重做。
void main() {
  late DocumentV2 doc;
  late DocumentReducer reducer;

  setUp(() {
    // 创建带 layer 的文档（命令需要找到 layerId）。
    const layer = LayerV2(id: 'l1', name: 'Layer 1');
    doc = const DocumentV2(id: 'doc1', pageCount: 1, layers: [layer]);
    reducer = DocumentReducer(doc);
  });

  test('DocumentReducer：初始状态', () {
    expect(reducer.current, doc);
    expect(reducer.canUndo, false);
    expect(reducer.canRedo, false);
  });

  test('AddStrokeCommand：执行命令后状态更新', () {
    final stroke = LineItem(id: 's1', points: [Point(0, 0), Point(10, 10)]);
    final cmd = AddStrokeCommand(layerId: 'l1', stroke: stroke);
    
    final newState = reducer.execute(cmd);
    expect(newState.revision, 1);
    expect(newState.layers.first.strokes.length, 1);
    expect(reducer.canUndo, true);
    expect(reducer.canRedo, false);
  });

  test('AddStrokeCommand：撤销后恢复', () {
    final stroke = LineItem(id: 's1', points: [Point(0, 0), Point(10, 10)]);
    final cmd = AddStrokeCommand(layerId: 'l1', stroke: stroke);
    
    reducer.execute(cmd);
    final undone = reducer.undo();
    expect(undone, isNotNull);
    expect(undone!.revision, 0); // 恢复到初始状态
    expect(undone.layers.first.strokes.length, 0);
    expect(reducer.canRedo, true);
  });

  test('AddStrokeCommand：重做后恢复', () {
    final stroke = LineItem(id: 's1', points: [Point(0, 0), Point(10, 10)]);
    final cmd = AddStrokeCommand(layerId: 'l1', stroke: stroke);
    
    reducer.execute(cmd);
    reducer.undo();
    final redone = reducer.redo();
    expect(redone, isNotNull);
    expect(redone!.revision, 1);
    expect(redone.layers.first.strokes.length, 1);
    expect(reducer.canUndo, true);
  });

  test('CreateShapeCommand：执行命令', () {
    final shape = ShapeItem(
      id: 'shape1',
      type: 'rect',
      x: 10,
      y: 20,
      width: 100,
      height: 80,
    );
    final cmd = CreateShapeCommand(layerId: 'l1', shape: shape);
    
    final newState = reducer.execute(cmd);
    expect(newState.revision, 1);
    expect(newState.layers.first.shapes.length, 1);
    expect(reducer.canUndo, true);
  });

  test('CreateTextCommand：执行命令', () {
    final text = TextItem(id: 'text1', content: 'Hello', x: 50, y: 50);
    final cmd = CreateTextCommand(layerId: 'l1', text: text);
    
    final newState = reducer.execute(cmd);
    expect(newState.revision, 1);
    expect(newState.layers.first.texts.length, 1);
    expect(reducer.canUndo, true);
  });

  test('MoveItemCommand：移动元素', () {
    // 先添加一个形状
    final shape = ShapeItem(
      id: 'shape1',
      type: 'rect',
      x: 10,
      y: 20,
      width: 100,
      height: 80,
    );
    final addCmd = CreateShapeCommand(layerId: 'l1', shape: shape);
    reducer.execute(addCmd);

    // 移动形状
    final moveCmd = MoveItemCommand(
      layerId: 'l1',
      itemId: 'shape1',
      itemType: 'shape',
      oldX: 10,
      oldY: 20,
      newX: 50,
      newY: 60,
    );
    final movedState = reducer.execute(moveCmd);
    expect(movedState.revision, 2);
    expect(reducer.canUndo, true);
  });

  test('clearHistory：清空历史', () {
    final stroke = LineItem(id: 's1', points: [Point(0, 0)]);
    reducer.execute(AddStrokeCommand(layerId: 'l1', stroke: stroke));
    reducer.clearHistory();
    expect(reducer.canUndo, false);
    expect(reducer.canRedo, false);
  });
}
