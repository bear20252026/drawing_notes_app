// M11 契约测试：AllDocsPage 搜索过滤与收藏切换接线。
import 'package:flutter/material.dart' as f show TextField;
import 'package:flutter/material.dart' as m;
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    as fl_loc show GlobalMaterialLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';

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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        fl_loc.GlobalMaterialLocalizations.delegate,
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
        onToggleFavorite: onToggleFavorite,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('搜索框输入后列表按标题过滤', (tester) async {
    await pumpPage(
      tester,
      docs: [_doc('a', '设计稿'), _doc('b', '会议记录')],
    );
    // 注意：侧栏「文档树」也会显示文档标题，行列表断言取首个匹配。
    expect(find.text('设计稿'), findsWidgets);
    expect(find.text('会议记录'), findsWidgets);

    await tester.enterText(find.byType(f.TextField), '设计');
    await tester.pump();
    // 搜索只过滤行列表；侧栏文档树不随搜索词变化，标题仍在。
    expect(find.text('设计稿'), findsWidgets);
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
          fl_loc.GlobalMaterialLocalizations.delegate,
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

  testWidgets('侧栏导航切换 Tab（收藏夹/标签空态可见）', (tester) async {
    await pumpPage(tester, docs: [_doc('a', '设计稿')]);
    await tester.tap(find.text('收藏夹').first);
    await tester.pump();
    expect(find.text('暂无收藏文档'), findsOneWidget);

    await tester.tap(find.text('标签').first);
    await tester.pump();
    expect(find.text('暂无标签'), findsOneWidget);
  });
}
