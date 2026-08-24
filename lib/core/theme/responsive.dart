// 响应式设计系统 - Responsive Design System
//
// 提供统一的断点定义、响应式布局工具和平台适配。
// 目标：电脑版、手机版、平板版都能按比例适配，不出现 UI 错乱和位移。
//
// 使用方式：
// ```dart
// // 1. 使用 ResponsiveBuilder 构建不同断点的布局
// ResponsiveBuilder(
//   mobile: (context) => MobileLayout(),
//   tablet: (context) => TabletLayout(),
//   desktop: (context) => DesktopLayout(),
// )
//
// // 2. 使用 ResponsiveValue 获取不同断点的值
// final padding = ResponsiveValue<double>(
//   mobile: 12.0,
//   tablet: 16.0,
//   desktop: 24.0,
// ).value(context);
//
// // 3. 使用扩展方法
// context.responsivePadding  // 根据断点返回不同的 padding
// context.scale(16)          // 根据屏幕宽度按比例缩放
// ```
import 'package:flutter/material.dart';

/// 响应式断点定义
/// Responsive breakpoints
class ResponsiveBreakpoints {
  ResponsiveBreakpoints._();

  /// 移动端最大宽度 (Mobile: < 600px)
  static const double mobile = 600.0;

  /// 平板端最大宽度 (Tablet: 600px - 1024px)
  static const double tablet = 1024.0;

  /// 桌面端最小宽度 (Desktop: >= 1024px)
  static const double desktop = 1024.0;

  /// 大屏幕最小宽度 (Large desktop: >= 1440px)
  static const double largeDesktop = 1440.0;
}

/// 设备类型枚举
enum DeviceType {
  mobile,
  tablet,
  desktop,
}

/// 响应式工具类
class Responsive {
  Responsive._();

  /// 根据屏幕宽度获取设备类型
  static DeviceType deviceType(double width) {
    if (width < ResponsiveBreakpoints.mobile) return DeviceType.mobile;
    if (width < ResponsiveBreakpoints.tablet) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  /// 是否为移动端
  static bool isMobile(double width) => width < ResponsiveBreakpoints.mobile;

  /// 是否为平板端
  static bool isTablet(double width) =>
      width >= ResponsiveBreakpoints.mobile && width < ResponsiveBreakpoints.tablet;

  /// 是否为桌面端
  static bool isDesktop(double width) => width >= ResponsiveBreakpoints.tablet;

  /// 获取响应式值
  /// Get responsive value based on current breakpoint
  static T value<T>({
    required double screenWidth,
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (screenWidth < ResponsiveBreakpoints.mobile) return mobile;
    if (screenWidth < ResponsiveBreakpoints.tablet) return tablet ?? mobile;
    return desktop;
  }

  /// 线性插值缩放
  /// Linear interpolation scaling for smooth transitions
  static double scale(
    double screenWidth, {
    required double minValue,
    required double maxValue,
    double minWidth = ResponsiveBreakpoints.mobile,
    double maxWidth = ResponsiveBreakpoints.desktop,
  }) {
    if (screenWidth <= minWidth) return minValue;
    if (screenWidth >= maxWidth) return maxValue;
    final t = (screenWidth - minWidth) / (maxWidth - minWidth);
    return minValue + (maxValue - minValue) * t;
  }

  /// 计算响应式字体大小
  /// Responsive font size with clamping
  static double fontSize(
    double screenWidth, {
    required double mobile,
    double? tablet,
    required double desktop,
  }) {
    return value(
      screenWidth: screenWidth,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}

/// 响应式构建器
/// Responsive builder widget for different breakpoints
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < ResponsiveBreakpoints.mobile) {
      return mobile(context);
    }
    if (width < ResponsiveBreakpoints.tablet) {
      return tablet?.call(context) ?? mobile(context);
    }
    return desktop(context);
  }
}

/// 响应式值
/// Responsive value that changes based on breakpoint
class ResponsiveValue<T> {
  const ResponsiveValue({
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  final T mobile;
  final T? tablet;
  final T desktop;

  T value(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Responsive.value(screenWidth: width, mobile: mobile, tablet: tablet, desktop: desktop);
  }
}

/// 响应式间距
/// Responsive spacing values
class ResponsiveSpacing {
  ResponsiveSpacing._();

  static double all(BuildContext context, double base) {
    final width = MediaQuery.of(context).size.width;
    return Responsive.scale(width, minValue: base * 0.75, maxValue: base * 1.5);
  }

  static EdgeInsets padding(BuildContext context, {
    double? horizontal,
    double? vertical,
  }) {
    final width = MediaQuery.of(context).size.width;
    final h = horizontal != null
        ? Responsive.scale(width, minValue: horizontal * 0.6, maxValue: horizontal * 1.5)
        : null;
    final v = vertical != null
        ? Responsive.scale(width, minValue: vertical * 0.6, maxValue: vertical * 1.5)
        : null;

    if (h != null && v != null) {
      return EdgeInsets.symmetric(horizontal: h, vertical: v);
    }
    if (h != null) {
      return EdgeInsets.symmetric(horizontal: h);
    }
    if (v != null) {
      return EdgeInsets.symmetric(vertical: v);
    }
    return EdgeInsets.zero;
  }
}

/// BuildContext 扩展 - 响应式工具
/// BuildContext extensions for responsive design
extension ResponsiveContext on BuildContext {
  /// 屏幕宽度
  double get screenWidth => MediaQuery.of(this).size.width;

  /// 屏幕高度
  double get screenHeight => MediaQuery.of(this).size.height;

  /// 设备类型
  DeviceType get deviceType => Responsive.deviceType(screenWidth);

  /// 是否为移动端
  bool get isMobile => Responsive.isMobile(screenWidth);

  /// 是否为平板端
  bool get isTablet => Responsive.isTablet(screenWidth);

  /// 是否为桌面端
  bool get isDesktop => Responsive.isDesktop(screenWidth);

  /// 响应式缩放
  /// Scale a value based on screen width
  double responsiveScale(double base, {double minFactor = 0.75, double maxFactor = 1.5}) {
    return Responsive.scale(screenWidth, minValue: base * minFactor, maxValue: base * maxFactor);
  }

  /// 响应式字体大小
  double responsiveFont({
    required double mobile,
    double? tablet,
    required double desktop,
  }) {
    return Responsive.fontSize(screenWidth, mobile: mobile, tablet: tablet, desktop: desktop);
  }

  /// 响应式内边距
  EdgeInsets responsivePadding({
    double? horizontal,
    double? vertical,
  }) {
    return ResponsiveSpacing.padding(
      this,
      horizontal: horizontal,
      vertical: vertical,
    );
  }

  /// 响应式水平间距
  Widget responsiveHSpace(double base) {
    return SizedBox(width: responsiveScale(base));
  }

  /// 响应式垂直间距
  Widget responsiveVSpace(double base) {
    return SizedBox(height: responsiveScale(base));
  }
}

/// 响应式布局容器
/// Responsive layout container that adapts to screen size
class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.mobilePadding = const EdgeInsets.all(12),
    this.tabletPadding = const EdgeInsets.all(16),
    this.desktopPadding = const EdgeInsets.all(24),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsets mobilePadding;
  final EdgeInsets tabletPadding;
  final EdgeInsets desktopPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    EdgeInsets padding;
    double? effectiveMaxWidth;

    if (width < ResponsiveBreakpoints.mobile) {
      padding = mobilePadding;
      effectiveMaxWidth = maxWidth;
    } else if (width < ResponsiveBreakpoints.tablet) {
      padding = tabletPadding;
      effectiveMaxWidth = maxWidth ?? 800;
    } else {
      padding = desktopPadding;
      effectiveMaxWidth = maxWidth ?? 1200;
    }

    return Container(
      alignment: alignment,
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth ?? double.infinity),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// 响应式网格
/// Responsive grid that adjusts column count based on screen width
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 12,
    this.childAspectRatio = 1.0,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    int columns;
    if (width < ResponsiveBreakpoints.mobile) {
      columns = mobileColumns;
    } else if (width < ResponsiveBreakpoints.tablet) {
      columns = tabletColumns;
    } else {
      columns = desktopColumns;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}

/// 响应式行/列布局
/// Responsive row/column layout that switches based on screen size
class ResponsiveRowColumn extends StatelessWidget {
  const ResponsiveRowColumn({
    super.key,
    required this.children,
    this.mainAxisSize = MainAxisSize.max,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing = 8.0,
    this.breakpoint = ResponsiveBreakpoints.mobile,
  });

  final List<Widget> children;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isRow = width >= breakpoint;

    if (isRow) {
      return Row(
        mainAxisSize: mainAxisSize,
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        children: _withSpacing(children, spacing, true),
      );
    }
    return Column(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: _withSpacing(children, spacing, false),
    );
  }

  List<Widget> _withSpacing(List<Widget> children, double spacing, bool isRow) {
    if (children.isEmpty) return children;
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(isRow
            ? SizedBox(width: spacing)
            : SizedBox(height: spacing));
      }
    }
    return result;
  }
}

/// 平台自适应组件
/// Platform-adaptive widget that shows different content based on platform
class PlatformAdaptiveWidget extends StatelessWidget {
  const PlatformAdaptiveWidget({
    super.key,
    this.mobile,
    this.tablet,
    this.desktop,
    required this.fallback,
  });

  final Widget? mobile;
  final Widget? tablet;
  final Widget? desktop;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < ResponsiveBreakpoints.mobile) {
      return mobile ?? fallback;
    }
    if (width < ResponsiveBreakpoints.tablet) {
      return tablet ?? mobile ?? fallback;
    }
    return desktop ?? tablet ?? mobile ?? fallback;
  }
}
