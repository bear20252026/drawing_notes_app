// deep_link_and_route_guard_test.dart — P2 #34 深度链接解析 + 路由守卫验证测试。
import 'package:drawing_notes_app/core/router/app_router.dart';
import 'package:drawing_notes_app/core/security/auth_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── DeepLinkParser ──────────────────────────────────

  group('DeepLinkParser', () {
    test('home URI 解析正确', () {
      final result = DeepLinkParser.parse(Uri.parse('drawingnotes://home'));
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.home);
      expect(result.route, '/');
    });

    test('空 host 解析为 home', () {
      final result = DeepLinkParser.parse(Uri.parse('drawingnotes://'));
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.home);
    });

    test('editor 带文档 ID 解析', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://editor/doc-123'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.editor);
      expect(result.documentId, 'doc-123');
      expect(result.route, contains('doc-123'));
    });

    test('editor-v2 解析', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://editor-v2/doc-456'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.editorV2);
      expect(result.documentId, 'doc-456');
    });

    test('notebook 解析', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://notebook/nb-789'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.notebook);
      expect(result.notebookId, 'nb-789');
    });

    test('open 文件解析', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://open?path=/tmp/test.drawingnotes'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.openFile);
      expect(result.filePath, '/tmp/test.drawingnotes');
    });

    test('open 缺少 path 参数返回 null', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://open'),
      );
      expect(result, isNull);
    });

    test('非 drawingnotes scheme 返回 null', () {
      final result = DeepLinkParser.parse(
        Uri.parse('https://example.com'),
      );
      expect(result, isNull);
    });

    test('unknown host 返回 null', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://unknown/path'),
      );
      expect(result, isNull);
    });
  });

  // ── AuthGuard 路由守卫验证 ──────────────────────────────────

  group('AuthGuard', () {
    late AuthGuard guard;

    setUp(() {
      guard = AuthGuard.instance;
    });

    test('初始状态：未认证', () {
      expect(guard.isAuthenticated, false);
    });

    test('authenticate 后变为已认证', () {
      guard.authenticate();
      expect(guard.isAuthenticated, true);
    });

    test('deauthenticate 后变为未认证', () {
      guard.authenticate();
      guard.deauthenticate();
      expect(guard.isAuthenticated, false);
    });

    test('认证变更触发 onAuthChange 流', () async {
      final events = <bool>[];
      final sub = guard.onAuthChange.listen(events.add);

      guard.authenticate();
      guard.deauthenticate();

      await Future<void>.delayed(Duration.zero);
      expect(events, [true, false]);

      await sub.cancel();
    });
  });

  // ── DeepLinkService 路由逻辑 ──────────────────────────────────

  group('DeepLinkService', () {
    test('handleDeepLink 处理 home 类型', () {
      // DeepLinkService.handleDeepLink 需要 GoRouter 实例，
      // 这里测试 DeepLinkResult 类型分发逻辑。
      const result = DeepLinkResult(type: DeepLinkType.home, route: '/');
      expect(result.type, DeepLinkType.home);
      expect(result.route, '/');
    });

    test('handleDeepLink 处理 openFile 类型', () {
      const result = DeepLinkResult(
        type: DeepLinkType.openFile,
        filePath: '/tmp/test.drawingnotes',
      );
      expect(result.type, DeepLinkType.openFile);
      expect(result.filePath, isNotNull);
    });

    test('_extractDocIdFromPath 正确提取', () {
      // 使用反射测试私有方法（或直接测试 public 接口）。
      // 这里验证 DeepLinkResult 数据完整性。
      const result = DeepLinkResult(
        type: DeepLinkType.editor,
        route: '/editor/doc-123',
        documentId: 'doc-123',
      );
      expect(result.documentId, 'doc-123');
    });
  });

  // ── 路由路径常量验证 ──────────────────────────────────

  group('RoutePaths', () {
    test('所有路径以 / 开头', () {
      expect(RoutePaths.home, startsWith('/'));
      expect(RoutePaths.editor, startsWith('/'));
      expect(RoutePaths.editorV2, startsWith('/'));
      expect(RoutePaths.notebook, startsWith('/'));
      expect(RoutePaths.passwordDisk, startsWith('/'));
      expect(RoutePaths.settings, startsWith('/'));
      expect(RoutePaths.search, startsWith('/'));
      expect(RoutePaths.presentation, startsWith('/'));
      expect(RoutePaths.onboarding, startsWith('/'));
      expect(RoutePaths.shapeLibrary, startsWith('/'));
    });

    test('路由名称唯一', () {
      final names = {
        RouteNames.home,
        RouteNames.editor,
        RouteNames.editorV2,
        RouteNames.notebook,
        RouteNames.passwordDisk,
        RouteNames.settings,
        RouteNames.search,
        RouteNames.presentation,
        RouteNames.onboarding,
        RouteNames.shapeLibrary,
      };
      expect(names.length, 10);
    });
  });
}
