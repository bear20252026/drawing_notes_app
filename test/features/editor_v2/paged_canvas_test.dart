import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/editor_v2/application/paged_canvas_viewmodel.dart';

/// 批次 F-1：分页画布测试——页面管理 + 每页独立撤销/重做。
void main() {
  late ProviderContainer container;
  late PagedCanvasNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(pagedCanvasNotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  test('初始状态：一页', () {
    final state = container.read(pagedCanvasNotifierProvider);
    expect(state.pages.length, 1);
    expect(state.currentPageIndex, 0);
    expect(state.currentPage!.id, 'page-1');
  });

  test('addPage：追加新页', () {
    notifier.addPage();
    final state = container.read(pagedCanvasNotifierProvider);
    expect(state.pages.length, 2);
    expect(state.currentPageIndex, 1); // 切换到新页
  });

  test('insertPage：指定位置插入', () {
    notifier.insertPage(0);
    final state = container.read(pagedCanvasNotifierProvider);
    expect(state.pages.length, 2);
    expect(state.currentPageIndex, 0); // 切换到插入位置
  });

  test('deletePage：删除页（至少保留一页）', () {
    notifier.addPage();
    notifier.deletePage(1);
    final state = container.read(pagedCanvasNotifierProvider);
    expect(state.pages.length, 1);
    // 不能删除最后一页。
    notifier.deletePage(0);
    expect(container.read(pagedCanvasNotifierProvider).pages.length, 1);
  });

  test('reorderPage：重排页面', () {
    notifier.addPage();
    notifier.reorderPage(0, 1);
    final state = container.read(pagedCanvasNotifierProvider);
    expect(state.pages[0].id, isNot('page-1'));
    expect(state.pages[1].id, 'page-1');
  });

  test('每页独立撤销/重做', () {
    // 第一页添加笔画。
    notifier.addPage(); // 切换到第二页
    notifier.setCurrentPage(0); // 回第一页
    final page1Notifier = container.read(pagedCanvasNotifierProvider.notifier);
    page1Notifier.executeOnCurrentPage(
      AddStrokeCommand(layerId: 'layer-1', stroke: LineItem(id: 's1', points: [Point(0, 0), Point(10, 10)])),
    );
    expect(container.read(pagedCanvasNotifierProvider).currentPage!.document.layers.first.strokes.length, 1);

    // 第一页撤销。
    page1Notifier.undoCurrentPage();
    expect(container.read(pagedCanvasNotifierProvider).currentPage!.document.layers.first.strokes.length, 0);

    // 切换到第二页——应为空（独立栈）。
    notifier.setCurrentPage(1);
    expect(container.read(pagedCanvasNotifierProvider).currentPage!.document.layers.first.strokes.length, 0);
  });
}
