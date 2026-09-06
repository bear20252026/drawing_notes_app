// M12.4 回归（W1 归位后口径更新 2026-09-02）：首页与 All Docs 统一数据源。
//
// 原契约：笔记本页（kind=note）与打字笔记（kind=blockdoc）并列显示于笔记 Tab。
// W1 归位：分页画布**整本**移至画布 Tab（整本粒度卡片），笔记 Tab 只收
// 打字笔记（kind=blockdoc）——页粒度条目不再混入笔记页。本测试锁定新契约。
//
// 数据源契约不变：首页与 All Docs 共用同一装配 loader（buildAllDocs 三源），
// 打开路径统一走 shell 的 _openAllDoc 回调。

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
import 'package:drawing_notes_app/features/notes/domain/notebook_entity.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';

/// 无 IO 画布存储（FakeAsync 安全；画布 Tab 的无限画布区与本测试无关）。
class _NoDocsStorage extends StorageService {
  _NoDocsStorage() : super(directoryProvider: _tempDir);

  static Future<Directory> _tempDir() async =>
      Directory.systemTemp.createTemp('home_sync_test');

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

Notebook _notebook({
  required String id,
  required String title,
  bool encrypted = false,
  String? encryptedPayload,
}) {
  return Notebook(
    id: id,
    title: title,
    encrypted: encrypted,
    encryptedPayload: encryptedPayload,
    createdAt: DateTime(2026, 8, 30, 12),
    updatedAt: DateTime(2026, 8, 30, 12),
  );
}

Widget _homePage({
  required Future<AllDocQueryResult> Function() loadDocs,
  required void Function(AllDoc doc) onOpenDoc,
  ValueListenable<int>? refreshSignal,
  Future<List<Notebook>> Function()? loadNotebooks,
}) {
  return _wrap(
    HomePage(
      docStorage: _NoDocsStorage(),
      notebookStorage: NotebookStorage(
        directoryProvider: _NoDocsStorage._tempDir,
      ),
      refreshSignal: refreshSignal,
      loadDocs: loadDocs,
      loadNotebooks: loadNotebooks ?? (() async => const <Notebook>[]),
      onOpenDoc: onOpenDoc,
    ),
  );
}

void main() {
  testWidgets('笔记 Tab 只显示打字笔记：kind=note 页条目不再混入（W1 归位）', (tester) async {
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

    // W1 归位：页粒度分页画布条目不再出现在笔记 Tab。
    expect(find.text('旅行计划页'), findsNothing);
    expect(find.text('读书笔记'), findsOneWidget);
    expect(find.textContaining('笔记 · 更新于'), findsOneWidget);
  });

  testWidgets('点击打字笔记走统一打开回调（与 All Docs 同路径）', (tester) async {
    final entries = [
      _entry(id: 'bd1', title: '读书笔记', kind: AllDocKind.blockdoc),
    ];
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

    await tester.tap(find.text('读书笔记'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.id, 'bd1');
    expect(opened.single.kind, AllDocKind.blockdoc);
  });

  testWidgets('数据版本变化后打字笔记列表自动重载', (tester) async {
    final signal = ValueNotifier<int>(0);
    await tester.pumpWidget(
      _homePage(
        refreshSignal: signal,
        loadDocs: () async {
          final list = <AllDoc>[
            _entry(id: 'bd1', title: '读书笔记', kind: AllDocKind.blockdoc),
          ];
          if (signal.value >= 1) {
            list.add(
              _entry(id: 'bd2', title: '第二篇笔记', kind: AllDocKind.blockdoc),
            );
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
    expect(find.text('读书笔记'), findsOneWidget);
    expect(find.text('第二篇笔记'), findsNothing);

    signal.value++;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('第二篇笔记'), findsOneWidget);
  });

  testWidgets('W1 归位：分页画布整本卡显示在画布 Tab，点击走统一打开回调', (tester) async {
    final opened = <AllDoc>[];
    await tester.pumpWidget(
      _homePage(
        loadDocs: () async =>
            AllDocQueryResult(docs: const [], sections: const []),
        loadNotebooks: () async => [_notebook(id: 'nb1', title: '旅行画册')],
        onOpenDoc: opened.add,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 画布 Tab（默认）：区段标题 + 整本卡（页数粒度，非页条目）。
    expect(find.text('旅行画册'), findsOneWidget);
    expect(find.textContaining('页 · 更新于'), findsOneWidget);
    await tester.tap(find.text('旅行画册'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.notebookId, 'nb1');
    expect(opened.single.kind, AllDocKind.note);
  });

  testWidgets('W1 归位：加密分页画布显示锁态副标题（不泄露页数）', (tester) async {
    await tester.pumpWidget(
      _homePage(
        loadDocs: () async =>
            AllDocQueryResult(docs: const [], sections: const []),
        loadNotebooks: () async => [
          // 保险库锁定占位：encrypted + 无页面 + 无密文载荷。
          _notebook(id: 'nb1', title: '秘密画册', encrypted: true),
          // 文件密码受密：encrypted + 密文载荷（页面未解密为空）。
          _notebook(
            id: 'nb2',
            title: '加密画册',
            encrypted: true,
            encryptedPayload: 'cipher',
          ),
        ],
        onOpenDoc: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('已加密 · 更新于'), findsNWidgets(2));
  });
}
