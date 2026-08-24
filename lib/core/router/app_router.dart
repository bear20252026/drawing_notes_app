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
import 'package:path_provider/path_provider.dart';

import 'package:editor_core/editor_core.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/editor_v2/presentation/editor_v2_screen.dart';
import 'package:drawing_notes_app/features/notes/presentation/password_disk_page.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/core/security/auth_guard.dart';
import 'package:drawing_notes_app/core/exceptions/app_exceptions.dart';
import 'package:drawing_notes_app/core/ui/widgets/app_error_widget.dart';

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

    // 全局路由守卫：认证检查
    redirect: (BuildContext context, GoRouterState state) {
      final location = state.matchedLocation;
      final auth = AuthGuard.instance;

      // 不拦截密码盘页本身（避免死循环）
      if (location == RoutePaths.passwordDisk) return null;

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
          return EditorPage(
            document: DrawingDocument(id: docId, title: title),
            docStorage: StorageService(),
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
          return NotebookViewPage(
            notebook: Notebook(
              id: notebookId,
              title: title,
            ),
            storage: NotebookStorage(),
          );
        },
      ),

      // =====================================================================
      // 密码盘页（路由守卫目标）
      // =====================================================================
      GoRoute(
        path: RoutePaths.passwordDisk,
        name: RouteNames.passwordDisk,
        builder: (context, state) {
          return const PasswordDiskPage();
        },
      ),

      // =====================================================================
      // 404
      // =====================================================================
      GoRoute(
        path: '/404',
        name: 'not-found',
        builder: (context, state) => Scaffold(
          body: AppErrorWidget(
            error: const UIException(
              code: 'ROUTE_NOT_FOUND',
              message: '页面未找到',
            ),
            onRetry: () => context.go(RoutePaths.home),
          ),
        ),
      ),
    ],

    // 未匹配路由 → 404
    errorBuilder: (context, state) => Scaffold(
      body: AppErrorWidget(
        error: UIException(
          code: 'ROUTE_NOT_FOUND',
          message: '页面未找到: ${state.matchedLocation}',
        ),
        onRetry: () => context.go(RoutePaths.home),
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
///
/// 解析 drawingnotes:// 协议的 URI。
class DeepLinkParser {
  DeepLinkParser._();

  /// 协议前缀
  static const String scheme = 'drawingnotes';

  /// 解析深度链接
  ///
  /// 支持的格式：
  /// - drawingnotes://home — 首页
  /// - drawingnotes://editor/{docId} — 编辑器
  /// - drawingnotes://editor-v2/{docId}?mode=note — V2 编辑器（笔记模式）
  /// - drawingnotes://notebook/{notebookId} — 笔记本
  /// - drawingnotes://open?path=/path/to/file.drawingnotes — 打开文件
  static DeepLinkResult? parse(Uri uri) {
    if (uri.scheme != scheme) return null;

    final host = uri.host;
    final pathSegments = uri.pathSegments;

    // drawingnotes://open?path=...
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

    // drawingnotes://home
    if (host == 'home' || host.isEmpty) {
      return const DeepLinkResult(
        type: DeepLinkType.home,
        route: '/',
      );
    }

    // drawingnotes://editor/{docId}
    if (host == 'editor' && pathSegments.isNotEmpty) {
      final docId = pathSegments.first;
      return DeepLinkResult(
        type: DeepLinkType.editor,
        route: '${RoutePaths.editor}/$docId',
        documentId: docId,
      );
    }

    // drawingnotes://editor-v2/{docId}
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

    // drawingnotes://notebook/{notebookId}
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
  ///
  /// Windows: app.exe /path/to/file.drawingnotes
  /// macOS/Linux: app /path/to/file.drawingnotes
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
///
/// 处理深度链接的调度和文件关联打开。
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

  /// 从文件路径提取文档 ID
  static String _extractDocIdFromPath(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    return fileName.replaceAll('.drawingnotes', '');
  }
}
