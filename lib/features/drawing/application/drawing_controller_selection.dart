part of 'drawing_controller.dart';

/// 笔画选区公开 API 的兼容委托层。
///
/// 草稿完成与笔画命中由 [StrokeSelectionInteractionSession] 管理；已选笔画
/// 的变换、剪贴板和快照由 [StrokeSelectionEditingSession] 管理。控制器仅
/// 保留既有调用面，避免输入层、工具栏与测试发生迁移。
extension DrawingControllerSelectionOps on DrawingController {
  void beginSelection(Offset canvasPoint) =>
      _strokeSelectionInteractionSession.beginSelection(canvasPoint);

  void extendSelection(Offset canvasPoint) =>
      _strokeSelectionInteractionSession.extendSelection(canvasPoint);

  void endSelection() => _strokeSelectionInteractionSession.endSelection();

  /// 清除笔画、形状和图片的统一选择状态。
  void clearSelection() => clearDocumentObjectSelection();

  void moveSelectedStrokes(Offset delta) =>
      _strokeSelectionEditingSession.moveSelectedStrokes(delta);
  void scaleSelectedStrokes(double factor) =>
      _strokeSelectionEditingSession.scaleSelectedStrokes(factor);
  void rotateSelectedStrokes(double radians) =>
      _strokeSelectionEditingSession.rotateSelectedStrokes(radians);
  void endTransform() => _strokeSelectionEditingSession.endTransform();
  void deleteSelectedStrokes() =>
      _strokeSelectionEditingSession.deleteSelectedStrokes();
  void copySelectedStrokes() =>
      _strokeSelectionEditingSession.copySelectedStrokes();
  void pasteClipboard() => _strokeSelectionEditingSession.pasteClipboard();
}
