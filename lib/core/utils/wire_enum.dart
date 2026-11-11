/// 落盘枚举的显式 wire 名契约（CTL-03 ②，2026-11）。
///
/// ## 为什么需要它
///
/// Flutter 混淆文档对枚举的原话是「Enum names are not obfuscated **currently**」
/// ——"currently" 不是承诺。`--obfuscate` 之后 `Enum.name` 与 `values.byName()`
/// 会跟着 Dart 标识符一起被改名，而 `flutter test` 与 `-d windows` smoke 跑的都是
/// **非混淆**编译 ⇒ 这类失效 CI 天生看不见，只有装到用户机器上才现形。
/// 这正是 CTL-03 挡住混淆的那一类「本机看不见」失效，详见
/// `.github/workflows/release-build.yml` 文件头。
///
/// ## 口径
///
/// * **wire 名与今天的 `.name` 逐字相同** ⇒ 磁盘格式零变化、无需迁移、老文件照读。
///   变的是「格式不再由 Dart 标识符派生」：改 Dart 标识符不再等于改格式。
/// * 每个落盘枚举实现 [WireEnum]，在 `wireName` 的 switch 里用**显式字面量**
///   声明每个取值。漏一个取值 → 编译不过（switch 穷尽性），不像 `.name`
///   那样「加了取值忘不改格式」也能跑得起来。
/// * 编解码一律走 [wireEnumOf] 与 `wireName`；落盘形状里**禁止**再出现
///   `.name` / `values.byName()`。门禁见
///   `test/architecture/persisted_enum_wire_gate_test.dart`。
///
/// ## 回落策略为什么由调用点决定
///
/// 既有解码有两种口径：未知 → **缺省值**（如 `PaperType.blank`、
/// `BrushType.pen`）与未知 → **null**（如 `strokeStyle`/`fillStyle`，交由
/// `effective*` 属性按 v3 语义推导）。[wireEnumOf] 统一返回 null，由调用点按
/// 各自的既有口径回落——不在工具函数里预设默认值，避免「解码层不新增拒绝
/// 路径」这条纪律被一个随手加的默认值悄悄破坏。
///
/// ## 谁该实现本接口
///
/// 只用于**落盘**枚举（JSON / SharedPreferences / 预设簿）。仅在内存里流转、
/// 从不写盘的枚举不需要实现——给它加 wire 名等于凭空造一份格式承诺，
/// 反而让下一个人以为改了名字要同步改格式。
library;

/// 落盘枚举必须实现本接口：用显式字面量声明每个取值的 wire 名。
abstract interface class WireEnum {
  String get wireName;
}

/// 按 [WireEnum.wireName] 在 [values] 里查值；缺失或未知一律返回 null。
///
/// 入参 [raw] 允许为 null（对应「旧文件不带这个键」），也允许是类型不符的值
/// 被调用点提前过滤——本函数只处理 String。
T? wireEnumOf<T extends WireEnum>(List<T> values, String? raw) {
  if (raw == null) return null;
  for (final value in values) {
    if (value.wireName == raw) return value;
  }
  return null;
}

/// 按 [WireEnum.wireName] 在 [values] 里查值；缺失或未知抛 [ArgumentError]。
///
/// 对应改造前 `Enum.values.byName()` 的**严格**口径：`NoteAttachment.fromJson`
/// 遇到未知 `kind` 直接抛，把「要不要容忍」的决定权留给上层（同文件的
/// `tryParse` 才是宽容口径，两者有意并存）。
T wireEnumOfOrThrow<T extends WireEnum>(List<T> values, String? raw) {
  final matched = wireEnumOf(values, raw);
  if (matched != null) return matched;
  throw ArgumentError.value(raw, 'raw', 'no $T wire name');
}
