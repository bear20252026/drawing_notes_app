import 'dart:io';

import 'package:flutter/foundation.dart';

import 'audit_logger.dart';

/// Root 守卫（用户拍板 2026-09-01：检测到 root 拒绝启动；
/// U1 修订 2026-09-02：拒绝方式由静默 exit(1) 改为明确提示页——
/// 应用本体照常不运行，但用户能看到"拒绝原因"，不再表现成闪退）。
///
/// 策略：Android 启动最早期（runApp 之前）扫描已知 root 特征路径，
/// 命中即记录审计日志并进入拒绝提示页——不执行任何初始化与业务装配。
/// Windows 桌面无 root 威胁模型（管理员权限≠root），检测不生效。
///
/// 诚实边界：基于文件路径的检测可被 Magisk DenyList / Shamiko 等隐藏
/// 手段规避——本守卫拦截的是"普通 root"，不是"蓄意隐匿的攻击者"。
/// 真正的底线由全盘加密兜底（无 PIN 密文不可解，见加密底座批次）。
abstract final class RootGuard {
  /// 已知 root 特征路径（su 二进制 / Superuser APK / Magisk 残留）。
  ///
  /// 注：`/data/adb/*` 未 root 时不可读，existsSync 返回 false——
  /// 列入无害，命中即强信号。
  static const List<String> knownRootPaths = [
    '/system/bin/su',
    '/system/xbin/su',
    '/sbin/su',
    '/system/sd/xbin/su',
    '/system/bin/failsafe/su',
    '/system/bin/.ext/.su',
    '/system/usr/we-need-root/su-backup',
    '/vendor/bin/su',
    '/su/bin/su',
    '/su/bin/sudaemon',
    '/data/local/xbin/su',
    '/data/local/bin/su',
    '/system/app/Superuser.apk',
    '/system/app/Superuser/Superuser.apk',
    '/system/app/SuperSU/SuperSU.apk',
    '/system/xbin/daemonsu',
    '/system/etc/init.d/99SuperSUDaemon',
    '/cache/magisk.log',
    '/data/adb/magisk',
    '/data/adb/magisk.db',
    '/data/adb/magisk_simple',
  ];

  /// 生产入口：平台判定 + 文件探测。
  ///
  /// 仅 Android 生效；Web/Windows/其他平台恒返回 false。
  static bool detect() {
    if (kIsWeb || !Platform.isAndroid) return false;
    return isRootedOnAndroid(existingPaths: _probe());
  }

  /// 纯判定函数（可测）：Android 上，任一已知特征路径存在即判 root。
  static bool isRootedOnAndroid({required List<String> existingPaths}) {
    return existingPaths.isNotEmpty;
  }

  /// 拒绝启动审计日志（U1：由调用方 runApp 拒绝提示页，不再 exit 闪退）。
  ///
  /// 审计日志仅记录事件类型，不含路径清单（不给攻击者反侦察线索）。
  static void logRefusal() {
    AuditLogger.log('security.root_detected.refuse_start', success: false);
  }

  /// 生产探测：逐个 existsSync，单条路径异常（权限/IO）跳过不误判。
  static List<String> _probe() {
    final found = <String>[];
    for (final path in knownRootPaths) {
      try {
        if (File(path).existsSync()) found.add(path);
      } catch (_) {
        // 探测失败视为不存在（保守：不因 IO 异常误杀正常设备）。
      }
    }
    return found;
  }
}
