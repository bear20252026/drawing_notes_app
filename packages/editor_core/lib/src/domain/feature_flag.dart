// editor_core——FeatureFlag 特性标志（AFFiNE 借鉴——2026-08-21）。
//
// AFFiNE Feature Flag System（2.7）本地化——特性开关系统。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// AFFiNE 原版参考：
// - 2.7 Feature Flag System——运行时特性开关
// - 特性分组（beta/stable/experimental）+ 启用/禁用 + 用户/全局
library;

/// 特性状态（AFFiNE Feature Flag 借鉴）。
enum FeatureStatus {
  /// 实验性（默认关闭——需手动启用）。
  experimental,

  /// Beta 测试（默认关闭——测试用户可启用）。
  beta,

  /// 稳定（默认开启——所有用户可用）。
  stable,

  /// 已废弃（默认关闭——即将移除）。
  deprecated,
}

/// 特性标志（AFFiNE Feature Flag 本地化——不可变）。
class FeatureFlag {
  const FeatureFlag({
    required this.id,
    required this.name,
    this.description = '',
    this.status = FeatureStatus.experimental,
    this.enabled = false,
    this.defaultValue = false,
    this.group = '',
  });

  final String id;
  final String name;
  final String description;
  final FeatureStatus status;
  final bool enabled;
  final bool defaultValue;
  final String group;

  /// 是否可用（stable 默认开启，其他需显式启用）。
  bool get isAvailable => status == FeatureStatus.stable || enabled;

  FeatureFlag copyWith({
    FeatureStatus? status,
    bool? enabled,
    String? description,
    String? group,
  }) {
    return FeatureFlag(
      id: id,
      name: name,
      description: description ?? this.description,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      defaultValue: defaultValue,
      group: group ?? this.group,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeatureFlag && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 特性标志管理器（AFFiNE Feature Flag System 本地化——积木式纯 Dart）。
///
/// 功能：
/// - 特性注册表（add/remove/get）
/// - 启用/禁用特性（toggle）
/// - 按状态/分组过滤
/// - 批量操作（enableAll/disableAll）
class FeatureFlagManager {
  const FeatureFlagManager({this.flags = const []});

  final List<FeatureFlag> flags;

  /// 注册特性。
  FeatureFlagManager add(FeatureFlag flag) {
    return FeatureFlagManager(flags: [...flags, flag]);
  }

  /// 移除特性。
  FeatureFlagManager remove(String flagId) {
    return FeatureFlagManager(flags: flags.where((f) => f.id != flagId).toList());
  }

  /// 获取特性。
  FeatureFlag? get(String flagId) {
    return flags.where((f) => f.id == flagId).firstOrNull;
  }

  /// 检查特性是否可用（AFFiNE isEnabled 核心逻辑）。
  bool isEnabled(String flagId) {
    final flag = get(flagId);
    if (flag == null) return false;
    return flag.isAvailable;
  }

  /// 切换特性状态（启用/禁用）。
  FeatureFlagManager toggle(String flagId) {
    return FeatureFlagManager(
      flags: flags.map((f) => f.id == flagId ? f.copyWith(enabled: !f.enabled) : f).toList(),
    );
  }

  /// 启用特性。
  FeatureFlagManager enable(String flagId) {
    return FeatureFlagManager(
      flags: flags.map((f) => f.id == flagId ? f.copyWith(enabled: true) : f).toList(),
    );
  }

  /// 禁用特性。
  FeatureFlagManager disable(String flagId) {
    return FeatureFlagManager(
      flags: flags.map((f) => f.id == flagId ? f.copyWith(enabled: false) : f).toList(),
    );
  }

  /// 按状态过滤（AFFiNE getFlagsByStatus）。
  List<FeatureFlag> byStatus(FeatureStatus status) {
    return flags.where((f) => f.status == status).toList();
  }

  /// 按分组过滤。
  List<FeatureFlag> byGroup(String group) {
    return flags.where((f) => f.group == group).toList();
  }

  /// 批量启用所有 beta 特性。
  FeatureFlagManager enableAllBeta() {
    return FeatureFlagManager(
      flags: flags.map((f) => f.status == FeatureStatus.beta ? f.copyWith(enabled: true) : f).toList(),
    );
  }

  /// 批量禁用所有实验性特性。
  FeatureFlagManager disableAllExperimental() {
    return FeatureFlagManager(
      flags: flags.map((f) => f.status == FeatureStatus.experimental ? f.copyWith(enabled: false) : f).toList(),
    );
  }

  int get count => flags.length;
  bool get isEmpty => flags.isEmpty;
  int get enabledCount => flags.where((f) => f.enabled).length;

  FeatureFlagManager copyWith({List<FeatureFlag>? flags}) {
    return FeatureFlagManager(flags: flags ?? this.flags);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FeatureFlagManager && count == other.count;

  @override
  int get hashCode => count.hashCode;
}
