// U5 审计残留回归（P2-6）：新建分页画布保存失败给用户提示。
//
// 审计发现：home_page._createNotebook 的 save 裸奔——磁盘满/权限等异常
// 会未捕获崩溃且用户无感知。U5a 修复：try/catch + SnackBar 提示，停留在
// 首页（不进入未落盘的编辑页）。本测试注入抛错的 directoryProvider
// 模拟不可写磁盘，验证提示出现且未导航。

import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';

Future<Directory> _tempDir() async {
  return Directory.systemTemp.createTemp('u5_home_test');
}

Future<Directory> _brokenDir() async {
  throw const FileSystemException('模拟磁盘不可写（U5 测试注入）');
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: child,
  );
}

void main() {
  testWidgets('新建分页画布保存失败 → SnackBar 提示且不进入编辑页',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomePage(
          docStorage: StorageService(directoryProvider: _tempDir),
          // 笔记本存储指向不可写「磁盘」——save 必抛。
          notebookStorage: NotebookStorage(directoryProvider: _brokenDir),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));

    // 切到画布 tab（N1：画布 FAB 弹两选项；默认 tab 可能不是画布）。
    await tester.tap(find.text('画布').first);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // FAB → 两选项 → 「新建分页画布」。
    // 全程固定步长 pump：编辑器光标闪烁等持续帧调度会让 pumpAndSettle 超时。
    await tester.tap(find.byType(FloatingActionButton).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('新建画布', findRichText: true),
      findsWidgets,
      reason: '画布 FAB 应弹出「新建画布」两选项对话框',
    );
    await tester.tap(find.text('新建分页画布'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 命名修复（2026-09-06）：新建分页画布现先弹命名对话框，填名提交
    //（随后 save 抛错 → SnackBar；空名取消则根本不进入 save，故此处必填）。
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '测试分页画布',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.text('新建失败：笔记本未能保存，请检查磁盘空间后重试'),
      findsOneWidget,
      reason: '保存失败必须提示用户（审计 P2-6）',
    );
    // 未进入 NotebookViewPage（保存失败不应把用户带进未落盘的编辑页）。
    expect(find.byType(NotebookViewPage), findsNothing);
  });
}
