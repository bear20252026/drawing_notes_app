// M11 冒烟测试：AppShell 真实链路（内存存储注入，FakeAsync 安全）。
//
// 目标：复现并守住"能打开但点不动/功能是空的"回归——
// 空文档时也必须有创建入口；点击新建→编辑器打开；目的地切换正常。
//
// 注意：
// - testWidgets 是 FakeAsync 区，页面里 await 真实文件 IO 会永久挂起，
//   故注入内存版存储（IO 语义由各 store 自身测试锁定）。
// - AppShell 含常驻环境背景动画，不能 pumpAndSettle。
import 'dart:io';

import 'package:flutter/material.dart' as m;
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    as fl_loc show GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/note_block_doc_store.dart';

/// 内存版块文档存储（FakeAsync 安全）。
class _MemBlockDocStore extends NoteBlockDocStore {
  final Map<String, NoteBlockDoc> docs = {};

  @override
  Future<void> saveDocument(NoteBlockDoc doc) async {
    docs[doc.id] = doc;
  }

  @override
  Future<NoteBlockDoc?> loadDocument(String pageId) async => docs[pageId];

  @override
  Future<List<String>> listIds() async => docs.keys.toList();
}

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    _MemBlockDocStore? blockDocStore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.lightTheme(),
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          fl_loc.GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: AppShell(
          blockDocStore: blockDocStore ?? _MemBlockDocStore(),
          favoriteStore: FavoriteStore(
            directoryProvider: () async => Directory.systemTemp.createTemp(
              'shell_smoke',
            ),
          ),
        ),
      ),
    );
    // 常驻环境背景动画，不能 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('空态 CTA 新建笔记（打字）→ 块编辑器打开', (tester) async {
    final store = _MemBlockDocStore();
    await pumpShell(tester, blockDocStore: store);

    // 空态创建入口存在（回归：此前空文档时工具条整体不渲染，无任何入口）。
    expect(find.text('新建笔记（打字）'), findsWidgets);
    expect(find.text('新建画板'), findsWidgets);

    final ctaFinder = find.ancestor(
      of: find.text('新建笔记（打字）'),
      matching: find.byType(m.FilledButton),
    );
    await tester.tap(ctaFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 编辑器已推入：出现块输入框；文档已落库（内存）。
    expect(find.byType(m.TextField), findsWidgets);
    expect(store.docs.length, 1);
  });

  testWidgets('目的地切换：画板 / 日历均正常渲染', (tester) async {
    await pumpShell(tester);

    // 2 号目的地：画板·笔记本
    await tester.tap(find.text('画板').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('无限画布'), findsOneWidget);

    // 3 号目的地：日历
    await tester.tap(find.text('日历').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('日历 · 待办'), findsOneWidget);
    expect(find.text('全部日程'), findsOneWidget);
  });
}
