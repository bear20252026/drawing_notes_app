/// GoRouter 统一路由配置（P2 #34 深度链接和路由守卫）
///
/// 职责：
/// - 声明式路由定义
/// - 深度链接支持（drawingnotes://）
/// - 文件关联打开（.drawingnotes）
/// - 路由守卫（认证 → 密码盘页，加密 → 提示）
library;

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/drawing/application/search_service.dart';
import '../../features/editor_v2/presentation/editor_v2_screen.dart';
import '../../features/notes/domain/notebook.dart';
import '../../features/notes/infrastructure/services/notebook_storage.dart';
import '../../features/notes/presentation/home_page.dart';
import 'package:editor_core/editor_core.dart';
import '../../features/notes/presentation/notebook_view_page.dart';
import '../../features/notes/presentation/password_disk_page.dart';
import '../../features/notes/presentation/presentation_page.dart';
import '../../features/notes/presentation/search_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/security/presentation/pm_code_setup_page.dart';
import '../../features/security/presentation/pm_code_input_page.dart';
import '../../features/settings/presentation/app_lock_page.dart';
import '../../features/settings/presentation/app_lock_settings_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/shapes/presentation/shape_library_page.dart';
import '../security/auth_guard.dart';
import '../storage/storage_service.dart';
import '../theme/text_scale_helper.dart';

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
  static const appLock = '/app-lock';
  static const appLockSettings = '/app-lock-settings';
  static const pmCodeSetup = '/pm-code-setup';
  static const pmCodeInput = '/pm-code-input';
  static const settings = '/settings';
  static const search = '/search';
  static const presentation = '/presentation';
  static const onboarding = '/onboarding';
  static const shapeLibrary = '/shape-library';
}

/// 路由名称常量
class RouteNames {
  RouteNames._();

  static const home = 'home';
  static const editor = 'editor';
  static const editorV2 = 'editor-v2';
  static const notebook = 'notebook';
  static const passwordDisk = 'password-disk';
  static const appLock = 'app-lock';
  static const appLockSettings = 'app-lock-settings';
  static const pmCodeSetup = 'pm-code-setup';
  static const pmCodeInput = 'pm-code-input';
  static const settings = 'settings';
  static const search = 'search';
  static const presentation = 'presentation';
  static const onboarding = 'onboarding';
  static const shapeLibrary = 'shape-library';
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
    refreshListenable: AuthGuard.instance,  // AuthGuard 状态变更时重新评估 redirect

    // 全局路由守卫：认证 + 加密检查 + 应用锁检查
    redirect: (BuildContext context, GoRouterState state) {
      final location = state.matchedLocation;
      final auth = AuthGuard.instance;

      // 不拦截密码盘页本身（避免死循环）
      if (location == RoutePaths.passwordDisk) return null;

      // 不拦截应用锁页本身（避免死循环）
      if (location == RoutePaths.appLock) return null;

      // 不拦截 404 页
      if (location == '/404') return null;

      // 需要认证时（有密码盘且未跳过加密），重定向到密码盘页
      if (auth.requiresAuth && !auth.isAuthenticated) {
        final redirectPath = Uri.encodeComponent(location);
        return '${RoutePaths.passwordDisk}?redirect=$redirectPath';
      }

      // 需要应用锁验证时，重定向到应用锁页
      // 注意：密码盘验证优先于应用锁（密码盘是更高级别的安全机制）
      if (auth.requiresAppLock) {
        return RoutePaths.appLock;
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
      // 编辑器 V1（真实 EditorPage）
      // =====================================================================
      GoRoute(
        path: '${RoutePaths.editor}/:docId',
        name: RouteNames.editor,
        builder: (context, state) {
          final docId = state.pathParameters['docId']!;
          final title = state.uri.queryParameters['title'] ?? '未命名';
          return _EditorPageWrapper(docId: docId, title: title);
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
      // 笔记本视图（真实 NotebookViewPage）
      // =====================================================================
      GoRoute(
        path: '${RoutePaths.notebook}/:notebookId',
        name: RouteNames.notebook,
        builder: (context, state) {
          final notebookId = state.pathParameters['notebookId']!;
          final title = state.uri.queryParameters['title'] ?? '未命名笔记本';
          return _NotebookViewWrapper(notebookId: notebookId, title: title);
        },
      ),

      // =====================================================================
      // 密码盘页（路由守卫目标）
      // =====================================================================
      GoRoute(
        path: RoutePaths.passwordDisk,
        name: RouteNames.passwordDisk,
        builder: (context, state) {
          final redirect = state.uri.queryParameters['redirect'];
          return PasswordDiskPage(
            redirect: redirect,
          );
        },
      ),

      // =====================================================================
      // 应用锁页（应用级密码锁定）
      // =====================================================================
      GoRoute(
        path: RoutePaths.appLock,
        name: RouteNames.appLock,
        builder: (context, state) => const AppLockPage(),
      ),

      // =====================================================================
      // 应用锁设置页
      // =====================================================================
      GoRoute(
        path: RoutePaths.appLockSettings,
        name: RouteNames.appLockSettings,
        builder: (context, state) => const AppLockSettingsPage(),
      ),

      // =====================================================================
      // PM码（胁迫密码）设置页
      // =====================================================================
      GoRoute(
        path: RoutePaths.pmCodeSetup,
        name: RouteNames.pmCodeSetup,
        builder: (context, state) => const PmCodeSetupPage(),
      ),

      // =====================================================================
      // PM码（胁迫密码）输入页
      // =====================================================================
      GoRoute(
        path: RoutePaths.pmCodeInput,
        name: RouteNames.pmCodeInput,
        builder: (context, state) => const PmCodeInputPage(),
      ),

      // =====================================================================
      // 404
      // =====================================================================
      GoRoute(
        path: '/404',
        name: 'not-found',
        builder: (context, state) => _buildNotFoundPage(context),
      ),

      // =====================================================================
      // 设置（真实 SettingsPage）
      // =====================================================================
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),

      // =====================================================================
      // 搜索（真实 SearchPage）
      // =====================================================================
      GoRoute(
        path: RoutePaths.search,
        name: RouteNames.search,
        builder: (context, state) => SearchPage(
          searchService: SearchService(docStorage: StorageService()),
        ),
      ),

      // =====================================================================
      // 演示模式（真实 PresentationPage）
      // =====================================================================
      GoRoute(
        path: RoutePaths.presentation,
        name: RouteNames.presentation,
        builder: (context, state) {
          final notebookId = state.uri.queryParameters['notebookId'];
          if (notebookId != null) {
            return _PresentationWrapper(notebookId: notebookId);
          }
          return Scaffold(
            appBar: AppBar(title: const Text('演示模式')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '请从主页选择一本笔记本进入演示模式。\n\n'
                  '提示：在主页长按笔记本，选择「演示」。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),

      // =====================================================================
      // 引导页（真实 OnboardingPage）
      // =====================================================================
      GoRoute(
        path: RoutePaths.onboarding,
        name: RouteNames.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),

      // =====================================================================
      // 形状库（真实 ShapeLibraryPage）
      // =====================================================================
      GoRoute(
        path: RoutePaths.shapeLibrary,
        name: RouteNames.shapeLibrary,
        builder: (context, state) => const ShapeLibraryPage(),
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
          const Icon(Icons.error_outline, size: 64, color: Color(0xFFFF3B30)),
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
// 路由包装器（异步加载文档/笔记本）
// ============================================================================

/// V2 编辑器包装器 — 异步加载文档后传入 EditorV2Screen。
class _EditorPageWrapper extends StatefulWidget {
  const _EditorPageWrapper({required this.docId, required this.title});

  final String docId;
  final String title;

  @override
  State<_EditorPageWrapper> createState() => _EditorPageWrapperState();
}

class _EditorPageWrapperState extends State<_EditorPageWrapper> {
  @override
  Widget build(BuildContext context) {
    // Apple 风格：使用 V2 编辑器，保持统一架构
    return EditorV2Screen(
      documentId: widget.docId,
      mode: UnifiedEditorMode.whiteboard,
    );
  }
}

/// 笔记本视图包装器 — 异步加载 Notebook 后传入 NotebookViewPage。
class _NotebookViewWrapper extends StatefulWidget {
  const _NotebookViewWrapper({required this.notebookId, required this.title});

  final String notebookId;
  final String title;

  @override
  State<_NotebookViewWrapper> createState() => _NotebookViewWrapperState();
}

class _NotebookViewWrapperState extends State<_NotebookViewWrapper> {
  late final Future<Notebook?> _future;
  final _storage = NotebookStorage();

  @override
  void initState() {
    super.initState();
    _future = _storage.load(widget.notebookId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Notebook?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(child: CupertinoActivityIndicator(radius: 14)),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Color(0xFFFF3B30)),
                  const SizedBox(height: 16),
                  Text('无法加载笔记本: ${widget.notebookId}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(RoutePaths.home),
                    child: const Text('返回首页'),
                  ),
                ],
              ),
            ),
          );
        }

        return NotebookViewPage(
          notebook: snapshot.data!,
          storage: _storage,
        );
      },
    );
  }
}

/// 演示模式包装器 — 从笔记本加载内容并映射为 PresentationPage 所需格式。
class _PresentationWrapper extends StatefulWidget {
  const _PresentationWrapper({required this.notebookId});

  final String notebookId;

  @override
  State<_PresentationWrapper> createState() => _PresentationWrapperState();
}

class _PresentationWrapperState extends State<_PresentationWrapper> {
  late final Future<Notebook?> _future;

  @override
  void initState() {
    super.initState();
    _future = NotebookStorage().load(widget.notebookId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Notebook?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CupertinoActivityIndicator(radius: 14)),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Color(0xFFFF3B30)),
                  const SizedBox(height: 16),
                  Text('无法加载笔记本: ${widget.notebookId}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(RoutePaths.home),
                    child: const Text('返回首页'),
                  ),
                ],
              ),
            ),
          );
        }

        final notebook = snapshot.data!;
        // 从笔记本页面映射演示内容
        final allTextItems = <PageTextItem>[];
        final allImageItems = <PageImageItem>[];
        final allShapes = <PageShapeItem>[];

        for (final page in notebook.pages) {
          allTextItems.addAll(page.textItems);
          allImageItems.addAll(page.imageItems);
          allShapes.addAll(page.shapes);
        }

        return PresentationPage(
          textItems: allTextItems,
          imageItems: allImageItems,
          shapes: allShapes,
        );
      },
    );
  }
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
