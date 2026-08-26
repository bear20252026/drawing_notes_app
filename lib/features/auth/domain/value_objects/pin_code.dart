/// PIN 码值对象 — 零依赖。
///
/// 封装 PIN 码的验证逻辑，确保 PIN 码始终处于有效状态。
class PinCode {
  final String value;

  const PinCode._(this.value);

  /// 工厂构造函数：验证并创建 PIN 码。
  /// 返回 null 表示无效（非 6 位数字）。
  static PinCode? tryCreate(String input) {
    if (input.length != 6) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(input)) return null;
    return PinCode._(input);
  }

  /// 工厂构造函数：验证并创建 PIN 码。
  /// 无效时抛出 [ArgumentError]。
  factory PinCode.create(String input) {
    final pin = tryCreate(input);
    if (pin == null) {
      throw ArgumentError('PIN 码必须为 6 位数字');
    }
    return pin;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PinCode && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PinCode(******)';
}
