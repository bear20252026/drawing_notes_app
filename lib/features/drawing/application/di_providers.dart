import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notes_accessor.dart';
import '../../notes/domain/notebook.dart';
import '../domain/document.dart';
import 'drawing_controller.dart';

/// 绘图域 Riverpod Provider（P1-a B1/B2 落地，2026 官方推荐模式）。
///
/// 设计：绘图专属 provider 放在本模块（不污染 core 共享内核）；
/// core/di/providers.dart 仅保留跨功能共享 provider（theme/darkMode）。
/// - family：每个文档一个 DrawingController（Riverpod 官方模式）
/// - DrawingController 内部（971 行 + 8 part）保持 ChangeNotifier 不动，
///   本 provider 提供容器接入（可回滚），分域迁移渐进推进
/// - history 操作（undo/redo）经 ref.read(provider.notifier) 可达，
///   ProviderContainer 可独立单测（可测性闭环第一步）
final drawingControllerProvider =
    Provider.family<DrawingController, DrawingDocument>(
  (ref, document) => DrawingController(document),
);

/// 文档脏标记派生 Provider（P1-a B2 示范：状态派生走 Riverpod）。
///
/// 从 [DrawingController.isDirty] 派生未保存状态；controller 为
/// ChangeNotifier，provider 值变化时由调用方 `ref.invalidate(...)`
/// 失效重建（UI 层可经 ref.watch + controller 通知桥接自动刷新）。
final drawingDirtyProvider = Provider.family<bool, DrawingDocument>(
  (ref, document) =>
      ref.watch(drawingControllerProvider(document)).isDirty,
);

/// 撤销可用状态派生 Provider（B3：history 域核心状态走 Riverpod）。
final drawingCanUndoProvider = Provider.family<bool, DrawingDocument>(
  (ref, document) =>
      ref.watch(drawingControllerProvider(document)).canUndo,
);

/// 重做可用状态派生 Provider（B3：history 域核心状态走 Riverpod）。
final drawingCanRedoProvider = Provider.family<bool, DrawingDocument>(
  (ref, document) =>
      ref.watch(drawingControllerProvider(document)).canRedo,
);

/// 当前图层索引派生 Provider（B4：核心状态走 Riverpod，供图层面板接线）。
final drawingCurrentLayerProvider = Provider.family<int, DrawingDocument>(
  (ref, document) =>
      ref.watch(drawingControllerProvider(document)).currentLayerIndex,
);

/// 笔记访问接口 Provider（S4b 接口化装配点）：默认空实现，
/// 正式装配由 app 层 override 注入真实 [NotebookAccessorImpl]。
final notebookAccessorProvider = Provider<INotebookAccessor>(
  (ref) => _EmptyNotebookAccessor(),
);

/// 空实现（无注入时安全降级，保持 drawing 完全隔离）。
class _EmptyNotebookAccessor implements INotebookAccessor {
  @override
  bool get isStorageAvailable => false;

  @override
  Future<List<Notebook>> listNotebooks() async => const [];

  @override
  NotebookPage? pageById(String notebookId, String pageId) => null;
}
