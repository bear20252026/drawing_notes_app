import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/canvas_model/document.dart';
import 'drawing_controller.dart';

/// 绘图域 Riverpod Provider（P1-a B1 落地，2026 官方推荐模式）。
///
/// 设计：绘图专属 provider 放在本模块（不污染 core 共享内核）；
/// core/di/providers.dart 仅保留跨功能共享 provider（theme/darkMode）。
/// - family：每个文档一个 DrawingController（Riverpod 官方模式）
/// - DrawingController 内部保持 ChangeNotifier 不动，本 provider 提供
///   容器接入（可回滚）
/// - ProviderContainer 可独立单测（可测性闭环）
///
/// R5 裁决（业主批准 2026-11-17）：原 B2~B4 示范派生 provider
/// （drawingDirtyProvider / drawingCanUndoProvider / drawingCanRedoProvider /
/// drawingCurrentLayerProvider）与 notebookAccessorProvider 空装配点生产
/// 零消费，整体删除——容器本体 drawingControllerProvider 已在生产接线
/// （editor_page initState / editor_statusbar），保留。真实笔记访问走
/// NotebookStorage 直接实现 INotebookAccessor 后传参（home_page），不经
/// provider 装配；派生状态 UI 直接读 controller（经 _applyState 单点刷新）。
final drawingControllerProvider = Provider.autoDispose
    .family<DrawingController, DrawingDocument>((ref, document) {
      final controller = DrawingController(document);
      ref.onDispose(controller.dispose); // provider 销毁时释放控制器资源
      return controller;
    });