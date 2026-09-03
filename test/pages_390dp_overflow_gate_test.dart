// R2 门禁探针（第二轮审计）：移动布局页面在 390dp 手机屏无布局溢出。
//
// 背景（2026-09-03）：U6 实测证明「0 宽容器不报溢出、既有缺陷门禁测不出」
// ——此前仅 app_shell 首页三页签与画板编辑器有 390dp 探针，本文件为
// 其余 7 个移动布局页面补齐溢出防线（纯测试，零产品代码改动）。
// 模式照抄 editor_page_390dp_overflow_test（takeException isNull 探针）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/theme/app_theme_controller.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/tags_view.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/presentation/trash_page.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_view_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/search_page.dart';
import 'package:drawing_notes_app/features/notes/presentation/settings_page.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_page.dart';
import 'package:drawing_notes_app/shared/application/search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump390(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  NoteBlockDoc makeDoc() {
    final now = DateTime(2026, 9, 3, 10);
    return NoteBlockDoc(
      id: 'gate-390',
      title: '门禁文档',
      body: const [
        NoteBlock(id: 'h1', type: NoteBlockType.heading, text: '标题'),
        NoteBlock(id: 'p1', type: NoteBlockType.text, text: '正文段落'),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  AllDoc makeAllDoc() {
    final now = DateTime(2026, 9, 3, 10);
    return AllDoc(
      id: 'doc-1',
      title: '带标签笔记',
      kind: AllDocKind.blockdoc,
      folder: '',
      tags: const ['重点'],
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('390x844：回收站页无溢出', (tester) async {
    await pump390(
      tester,
      TrashPage(
        loadTrash: () async => [],
        onRestore: (_) async => true,
        onPurge: (_) async => true,
      ),
    );
    expect(tester.takeException(), isNull, reason: '回收站 390dp 溢出');
  });

  testWidgets('390x844：搜索页无溢出', (tester) async {
    await pump390(tester, SearchPage(searchService: SearchService()));
    expect(tester.takeException(), isNull, reason: '搜索页 390dp 溢出');
  });

  testWidgets('390x844：标签视图无溢出', (tester) async {
    await pump390(tester, TagsView(docs: [makeAllDoc()]));
    expect(tester.takeException(), isNull, reason: '标签视图 390dp 溢出');
  });

  testWidgets('390x844：日程页无溢出', (tester) async {
    await pump390(tester, const SchedulePage());
    expect(tester.takeException(), isNull, reason: '日程页 390dp 溢出');
  });

  testWidgets('390x844：设置页无溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump390(
      tester,
      SettingsPage(
        appLockService: AppLockService(),
        themeController: AppThemeController(),
      ),
    );
    expect(tester.takeException(), isNull, reason: '设置页 390dp 溢出');
  });

  testWidgets('390x844：笔记编辑页（DocPage）无溢出', (tester) async {
    await pump390(tester, DocPage(document: makeDoc()));
    expect(tester.takeException(), isNull, reason: '笔记编辑页 390dp 溢出');
  });

  testWidgets('390x844：分页画布页（NotebookViewPage）无溢出', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('gate390_nb');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final notebook = Notebook(id: 'nb-gate', title: '门禁分页画布');
    await pump390(
      tester,
      NotebookViewPage(
        notebook: notebook,
        storage: NotebookStorage(directoryProvider: () async => tempDir),
      ),
    );
    expect(tester.takeException(), isNull, reason: '分页画布页 390dp 溢出');
  });
}
