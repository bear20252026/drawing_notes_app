import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 自动更新检查器（桌面平台）。
///
/// 检查 GitHub Releases 是否有新版本，提示用户更新。
/// 移动平台（Android/iOS）通过应用商店更新，不使用此机制。
class AutoUpdater {
  AutoUpdater._();

  /// GitHub 仓库信息（发布页面 API 地址）。
  static const String _owner = 'drawing-notes';
  static const String _repo = 'drawing_notes_app';

  /// 最后检查时间戳（防止频繁检查）。
  static DateTime? _lastCheckTime;

  /// 最小检查间隔（30分钟）。
  static const Duration _minInterval = Duration(minutes: 30);

  /// 当前版本（从 pubspec.yaml 或编译时常量获取）。
  static String? _currentVersion;

  /// 设置当前版本号。
  static void setCurrentVersion(String version) {
    _currentVersion = version;
  }

  /// 检查是否有新版本。
  ///
  /// 返回 [UpdateInfo] 如果有新版本，否则返回 null。
  /// 桌面平台（Windows/macOS/Linux）才执行检查，移动平台直接返回 null。
  static Future<UpdateInfo?> checkForUpdate() async {
    if (!kIsWeb &&
        !Platform.isWindows &&
        !Platform.isMacOS &&
        !Platform.isLinux) {
      return null;
    }

    // 防频繁检查。
    if (_lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _minInterval) {
      return null;
    }

    _lastCheckTime = DateTime.now();

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('', 408),
      );

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String?;
      final body = json['body'] as String?;
      final htmlUrl = json['html_url'] as String?;
      final assets = json['assets'] as List<dynamic>?;

      if (tagName == null) return null;

      // 清理版本号（去掉 'v' 前缀）。
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;

      final currentVersion = _currentVersion ?? '1.0.0';

      // 比较版本号。
      if (_isNewerVersion(latestVersion, currentVersion)) {
        // 找到当前平台的安装包 URL。
        String? downloadUrl;
        if (assets != null) {
          downloadUrl = _findPlatformAsset(assets);
        }

        return UpdateInfo(
          version: latestVersion,
          releaseNotes: body ?? '',
          releaseUrl: htmlUrl ?? '',
          downloadUrl: downloadUrl,
        );
      }
    } catch (_) {
      // 网络错误静默忽略（离线场景）。
    }

    return null;
  }

  /// 比较两个语义化版本号，判断 [latest] 是否比 [current] 更新。
  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      // 补齐长度。
      while (latestParts.length < 3) {
        latestParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      for (var i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 从 assets 中查找当前平台的安装包。
  static String? _findPlatformAsset(List<dynamic> assets) {
    String pattern;
    if (Platform.isWindows) {
      pattern = '.exe';
    } else if (Platform.isMacOS) {
      pattern = '.dmg';
    } else if (Platform.isLinux) {
      pattern = '.AppImage';
    } else {
      return null;
    }

    for (final asset in assets) {
      final name = asset['name'] as String?;
      if (name != null && name.contains(pattern)) {
        return asset['browser_download_url'] as String?;
      }
    }

    // 回退：查找任何可下载资产。
    if (assets.isNotEmpty) {
      return assets.first['browser_download_url'] as String?;
    }

    return null;
  }

  /// 重置检查时间（用于测试或手动触发）。
  static void resetCheckTimer() {
    _lastCheckTime = null;
  }
}

/// 更新信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseUrl,
    this.downloadUrl,
  });

  /// 最新版本号。
  final String version;

  /// 更新日志。
  final String releaseNotes;

  /// Release 页面 URL。
  final String releaseUrl;

  /// 安装包下载 URL（当前平台）。
  final String? downloadUrl;

  @override
  String toString() => 'UpdateInfo(version: $version)';
}
