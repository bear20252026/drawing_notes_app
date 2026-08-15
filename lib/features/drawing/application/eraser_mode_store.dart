import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/features/drawing/application/eraser_mode.dart';

/// 橡皮擦模式的跨平台持久化设置。
///
/// 首次使用默认 [EraserMode.stroke]，避免透明擦除轨迹在用户没有明确选择时
/// 覆盖内容；损坏或旧值会安全回退至该默认模式。
class EraserModeStore {
  EraserModeStore({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const storageKey = 'eraser_mode.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<EraserMode> load() async {
    final preferences = await _preferencesLoader();
    final raw = preferences.getString(storageKey);
    return EraserMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => EraserMode.stroke,
    );
  }

  Future<void> save(EraserMode mode) async {
    final preferences = await _preferencesLoader();
    await preferences.setString(storageKey, mode.name);
  }
}
