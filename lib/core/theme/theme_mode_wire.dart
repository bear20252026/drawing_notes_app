// `ThemeMode` 的落盘 wire 名适配（CTL-03 ②，2026-11）。
//
// 为什么是 `app_design.dart` 的 part 而不是独立库：`core/di/providers.dart`
// 也持久化主题模式，而那个文件是 DI 装配层，文件头自己钉了一条约束——
// 「出向依赖每多一条，Martin instability 就往上走一档（0.33 → 0.50 会撞上
// `test/architecture_test.dart` 规则 3b 的 0.4 基线）」。做成 part 之后
// providers 侧一条 import 都不用加（它本来就 import app_design.dart）。
//
// 为什么不用 `implements WireEnum`：`ThemeMode` 是 Flutter SDK 的枚举，
// 不能为本仓接口加成员，只能在外侧适配。
//
// 口径：**wire 名与今天的 `.name` 逐字相同**（`system`/`light`/`dark`）
// ⇒ 磁盘格式零变化、无需迁移、老文件照读。用显式字面量 switch 声明，
// 不再读 `ThemeMode.name`——混淆会改 Dart 标识符，`.name` 随之变成随机串，
// 而 `flutter test` 跑非混淆编译，CI 天生看不见（CTL-03）。
part of 'app_design.dart';

/// `ThemeMode` → 落盘 wire 名。
String themeModeWire(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'system',
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
};

/// 落盘 wire 名 → `ThemeMode`。
///
/// 回落口径与改造前**逐字相同**：未知/缺失/空串一律跟随系统
/// （改造前是 `firstWhere(..., orElse: () => ThemeMode.system)`）。
ThemeMode themeModeFromWire(String? raw) => switch (raw) {
  'system' => ThemeMode.system,
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};
