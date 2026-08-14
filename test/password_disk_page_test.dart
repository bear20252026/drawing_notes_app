import 'dart:io';

import 'package:drawing_notes_app/storage/password_disk.dart';
import 'package:drawing_notes_app/ui/pages/password_disk_page.dart';
import 'package:flutter/material.dart';
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
        home: PasswordDiskPage(disk: MockPasswordDisk(baseDir: diskDir.path)),
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
        home: PasswordDiskPage(disk: MockPasswordDisk(baseDir: diskDir.path)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建密码盘（生成密钥 + 恢复密钥）'));
    // 创建流程含 PBKDF2 信封（耗时），多次 pump 等待异步完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

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
        home: PasswordDiskPage(disk: MockPasswordDisk(baseDir: diskDir.path)),
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
}
