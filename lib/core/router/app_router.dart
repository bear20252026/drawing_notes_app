/// GoRouter 统一路由配置（P2 #34 深度链接和路由守卫）
///
/// 职责：
/// - 声明式路由定义
/// - 深度链接支持（drawingnotes://）
/// - 文件关联打开（.drawingnotes）
/// - 路由守卫（认证 → 密码盘页，加密 → 提示）
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:drawing_notes_app/core/security/auth_guard.dart';
import 'package:drawing_notes_app/core/theme/text_scale_helper.dart';
import 'package:drawing_notes_app/features/editor_v2/presentation/editor_v2_screen.dart';
import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/password_disk_page.dart';

// ============================================================================
// 路由常量
// ============================================================================

/// 路由路径常量
class RoutePaths {
  RoutePaths._();

  static const home = '/';
  static const editor = '/editor';
  static const editorV2 = '/editor-v2';
  static const notebook = '/notebook';
  static const passwordDisk = '/password-disk';
  static const settings = '/settings';
}

/// 路由名称常量
class RouteNames {
  RouteNames._();

  static const home = 'home';
  static const editor = 'editor';
  static const editorV2 = 'editor-v2';
  static const notebook = 'notebook';
  static const passwordDisk = 'password-disk';
  static const settings = 'settings';
}

// ============================================================================
// GoRouter 配置
// ============================================================================

/// 全局 Navigator Key
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

/// 创建 GoRouter 实例
GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RoutePaths.home,
    debugLogDiagnostics: false,

    // 全局路由守卫：认证 + 加密检查
    redirect: (BuildContext context, GoRouterState state) {
      final location = state.matchedLocation;
      final auth = AuthGuard.instance;

      // 不拦截密码盘页本身（避免死循环）
      if (location == RoutePaths.passwordDisk) return null;

      // 不拦截 404 页
      if (location == '/404') return null;

      // 如果密码盘已设置但会话未认证，重定向到密码盘页
      if (auth.passwordDiskExists && !auth.isAuthenticated) {
        final redirectPath = Uri.encodeComponent(location);
        return '${RoutePaths.passwordDisk}?redirect=$redirectPath';
      }

      return null;
    },

    routes: [
      // =====================================================================
      // 首页
      // =====================================================================
      GoRoute(
        path: RoutePaths.home,
        name: RouteNames.home,
        builder: (context, state) => const HomePage(),
      ),

      // =====================================================================
      // 编辑器 V1
      // =====================================================================
      GoRoute(
        path: '${RoutePaths.editor}/:docId',
        name: RouteNames.editor,
        builder: (context, state) {
          final docId = state.pathParameters['docId']!;
          final title = state.uri.queryParameters['title'] ?? '未命名';
          // TODO: 接入 EditorPage(document: doc, docStorage: StorageService())
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Center(child: Text('编辑器: $docId')),
          );
        },
      ),

      // =====================================================================
      // 编辑器 V2
      // =====================================================================
      GoRoute(
        path: '${RoutePaths.editorV2}/:docId',
        name: RouteNames.editorV2,
        builder: (context, state) {
          final docId = state.pathParameters['docId']!;
          final modeStr = state.uri.queryParameters['mode'];
          final mode = modeStr == 'note'
              ? UnifiedEditorMode.note
              : UnifiedEditorMode.whiteboard;
          return EditorV2Screen(
            documentId: docId,
            mode: mode,
          );
        },
      ),

      // =====================================================================
      // 笔记本视图
      // =====================================================================
      GoRoute(
        path: '${RoutePaths.notebook}/:notebookId',
        name: RouteNames.notebook,
        builder: (context, state) {
          final notebookId = state.pathParameters['notebookId']!;
          final title = state.uri.queryParameters['title'] ?? '未命名笔记本';
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: Center(child: Text('笔记本: $notebookId')),
          );
        },
      ),

      // =====================================================================
      // 密码盘页（路由守卫目标）
      // =====================================================================
      GoRoute(
        path: RoutePaths.passwordDisk,
        name: RouteNames.passwordDisk,
        builder: (context, state) => const PasswordDiskPage(),
      ),

      // =====================================================================
      // 404
      // =====================================================================
      GoRoute(
        path: '/404',
        name: 'not-found',
        builder: (context, state) => _buildNotFoundPage(context),
      ),
    ],

    // 未匹配路由 → 404
    errorBuilder: (context, state) => _buildNotFoundPage(
      context,
      subtitle: '页面未找到: ${state.matchedLocation}',
    ),
  );
}

// ============================================================================
// 辅助页面构建器
// ============================================================================

Widget _buildNotFoundPage(BuildContext context, {String? subtitle}) {
  return Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 24),
          Text(
            subtitle ?? '页面未找到',
            style: TextStyle(
              fontSize: TextScaleHelper.scaled(context, 18),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go(RoutePaths.home),
            icon: const Icon(Icons.home),
            label: const Text('返回首页'),
          ),
        ],
      ),
    ),
  );
}

// ============================================================================
// 深度链接
// ============================================================================

/// 深度链接类型
enum DeepLinkType {
  home,
  editor,
  editorV2,
  notebook,
  openFile,
}

/// 深度链接解析结果
class DeepLinkResult {
  const DeepLinkResult({
    required this.type,
    this.route,
    this.filePath,
    this.documentId,
    this.notebookId,
    this.extra,
  });

  final DeepLinkType type;
  final String? route;
  final String? filePath;
  final String? documentId;
  final String? notebookId;
  final Map<String, dynamic>? extra;
}

/// 深度链接解析器
class DeepLinkParser {
  DeepLinkParser._();

  /// 协议前缀
  static const String scheme = 'drawingnotes';

  /// 解析深度链接
  static DeepLinkResult? parse(Uri uri) {
    if (uri.scheme != scheme) return null;

    final host = uri.host;
    final pathSegments = uri.pathSegments;

    if (host == 'open') {
      final filePath = uri.queryParameters['path'];
      if (filePath != null && filePath.isNotEmpty) {
        return DeepLinkResult(
          type: DeepLinkType.openFile,
          filePath: filePath,
        );
      }
      return null;
    }

    if (host == 'home' || host.isEmpty) {
      return const DeepLinkResult(type: DeepLinkType.home, route: '/');
    }

    if (host == 'editor' && pathSegments.isNotEmpty) {
      final docId = pathSegments.first;
      return DeepLinkResult(
        type: DeepLinkType.editor,
        route: '${RoutePaths.editor}/$docId',
        documentId: docId,
      );
    }

    if (host == 'editor-v2' && pathSegments.isNotEmpty) {
      final docId = pathSegments.first;
      final mode = uri.queryParameters['mode'] ?? 'whiteboard';
      return DeepLinkResult(
        type: DeepLinkType.editorV2,
        route: '${RoutePaths.editorV2}/$docId?mode=$mode',
        documentId: docId,
        extra: {'mode': mode},
      );
    }

    if (host == 'notebook' && pathSegments.isNotEmpty) {
      final notebookId = pathSegments.first;
      return DeepLinkResult(
        type: DeepLinkType.notebook,
        route: '${RoutePaths.notebook}/$notebookId',
        notebookId: notebookId,
      );
    }

    return null;
  }

  /// 从命令行参数解析文件关联打开
  static DeepLinkResult? parseFileAssociation(List<String> args) {
    if (args.isEmpty) return null;

    for (final arg in args) {
      if (arg.endsWith('.drawingnotes') && !arg.startsWith('-')) {
        return DeepLinkResult(
          type: DeepLinkType.openFile,
          filePath: arg,
        );
      }
    }

    return null;
  }
}

// ============================================================================
// 深度链接调度服务
// ============================================================================

/// 深度链接服务
class DeepLinkService {
  DeepLinkService._();

  /// 处理深度链接路由
  static void handleDeepLink(GoRouter router, DeepLinkResult result) {
    switch (result.type) {
      case DeepLinkType.openFile:
        _handleFileOpen(router, result.filePath!);
        break;
      case DeepLinkType.editor:
      case DeepLinkType.editorV2:
      case DeepLinkType.notebook:
      case DeepLinkType.home:
        if (result.route != null) {
          router.go(result.route!);
        }
        break;
    }
  }

  /// 处理文件关联打开
  static void _handleFileOpen(GoRouter router, String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      router.go(
        '${RoutePaths.home}?error=${Uri.encodeComponent('文件不存在: $filePath')}',
      );
      return;
    }

    final docId = _extractDocIdFromPath(filePath);
    router.go(
      '${RoutePaths.editor}/$docId?title=${Uri.encodeComponent(file.uri.pathSegments.last)}',
    );
  }

  static String _extractDocIdFromPath(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    return fileName.replaceAll('.drawingnotes', '');
  }
}
