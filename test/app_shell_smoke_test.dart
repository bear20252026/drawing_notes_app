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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
// v1.10.5：导航类控件玻璃化——底部导航条 / FAB 材质替换壳。
import 'package:drawing_notes_app/shared/widgets/glass_fab.dart';
import 'package:drawing_notes_app/shared/widgets/glass_nav_bar.dart';

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
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: AppShell(
          blockDocStore: blockDocStore ?? _MemBlockDocStore(),
          favoriteStore: FavoriteStore(
            directoryProvider: () async =>
                Directory.systemTemp.createTemp('shell_smoke'),
          ),
        ),
      ),
    );
    // 常驻环境背景动画，不能 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('手机尺寸（390x844）：各主页面无布局溢出', (tester) async {
    // 门禁原因：桌面布局的顶栏/侧栏在手机上会溢出（笔记页顶栏曾在 400dp
    // 下溢出 24px）。默认测试曲面 800x600 同样是窄屏，但不足以覆盖 390 这一档。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpShell(tester);

    // 窄屏走底部导航（外层断点 <900）
    expect(find.byType(NavigationBar), findsOneWidget);

    for (final label in const ['全部文档', '画布·笔记', '日历', '设置']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '$label 在 390dp 下布局溢出');
    }
  });

  testWidgets('空态 CTA 新建笔记→ 块编辑器打开', (tester) async {
    final store = _MemBlockDocStore();
    await pumpShell(tester, blockDocStore: store);

    // 空态创建入口存在（回归：此前空文档时工具条整体不渲染，无任何入口）。
    expect(find.text('新建笔记'), findsWidgets);
    expect(find.text('新建画布'), findsWidgets);

    final ctaFinder = find.ancestor(
      of: find.text('新建笔记'),
      matching: find.byType(m.FilledButton),
    );
    await tester.tap(ctaFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // DocPage 已推入：顶栏（分享/大纲/更多）+ 正文大标题；文档已落库（内存）。
    // 注意：默认测试曲面 800x600 < 900 断点 → 走移动端顶栏，「文档信息」收在
    // ⋯ 菜单里（不直接渲染图标），故此处断言 ⋯ 而非 info 图标。
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    expect(find.byIcon(Icons.format_list_bulleted_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.byType(m.TextField), findsWidgets);
    expect(store.docs.length, 1);
  });

  testWidgets('P0 回归：退出文档页触发 _bumpDataVersion 不无限递归', (tester) async {
    final store = _MemBlockDocStore();
    await pumpShell(tester, blockDocStore: store);

    final ctaFinder = find.ancestor(
      of: find.text('新建笔记'),
      matching: find.byType(m.FilledButton),
    );
    await tester.tap(ctaFinder.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.docs.length, 1);

    // 退出文档页：push 返回后 shell 会调 _bumpDataVersion 刷新列表。
    // 回归背景（架构审计 2026-08-31）：该方法体曾被全局替换误改为
    // 自递归调用，任何文档退出即栈溢出崩溃。
    final navigator = tester.state<m.NavigatorState>(
      find.byType(m.Navigator).first,
    );
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 未崩溃且回到主页，文档仍在存储中。
    expect(find.text('新建笔记'), findsWidgets);
    expect(store.docs.length, 1);
  });

  testWidgets('目的地切换：画布 / 日历均正常渲染', (tester) async {
    await pumpShell(tester);

    // 2 号目的地：画布·笔记
    await tester.tap(find.text('画布·笔记').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('画布'), findsOneWidget);

    // 3 号目的地：日历
    await tester.tap(find.text('日历').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('日历 · 待办'), findsOneWidget);
    expect(find.text('全部日程'), findsOneWidget);
  });

  testWidgets('4 号目的地「设置」渲染密码体系卡与集中入口', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('设置').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('设置'), findsWidgets); // 导航标签 + AppBar 标题
    expect(find.text('密码体系'), findsOneWidget);
    expect(find.text('密码与安全'), findsOneWidget);
    expect(find.text('通用'), findsOneWidget);
    // HomePage 原散落入口已收编（应用锁入口依赖 service 注入，
    // 此装配未注入则按设计隐藏——专项断言在 settings_page_test）。
    // key.frogkey 密码盘体系已删除（N4 批 1，2026-09-02）——入口不复存在。
    expect(find.text('密码盘与恢复'), findsNothing);
    expect(find.text('WebDAV 同步'), findsOneWidget);
  });

  // ---- v1.10.5：导航类控件玻璃化（extendBody + 玻璃导航条 / 玻璃 FAB）----

  testWidgets('窄屏：底部导航条为玻璃胶囊，Scaffold extendBody 开启',
      (tester) async {
    await pumpShell(tester);

    // 玻璃胶囊在位（内部仍复用原生 NavigationBar——交互行为不变）。
    expect(find.byType(GlassNavigationBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    // extendBody 断言：找到持有玻璃导航条的外层 Scaffold。
    final shells = tester.widgetList<m.Scaffold>(find.byType(m.Scaffold));
    final outer = shells.firstWhere(
      (s) => s.bottomNavigationBar is GlassNavigationBar,
    );
    expect(
      outer.extendBody,
      isTrue,
      reason: '内容必须延伸到玻璃条之后，BackdropFilter 才有东西可模糊',
    );
  });

  testWidgets('窄屏：设置页列表消费注入的底部让位（可滚动 padding）',
      (tester) async {
    await pumpShell(tester);

    // IndexedStack 惰性挂载：先切到设置页才在树上。
    await tester.tap(find.text('设置').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 设置页顶层 ListView 的 bottom padding = 注入值（条总高 76，
    // 无系统手势条时）+ 原呼吸空间 24。
    final listViews = tester.widgetList<m.ListView>(
      find.byType(m.ListView),
    );
    final settingsList = listViews.firstWhere(
      (lv) => lv.padding is m.EdgeInsets && (lv.padding as m.EdgeInsets).left == 16,
    );
    final padding = settingsList.padding as m.EdgeInsets;
    expect(
      padding.bottom,
      GlassNavigationBar.totalHeight + 24,
      reason: '内容须能滚到玻璃条背后被模糊（外层固定 padding 会让玻璃退化）',
    );
  });

  testWidgets('窄屏：玻璃 FAB 在位（全部文档圆形 ↔ 首页 extended）',
      (tester) async {
    await pumpShell(tester);

    // IndexedStack 实测行为：同屏只保留当前目的地子树（切换即卸载旧页），
    // 因此 FAB 永远只有 1 个——按状态分别断言。
    // index 0：全部文档移动端 GlassFab（heroTag 'allDocsNewDocFab'，
    // 显式 tag 是 hero 冲突防护的历史保留下）。
    var fab = tester.widgetList<GlassFab>(find.byType(GlassFab)).single;
    expect(fab.heroTag, 'allDocsNewDocFab');

    // index 1：首页 GlassFab.extended（新建画布）。
    await tester.tap(find.text('画布·笔记').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    fab = tester.widgetList<GlassFab>(find.byType(GlassFab)).single;
    expect(fab.heroTag, isNull);
    expect(find.text('新建画布'), findsOneWidget);
  });
}
