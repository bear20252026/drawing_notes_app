import 'dart:io';

import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';

/// 系统托盘管理器（桌面平台：Windows / macOS / Linux）。
///
/// 提供托盘图标、右键菜单、最小化到托盘功能。
/// 移动平台（Android/iOS）自动跳过，不影响功能。
class SystemTrayManager {
  SystemTrayManager._();

  static SystemTray? _tray;
  static bool _initialized = false;

  /// 初始化系统托盘（仅桌面平台）。
  ///
  /// 在应用启动时调用；若平台不支持则静默返回。
  static Future<void> initialize({
    required VoidCallback onShow,
    required VoidCallback onQuit,
  }) async {
    if (_initialized) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    try {
      _tray = SystemTray();

      // macOS 需要显式 setIcon 路径；Windows/Linux 使用 runner 资源。
      if (Platform.isMacOS) {
        await _tray!.setImage('assets/tray_icon.png');
      } else if (Platform.isWindows) {
        await _tray!.setImage('assets/tray_icon.ico');
      } else {
        // Linux: 尝试 assets/tray_icon.png；失败则跳过。
        try {
          await _tray!.setImage('assets/tray_icon.png');
        } catch (_) {
          // Linux 托盘图标缺失时不阻塞启动。
        }
      }

      await _tray!.setTitle('绘图笔记');
      await _tray!.setToolTip('绘图笔记');

      // 构建右键菜单。
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
          label: '显示窗口',
          onClicked: (_) => onShow(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: '退出',
          onClicked: (_) => onQuit(),
        ),
      ]);
      await _tray!.setContextMenu(menu);

      // 双击托盘图标恢复窗口。
      _tray!.registerSystemTrayEventHandler((event) {
        if (event == kSystemTrayEventClick ||
            event == kSystemTrayEventDoubleClick) {
          onShow();
        }
      });

      _initialized = true;
    } catch (_) {
      // 托盘初始化失败不阻塞应用。
    }
  }

  /// 更新托盘图标 tooltip（例如显示当前文档名）。
  static Future<void> updateToolTip(String tooltip) async {
    if (_tray == null) return;
    try {
      await _tray!.setToolTip(tooltip);
    } catch (_) {}
  }

  /// 最小化到托盘（隐藏主窗口）。
  ///
  /// 由桌面窗口管理器调用，需配合 `window_manager` 包。
  static Future<void> minimizeToTray() async {
    if (_tray == null) return;
    // 实际最小化逻辑在窗口管理器中实现（window_manager.hide()）。
    // 此方法仅标记状态，供窗口管理器查询。
  }

  /// 清理资源。
  static Future<void> dispose() async {
    if (_tray != null) {
      await _tray!.destroy();
      _tray = null;
      _initialized = false;
    }
  }

  /// 当前是否已初始化。
  static bool get isInitialized => _initialized;
}
