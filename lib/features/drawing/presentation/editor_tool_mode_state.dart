import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';

/// 编辑器画布工具的短生命周期展示状态。
///
/// 该协作者只维护手型、框选和形状工具之间的互斥规则。页面仍负责在同一
/// `setState` 周期内同步 `DrawingController`、`EditorViewModel`、框选草稿及
/// 实际输入路由，因而不会形成第二个持久化工具状态源。
class EditorToolModeState {
  bool _handActive = false;
  bool _marqueeActive = false;
  ShapeType? _activeShape;

  bool get handActive => _handActive;
  bool get marqueeActive => _marqueeActive;
  ShapeType? get activeShape => _activeShape;

  /// 进入手型模式。返回新状态，便于页面决定是否清理手势暂态。
  bool toggleHand() {
    _handActive = !_handActive;
    _marqueeActive = false;
    _activeShape = null;
    return _handActive;
  }

  /// 进入或切换框选模式。形状和手型模式必然退出。
  bool toggleMarquee() {
    _marqueeActive = !_marqueeActive;
    _handActive = false;
    _activeShape = null;
    return _marqueeActive;
  }

  /// 选择形状工具。手型和框选模式必然退出。
  void selectShape(ShapeType type) {
    _handActive = false;
    _marqueeActive = false;
    _activeShape = type;
  }

  /// 进入非形状的画布工具（书写、取色、选区或文字）。
  void clearPointerModes() {
    _handActive = false;
    _marqueeActive = false;
    _activeShape = null;
  }
}
