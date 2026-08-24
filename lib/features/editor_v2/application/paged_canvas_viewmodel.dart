// editor_v2——PagedCanvasViewModel（批次 F-1——2026-08-21——2026 最佳实践）。
//
// 多页画布 ViewModel——每页独立 DocumentReducer（独立撤销/重做栈）。
// 遵循：scribe_canvas（2026）/专家方案批次 F。
// 纯 Dart 逻辑——无 UI 依赖——Headless Logic。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:editor_core/editor_core.dart';

/// 多页画布状态（不可变）。
@immutable
class PagedCanvasState {
  const PagedCanvasState({
    required this.pages,
    this.currentPageIndex = 0,
  });

  final List<PageV2> pages;
  final int currentPageIndex;

  PageV2? get currentPage =>
      pages.isNotEmpty ? pages[currentPageIndex] : null;

  PagedCanvasState copyWith({
    List<PageV2>? pages,
    int? currentPageIndex,
  }) {
    return PagedCanvasState(
      pages: pages ?? this.pages,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PagedCanvasState &&
          pages == other.pages &&
          currentPageIndex == other.currentPageIndex;

  @override
  int get hashCode => Object.hash(pages, currentPageIndex);
}

/// 多页画布 ViewModel（Riverpod Notifier）。
///
/// 遵循：
/// - 每页独立 DocumentReducer（独立撤销/重做）
/// - 不可变状态（PagedCanvasState — copyWith）
/// - Headless Logic
class PagedCanvasNotifier extends Notifier<PagedCanvasState> {
  final Map<String, DocumentReducer> _pageReducers = {};

  @override
  PagedCanvasState build() {
    // 默认一页。
    final page = PageV2(
      id: 'page-1',
      document: const DocumentV2(id: 'doc-1', pageCount: 1, layers: [
        LayerV2(id: 'layer-1', name: 'Layer 1'),
      ]),
      index: 0,
    );
    _pageReducers['page-1'] = DocumentReducer(page.document);
    return PagedCanvasState(pages: [page]);
  }

  /// 获取当前页的 DocumentReducer。
  DocumentReducer? get _currentReducer {
    final page = state.currentPage;
    if (page == null) return null;
    return _pageReducers[page.id];
  }

  /// 在当前页执行命令。
  void executeOnCurrentPage(DocumentCommand command) {
    final reducer = _currentReducer;
    if (reducer == null) return;
    final newDoc = reducer.execute(command);
    _updateCurrentPageDocument(newDoc);
  }

  /// 撤销当前页。
  void undoCurrentPage() {
    final reducer = _currentReducer;
    if (reducer == null) return;
    final newDoc = reducer.undo();
    if (newDoc != null) _updateCurrentPageDocument(newDoc);
  }

  /// 重做当前页。
  void redoCurrentPage() {
    final reducer = _currentReducer;
    if (reducer == null) return;
    final newDoc = reducer.redo();
    if (newDoc != null) _updateCurrentPageDocument(newDoc);
  }

  void _updateCurrentPageDocument(DocumentV2 newDoc) {
    final pages = List<PageV2>.from(state.pages);
    final idx = state.currentPageIndex;
    pages[idx] = pages[idx].copyWith(document: newDoc);
    state = state.copyWith(pages: pages);
  }

  // ──────────────────────────── 页面管理 ────────────────────────────

  /// 新建页（追加到末尾）。
  void addPage() {
    final newIndex = state.pages.length;
    final pageId = 'page-${DateTime.now().millisecondsSinceEpoch}';
    final page = PageV2(
      id: pageId,
      document: DocumentV2(id: 'doc-$pageId', pageCount: 1, layers: [
        const LayerV2(id: 'layer-1', name: 'Layer 1'),
      ]),
      index: newIndex,
    );
    _pageReducers[pageId] = DocumentReducer(page.document);
    state = PagedCanvasState(
      pages: [...state.pages, page],
      currentPageIndex: newIndex,
    );
  }

  /// 插入页（指定位置）。
  void insertPage(int index) {
    final pageId = 'page-${DateTime.now().millisecondsSinceEpoch}';
    final page = PageV2(
      id: pageId,
      document: DocumentV2(id: 'doc-$pageId', pageCount: 1, layers: [
        const LayerV2(id: 'layer-1', name: 'Layer 1'),
      ]),
      index: index,
    );
    _pageReducers[pageId] = DocumentReducer(page.document);
    final pages = List<PageV2>.from(state.pages)..insert(index, page);
    // 重排索引。
    for (var i = 0; i < pages.length; i++) {
      pages[i] = pages[i].copyWith(index: i);
    }
    state = PagedCanvasState(
      pages: pages,
      currentPageIndex: index,
    );
  }

  /// 删除页。
  void deletePage(int index) {
    if (state.pages.length <= 1) return; // 至少保留一页。
    final removed = state.pages[index];
    _pageReducers.remove(removed.id);
    final pages = List<PageV2>.from(state.pages)..removeAt(index);
    for (var i = 0; i < pages.length; i++) {
      pages[i] = pages[i].copyWith(index: i);
    }
    final newIdx = state.currentPageIndex.clamp(0, pages.length - 1);
    state = PagedCanvasState(pages: pages, currentPageIndex: newIdx);
  }

  /// 重排页。
  void reorderPage(int oldIndex, int newIndex) {
    final pages = List<PageV2>.from(state.pages);
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex, page);
    for (var i = 0; i < pages.length; i++) {
      pages[i] = pages[i].copyWith(index: i);
    }
    state = PagedCanvasState(
      pages: pages,
      currentPageIndex: newIndex,
    );
  }

  /// 切换当前页。
  void setCurrentPage(int index) {
    if (index >= 0 && index < state.pages.length) {
      state = state.copyWith(currentPageIndex: index);
    }
  }
}

/// Riverpod Provider。
final pagedCanvasNotifierProvider =
    NotifierProvider<PagedCanvasNotifier, PagedCanvasState>(
  () => PagedCanvasNotifier(),
);
