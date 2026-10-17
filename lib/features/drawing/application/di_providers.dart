import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notes_accessor.dart';
import '../../../core/canvas_model/document.dart';
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
final drawingControllerProvider = Provider.autoDispose
    .family<DrawingController, DrawingDocument>((ref, document) {
      final controller = DrawingController(document);
      ref.onDispose(controller.dispose); // provider 销毁时释放控制器资源
      return controller;
    });

/// 文档脏标记派生 Provider（P1-a B2 示范：状态派生走 Riverpod）。
///
/// ⚠ 注释更正（EUI-12 重采 R43）：这里以前写「UI 层可经 ref.watch + controller 通知桥接
/// 自动刷新」——UI 侧对 `drawingDirtyProvider` **零命中**，脏标记实际是
/// `editor_statusbar.dart:216` 直接读 `controller.isDirty`。今天只有
/// `test/riverpod_providers_test.dart:86-92` 在读它。示范单元就是示范单元，
/// 别把它读成已经接管了刷新链路。
final drawingDirtyProvider = Provider.family<bool, DrawingDocument>(
  (ref, document) => ref.watch(drawingControllerProvider(document)).isDirty,
);

/// 撤销可用状态派生 Provider（B3：history 域核心状态走 Riverpod）。
final drawingCanUndoProvider = Provider.family<bool, DrawingDocument>(
  (ref, document) => ref.watch(drawingControllerProvider(document)).canUndo,
);

/// 重做可用状态派生 Provider（B3：history 域核心状态走 Riverpod）。
final drawingCanRedoProvider = Provider.family<bool, DrawingDocument>(
  (ref, document) => ref.watch(drawingControllerProvider(document)).canRedo,
);

/// 当前图层索引派生 Provider（B4：核心状态走 Riverpod）。
///
/// ⚠ 注释更正（EUI-12 重采 R43）：原来写着「供图层面板接线」——`LayerPanel` 是
/// `StatelessWidget`（`layer_panel.dart:31`），全文件 `ref.watch` / `WidgetRef` /
/// `ConsumerWidget` **零命中**，所以面板并没有接在这条 provider 上。今天只有
/// `test/riverpod_providers_test.dart:106-111` 在读。
final drawingCurrentLayerProvider = Provider.family<int, DrawingDocument>(
  (ref, document) =>
      ref.watch(drawingControllerProvider(document)).currentLayerIndex,
);

/// 笔记访问接口 Provider（S4b 接口化装配点）：默认空实现。
///
/// ⚠ 注释更正（EUI-12 重采 R43，实数）：原来写着「正式装配由 app 层 override 注入真实
/// [NotebookAccessorImpl]」——除注释行之外，全仓（lib + test）**没有任何** `ref.override`
/// 或 `ref.watch` 引用这个 provider：`grep -rn notebookAccessorProvider lib test` 的命中
/// 只有下面这行声明、各处解释它没人读的注释，以及棘轮测试里的基线字面量。
/// 也就是说它恒落 [_EmptyNotebookAccessor]，而真实的笔记访问走的是**另一条路**
/// （存储对象自己实现接口后直接传参，见 `home_page.dart:314`）。
/// 它是 `test/architecture/provider_reader_ratchet_test.dart` 具名基线里的**唯一一格**：
/// 要么把 app 层 override 真接上，要么删掉这个装配点（删代码归业主点名）——
/// 但新增一个「没人读的 provider」会当场红。
final notebookAccessorProvider = Provider<INotebookAccessor>(
  (ref) => _EmptyNotebookAccessor(),
);

/// 空实现（无注入时安全降级，保持 drawing 完全隔离）。
class _EmptyNotebookAccessor implements INotebookAccessor {
  @override
  bool get isStorageAvailable => false;

  @override
  Future<List<NotebookSearchDocument>> listSearchDocuments() async => const [];

  @override
  Future<String> storeImage(String sourcePath, String pageId) async =>
      throw UnimplementedError('未注入笔记存储，图片保存不可用');
}
