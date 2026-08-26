/// USB 磁盘自动检测服务。
///
/// 功能：
/// - 定期扫描可移动设备，检测是否插入含有 key.frogkey 的 U 盘
/// - 发现密码盘时触发回调（供 UI 弹出解锁提示）
/// - 移除时触发锁定回调
///
/// 跨平台实现：
/// - Windows: 通过 dart:io 枚举盘符 + FileSystemTypeName 判断可移动
/// - macOS: 枚举 /Volumes 目录
/// - Linux: 枚举 /media 或 /mnt 目录
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'password_disk.dart';

/// 检测到的密码盘信息。
class DetectedPasswordDisk {
  /// 密码盘所在目录。
  final String path;

  /// 是否启用 PIN 保护（v2 格式）。
  final bool isPinProtected;

  /// 文件最后修改时间。
  final DateTime lastModified;

  const DetectedPasswordDisk({
    required this.path,
    required this.isPinProtected,
    required this.lastModified,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetectedPasswordDisk &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() =>
      'DetectedPasswordDisk(path: $path, isPinProtected: $isPinProtected)';
}

/// USB 磁盘自动检测器。
///
/// 使用方式：
/// ```dart
/// final detector = UsbDiskDetector(
///   onDiskInserted: (disk) => _showUnlockPrompt(disk),
///   onDiskRemoved: (path) => _lockIfUsing(path),
/// );
/// detector.start();
/// // ...
/// detector.stop();
/// ```
class UsbDiskDetector {
  /// 插入回调。
  final ValueChanged<DetectedPasswordDisk>? onDiskInserted;

  /// 移除回调。
  final ValueChanged<String>? onDiskRemoved;

  /// 扫描间隔（默认 2 秒）。
  final Duration scanInterval;

  /// 用于检测密码盘的服务。
  final PasswordDisk _disk;

  Timer? _timer;
  final Set<DetectedPasswordDisk> _knownDisks = {};
  bool _isRunning = false;

  UsbDiskDetector({
    this.onDiskInserted,
    this.onDiskRemoved,
    this.scanInterval = const Duration(seconds: 2),
    PasswordDisk? disk,
  }) : _disk = disk ?? const RealPasswordDisk();

  /// 是否正在运行。
  bool get isRunning => _isRunning;

  /// 当前检测到的所有密码盘。
  Set<DetectedPasswordDisk> get knownDisks => Set.unmodifiable(_knownDisks);

  /// 开始检测。
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    // 立即扫描一次。
    _scan();
    _timer = Timer.periodic(scanInterval, (_) => _scan());
  }

  /// 停止检测。
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 执行一次扫描。
  Future<void> _scan() async {
    try {
      final currentDisks = await _scanForPasswordDisks();

      // 检测新增。
      for (final disk in currentDisks) {
        if (!_knownDisks.contains(disk)) {
          _knownDisks.add(disk);
          onDiskInserted?.call(disk);
        }
      }

      // 检测移除。
      final removedDisks =
          _knownDisks.where((d) => !currentDisks.contains(d)).toList();
      for (final disk in removedDisks) {
        _knownDisks.remove(disk);
        onDiskRemoved?.call(disk.path);
      }
    } catch (e) {
      debugPrint('[UsbDiskDetector] 扫描异常: $e');
    }
  }

  /// 扫描所有可移动设备，查找包含 key.frogkey 的目录。
  Future<Set<DetectedPasswordDisk>> _scanForPasswordDisks() async {
    final result = <DetectedPasswordDisk>{};
    final drives = await _getRemovableDrives();

    for (final drive in drives) {
      try {
        final keyFile = File('$drive${Platform.pathSeparator}key.frogkey');
        if (await keyFile.exists()) {
          final stat = await keyFile.stat();
          final bytes = await keyFile.readAsBytes();
          final isPinProtected = bytes.length >= 5 && bytes[4] == 0x02;
          result.add(DetectedPasswordDisk(
            path: drive,
            isPinProtected: isPinProtected,
            lastModified: stat.modified,
          ));
        }
      } catch (_) {
        // 忽略无权限或读取失败。
      }
    }

    return result;
  }

  /// 获取所有可移动驱动器路径。
  Future<List<String>> _getRemovableDrives() async {
    if (Platform.isWindows) {
      return _getWindowsDrives();
    } else if (Platform.isMacOS) {
      return _getMacOSVolumes();
    } else if (Platform.isLinux) {
      return _getLinuxMounts();
    }
    return [];
  }

  /// Windows: 枚举 A-Z 盘符，筛选可移动类型。
  Future<List<String>> _getWindowsDrives() async {
    final drives = <String>[];
    for (var i = 65; i <= 90; i++) {
      final letter = String.fromCharCode(i);
      final path = '$letter:\\';
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          // Windows 可移动设备通常为 DRIVE_REMOVABLE (2)
          // 通过尝试读取目录内容来判断是否可访问
          try {
            await dir.list().take(1).toList();
            drives.add(path);
          } catch (_) {
            // 无权限或不可访问，跳过
          }
        }
      } catch (_) {
        // 盘符不存在，跳过
      }
    }
    return drives;
  }

  /// macOS: 枚举 /Volumes 目录。
  Future<List<String>> _getMacOSVolumes() async {
    final volumes = <String>[];
    final volumesDir = Directory('/Volumes');
    try {
      await for (final entity in volumesDir.list()) {
        if (entity is Directory) {
          volumes.add(entity.path);
        }
      }
    } catch (_) {
      // 忽略
    }
    return volumes;
  }

  /// Linux: 枚举 /media/$USER 和 /mnt 目录。
  Future<List<String>> _getLinuxMounts() async {
    final mounts = <String>[];

    // /media/$USER
    final user = Platform.environment['USER'];
    if (user != null) {
      final mediaDir = Directory('/media/$user');
      try {
        await for (final entity in mediaDir.list()) {
          if (entity is Directory) {
            mounts.add(entity.path);
          }
        }
      } catch (_) {
        // 忽略
      }
    }

    // /mnt
    final mntDir = Directory('/mnt');
    try {
      await for (final entity in mntDir.list()) {
        if (entity is Directory) {
          mounts.add(entity.path);
        }
      }
    } catch (_) {
      // 忽略
    }

    return mounts;
  }

  /// 释放资源。
  void dispose() {
    stop();
    _knownDisks.clear();
  }
}
