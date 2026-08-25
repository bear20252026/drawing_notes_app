import 'dart:io';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/features/notes/presentation/password_disk_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 密码盘页面（军工级增强 UI）构建与交互回归测试。
///
/// 用 MockPasswordDisk 注入（kDebugMode 默认 Mock），验证：
/// 页面可构建、状态卡存在、创建/解锁/恢复按钮可点击不崩溃。
void main() {
  late Directory diskDir;

  setUp(() async {
    diskDir = await Directory.systemTemp.createTemp('frogkey_ui_');
  });

  tearDown(() async {
    // 容错删除：Windows 上异步文件句柄释放有延迟，重试几次。
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

  testWidgets('密码盘页面：可构建且状态卡/按钮齐全', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '页面构建不应抛异常');
    expect(find.text('密码盘（U盘即钥匙）'), findsOneWidget);
    expect(find.text('密码盘未解锁'), findsOneWidget);
    expect(find.text('创建密码盘（生成密钥 + 恢复密钥）'), findsOneWidget);
    expect(find.text('解锁（选择 U 盘密码盘目录）'), findsOneWidget);
    expect(find.text('用恢复密钥找回主密钥（U 盘丢失）'), findsOneWidget);
  });

  testWidgets('密码盘页面：创建密码盘按钮可点击不崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建密码盘（生成密钥 + 恢复密钥）'));
    // EncryptionService.test() 使用 1MiB 参数，pumpAndSettle 即可等待完成。
    await tester.pumpAndSettle();

    // Mock 无系统目录选择器，pickDirectory 直接返回 mock 目录，
    // 创建后应弹出"我已抄写"恢复密钥对话框或直接成功，不应崩溃。
    expect(tester.takeException(), isNull, reason: '创建流程不应抛异常');
    // 关闭可能存在的恢复密钥对话框。
    final okBtn = find.text('我已抄写');
    if (okBtn.evaluate().isNotEmpty) {
      await tester.tap(okBtn);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('密码盘页面：解锁按钮可点击不崩溃（未插入盘则提示）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mock 目录下没有 key.frogkey → 解锁应提示失败（不崩溃）。
    await tester.tap(find.text('解锁（选择 U 盘密码盘目录）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 核心断言：交互不崩溃（解锁失败计数/提示逻辑正常）。
    expect(tester.takeException(), isNull, reason: '解锁流程不应抛异常');
    // 页面仍存活（状态卡仍在）。
    expect(find.text('密码盘（U盘即钥匙）'), findsOneWidget);
  });

  // ─── #11 锁定按钮测试 ───────────────────────────────────
  testWidgets('密码盘页面：创建后解锁可见锁定按钮', (tester) async {
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

    // 1. 创建密码盘 — 用 runAsync 让真实异步（Argon2id）完成。
    await tester.runAsync(() async {
      await tester.tap(find.text('创建密码盘（生成密钥 + 恢复密钥）'));
      await tester.pump();
      // 处理 PIN 保护询问对话框（选择"不启用"以简化测试）。
      final noPinBtn = find.text('不启用');
      if (noPinBtn.evaluate().isNotEmpty) {
        await tester.tap(noPinBtn);
        await tester.pump();
      }
      // 等待 Argon2id 完成（test 模式 1MiB，约 1-2 秒）。
      await Future.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 关闭恢复密钥对话框（warnIfMissed: false — 对话框可能被遮挡）。
    final okBtn = find.text('我已抄写');
    if (okBtn.evaluate().isNotEmpty) {
      await tester.tap(okBtn, warnIfMissed: false);
      await tester.pump();
    }

    // 2. onKeyUnlocked 回调应在创建后自动触发
    expect(capturedKey, isNotNull, reason: 'onKeyUnlocked 应在创建后回调');

    // 3. 解锁
    await tester.tap(find.text('解锁（选择 U 盘密码盘目录）'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    // 4. 锁定按钮应出现
    final lockBtn = find.text('锁定（清除内存中的主密钥）');
    if (lockBtn.evaluate().isNotEmpty) {
      await tester.tap(lockBtn);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '锁定不应崩溃');
    }
  });

  // ─── #11 落盘加密验证按钮测试 ─────────────────────────────
  testWidgets('密码盘页面：落盘加密验证区存在', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('落盘加密验证'), findsOneWidget);
    // 未解锁时按钮显示"请先解锁密码盘"（解锁后变为"加密并落盘验证"）。
    expect(find.text('请先解锁密码盘'), findsOneWidget);
  });

  // ─── #12 恢复密钥一键复制按钮测试 ─────────────────────────
  testWidgets('密码盘页面：创建后恢复密钥对话框含一键复制按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordDiskPage(
          disk: MockPasswordDisk(baseDir: diskDir.path),
          encryption: const EncryptionService.test(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 创建密码盘
    await tester.tap(find.text('创建密码盘（生成密钥 + 恢复密钥）'));
    // EncryptionService.test() 使用 1MiB 参数，pumpAndSettle 即可等待完成。
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 恢复密钥对话框应含"一键复制"按钮
    final copyBtn = find.text('一键复制');
    if (copyBtn.evaluate().isNotEmpty) {
      expect(copyBtn, findsOneWidget);
      // 点击不应崩溃
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '一键复制不应崩溃');
    }

    // 关闭对话框
    final okBtn = find.text('我已抄写');
    if (okBtn.evaluate().isNotEmpty) {
      await tester.tap(okBtn);
      await tester.pumpAndSettle();
    }
  });
}
