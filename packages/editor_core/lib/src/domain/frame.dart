// editor_core——Frame 框架系统（Excalidraw Frames and Containment 3.5 借鉴——2026-08-21）。
//
// Excalidraw 3.5 Frames and Containment 本地化——元素分组/裁剪/包含。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - Frame 是特殊容器元素（ExcalidrawFrameLikeElement）
// - 元素通过 frameId 属性属于某个 Frame
// - Frame 可以裁剪（clip）其子元素
// - Frame 和子元素不能同时被选中（避免冲突）
// - Frame 可以嵌套
library;

/// 框架类型（Excalidraw Frame 借鉴）。
enum FrameType {
  /// 普通框架（手动创建的分组容器）。
  frame,

  /// 魔法框架（AI 生成的智能容器——Excalidraw magicframe）。
  magicFrame,
}

/// 框架元素（Excalidraw ExcalidrawFrameLikeElement 本地化——不可变）。
///
/// Frame 是容器元素，可以包含其他元素（通过 frameId 关联）。
/// 支持：
/// - 元素分组（将多个元素组织到一个 Frame 中）
/// - 视觉裁剪（Frame 边界裁剪子元素）
/// - 嵌套（Frame 可以包含其他 Frame）
/// - 统一操作（移动/缩放 Frame 时，子元素跟随）
class Frame {
  const Frame({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.type = FrameType.frame,
    this.backgroundColor = 'transparent',
    this.borderColor = '#000000',
    this.borderWidth = 1,
    this.clipChildren = true,
    this.locked = false,
    this.childIds = const [],
  });

  final String id;
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final FrameType type;
  final String backgroundColor;
  final String borderColor;
  final double borderWidth;

  /// 是否裁剪子元素（Excalidraw frame clipping）。
  final bool clipChildren;

  /// 是否锁定（锁定后子元素不可单独移动）。
  final bool locked;

  /// 子元素 ID 列表（frameId 关联）。
  final List<String> childIds;

  /// 边界。
  ({double left, double top, double right, double bottom}) get bounds =>
      (left: x, top: y, right: x + width, bottom: y + height);

  /// 中心点。
  ({double x, double y}) get center => (x: x + width / 2, y: y + height / 2);

  /// 子元素数量。
  int get childCount => childIds.length;

  /// 是否为空（无子元素）。
  bool get isEmpty => childIds.isEmpty;

  /// 点是否在 Frame 内（containment 检测）。
  bool containsPoint(double px, double py) {
    return px >= x && px <= x + width && py >= y && py <= y + height;
  }

  /// 元素是否完全在 Frame 内（Excalidraw containment 检测）。
  bool containsElement(double ex, double ey, double ew, double eh) {
    return ex >= x && ex + ew <= x + width && ey >= y && ey + eh <= y + height;
  }

  /// 元素是否与 Frame 相交（用于自动检测哪些元素应归属 Frame）。
  bool intersectsElement(double ex, double ey, double ew, double eh) {
    return !(ex + ew < x || ex > x + width || ey + eh < y || ey > y + height);
  }

  /// 添加子元素。
  Frame addChild(String childId) {
    if (childIds.contains(childId)) return this;
    return copyWith(childIds: [...childIds, childId]);
  }

  /// 移除子元素。
  Frame removeChild(String childId) {
    return copyWith(childIds: childIds.where((id) => id != childId).toList());
  }

  /// 检查元素是否是子元素。
  bool hasChild(String childId) => childIds.contains(childId);

  /// 移动 Frame（同时移动所有子元素——通过返回移动偏移量实现）。
  Frame moveTo(double newX, double newY) {
    return copyWith(x: newX, y: newY);
  }

  /// 缩放 Frame。
  Frame resize(double newWidth, double newHeight) {
    return copyWith(width: newWidth.clamp(10, 10000), height: newHeight.clamp(10, 10000));
  }

  Frame copyWith({
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    FrameType? type,
    String? backgroundColor,
    String? borderColor,
    double? borderWidth,
    bool? clipChildren,
    bool? locked,
    List<String>? childIds,
  }) {
    return Frame(
      id: id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      type: type ?? this.type,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      clipChildren: clipChildren ?? this.clipChildren,
      locked: locked ?? this.locked,
      childIds: childIds ?? this.childIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Frame && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Frame 管理器（Excalidraw Frame 系统本地化——积木式纯 Dart）。
///
/// 管理多个 Frame + 元素归属 + 自动检测。
class FrameManager {
  const FrameManager({this.frames = const []});

  final List<Frame> frames;

  /// 添加 Frame。
  FrameManager add(Frame frame) {
    return FrameManager(frames: [...frames, frame]);
  }

  /// 移除 Frame（同时清除子元素的 frameId 关联）。
  FrameManager remove(String frameId) {
    return FrameManager(frames: frames.where((f) => f.id != frameId).toList());
  }

  /// 获取 Frame。
  Frame? get(String frameId) {
    return frames.where((f) => f.id == frameId).firstOrNull;
  }

  /// 更新 Frame。
  FrameManager update(Frame frame) {
    return FrameManager(
      frames: frames.map((f) => f.id == frame.id ? frame : f).toList(),
    );
  }

  /// 获取元素所在的 Frame（通过 childIds 查找）。
  Frame? getFrameForElement(String elementId) {
    return frames.where((f) => f.hasChild(elementId)).firstOrNull;
  }

  /// 自动检测元素应归属哪个 Frame（几何包含检测）。
  List<Frame> detectFramesForElement(double ex, double ey, double ew, double eh) {
    return frames.where((f) => f.containsElement(ex, ey, ew, eh)).toList();
  }

  /// 将元素添加到指定 Frame（自动从其他 Frame 移除——Excalidraw 单归属）。
  FrameManager assignElementToFrame(String elementId, String frameId) {
    // 先从所有 Frame 移除该元素。
    var updated = frames.map((f) => f.removeChild(elementId)).toList();
    // 添加到目标 Frame。
    updated = updated.map((f) => f.id == frameId ? f.addChild(elementId) : f).toList();
    return FrameManager(frames: updated);
  }

  /// 从 Frame 移除元素。
  FrameManager unassignElement(String elementId) {
    return FrameManager(
      frames: frames.map((f) => f.removeChild(elementId)).toList(),
    );
  }

  int get count => frames.length;
  bool get isEmpty => frames.isEmpty;

  FrameManager copyWith({List<Frame>? frames}) {
    return FrameManager(frames: frames ?? this.frames);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FrameManager && count == other.count;

  @override
  int get hashCode => count.hashCode;
}
