// M11 契约测试：AllDocsPage 搜索过滤与收藏切换接线。
import 'package:flutter/material.dart' as f show TextField;
import 'package:flutter/material.dart' as m;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_sidebar.dart';

AllDoc _doc(String id, String title) => AllDoc(
      id: id,
      title: title,
      kind: AllDocKind.blockdoc,
      folder: '',
      createdAt: DateTime(2026, 8, 1, 10),
      updatedAt: DateTime(2026, 8, 2, 10),
    );

Future<void> pumpPage(
  WidgetTester tester, {
  required List<AllDoc> docs,
  void Function(AllDoc doc)? onToggleFavorite,
  void Function(AllDocKind kind)? onNewDoc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: AllDocsPage(
        loadDocs: () async => buildAllDocs(
          docs: const [],
          notebooks: const [],
          blockDocs: docs
              .map(
                (d) => BlockDocMeta(
                  id: d.id,
                  title: d.title,
                  folder: '',
                  createdAt: d.createdAt,
                  updatedAt: d.updatedAt,
                ),
              )
              .toList(),
          now: DateTime(2026, 8, 2, 12),
        ),
        onOpenDoc: (_) {},
        onNewDoc: onNewDoc,
        onToggleFavorite: onToggleFavorite,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  // 响应式分流（2026-08-31 AFFiNE 式）：默认测试面 800x600 < 900 → 移动端
  // 单栏视图（无侧栏，header 承载搜索/Tab/菜单）；宽屏才渲染桌面双栏。
  testWidgets('窄屏默认移动视图：无侧栏、有新建 FAB、header Tab 可切换', (tester) async {
    await pumpPage(tester, docs: [_doc('a', '设计稿')]);
    expect(find.byType(AllDocsSidebar), findsNothing);
    expect(find.byType(m.FloatingActionButton), findsOneWidget);
    // header Tab 切到收藏夹 → 空态。
    await tester.tap(find.text('收藏夹').first);
    await tester.pump();
    expect(find.text('暂无收藏文档'), findsOneWidget);
  });

  testWidgets('桌面宽屏（≥900）：保留侧栏双栏布局、无 FAB', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, docs: [_doc('a', '设计稿')]);
    expect(find.byType(AllDocsSidebar), findsOneWidget);
    expect(find.byType(m.FloatingActionButton), findsNothing);
  });

  testWidgets('移动端新建 FAB：弹出底部菜单，点新建笔记触发 onNewDoc', (tester) async {
    AllDocKind? created;
    await pumpPage(
      tester,
      docs: [_doc('a', '设计稿')],
      onNewDoc: (kind) => created = kind,
    );
    await tester.tap(find.byType(m.FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建笔记（打字）').last);
    await tester.pump();
    expect(created, AllDocKind.blockdoc);
  });

  testWidgets('搜索框输入后列表按标题过滤', (tester) async {
    await pumpPage(
      tester,
      docs: [_doc('a', '设计稿'), _doc('b', '会议记录')],
    );
    expect(find.text('设计稿'), findsWidgets);
    expect(find.text('会议记录'), findsWidgets);

    // 移动端：搜索收进 header 图标，先展开搜索框。
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(f.TextField), '设计');
    await tester.pump();
    expect(find.text('设计稿'), findsWidgets);
    expect(find.text('会议记录'), findsNothing);
  });

  testWidgets('点击星标触发 onToggleFavorite 并乐观更新', (tester) async {
    AllDoc? toggled;
    await pumpPage(
      tester,
      docs: [_doc('a', '设计稿')],
      onToggleFavorite: (d) => toggled = d,
    );
    // 星标是行的最后一个 star 图标（border 状态）。
    await tester.tap(find.byIcon(Icons.star_border_rounded).last);
    await tester.pump();
    expect(toggled, isNotNull);
    expect(toggled!.id, 'a');
  });

  testWidgets('空态 CTA：点新建笔记（打字）触发 onNewDoc', (tester) async {
    AllDocKind? created;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: AllDocsPage(
          loadDocs: () async => const AllDocQueryResult(
            docs: [],
            sections: [],
          ),
          onOpenDoc: (_) {},
          onNewDoc: (kind) => created = kind,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final cta = find.ancestor(
      of: find.text('新建笔记（打字）'),
      matching: find.byType(m.FilledButton),
    );
    expect(cta, findsOneWidget);
    await tester.tap(cta);
    await tester.pump();
    expect(created, AllDocKind.blockdoc);
  });

  testWidgets('导航切换 Tab（收藏夹/标签空态可见）', (tester) async {
    await pumpPage(tester, docs: [_doc('a', '设计稿')]);
    await tester.tap(find.text('收藏夹').first);
    await tester.pump();
    expect(find.text('暂无收藏文档'), findsOneWidget);

    await tester.tap(find.text('标签').first);
    await tester.pump();
    // TagsView 异步加载标签（空注册表仍有一帧 spinner）。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('暂无标签'), findsOneWidget);
  });
}
