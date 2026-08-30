// M12.4 回归：首页笔记 Tab 与 All Docs 统一数据源。
//
// 背景（用户反馈）：笔记本页（NotebookPage，显示于 All Docs 的"笔记"行）
// 与打字笔记（NoteBlockDoc，显示于首页笔记 Tab）双源分裂——在笔记页
// （NotebookViewPage）新增页面后，首页列表永远不会显示该页。
// 修复：首页笔记 Tab 改用与 All Docs 同一装配 loader（buildAllDocs 三源），
// 打开路径统一走 shell 的 _openAllDoc 回调。本测试锁定该契约。

import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/storage/repository.dart'
    show DocumentMeta;
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';

Future<Directory> _tempDir() async =>
    Directory.systemTemp.createTemp('home_sync_test');

/// 无 IO 画布存储（FakeAsync 安全；首页画布 Tab 与本测试无关，恒空即可）。
class _NoDocsStorage extends StorageService {
  _NoDocsStorage() : super(directoryProvider: _tempDir);

  @override
  Future<List<DocumentMeta>> listDocuments() async => const <DocumentMeta>[];
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

AllDoc _entry({
  required String id,
  required String title,
  required AllDocKind kind,
}) {
  final now = DateTime(2026, 8, 30, 12);
  return AllDoc(
    id: id,
    title: title,
    kind: kind,
    folder: '',
    createdAt: now,
    updatedAt: now,
  );
}

Widget _homePage({
  required Future<AllDocQueryResult> Function() loadDocs,
  required void Function(AllDoc doc) onOpenDoc,
  ValueListenable<int>? refreshSignal,
}) {
  return _wrap(
    HomePage(
      docStorage: _NoDocsStorage(),
      notebookStorage: NotebookStorage(directoryProvider: _tempDir),
      refreshSignal: refreshSignal,
      loadDocs: loadDocs,
      onOpenDoc: onOpenDoc,
    ),
  );
}

void main() {
  testWidgets('笔记 Tab 同源渲染：笔记本页面 + 打字笔记并列显示', (tester) async {
    final entries = [
      _entry(id: 'pg1', title: '旅行计划页', kind: AllDocKind.note),
      _entry(id: 'bd1', title: '读书笔记', kind: AllDocKind.blockdoc),
    ];
    await tester.pumpWidget(
      _homePage(
        loadDocs: () async =>
            AllDocQueryResult(docs: entries, sections: const []),
        onOpenDoc: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 切到「笔记」Tab（TabBarView 懒构建）。
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();

    // 两种来源的条目同列表可见（修复前：笔记本页面永远不会出现在首页）。
    expect(find.text('旅行计划页'), findsOneWidget);
    expect(find.text('读书笔记'), findsOneWidget);
    // 副标题标注来源类型。
    expect(find.textContaining('笔记本页面'), findsOneWidget);
    expect(find.textContaining('打字笔记'), findsOneWidget);
  });

  testWidgets('点击条目走统一打开回调（与 All Docs 同路径）', (tester) async {
    final entries = [_entry(id: 'pg1', title: '会议记录页', kind: AllDocKind.note)];
    final opened = <AllDoc>[];
    await tester.pumpWidget(
      _homePage(
        loadDocs: () async =>
            AllDocQueryResult(docs: entries, sections: const []),
        onOpenDoc: opened.add,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('会议记录页'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.id, 'pg1');
    expect(opened.single.kind, AllDocKind.note);
  });

  testWidgets('数据版本变化后列表自动重载（新增页面无需手动刷新）', (tester) async {
    final signal = ValueNotifier<int>(0);
    await tester.pumpWidget(
      _homePage(
        refreshSignal: signal,
        loadDocs: () async {
          // 模拟真实装配：每次读取都反映最新落盘数据（版本>=1 时有新页）。
          final list = <AllDoc>[
            _entry(id: 'pg1', title: '第一页', kind: AllDocKind.note),
          ];
          if (signal.value >= 1) {
            list.add(_entry(id: 'pg2', title: '第二页', kind: AllDocKind.note));
          }
          return AllDocQueryResult(docs: list, sections: const []);
        },
        onOpenDoc: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('笔记'));
    await tester.pumpAndSettle();
    expect(find.text('第一页'), findsOneWidget);
    expect(find.text('第二页'), findsNothing);

    // 笔记页新增页面 → 落盘 → 返回首页时 shell 自增数据版本 → 自动重载。
    signal.value++;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);
  });
}
