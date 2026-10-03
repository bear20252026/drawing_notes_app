/// P2 回归锁：`AppServices.dispose()` 的注释承诺「AppShell dispose 时调用」
/// 此前**无任何调用点**（dataVersion 有 HomePage/AllDocsPage 两个 addListener）。
///
/// 本文件锁两件事：
/// ① 释放语义与幂等——释放后通知器不可再用，而存储层 onWrite 仍指向
///   `bumpDataVersion`（迟到写回调必须静默丢弃，不得抛「used after disposed」）；
/// ② 接线——AppShell 卸载时必须真的释放掉它装配出来的那份 dataVersion。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/app/app_services.dart';
import 'package:drawing_notes_app/app/app_shell.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';

import 'helpers/temp_dir_cleanup.dart';

/// 内存版块文档存储（testWidgets 是 FakeAsync 区，真实文件 IO 会挂起——
/// 与 app_shell_smoke_test 同一策略）。
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
  final tempDirs = <Directory>[];

  Future<Directory> tempDir() async {
    final dir = await Directory.systemTemp.createTemp('app_services_');
    tempDirs.add(dir);
    return dir;
  }

  tearDownAll(() async {
    for (final dir in tempDirs) {
      await deleteTempDirWithRetry(dir);
    }
  });

  test('AppServices.dispose：释放 dataVersion、幂等，迟到 bump 静默丢弃', () async {
    final services = AppServices(
      blockDocStore: NoteBlockDocStore(directoryProvider: tempDir),
      favoriteStore: FavoriteStore(directoryProvider: tempDir),
      tagStore: TagStore(directoryProvider: tempDir),
      syncController: SyncController(),
      mediaCrypto: MediaCryptoService.instance,
    );
    final notifier = services.dataVersion;
    var notified = 0;
    notifier.addListener(() => notified++);
    services.bumpDataVersion();
    expect(notified, 1, reason: '释放前正常自增并通知');

    services.dispose();
    // 通知器确已释放（Flutter debug 下对已释放 ChangeNotifier 再加监听即抛）。
    expect(
      () => notifier.addListener(() {}),
      throwsFlutterError,
      reason: 'dispose 必须真正释放 dataVersion',
    );
    // 存储层 onWrite 仍指向 bumpDataVersion：释放后的迟到写回调不得外抛。
    services.bumpDataVersion();
    services.dispose();
  });

  testWidgets('AppShell 卸载时释放它装配的 dataVersion（调用点接线）', (tester) async {
    await tester.pumpWidget(
      m.MaterialApp(
        theme: AppDesign.lightTheme(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [m.Locale('zh'), m.Locale('en')],
        home: AppShell(
          blockDocStore: _MemBlockDocStore(),
          favoriteStore: FavoriteStore(directoryProvider: tempDir),
          tagStore: TagStore(directoryProvider: tempDir),
        ),
      ),
    );
    // AppShell 有常驻环境背景动画，不能 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // AppShell 用 IndexedStack 承载 3 个目的地，非当前目的地在 offstage
    // 子树里（State 已 initState 并订阅信号），故 finder 须放行 offstage。
    final notifier =
        tester
                .widgetList<AllDocsPage>(
                  find.byType(AllDocsPage, skipOffstage: false),
                )
                .first
                .refreshSignal
            as ValueNotifier<int>;
    // 本用例只锁「卸载即释放」：hasListeners 是 ChangeNotifier 的 protected
    // 成员，测试里读它属越界访问，而释放断言本身不依赖壳在场的订阅状态。
    // 卸载壳：换成空树。裸 pumpWidget(Scaffold()) 没有 Directionality 祖先，
    // 会在 debug 下另抛一条无关断言，掩盖本用例真正要验的释放语义。
    await tester.pumpWidget(const m.SizedBox.shrink());
    await tester.pump();

    expect(
      () => notifier.addListener(() {}),
      throwsFlutterError,
      reason: '_AppShellState.dispose 必须调用 AppServices.dispose',
    );
  });
}
