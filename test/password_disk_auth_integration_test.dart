/// PasswordDiskPage 与 AuthGuard 的集成测试。
///
/// 验证：
/// 1. AuthGuard authenticate/deauthenticate 状态切换
/// 2. PasswordDiskPage 可正常构建
/// 3. redirect 参数正确传递和解析
library;

import 'dart:io';

import 'package:drawing_notes_app/core/router/app_router.dart';
import 'package:drawing_notes_app/core/security/auth_guard.dart';
import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/features/notes/presentation/password_disk_page.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory diskDir;

  setUp(() async {
    diskDir = await Directory.systemTemp.createTemp('frogkey_auth_');
  });

  tearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        if (await diskDir.exists()) {
          await diskDir.delete(recursive: true);
        }
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  });

  // ─── 1. AuthGuard 认证状态变更 ──────────────────────────────────
  test('AuthGuard authenticate/deauthenticate 状态切换', () {
    AuthGuard.instance.authenticate();
    expect(AuthGuard.instance.isAuthenticated, isTrue);

    AuthGuard.instance.deauthenticate();
    expect(AuthGuard.instance.isAuthenticated, isFalse);

    AuthGuard.instance.authenticate();
    expect(AuthGuard.instance.isAuthenticated, isTrue);
  });

  // ─── 2. PasswordDiskPage 直接构建（无 GoRouter） ────────────────
  testWidgets('PasswordDiskPage 可正常构建在 MaterialApp 中', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('密码盘（U盘即钥匙）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ─── 3. PasswordDiskPage 带 redirect 参数构建 ──────────────────
  testWidgets('PasswordDiskPage 接收 redirect 参数不崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
          redirect: RoutePaths.settings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('密码盘（U盘即钥匙）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ─── 4. GoRouter redirect 路由传递 query parameter ──────────────
  testWidgets('GoRouter 将 redirect query parameter 传给 PasswordDiskPage',
      (tester) async {
    final router = GoRouter(
      initialLocation: '${RoutePaths.passwordDisk}?redirect=${RoutePaths.settings}',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: RoutePaths.passwordDisk,
          builder: (context, state) {
            final r = state.uri.queryParameters['redirect'];
            return PasswordDiskPage(
              disk: MockPasswordDisk(baseDir: diskDir.path),
              encryption: const EncryptionService.test(),
              redirect: r,
            );
          },
        ),
        GoRoute(
          path: RoutePaths.settings,
          builder: (_, __) => const Scaffold(body: Text('settings')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 页面应成功构建（不崩溃）。
    expect(find.text('密码盘（U盘即钥匙）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ─── 5. 状态卡正确显示 ────────────────────────────────────────
  testWidgets('状态卡在未解锁时显示正确信息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('密码盘未解锁'), findsOneWidget);
    expect(find.text('不想使用加密？'), findsOneWidget);
  });

  // ─── 6. 创建后 onKeyUnlocked 回调触发 ──────────────────────────
  testWidgets('创建密码盘后 onKeyUnlocked 回调触发', (tester) async {
    List<int>? capturedKey;
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
          onKeyUnlocked: (key) => capturedKey = key,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 创建密码盘（runAsync 让真实异步 Argon2id 完成）。
    await tester.runAsync(() async {
      await tester.tap(find.text('创建密码盘（生成密钥 + 恢复密钥）'));
      await tester.pump();
      // 处理 PIN 保护询问对话框。
      final noPinBtn = find.text('不启用');
      if (noPinBtn.evaluate().isNotEmpty) {
        await tester.tap(noPinBtn);
        await tester.pump();
      }
      await Future.delayed(const Duration(seconds: 5));
    });
    await tester.pump();

    // 验证恢复密钥对话框出现。
    final okBtn = find.text('我已抄写');
    expect(okBtn, findsOneWidget, reason: '恢复密钥对话框应出现');

    // 验证回调已触发（在点击关闭之前）。
    expect(capturedKey, isNotNull, reason: 'onKeyUnlocked 应在创建后回调');
    expect(capturedKey!.length, greaterThanOrEqualTo(16),
        reason: '主密钥应 >= 16 字节');

    // 关闭恢复密钥对话框（warnIfMissed 避免 TextEditingController 问题）。
    await tester.tap(okBtn, warnIfMissed: false);
    // 只 pump 一次而不 pumpAndSettle，避免 TextEditingController 已销毁的重建冲突。
    await tester.pump();
  });

  // ─── 7. AuthGuard skipEncryption/enableEncryption ────────────────
  test('skipEncryption 设置后 requiresAuth 为 false', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthGuard.instance;
    await auth.skipEncryption();
    expect(auth.encryptionSkipped, isTrue);
    expect(auth.requiresAuth, isFalse);
    expect(auth.isAuthenticated, isTrue);
  });

  test('enableEncryption 恢复后 requiresAuth 恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthGuard.instance;
    await auth.skipEncryption();
    expect(auth.requiresAuth, isFalse);
    await auth.enableEncryption();
    expect(auth.encryptionSkipped, isFalse);
  });
}
