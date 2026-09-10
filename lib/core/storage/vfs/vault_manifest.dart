import 'dart:convert';

import 'package:drawing_notes_app/core/utils/time_serialization.dart';

/// VFS 加密对象清单（专家目标架构 VFS——2026-08-16）。
///
/// AeroVault V3 manifest 模式：加密清单描述对象条目（id/type/version/
/// size/aad/modified）——每对象版本（变更递增——openbucket 版本保留）、
/// AAD 上下文（NIST SP 800-38D——应用/用途/对象 ID/版本——防拼接/重排）。
class VaultManifestEntry {
  const VaultManifestEntry({
    required this.id,
    required this.type,
    required this.version,
    required this.size,
    required this.aad,
    required this.modified,
  });

  final String id;
  final String type;
  final int version;
  final int size;
  final String aad;
  final DateTime modified;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'version': version,
    'size': size,
    'aad': aad,
    'modified': timeToIso(modified),
  };

  factory VaultManifestEntry.fromJson(Map<String, dynamic> json) =>
      VaultManifestEntry(
        id: json['id'] as String,
        type: json['type'] as String,
        version: json['version'] as int,
        size: json['size'] as int,
        aad: json['aad'] as String,
        modified: timeFromIso(json['modified']),
      );
}

/// VFS 清单（格式版本 + 对象条目集——AeroVault manifest 结构）。
class VaultManifest {
  VaultManifest({required this.entries});

  /// 清单格式版本（实现必须拒绝不支持的版本——AeroVault 模式）。
  static const int formatVersion = 1;

  final List<VaultManifestEntry> entries;

  Map<String, dynamic> toJson() => {
    'format': formatVersion,
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory VaultManifest.fromJson(Map<String, dynamic> json) {
    final format = json['format'] as int?;
    if (format == null || format > formatVersion) {
      throw const FormatException('VFS 清单版本不支持');
    }
    return VaultManifest(
      entries: (json['entries'] as List<Object?>? ?? const <Object?>[])
          .map((e) => VaultManifestEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  VaultManifestEntry? find(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  String encode() => jsonEncode(toJson());

  static VaultManifest decode(String text) =>
      VaultManifest.fromJson(jsonDecode(text) as Map<String, dynamic>);
}

/// 生命周期整理（vacuum/compact）结果。
///
/// [removed] 成功删除的旧物理对象文件数；[failed] 删除失败（尽力而为，
/// 失败文件保留仍可回溯，不致命）的文件数；[retained] 整理后仍保留的
/// 版本文件数（含最新与保留档内的旧版本）。
class VaultVacuumResult {
  const VaultVacuumResult({
    required this.removed,
    required this.failed,
    required this.retained,
  });

  final int removed;
  final int failed;
  final int retained;

  Map<String, dynamic> toJson() => {
    'removed': removed,
    'failed': failed,
    'retained': retained,
  };
}
