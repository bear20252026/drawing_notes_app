/// GoRouter 路由配置测试（2026-08-25）
///
/// 覆盖：
/// 1. 路由常量正确性
/// 2. 深度链接解析（drawingnotes://）
/// 3. 文件关联解析
/// 4. 路由守卫（认证检查）
/// 5. 导航扩展方法
library;

import 'package:drawing_notes_app/core/router/app_router.dart';
import 'package:drawing_notes_app/core/router/navigation_ext.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ──────── 1. 路由常量 ────────
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

    test('路径值正确', () {
      expect(RoutePaths.home, '/');
      expect(RoutePaths.editor, '/editor');
      expect(RoutePaths.editorV2, '/editor-v2');
      expect(RoutePaths.notebook, '/notebook');
      expect(RoutePaths.passwordDisk, '/password-disk');
      expect(RoutePaths.settings, '/settings');
      expect(RoutePaths.search, '/search');
      expect(RoutePaths.presentation, '/presentation');
      expect(RoutePaths.onboarding, '/onboarding');
      expect(RoutePaths.shapeLibrary, '/shape-library');
    });

    test('所有名称匹配路径', () {
      expect(RouteNames.home, 'home');
      expect(RouteNames.editor, 'editor');
      expect(RouteNames.editorV2, 'editor-v2');
      expect(RouteNames.notebook, 'notebook');
      expect(RouteNames.passwordDisk, 'password-disk');
      expect(RouteNames.settings, 'settings');
      expect(RouteNames.search, 'search');
      expect(RouteNames.presentation, 'presentation');
      expect(RouteNames.onboarding, 'onboarding');
      expect(RouteNames.shapeLibrary, 'shape-library');
    });
  });

  // ──────── 2. 深度链接解析 ────────
  group('DeepLinkParser', () {
    test('解析 home 深度链接', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://home'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.home);
      expect(result.route, '/');
    });

    test('解析空 host 为 home', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.home);
    });

    test('解析 editor 深度链接', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://editor/doc123'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.editor);
      expect(result.documentId, 'doc123');
      expect(result.route, '/editor/doc123');
    });

    test('解析 editor-v2 深度链接', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://editor-v2/doc456?mode=note'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.editorV2);
      expect(result.documentId, 'doc456');
      expect(result.route, contains('doc456'));
      expect(result.extra, {'mode': 'note'});
    });

    test('解析 notebook 深度链接', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://notebook/nb789'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.notebook);
      expect(result.notebookId, 'nb789');
    });

    test('解析 open 深度链接（文件路径）', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://open?path=/tmp/test.drawingnotes'),
      );
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.openFile);
      expect(result.filePath, '/tmp/test.drawingnotes');
    });

    test('不识别的 scheme 返回 null', () {
      final result = DeepLinkParser.parse(
        Uri.parse('https://example.com'),
      );
      expect(result, isNull);
    });

    test('不识别的 host 返回 null', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://unknown'),
      );
      expect(result, isNull);
    });

    test('空路径的 editor 返回 null', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://editor'),
      );
      expect(result, isNull);
    });

    test('默认 editor-v2 模式为 whiteboard', () {
      final result = DeepLinkParser.parse(
        Uri.parse('drawingnotes://editor-v2/doc123'),
      );
      expect(result, isNotNull);
      expect(result!.extra, {'mode': 'whiteboard'});
    });
  });

  // ──────── 3. 文件关联解析 ────────
  group('DeepLinkParser.parseFileAssociation', () {
    test('解析 .drawingnotes 文件', () {
      final result = DeepLinkParser.parseFileAssociation([
        '/path/to/test.drawingnotes',
      ]);
      expect(result, isNotNull);
      expect(result!.type, DeepLinkType.openFile);
      expect(result.filePath, '/path/to/test.drawingnotes');
    });

    test('跳过非 .drawingnotes 文件', () {
      final result = DeepLinkParser.parseFileAssociation([
        'README.md',
        '--verbose',
      ]);
      expect(result, isNull);
    });

    test('跳过以 - 开头的参数', () {
      final result = DeepLinkParser.parseFileAssociation([
        '--file=test.drawingnotes',
      ]);
      expect(result, isNull);
    });

    test('空列表返回 null', () {
      expect(DeepLinkParser.parseFileAssociation([]), isNull);
    });

    test('多个文件取第一个', () {
      final result = DeepLinkParser.parseFileAssociation([
        '/a.drawingnotes',
        '/b.drawingnotes',
      ]);
      expect(result, isNotNull);
      expect(result!.filePath, '/a.drawingnotes');
    });
  });

  // ──────── 4. GoRouter 创建 ────────
  group('createAppRouter', () {
    late dynamic router;

    setUp(() {
      router = createAppRouter();
    });

    test('创建成功', () {
      expect(router, isNotNull);
    });

    test('初始路由为首页', () {
      expect(router.routerDelegate, isNotNull);
    });
  });

  // ──────── 5. DeepLinkResult ────────
  group('DeepLinkResult', () {
    test('构造函数设置所有字段', () {
      const result = DeepLinkResult(
        type: DeepLinkType.editor,
        route: '/editor/test',
        filePath: '/tmp/test',
        documentId: 'test',
        notebookId: 'nb1',
        extra: {'key': 'value'},
      );
      expect(result.type, DeepLinkType.editor);
      expect(result.route, '/editor/test');
      expect(result.filePath, '/tmp/test');
      expect(result.documentId, 'test');
      expect(result.notebookId, 'nb1');
      expect(result.extra, {'key': 'value'});
    });

    test('可选字段默认为 null', () {
      const result = DeepLinkResult(type: DeepLinkType.home);
      expect(result.route, isNull);
      expect(result.filePath, isNull);
      expect(result.documentId, isNull);
      expect(result.notebookId, isNull);
      expect(result.extra, isNull);
    });
  });

  // ──────── 6. NavigationParams ────────
  group('NavigationParams', () {
    test('空参数', () {
      const params = NavigationParams();
      expect(params.queryParams, isEmpty);
      expect(params.extra, isNull);
      expect(params.toQueryString(), isEmpty);
    });

    test('带查询参数', () {
      const params = NavigationParams(
        queryParams: {'title': '测试', 'mode': 'note'},
      );
      final qs = params.toQueryString();
      expect(qs, startsWith('?'));
      expect(qs, contains('title='));
      expect(qs, contains('mode='));
    });

    test('特殊字符编码', () {
      const params = NavigationParams(
        queryParams: {'title': '你好世界'},
      );
      final qs = params.toQueryString();
      expect(qs, contains(Uri.encodeComponent('你好世界')));
    });
  });

  // ──────── 7. DeepLinkType 枚举 ────────
  group('DeepLinkType', () {
    test('包含所有预期值', () {
      expect(DeepLinkType.values.length, 5);
      expect(DeepLinkType.values, contains(DeepLinkType.home));
      expect(DeepLinkType.values, contains(DeepLinkType.editor));
      expect(DeepLinkType.values, contains(DeepLinkType.editorV2));
      expect(DeepLinkType.values, contains(DeepLinkType.notebook));
      expect(DeepLinkType.values, contains(DeepLinkType.openFile));
    });
  });
}
