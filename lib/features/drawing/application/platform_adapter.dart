// Copyright (c) AFFiNE - Platform adaptation patterns
// 多平台适配模块 - 参考 AFFiNE 桌面/移动端架构模式
// 基于 AFFiNE 的桌面适配方案进行跨平台支持

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 平台类型枚举
/// Platform types for adaptive layout decisions
enum PlatformType {
  /// 桌面端 - Desktop platform (Windows, macOS, Linux)
  desktop,

  /// 移动端 - Mobile platform (iOS, Android)
  mobile,

  /// Web 端 - Web platform (browser)
  web,
}

/// 屏幕断点常量
/// Breakpoint constants for responsive layout
class Breakpoints {
  Breakpoints._();

  /// 移动端断点 - Mobile breakpoint (max width: 600px)
  static const double mobile = 600.0;

  /// 平板断点 - Tablet breakpoint (600px - 1200px)
  static const double tablet = 1200.0;

  /// 桌面断点 - Desktop breakpoint (min width: 1200px)
  static const double desktop = 1200.0;
}

/// 设备类型
/// Device type based on screen size
enum DeviceType {
  /// 移动设备 - Mobile device
  mobile,

  /// 平板设备 - Tablet device
  tablet,

  /// 桌面设备 - Desktop device
  desktop,
}

/// 平台配置
/// Platform-specific configuration
class PlatformConfiguration {
  const PlatformConfiguration({
    required this.platformType,
    required this.deviceType,
    required this.screenWidth,
    required this.screenHeight,
  });

  final PlatformType platformType;
  final DeviceType deviceType;
  final double screenWidth;
  final double screenHeight;

  /// 从当前环境创建配置
  factory PlatformConfiguration.fromEnvironment({
    double screenWidth = 800.0,
    double screenHeight = 600.0,
  }) {
    final platformType = _detectPlatformType();
    final deviceType = _detectDeviceType(screenWidth);

    return PlatformConfiguration(
      platformType: platformType,
      deviceType: deviceType,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );
  }

  static PlatformType _detectPlatformType() {
    if (kIsWeb) return PlatformType.web;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return PlatformType.desktop;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return PlatformType.mobile;
    }
    return PlatformType.web;
  }

  static DeviceType _detectDeviceType(double width) {
    if (width < Breakpoints.mobile) return DeviceType.mobile;
    if (width < Breakpoints.tablet) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  bool get isDesktop =>
      platformType == PlatformType.desktop && deviceType == DeviceType.desktop;
  bool get isMobile =>
      platformType == PlatformType.mobile || deviceType == DeviceType.mobile;
  bool get isTablet => deviceType == DeviceType.tablet;
  bool get isWeb => platformType == PlatformType.web;
}

/// 自适应布局配置
/// Adaptive layout configuration for different device types
class AdaptiveLayoutConfig {
  const AdaptiveLayoutConfig({
    required this.sidebarVisible,
    required this.toolbarComplexity,
    required this.touchTargetSize,
    required this.navigationType,
    required this.supportsHover,
    required this.supportsPointer,
    required this.cornerRadius,
    required this.spacingScale,
  });

  /// 侧边栏是否可见
  final bool sidebarVisible;

  /// 工具栏复杂度
  final ToolbarComplexity toolbarComplexity;

  /// 触摸目标大小（像素）
  final double touchTargetSize;

  /// 导航类型
  final NavigationType navigationType;

  /// 是否支持悬停交互
  final bool supportsHover;

  /// 是否支持指针交互
  final bool supportsPointer;

  /// 圆角大小
  final double cornerRadius;

  /// 间距比例
  final double spacingScale;

  /// 桌面配置
  static const desktop = AdaptiveLayoutConfig(
    sidebarVisible: true,
    toolbarComplexity: ToolbarComplexity.complex,
    touchTargetSize: 32.0,
    navigationType: NavigationType.sidebar,
    supportsHover: true,
    supportsPointer: true,
    cornerRadius: 8.0,
    spacingScale: 1.0,
  );

  /// 移动端配置
  static const mobile = AdaptiveLayoutConfig(
    sidebarVisible: false,
    toolbarComplexity: ToolbarComplexity.simple,
    touchTargetSize: 48.0,
    navigationType: NavigationType.bottomNav,
    supportsHover: false,
    supportsPointer: true,
    cornerRadius: 12.0,
    spacingScale: 1.5,
  );

  /// 平板配置
  static const tablet = AdaptiveLayoutConfig(
    sidebarVisible: false, // 可折叠
    toolbarComplexity: ToolbarComplexity.medium,
    touchTargetSize: 44.0,
    navigationType: NavigationType.sidebarCollapsible,
    supportsHover: true,
    supportsPointer: true,
    cornerRadius: 10.0,
    spacingScale: 1.2,
  );

  /// 根据设备类型获取配置
  factory AdaptiveLayoutConfig.forDevice(DeviceType deviceType) {
    switch (deviceType) {
      case DeviceType.desktop:
        return desktop;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.mobile:
        return mobile;
    }
  }
}

/// 工具栏复杂度
enum ToolbarComplexity {
  /// 简单 - Simple (移动端)
  simple,

  /// 中等 - Medium (平板)
  medium,

  /// 复杂 - Complex (桌面)
  complex,
}

/// 导航类型
enum NavigationType {
  /// 侧边栏导航 - Sidebar navigation (桌面)
  sidebar,

  /// 底部导航 - Bottom navigation (移动端)
  bottomNav,

  /// 可折叠侧边栏 - Collapsible sidebar (平板)
  sidebarCollapsible,
}

/// 平台适配器 - 核心类
/// Platform adapter - Main class
class PlatformAdapter {
  PlatformAdapter._();

  static PlatformAdapter? _instance;

  /// 获取单例实例
  /// Get singleton instance
  static PlatformAdapter get instance {
    _instance ??= PlatformAdapter._();
    return _instance!;
  }

  PlatformConfiguration? _configuration;
  AdaptiveLayoutConfig? _layoutConfig;

  /// 初始化平台适配器
  /// Initialize platform adapter
  Future<void> initialize({
    double screenWidth = 800.0,
    double screenHeight = 600.0,
  }) async {
    _configuration = PlatformConfiguration.fromEnvironment(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );

    _layoutConfig = AdaptiveLayoutConfig.forDevice(
      _configuration!.deviceType,
    );

    debugPrint(
      'PlatformAdapter: 平台=${_configuration!.platformType.name}, '
      '设备=${_configuration!.deviceType.name}',
    );
  }

  /// 获取平台配置
  /// Get platform configuration
  PlatformConfiguration get configuration {
    if (_configuration == null) {
      throw StateError('PlatformAdapter 未初始化，请先调用 initialize()');
    }
    return _configuration!;
  }

  /// 获取布局配置
  /// Get layout configuration
  AdaptiveLayoutConfig get layoutConfig {
    if (_layoutConfig == null) {
      throw StateError('PlatformAdapter 未初始化，请先调用 initialize()');
    }
    return _layoutConfig!;
  }

  /// 检查当前是否为桌面平台
  bool get isDesktop => configuration.isDesktop;

  /// 检查当前是否为移动平台
  bool get isMobile => configuration.isMobile;

  /// 检查当前是否为 Web 平台
  bool get isWeb => configuration.isWeb;

  /// 检查当前是否为平板
  bool get isTablet => configuration.isTablet;

  /// 更新屏幕尺寸
  /// Update screen size
  void updateScreenSize(double width, double height) {
    _configuration = PlatformConfiguration.fromEnvironment(
      screenWidth: width,
      screenHeight: height,
    );

    _layoutConfig = AdaptiveLayoutConfig.forDevice(
      _configuration!.deviceType,
    );
  }
}

/// 系统托盘管理器 - 跨平台实现
/// System tray manager - Cross-platform implementation
///
/// 注意：系统托盘功能仅在桌面平台（Windows、macOS、Linux）上可用
/// 移动端和 Web 端使用空实现
class SystemTrayManager {
  SystemTrayManager._();

  static SystemTrayManager? _instance;

  /// 获取单例实例
  static SystemTrayManager get instance {
    _instance ??= SystemTrayManager._();
    return _instance!;
  }

  final StreamController<TrayEvent> _eventController =
      StreamController<TrayEvent>.broadcast();

  /// 系统托盘事件流
  Stream<TrayEvent> get events => _eventController.stream;

  bool _isInitialized = false;
  bool _isVisible = true;

  /// 初始化系统托盘
  /// Initialize system tray
  ///
  /// 仅在桌面平台执行，移动端和 Web 端为空操作
  Future<bool> initialize({
    String appName = 'DrawingNotes',
    String? iconPath,
  }) async {
    if (kIsWeb) {
      debugPrint('SystemTrayManager: Web 平台不支持系统托盘');
      return false;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('SystemTrayManager: 移动平台不支持系统托盘');
      return false;
    }

    try {
      // 桌面平台：初始化系统托盘
      // Desktop: Initialize system tray
      debugPrint('SystemTrayManager: 初始化系统托盘 - $appName');

      // TODO: 集成 tray_manager 或 system_tray 包
      // 这里提供接口，实际集成需要额外的包
      // 例如: await TrayManager.initialize(appName, iconPath);

      _isInitialized = true;
      _isVisible = true;

      debugPrint('SystemTrayManager: 系统托盘初始化成功');
      return true;
    } catch (e) {
      debugPrint('SystemTrayManager: 初始化失败 - $e');
      return false;
    }
  }

  /// 最小化窗口到系统托盘
  /// Minimize window to system tray
  Future<bool> minimizeToTray() async {
    if (!_isInitialized || kIsWeb) {
      return false;
    }

    try {
      debugPrint('SystemTrayManager: 最小化到系统托盘');
      _isVisible = false;
      _eventController.add(TrayEvent.hidden);

      // TODO: 实际最小化窗口到托盘
      // 例如: await window_manager_app.minimizeToTray();

      return true;
    } catch (e) {
      debugPrint('SystemTrayManager: 最小化失败 - $e');
      return false;
    }
  }

  /// 从系统托盘恢复窗口
  /// Restore window from system tray
  Future<bool> restoreFromTray() async {
    if (!_isInitialized || kIsWeb) {
      return false;
    }

    try {
      debugPrint('SystemTrayManager: 从系统托盘恢复');
      _isVisible = true;
      _eventController.add(TrayEvent.shown);

      // TODO: 恢复窗口
      // 例如: await window_manager_app.restoreFromTray();

      return true;
    } catch (e) {
      debugPrint('SystemTrayManager: 恢复失败 - $e');
      return false;
    }
  }

  /// 显示上下文菜单
  /// Show context menu
  Future<void> showContextMenu() async {
    if (!_isInitialized || kIsWeb) {
      return;
    }

    try {
      debugPrint('SystemTrayManager: 显示上下文菜单');

      // TODO: 显示系统托盘上下文菜单
      // 上下文菜单结构：
      // - 显示（Show）
      // - 分隔符（Separator）
      // - 退出（Quit）

      _eventController.add(TrayEvent.contextMenu);
    } catch (e) {
      debugPrint('SystemTrayManager: 显示菜单失败 - $e');
    }
  }

  /// 处理托盘点击事件
  void handleTrayClick() {
    if (!_isInitialized) return;

    if (_isVisible) {
      minimizeToTray();
    } else {
      restoreFromTray();
    }
  }

  /// 处理托盘双击事件
  void handleTrayDoubleClick() {
    if (!_isInitialized) return;

    if (!_isVisible) {
      restoreFromTray();
    }
  }

  /// 销毁系统托盘
  void dispose() {
    if (_isInitialized) {
      debugPrint('SystemTrayManager: 销毁系统托盘');
      _isInitialized = false;
      _eventController.close();
      _instance = null;
    }
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  /// 检查是否可见
  bool get isVisible => _isVisible;
}

/// 系统托盘事件类型
enum TrayEvent {
  /// 显示窗口
  shown,

  /// 隐藏窗口
  hidden,

  /// 上下文菜单
  contextMenu,

  /// 退出应用
  quit,
}

/// 文件关联处理器 - 跨平台实现
/// File association handler - Cross-platform implementation
///
/// 处理 .drawingnotes 文件扩展名的关联
class FileAssociationHandler {
  FileAssociationHandler._();

  static FileAssociationHandler? _instance;

  /// 获取单例实例
  static FileAssociationHandler get instance {
    _instance ??= FileAssociationHandler._();
    return _instance!;
  }

  final StreamController<String> _fileOpenController =
      StreamController<String>.broadcast();

  /// 文件打开事件流
  Stream<String> get fileOpenEvents => _fileOpenController.stream;

  /// 支持的文件扩展名
  static const List<String> supportedExtensions = [
    '.drawingnotes',
    '.drawing',
    '.notes',
  ];

  bool _isInitialized = false;
  String? _initialFilePath;

  /// 初始化文件关联处理器
  Future<bool> initialize(List<String> args) async {
    if (_isInitialized) {
      return true;
    }

    try {
      debugPrint('FileAssociationHandler: 初始化文件关联处理器');

      // 解析命令行参数中的文件路径
      _initialFilePath = _parseFilePathFromArgs(args);

      if (_initialFilePath != null) {
        debugPrint('FileAssociationHandler: 初始文件路径 - $_initialFilePath');
        _fileOpenController.add(_initialFilePath!);
      }

      // 在桌面平台监听文件打开事件
      if (PlatformAdapter.instance.isDesktop) {
        // TODO: 使用 app_links 包监听文件打开事件
        // 例如:
        // final appLinks = AppLinks();
        // appLinks.uriLinkStream.listen((Uri? uri) {
        //   if (uri?.path != null) {
        //     _fileOpenController.add(uri!.path);
        //   }
        // });

        debugPrint('FileAssociationHandler: 桌面文件关联监听已启用');
      }

      _isInitialized = true;
      debugPrint('FileAssociationHandler: 初始化成功');
      return true;
    } catch (e) {
      debugPrint('FileAssociationHandler: 初始化失败 - $e');
      return false;
    }
  }

  /// 从命令行参数解析文件路径
  String? _parseFilePathFromArgs(List<String> args) {
    if (args.length <= 1) return null;

    // 查找支持的文件扩展名
    for (final arg in args) {
      if (_isValidFilePath(arg)) {
        return arg;
      }
    }

    return null;
  }

  /// 验证文件路径
  bool _isValidFilePath(String path) {
    final lowerPath = path.toLowerCase();
    return supportedExtensions.any(
      (ext) => lowerPath.endsWith(ext),
    );
  }

  /// 处理文件打开请求
  Future<void> handleFileOpen(String filePath) async {
    if (!_isValidFilePath(filePath)) {
      debugPrint('FileAssociationHandler: 不支持的文件格式 - $filePath');
      return;
    }

    debugPrint('FileAssociationHandler: 打开文件 - $filePath');
    _fileOpenController.add(filePath);
  }

  /// 获取初始文件路径
  String? get initialFilePath => _initialFilePath;

  /// 检查文件是否为支持的格式
  bool isSupportedFile(String path) => _isValidFilePath(path);

  /// 销毁处理器
  void dispose() {
    if (_isInitialized) {
      debugPrint('FileAssociationHandler: 销毁文件关联处理器');
      _isInitialized = false;
      _fileOpenController.close();
      _instance = null;
    }
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;
}

/// 窗口状态管理器 - 仅桌面平台
/// Window state manager - Desktop only
///
/// 负责窗口位置和尺寸的持久化，支持多显示器场景
class WindowStateManager {
  WindowStateManager._();

  static WindowStateManager? _instance;

  /// 获取单例实例
  static WindowStateManager get instance {
    _instance ??= WindowStateManager._();
    return _instance!;
  }

  SharedPreferences? _prefs;

  // 存储键名
  static const String _keyPositionX = 'window_position_x';
  static const String _keyPositionY = 'window_position_y';
  static const String _keyWidth = 'window_width';
  static const String _keyHeight = 'window_height';
  static const String _keyIsMaximized = 'window_is_maximized';
  static const String _keyIsFullScreen = 'window_is_fullscreen';
  static const String _keyMonitorIndex = 'window_monitor_index';

  // 默认值
  static const double _defaultWidth = 1200.0;
  static const double _defaultHeight = 800.0;

  bool _isInitialized = false;
  WindowState? _currentState;

  /// 初始化窗口状态管理器
  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }

    try {
      debugPrint('WindowStateManager: 初始化窗口状态管理器');

      _prefs = await SharedPreferences.getInstance();
      _currentState = await _restoreState();

      _isInitialized = true;
      debugPrint('WindowStateManager: 初始化成功');
      return true;
    } catch (e) {
      debugPrint('WindowStateManager: 初始化失败 - $e');
      return false;
    }
  }

  /// 获取当前窗口状态
  WindowState get currentState {
    if (_currentState == null) {
      throw StateError('WindowStateManager 未初始化');
    }
    return _currentState!;
  }

  /// 保存窗口状态
  Future<void> saveState(WindowState state) async {
    if (!_isInitialized || _prefs == null) return;

    try {
      _currentState = state;

      await _prefs!.setDouble(_keyPositionX, state.positionX);
      await _prefs!.setDouble(_keyPositionY, state.positionY);
      await _prefs!.setDouble(_keyWidth, state.width);
      await _prefs!.setDouble(_keyHeight, state.height);
      await _prefs!.setBool(_keyIsMaximized, state.isMaximized);
      await _prefs!.setBool(_keyIsFullScreen, state.isFullScreen);
      await _prefs!.setInt(_keyMonitorIndex, state.monitorIndex);

      debugPrint('WindowStateManager: 窗口状态已保存 - '
          '位置(${state.positionX}, ${state.positionY}), '
          '大小(${state.width}x${state.height})');
    } catch (e) {
      debugPrint('WindowStateManager: 保存失败 - $e');
    }
  }

  /// 从存储中恢复窗口状态
  Future<WindowState> _restoreState() async {
    if (_prefs == null) {
      return _getDefaultState();
    }

    return WindowState(
      positionX: _prefs!.getDouble(_keyPositionX) ?? _getDefaultPositionX(),
      positionY: _prefs!.getDouble(_keyPositionY) ?? _getDefaultPositionY(),
      width: _prefs!.getDouble(_keyWidth) ?? _defaultWidth,
      height: _prefs!.getDouble(_keyHeight) ?? _defaultHeight,
      isMaximized: _prefs!.getBool(_keyIsMaximized) ?? false,
      isFullScreen: _prefs!.getBool(_keyIsFullScreen) ?? false,
      monitorIndex: _prefs!.getInt(_keyMonitorIndex) ?? 0,
    );
  }

  /// 获取默认窗口状态
  WindowState _getDefaultState() {
    return WindowState(
      positionX: _getDefaultPositionX(),
      positionY: _getDefaultPositionY(),
      width: _defaultWidth,
      height: _defaultHeight,
      isMaximized: false,
      isFullScreen: false,
      monitorIndex: 0,
    );
  }

  double _getDefaultPositionX() {
    // 计算屏幕中心位置
    return (1920 - _defaultWidth) / 2; // 假设默认屏幕宽度
  }

  double _getDefaultPositionY() {
    return (1080 - _defaultHeight) / 2; // 假设默认屏幕高度
  }

  /// 检查窗口是否在有效的显示器范围内
  bool isWindowOnValidMonitor({
    required double positionX,
    required double positionY,
    required double width,
    required double height,
    required int totalMonitors,
  }) {
    if (totalMonitors <= 0) return false;

    // 确保显示器索引有效
    final monitorIndex = _currentState?.monitorIndex ?? 0;
    if (monitorIndex >= totalMonitors) {
      return false;
    }

    // 简单的边界检查
    return positionX >= -width &&
        positionY >= -height &&
        positionX < 1920 * totalMonitors &&
        positionY < 1080;
  }

  /// 调整窗口到有效位置
  WindowState adjustToValidPosition({
    required WindowState state,
    required int totalMonitors,
  }) {
    var adjustedX = state.positionX;
    var adjustedY = state.positionY;
    var adjustedMonitor = state.monitorIndex;

    // 如果显示器索引无效，重置到主显示器
    if (adjustedMonitor >= totalMonitors) {
      adjustedMonitor = 0;
      adjustedX = _getDefaultPositionX();
      adjustedY = _getDefaultPositionY();
    }

    // 如果窗口完全在屏幕外，重置位置
    if (!isWindowOnValidMonitor(
      positionX: adjustedX,
      positionY: adjustedY,
      width: state.width,
      height: state.height,
      totalMonitors: totalMonitors,
    )) {
      adjustedX = _getDefaultPositionX();
      adjustedY = _getDefaultPositionY();
    }

    return state.copyWith(
      positionX: adjustedX,
      positionY: adjustedY,
      monitorIndex: adjustedMonitor,
    );
  }

  /// 重置窗口状态到默认值
  Future<void> resetToDefaults() async {
    if (!_isInitialized) return;

    final defaultState = _getDefaultState();
    await saveState(defaultState);

    debugPrint('WindowStateManager: 窗口状态已重置');
  }

  /// 销毁管理器
  void dispose() {
    if (_isInitialized) {
      debugPrint('WindowStateManager: 销毁窗口状态管理器');
      _isInitialized = false;
      _instance = null;
    }
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;
}

/// 窗口状态数据类
class WindowState {
  const WindowState({
    required this.positionX,
    required this.positionY,
    required this.width,
    required this.height,
    required this.isMaximized,
    required this.isFullScreen,
    required this.monitorIndex,
  });

  /// 窗口 X 坐标
  final double positionX;

  /// 窗口 Y 坐标
  final double positionY;

  /// 窗口宽度
  final double width;

  /// 窗口高度
  final double height;

  /// 是否最大化
  final bool isMaximized;

  /// 是否全屏
  final bool isFullScreen;

  /// 显示器索引
  final int monitorIndex;

  /// 创建副本
  WindowState copyWith({
    double? positionX,
    double? positionY,
    double? width,
    double? height,
    bool? isMaximized,
    bool? isFullScreen,
    int? monitorIndex,
  }) {
    return WindowState(
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      width: width ?? this.width,
      height: height ?? this.height,
      isMaximized: isMaximized ?? this.isMaximized,
      isFullScreen: isFullScreen ?? this.isFullScreen,
      monitorIndex: monitorIndex ?? this.monitorIndex,
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'positionX': positionX,
      'positionY': positionY,
      'width': width,
      'height': height,
      'isMaximized': isMaximized,
      'isFullScreen': isFullScreen,
      'monitorIndex': monitorIndex,
    };
  }

  /// 从 Map 创建
  factory WindowState.fromMap(Map<String, dynamic> map) {
    return WindowState(
      positionX: (map['positionX'] as num?)?.toDouble() ?? 0.0,
      positionY: (map['positionY'] as num?)?.toDouble() ?? 0.0,
      width: (map['width'] as num?)?.toDouble() ?? 1200.0,
      height: (map['height'] as num?)?.toDouble() ?? 800.0,
      isMaximized: map['isMaximized'] as bool? ?? false,
      isFullScreen: map['isFullScreen'] as bool? ?? false,
      monitorIndex: map['monitorIndex'] as int? ?? 0,
    );
  }
}

/// 平台工具类 - 集合常用工具方法
/// Platform utilities - Collection of common utility methods
class PlatformUtils {
  PlatformUtils._();

  /// 获取平台类型
  static PlatformType get platformType {
    if (kIsWeb) return PlatformType.web;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return PlatformType.desktop;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return PlatformType.mobile;
    }
    return PlatformType.web;
  }

  /// 检查是否为桌面平台
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 检查是否为移动平台
  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 检查是否为 Web 平台
  static bool get isWeb => kIsWeb;

  /// 检查是否为 Windows
  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 检查是否为 macOS
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// 检查是否为 Linux
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// 检查是否为 Android
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 检查是否为 iOS
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// 检查是否支持键盘快捷键
  static bool get supportsKeyboardShortcuts => isDesktop;

  /// 检查是否支持悬停
  static bool get supportsHover => isDesktop;

  /// 检查是否支持触控板手势
  static bool get supportsTrackpadGestures => isDesktop;

  /// 检查是否支持多窗口
  static bool get supportsMultipleWindows => isDesktop;
}
