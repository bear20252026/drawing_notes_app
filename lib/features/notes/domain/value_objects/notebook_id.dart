// notes — Domain 层：笔记本 ID 值对象（零外部依赖）
// 遵循 Clean Architecture：Domain 层不依赖任何外部库或框架

/// 笔记本唯一标识符（值对象）
///
/// 封装 ID 的验证逻辑，确保 ID 始终合法
class NotebookId {
  const NotebookId._(this._value);

  /// 原始 ID 字符串
  String get value => _value;

  final String _value;

  /// 创建 NotebookId（工厂方法——自动验证）
  ///
  /// 返回 null 表示 ID 非法（含路径遍历风险字符）
  static NotebookId? tryCreate(String id) {
    if (_isValid(id)) return NotebookId._(id);
    return null;
  }

  /// 创建 NotebookId（工厂方法——非法时抛异常）
  ///
  /// [ArgumentError] 当 ID 包含非法字符时抛出
  static NotebookId create(String id) {
    if (!_isValid(id)) {
      throw ArgumentError.value(id, 'id', '非法 ID（路径遍历防护）');
    }
    return NotebookId._(id);
  }

  /// 校验 ID 是否安全（仅允许字母、数字、下划线、连字符）
  ///
  /// 安全说明：ID 直接拼入文件路径，若允许 `../` 等字符会造成路径遍历
  static bool _isValid(String id) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotebookId &&
          runtimeType == other.runtimeType &&
          _value == other._value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'NotebookId($_value)';
}
