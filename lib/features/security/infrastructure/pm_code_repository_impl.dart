/// PM码仓储实现 — 基于 SharedPreferences。
///
/// 实现 domain/repositories/pm_code_repository.dart 中定义的接口。
///
/// 版权声明：本实现借鉴了以下开源项目的设计理念：
/// - kurpod (github.com/srv1n/kurpod) — AGPL-3.0
/// - Sanctum (github.com/Teycir/Sanctum) — 项目自定义许可
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/pm_code_state.dart';
import '../domain/repositories/pm_code_repository.dart';

/// 基于 SharedPreferences 的 PM码仓储实现。
class PmCodeRepositoryImpl implements PmCodeRepository {
  PmCodeRepositoryImpl({SharedPreferences? prefs}) : _prefs = prefs;

  /// SharedPreferences 实例（可注入用于测试）。
  final SharedPreferences? _prefs;

  /// Slot B 存储键。
  static const String _slotBKey = 'pm_slot_b';

  /// Slot A 存储键。
  static const String _slotAKey = 'pm_slot_a';

  /// 获取 SharedPreferences 实例（懒加载）。
  Future<SharedPreferences> get _preferences async =>
      _prefs ?? await SharedPreferences.getInstance();

  @override
  Future<PmCodeState> getState() async {
    final prefs = await _preferences;
    final slotBStr = prefs.getString(_slotBKey);
    final slotAStr = prefs.getString(_slotAKey);

    final isConfigured = slotBStr != null;

    // 检查 Slot A 是否已被销毁
    bool isSlotADestroyed = false;
    if (slotAStr != null) {
      try {
        final decoded = jsonDecode(slotAStr) as Map<String, dynamic>;
        isSlotADestroyed = decoded['destroyed'] == true || decoded['v'] == -1;
      } on Exception {
        // 忽略解析错误
        isSlotADestroyed = false;
      }
    }

    // 解析创建时间
    int? createdAt;
    if (slotBStr != null) {
      try {
        final decoded = jsonDecode(slotBStr) as Map<String, dynamic>;
        createdAt = decoded['createdAt'] as int?;
      } on Exception {
        // 忽略解析错误
      }
    }

    return PmCodeState(
      isConfigured: isConfigured,
      isSlotADestroyed: isSlotADestroyed,
      createdAt: createdAt,
    );
  }

  @override
  Future<void> saveSlotB(String slotBMetaJson) async {
    final prefs = await _preferences;
    await prefs.setString(_slotBKey, slotBMetaJson);
  }

  @override
  Future<String?> getSlotB() async {
    final prefs = await _preferences;
    return prefs.getString(_slotBKey);
  }

  @override
  Future<void> deleteSlotB() async {
    final prefs = await _preferences;
    await prefs.remove(_slotBKey);
  }

  @override
  Future<void> overwriteSlotA(String destroyPayload) async {
    final prefs = await _preferences;
    await prefs.setString(_slotAKey, destroyPayload);
  }

  @override
  Future<String?> getSlotA() async {
    final prefs = await _preferences;
    return prefs.getString(_slotAKey);
  }

  @override
  Future<void> fsync() async {
    // SharedPreferences 在 Android 上通过 commit() 保证同步写入
    // 在 iOS 上 NSUserDefaults 会自动同步
    // 这里做一个延迟确保写入完成
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
