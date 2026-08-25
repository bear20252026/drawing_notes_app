import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import 'package:drawing_notes_app/features/editor_v2/application/editor_v2_viewmodel.dart';
import 'package:editor_core/editor_core.dart';

/// CUJ-01 ViewModel 测试（Headless Logic——不依赖 Flutter UI）。
/// 使用 Riverpod ProviderContainer 测试 Notifier。
void main() {
  late ProviderContainer container;
  late EditorV2Notifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(editorV2NotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('初始状态：空文档', () {
    final state = container.read(editorV2NotifierProvider);
    expect(state.document.id, 'new');
    expect(state.canUndo, false);
    expect(state.canRedo, false);
  });

  test('createDocument：创建文档', () {
    notifier.createDocument('test-doc');
    final state = container.read(editorV2NotifierProvider);
    expect(state.document.id, 'test-doc');
    expect(state.document.layers.length, 1);
    expect(state.document.layers.first.id, 'layer-1');
  });

  test('addStroke：添加笔画', () {
    notifier.createDocument('test-doc');
    notifier.addStroke([Point(0, 0), Point(10, 10)]);
    final state = container.read(editorV2NotifierProvider);
    expect(state.document.layers.first.strokes.length, 1);
    expect(state.canUndo, true);
  });

  test('undo/redo：撤销/重做', () {
    notifier.createDocument('test-doc');
    notifier.addStroke([Point(0, 0), Point(10, 10)]);
    expect(container.read(editorV2NotifierProvider).document.layers.first.strokes.length, 1);
    expect(container.read(editorV2NotifierProvider).canUndo, true);

    notifier.undo();
    expect(container.read(editorV2NotifierProvider).document.layers.first.strokes.length, 0);
    expect(container.read(editorV2NotifierProvider).canRedo, true);

    notifier.redo();
    expect(container.read(editorV2NotifierProvider).document.layers.first.strokes.length, 1);
    expect(container.read(editorV2NotifierProvider).canUndo, true);
  });

  test('setTool/setShapeType：工具切换', () {
    notifier.setTool('select');
    expect(container.read(editorV2NotifierProvider).currentTool, 'select');
    notifier.setShapeType('ellipse');
    expect(container.read(editorV2NotifierProvider).currentShapeType, 'ellipse');
  });
}
