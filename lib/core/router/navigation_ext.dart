/// GoRouter 导航扩展（2026-08-25）
///
/// 提供类型安全的导航方法，替代 Navigator.push(MaterialPageRoute(...))。
/// 支持：
/// - context.pushRoute(routeName, params)
/// - context.goRoute(routeName, params)
/// - context.replaceRoute(routeName, params)
/// - context.popOrHome()
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';

/// 导航参数集合。
class NavigationParams {
  const NavigationParams({
    this.queryParams = const {},
    this.extra,
  });

  final Map<String, String> queryParams;
  final Object? extra;

  /// 从路径参数和查询参数构建 URI 查询字符串。
  String toQueryString() {
    if (queryParams.isEmpty) return '';
    final params = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '?$params';
  }
}

/// GoRouter 上下文导航扩展。
extension GoRouterNavigation on BuildContext {
  // ──────────── 基础导航 ────────────

  /// 导航到首页（清除导航栈）。
  void goHome() => go(RoutePaths.home);

  /// 返回上一页，如果在首页则无操作。
  void popOrHome() {
    final router = GoRouter.of(this);
    final canPop = router.canPop();
    if (canPop) {
      pop();
    } else {
      goHome();
    }
  }

  // ──────────── 命名路由导航 ────────────

  /// 导航到编辑器 V1。
  void goEditor(String docId, {String title = '未命名'}) {
    go('${RoutePaths.editor}/$docId?title=${Uri.encodeComponent(title)}');
  }

  /// 推入编辑器 V1。
  Future<T?> pushEditor<T>(String docId, {String title = '未命名'}) {
    return push<T>('${RoutePaths.editor}/$docId?title=${Uri.encodeComponent(title)}');
  }

  /// 导航到编辑器 V2。
  void goEditorV2(String docId, {String mode = 'whiteboard'}) {
    go('${RoutePaths.editorV2}/$docId?mode=$mode');
  }

  /// 推入编辑器 V2。
  Future<T?> pushEditorV2<T>(String docId, {String mode = 'whiteboard'}) {
    return push<T>(
        '${RoutePaths.editorV2}/$docId?mode=$mode');
  }

  /// 导航到笔记本视图。
  void goNotebook(String notebookId, {String title = '未命名笔记本'}) {
    go(
        '${RoutePaths.notebook}/$notebookId?title=${Uri.encodeComponent(title)}');
  }

  /// 推入笔记本视图。
  Future<T?> pushNotebook<T>(String notebookId,
      {String title = '未命名笔记本'}) {
    return push<T>(
        '${RoutePaths.notebook}/$notebookId?title=${Uri.encodeComponent(title)}');
  }

  /// 导航到密码盘页。
  void goPasswordDisk({String? redirect}) {
    final query = redirect != null ? '?redirect=${Uri.encodeComponent(redirect)}' : '';
    go('${RoutePaths.passwordDisk}$query');
  }

  /// 推入密码盘页。
  Future<T?> pushPasswordDisk<T>({String? redirect}) {
    final query = redirect != null ? '?redirect=${Uri.encodeComponent(redirect)}' : '';
    return push<T>('${RoutePaths.passwordDisk}$query');
  }

  /// 导航到设置页。
  void goSettings() => go(RoutePaths.settings);

  /// 推入设置页。
  Future<T?> pushSettings<T>() => push<T>(RoutePaths.settings);

  /// 导航到搜索页。
  void goSearch() => go(RoutePaths.search);

  /// 推入搜索页。
  Future<T?> pushSearch<T>() => push<T>(RoutePaths.search);

  /// 导航到演示页。
  void goPresentation() => go(RoutePaths.presentation);

  /// 推入演示页。
  Future<T?> pushPresentation<T>() => push<T>(RoutePaths.presentation);

  /// 导航到引导页。
  void goOnboarding() => go(RoutePaths.onboarding);

  /// 导航到形状库。
  void goShapeLibrary() => go(RoutePaths.shapeLibrary);

  /// 推入形状库。
  Future<T?> pushShapeLibrary<T>() => push<T>(RoutePaths.shapeLibrary);

  /// 导航到 404 页。
  void goNotFound({String? subtitle}) {
    final query = subtitle != null
        ? '?subtitle=${Uri.encodeComponent(subtitle)}'
        : '';
    go('/404$query');
  }
}
