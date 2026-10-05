// v1.4.2 实测（Q0 回归真机验证）：文档新建 → 输入 → 退出 → 落盘验证。
//
// 真实 Windows 运行时跑完整生命周期（架构审计 Q0：此前退出文档页即栈溢出）。
// 运行方式：flutter test integration_test/doc_lifecycle_test.dart -d windows
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/app.dart';
// 防抖阈值引用产品常量本身（见下方 realWait 注释），不再抄数字。
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
// AU-2（2026-10-05 真机跑出来的红）：落盘验证必须走产品自己的数据根。
// 原写法用 `getApplicationDocumentsDirectory()` 拼 `blockdocs`——那是 S-02
// 方案 B（v1.17.47）迁移**之前**的位置；迁移后统一根是
// `AppDataRoot.defaultRootDir()`（生产 `_baseDir()` 的单一事实来源，
// note_block_doc_store.dart:154）。旧路径不存在 ⇒ `dir.listSync()` 直接抛
// PathNotFoundException，本用例自 v1.17.47 起在真机上从未能通过。
// `path_provider` 因此不再需要，已移除该 import。
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'real_wait.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _uniqueText = 'Q0 实测内容 v142';

// 真实时钟等待已抽到 `real_wait.dart`（AU-2，2026-10-05）——此前只有本文件
// 内有一份私有实现，`cuj_01_test` 缺它而长期真机红。本仓对「同一实现只留一份」
// 有明确先例（test/helpers/wait_until.dart）。

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

    // 打开「新建文档 ▾」下拉 → 选「新建笔记」（arb docsNewNote）。
    await IntegrationTestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await AppDataRoot.defaultRootDir();
      final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
      debugPrint(
        'BEFORE-TAP blockdocs: '
        '${dir.existsSync() ? dir.listSync().length : 0} files',
      );
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          debugPrint(
            '  BEFORE ${f.path} mtime='
            '${(f as File).lastModifiedSync().toIso8601String()}',
          );
        }
      }
    });
    await tester.tap(find.text('新建文档'));
    await tester.pump(const Duration(milliseconds: 400));
    // arb docsNewNote 现值「新建笔记」——原字面量「新建笔记（打字）」随 N1
    // 命名统一改名，全 lib/ 零命中（2026-10-04 排查）。渲染点：桌面 showMenu
    // 首项 all_docs_page_widgets.dart:234。`.last` 取覆盖层菜单项——菜单晚于
    // 页面主体入树，空态同名按钮（:550）在前。
    await tester.tap(find.text('新建笔记').last);
    var editorReady = false;
    // 就绪判据（2026-10-04 测试侧加固）：原先只看「全树 TextField 数 ≥ 2」——
    // 非语义且脆：IndexedStack 三个目的地常驻，AllDocs 搜索框 / 桌面开屏锁的
    // PIN 框都是 TextField，凑够 2 个可以在 DocPage 根本没推入的情况下就误判
    // 就绪（随后 `.last` 定位正文框就会打空）。现改为**限定在 DocPage 作用域
    // 内**计数（标题框 + 正文块编辑框），与 smoke_test.dart 的
    // `find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))`
    // 同一口径。（`find.byPlaceholder` 在 CommonFinders 上不存在，不可用。）
    final editorScope = find.byType(DocPage);
    final editorFields = find.descendant(
      of: editorScope,
      matching: find.byType(TextField),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (editorScope.evaluate().isNotEmpty &&
          editorFields.evaluate().length >= 2) {
        editorReady = true;
        break;
      }
    }
    expect(
      editorReady,
      isTrue,
      reason:
          'DocPage 编辑器应在 10s 内就绪：DocPage 已推入且其子树内'
          '标题框+正文框都在位',
    );

    // 输入唯一文本 → 等防抖自动保存写盘（P0-H1 保存链）。
    // 注意：IndexedStack 下三个目的地常驻，必须限定 DocPage 子树定位正文框
    //（复用上面就绪判据的同一对 finder，不再另建一遍）。
    expect(editorScope, findsOneWidget);
    final bodyField = editorFields.last;
    await tester.enterText(bodyField, _uniqueText);
    // 真实时钟等防抖 + 写盘余量。
    //
    // AU-2/AV 定性结论（2026-10-05）：本用例原先固定等 3 秒，注释还写着
    // 「等防抖（1.2s）」——那是 800ms 防抖时代的数字。实际阈值早已改为
    // **5 秒**（`SaveScheduler.autoSaveInterval`，2026-09-06 用户要求
    // 「改动后最多每 5 秒落盘一次」，save_scheduler.dart:69）。等不够 → 防抖
    // 未触发 → 盘上没有该文本 → 看起来像「打字笔记丢内容」的 P0，实为测试
    // 抄了一份产品常量的陈旧副本。**现改为引用常量本身**，产品再调阈值时
    // 测试自动跟随，不会再以这种方式腐烂。
    await realWait(
      tester,
      SaveScheduler.autoSaveInterval + const Duration(seconds: 3),
    );

    await IntegrationTestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await AppDataRoot.defaultRootDir();
      final dir = Directory('${base.path}${Platform.pathSeparator}blockdocs');
      debugPrint(
        'AFTER-INPUT blockdocs: '
        '${dir.existsSync() ? dir.listSync().length : 0} files',
      );
      // 诊断输出判存再列（AU-2）：目录尚未创建时不该把整条用例炸成
      // PathNotFoundException——真正的落盘判定在下面的 `persisted` 断言里。
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          final c = f is File ? f.readAsStringSync() : '';
          debugPrint(
            '  AFTER ${f.path} len=${c.length} '
            'hasText=${c.contains(_uniqueText)}',
          );
        }
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

    // 落盘验证：统一数据根下的 `blockdocs/` 任一 json 含唯一文本
    // （自动保存链真实写盘，P0-H1 的核心保证）。
    var persisted = false;
    await IntegrationTestWidgetsFlutterBinding.instance.runAsync(() async {
      final base = await AppDataRoot.defaultRootDir();
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
