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
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
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

  // testWidgets 跑在 FakeAsync zone——后台 isolate 结果永不回投：
  // 轻量 KDF 档 + 同 isolate 直派生双保险（生产 isolate 路径不受影响）。
  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  /// 在指定尺寸 / 主题 / 字阶下泵页。
  ///
  /// **为什么需要**：第六批（次级信息色）、第七批（排版梯子）的改动都
  /// 专门修了「深色模式下几乎不可见」的问题，但既有 390dp 门禁只跑浅色
  /// 默认字阶，深色模式的视觉退化完全没被覆盖——这是迄今最大的门禁盲点。
  /// 1.5× 字阶则是无障碍（DESIGN.md 与 Android best practice 都要求验）。
  ///
  /// 调用点约定：默认浅色 / 390×844 / 1.0× 字阶——保持旧 [pump390] 行为。
  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppDesign.lightThemeFor(false),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        // 1.5× 字阶用 MediaQuery 包裹实现——不动平台层（Flutter 3.x 已
        // 没有 view.textScaleFactor setter，`platformDispatcher.textScale
        // FactorTestValue` 在测试体结束后会被框架检查，与既有的
        // debugDefaultTargetPlatformOverride 禁忌同源）。
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: page ?? const SizedBox.shrink(),
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 旧 [pump390] 的薄壳：默认 390×844 / 浅色 / 1.0× 字阶。
  /// 保留只是因为已泵测试还在用它；新写代码请直接调 [pumpAt]。
  Future<void> pump390(WidgetTester tester, Widget child) =>
      pumpAt(tester, child);

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

  // ===================================================================
  // 第八批新增：深色模式门禁。
  //
  // 第六批（次级信息色 / 容器底色）的全部改动都明确修了「深色模式下几乎
  // 不可见」的问题，但既有 390dp 门禁只跑浅色——这是迄今最大的门禁盲点。
  // 测试命名沿用既有格式以保持 `id` 维度统一：dark / 1.5x。
  // ===================================================================

  testWidgets('390x844 dark：回收站页无溢出', (tester) async {
    await pumpAt(
      tester,
      TrashPage(
        loadTrash: () async => [],
        onRestore: (_) async => true,
        onPurge: (_) async => true,
      ),
      theme: AppDesign.darkTheme(),
    );
    expect(tester.takeException(), isNull, reason: '回收站 390dp 深色溢出');
  });

  testWidgets('390x844 dark：搜索页无溢出', (tester) async {
    await pumpAt(
      tester,
      SearchPage(searchService: SearchService()),
      theme: AppDesign.darkTheme(),
    );
    expect(tester.takeException(), isNull, reason: '搜索页 390dp 深色溢出');
  });

  testWidgets('390x844 dark：标签视图无溢出', (tester) async {
    await pumpAt(
      tester,
      TagsView(docs: [makeAllDoc()]),
      theme: AppDesign.darkTheme(),
    );
    expect(tester.takeException(), isNull, reason: '标签视图 390dp 深色溢出');
  });

  testWidgets('390x844 dark：日程页无溢出', (tester) async {
    await pumpAt(tester, const SchedulePage(), theme: AppDesign.darkTheme());
    expect(tester.takeException(), isNull, reason: '日程页 390dp 深色溢出');
  });

  testWidgets('390x844 dark：设置页无溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpAt(
      tester,
      SettingsPage(
        appLockService: AppLockService(),
        themeController: AppThemeController(),
      ),
      theme: AppDesign.darkTheme(),
    );
    expect(tester.takeException(), isNull, reason: '设置页 390dp 深色溢出');
  });

  testWidgets('390x844 dark：笔记编辑页（DocPage）无溢出', (tester) async {
    await pumpAt(
      tester,
      DocPage(document: makeDoc()),
      theme: AppDesign.darkTheme(),
    );
    expect(tester.takeException(), isNull, reason: '笔记编辑页 390dp 深色溢出');
  });

  testWidgets('390x844 dark：分页画布页（NotebookViewPage）无溢出', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('gate390_nb_d');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final notebook = Notebook(id: 'nb-gate-d', title: '门禁分页画布');
    await pumpAt(
      tester,
      NotebookViewPage(
        notebook: notebook,
        storage: NotebookStorage(directoryProvider: () async => tempDir),
      ),
      theme: AppDesign.darkTheme(),
    );
    expect(tester.takeException(), isNull, reason: '分页画布页 390dp 深色溢出');
  });

  // ===================================================================
  // 1.5× 字阶（无障碍，DESIGN.md 与 Android best practice 都要求验）。
  // 第七批给笔记正文加了 1.47 行高——正常字阶下行距很宽松，但 1.5× 字阶
  // 下再叠加，可能让紧凑 UI（列表卡片、表格行）撞溢出。
  // ===================================================================

  testWidgets('390x844 1.5x：回收站页无溢出', (tester) async {
    await pumpAt(
      tester,
      TrashPage(
        loadTrash: () async => [],
        onRestore: (_) async => true,
        onPurge: (_) async => true,
      ),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull, reason: '回收站 390dp 1.5× 溢出');
  });

  testWidgets('390x844 1.5x：搜索页无溢出', (tester) async {
    await pumpAt(
      tester,
      SearchPage(searchService: SearchService()),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull, reason: '搜索页 390dp 1.5× 溢出');
  });

  testWidgets('390x844 1.5x：标签视图无溢出', (tester) async {
    await pumpAt(tester, TagsView(docs: [makeAllDoc()]), textScale: 1.5);
    expect(tester.takeException(), isNull, reason: '标签视图 390dp 1.5× 溢出');
  });

  testWidgets('390x844 1.5x：日程页无溢出', (tester) async {
    await pumpAt(tester, const SchedulePage(), textScale: 1.5);
    expect(tester.takeException(), isNull, reason: '日程页 390dp 1.5× 溢出');
  });

  testWidgets('390x844 1.5x：设置页无溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpAt(
      tester,
      SettingsPage(
        appLockService: AppLockService(),
        themeController: AppThemeController(),
      ),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull, reason: '设置页 390dp 1.5× 溢出');
  });

  testWidgets('390x844 1.5x：笔记编辑页（DocPage）无溢出', (tester) async {
    await pumpAt(tester, DocPage(document: makeDoc()), textScale: 1.5);
    expect(tester.takeException(), isNull, reason: '笔记编辑页 390dp 1.5× 溢出');
  });

  testWidgets('390x844 1.5x：分页画布页（NotebookViewPage）无溢出', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('gate390_nb_t');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final notebook = Notebook(id: 'nb-gate-t', title: '门禁分页画布');
    await pumpAt(
      tester,
      NotebookViewPage(
        notebook: notebook,
        storage: NotebookStorage(directoryProvider: () async => tempDir),
      ),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull, reason: '分页画布页 390dp 1.5× 溢出');
  });
}
