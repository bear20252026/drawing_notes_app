// v1.4.2 实测（Q0 回归真机验证）：文档新建 → 输入 → 退出 → 落盘验证。
//
// 真实 Windows 运行时跑完整生命周期（架构审计 Q0：此前退出文档页即栈溢出）。
// 运行方式：flutter test integration_test/doc_lifecycle_test.dart -d windows
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/app.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _uniqueText = 'Q0 实测内容 v142';

/// 真实时钟等待：LiveTest binding 下 Timer 为真实定时器，
/// pump(duration) 不会推进——必须真实 sleep + pump 出帧。
Future<void> realWait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
  });

  testWidgets('Q0 生命周期：新建 → 输入 → 退出不崩溃 → 自动保存落盘', (tester) async {
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    // 轮询等工具条就绪（真机首帧慢；背景动画禁用 pumpAndSettle）。
    var ready = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('新建文档').evaluate().isNotEmpty) {
        ready = true;
        break;
      }
    }
    expect(ready, isTrue, reason: 'AllDocs 工具条应在 10s 内就绪');

    // 打开「新建文档 ▾」下拉 → 选「新建笔记（打字）」。
    await IntegrationTestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
      debugPrint('BEFORE-TAP blockdocs: '
          '${dir.existsSync() ? dir.listSync().length : 0} files');
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          debugPrint('  BEFORE ${f.path} mtime='
              '${(f as File).lastModifiedSync().toIso8601String()}');
        }
      }
    });
    await tester.tap(find.text('新建文档'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('新建笔记（打字）').last);
    var editorReady = false;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(TextField).evaluate().length >= 2) {
        editorReady = true;
        break;
      }
    }
    expect(editorReady, isTrue, reason: 'DocPage 编辑器应在 10s 内就绪');

    // 输入唯一文本 → 等防抖自动保存写盘（P0-H1 保存链）。
    // 注意：IndexedStack 下三个目的地常驻，必须限定 DocPage 子树定位正文框。
    final docPageFinder = find.byType(DocPage);
    expect(docPageFinder, findsOneWidget);
    final bodyField = find.descendant(
      of: docPageFinder,
      matching: find.byType(TextField),
    ).last;
    await tester.enterText(bodyField, _uniqueText);
    // 真实时钟等防抖（1.2s）+ 写盘余量。
    await realWait(tester, const Duration(seconds: 3));

    await IntegrationTestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
      debugPrint('AFTER-INPUT blockdocs: '
          '${dir.existsSync() ? dir.listSync().length : 0} files');
      for (final f in dir.listSync()) {
        final c = f is File ? f.readAsStringSync() : '';
        debugPrint('  AFTER ${f.path} len=${c.length} '
            'hasText=${c.contains(_uniqueText)}');
      }
    });

    // 退出文档页（系统返回）——Q0 回归点：此处曾栈溢出崩溃。
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await realWait(tester, const Duration(seconds: 3));

    // 未崩溃且回到列表（P0-H2 flush 后 _bumpDataVersion 刷新）。
    expect(
      find.text('新建文档'),
      findsOneWidget,
      reason: '退出后应回到 AllDocs 且不崩溃（Q0 回归）',
    );

    // 落盘验证：Documents/blockdocs 下任一 json 含唯一文本
    // （自动保存链真实写盘，P0-H1 的核心保证）。
    var persisted = false;
    await IntegrationTestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
      debugPrint('DIR ${dir.path} exists=${dir.existsSync()}');
      if (!dir.existsSync()) return;
      for (final f in dir.listSync()) {
        debugPrint('  FILE ${f.path}');
        if (f is File && f.path.endsWith('.json')) {
          final c = f.readAsStringSync();
          debugPrint('    contains=${c.contains(_uniqueText)} len=${c.length}');
          if (c.contains(_uniqueText)) {
            persisted = true;
            return;
          }
        }
      }
    });
    expect(persisted, isTrue, reason: '编辑内容应已自动保存落盘');
  });
}
