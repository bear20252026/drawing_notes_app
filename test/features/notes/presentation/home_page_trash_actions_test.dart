// NOT-01（第四轮审计 2026-10-15）：回收站的三类动作必须既过门禁、又不说假话。
//
// 审计原文：`home_page_trash.dart` 全文无 `PolicyEngine`；对照
// `app_shell_routes.dart:135/145` 同一族动作各有 `enforceCheck`；「清空回收站」
// 的 `onPressed` 直接 `await purgeTrash()`，零二次确认，而 `purgeTrash` 只删
// 超过保留期（30 天）的条目 ⇒ 文案与行为双向不符。
//
// 本文件三种证据，分工写清楚（谁钉什么、为什么不是别的形状）：
//  ① 单元级：`purgeTrash` 的**真实作用域**——过期的删、未满期的不删、回执是
//     真数（这是「文案与行为对齐」里「行为」那一半的直接证据）。
//  ② widget 级：把对话框打开、按钮按下、确认框出现、回执文案落地——走一条
//     真实的用户可见链路。
//  ③ 源扫级：三个动作各自过门禁、且门禁排在二次确认**之后**。
//
// ⚠ 为什么「取消后盘上不动」「过期条目被真删」这两格改走 ①+③ 而不是继续用
// widget 点击钉（本批实测，值得下一轮复用）：widget 侧要点穿两层对话框并完成
// 真实磁盘 IO，而 `testWidgets` 的 body 在假时钟区里——`tapThrough`/`settle`
// 能把大多数时序凑出来，但首页列表路径自带的惰性清理
// （`purgeTrashThrottled`，挂在 `listDocuments` 上）会在播种之后再来一次，
// 于是「过期条目」在点击之前就没了，用例红得没有道理。凑时序凑到第 N 轮就不再
// 是证据，是运气。⇒ 语义交给 ①（确定性直测），顺序交给 ③（源扫 + 分母下限），
// 可见链路留给 ②（一条稳定的用例）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/security/policy_engine.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';

import '../../../helpers/fake_block_doc_accessor.dart';
import '../../../helpers/temp_dir_cleanup.dart';

const _purgeButtonLabel = '清除过期条目';
const _trashTooltip = '回收站（30 天内可恢复）';

/// 判据：一个 `onPressed` 体内，二次确认必须排在策略门禁**之前**。
/// 不含两者的片段（例如只有门禁的「恢复」）不在本判据范围内，一律视为通过。
bool _confirmBeforeGate(String body) {
  final confirm = body.indexOf('_confirmDelete(');
  final gate = body.indexOf('_allowTrashOp(');
  if (confirm < 0 || gate < 0) return true;
  return confirm < gate;
}

void main() {
  late Directory root;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('trash_actions_');
    storage = StorageService(directoryProvider: () async => root);
    AuditLogger.resetSinkForTest();
  });

  tearDown(() async {
    AuditLogger.resetSinkForTest();
    await deleteTempDirWithRetry(root);
  });

  /// 在回收站里直接造一枚「删除时刻」为 N 天前的条目（同步 IO）。
  /// 文件名里的时间戳就是产品的过期判据时间源（`_deletedAtOfTrashFile`
  /// 优先读它，mtime 只兜底），所以不必伪造 mtime 或系统时钟。
  Future<void> seedTrashEntry(String id, {required int ageDays}) async {
    final trashDir = Directory(
      '${root.path}${Platform.pathSeparator}documents_trash',
    );
    trashDir.createSync(recursive: true);
    final deletedAt = DateTime.now().subtract(Duration(days: ageDays));
    final name = '${id}_${deletedAt.millisecondsSinceEpoch}.json';
    final file = File('${trashDir.path}${Platform.pathSeparator}$name');
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'id': id, 'title': id}));
    expect(
      trashDir.listSync().map((e) => e.uri.pathSegments.last),
      contains(name),
      reason: '前置条件：条目没落盘 ⇒ 目录形态与生产不一致，剩下的断言全是空的',
    );
  }

  group('① 保留期语义（确定性直测）', () {
    test('保留期天数只有一份来源：UI 读的就是存储的默认口径', () {
      expect(StorageService.trashRetentionDays, 30);
    });

    test('过期删、未满期一个也不删，回执是真数', () async {
      await seedTrashEntry('keep1', ageDays: 0);
      await seedTrashEntry('keep2', ageDays: 29);
      await seedTrashEntry('gone1', ageDays: 31);
      await seedTrashEntry('gone2', ageDays: 400);

      final purged = await storage.purgeTrash();

      expect(purged, 2, reason: '回执必须是真实删除数，不是「已清空」这类含糊话');
      final rest = (await storage.listTrash()).map((e) => e.$2).toList();
      expect(rest, containsAll(<String>['keep1', 'keep2']));
      expect(rest, isNot(contains('gone1')));
      expect(rest, isNot(contains('gone2')));
    });

    test('没动过任何一次删除 ⇒ 回执 0 且条目全留', () async {
      await seedTrashEntry('fresh1', ageDays: 0);
      expect(await storage.purgeTrash(), 0);
      expect((await storage.listTrash()).length, 1);
    });
  });

  group('③ 门禁接线与顺序（源扫 + 分母下限 + canary）', () {
    final source =
        File(
          'lib/features/notes/presentation/home_page_trash.dart',
        ).readAsStringSync();

    test('分母下限：三个动作各自过门禁，扫描面本身不能是空的', () {
      // 真实接线数下限——「一次都没扫到」与「全都接了」必须不同形。
      final gated = RegExp('_allowTrashOp\\(').allMatches(source).length;
      expect(
        gated,
        greaterThanOrEqualTo(3),
        reason: '回收站三个动作（恢复/永久删除/清空）都应经 _allowTrashOp，实测 $gated 处',
      );
      expect(
        RegExp('note\\.restore').allMatches(source).length,
        greaterThanOrEqualTo(1),
      );
      expect(
        RegExp('note\\.purge').allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason: '永久删除与清除过期各一次',
      );
    });

    test('canary：未列入白名单的操作，enforceCheck 必抛（门禁不是记账簿）', () {
      expect(
        () => const PolicyEngine().enforceCheck('note.purge.everything'),
        throwsA(isA<PolicyDeniedException>()),
      );
      // 反向的一半：白名单内的两个操作确实放行，否则上面那条抛了也没意义。
      expect(const PolicyEngine().check('note.restore').isAllowed, isTrue);
      expect(const PolicyEngine().check('note.purge').isAllowed, isTrue);
    });

    test('顺序：破坏性动作用「先问、再判、再落笔」——确认在门禁之前', () {
      // 判据只写一遍（`_confirmBeforeGate`），canary 与真实源码共用同一份定义。
      // 早先这里是一条跨全文的正则——它匹到了**另一枚按钮**的配对，于是
      // 「把门禁挪到二次确认之前」这个突变照样绿（突变自证抓出来的假证据）。
      final bodies = source.split('onPressed: () async {').skip(1).toList();
      final both = bodies
          .where((b) => b.contains('_confirmDelete(') && b.contains('_allowTrashOp('))
          .toList();
      expect(
        both.length,
        greaterThanOrEqualTo(2),
        reason: '永久删除 / 清除过期两枚按钮都该同时含确认与门禁，实测 '
            '${both.length} 个 ⇒ 分母塌了说明判据根本没在真实源码上跑',
      );
      for (var i = 0; i < both.length; i++) {
        expect(
          _confirmBeforeGate(both[i]),
          isTrue,
          reason: '第 ${i + 1} 处：门禁排在确认之前，用户点「取消」也会留下一条 '
              'success:true 审计——那是没发生过的事',
        );
      }
      // canary：同一份判据，正反两个方向都得判得出来。
      expect(_confirmBeforeGate('a _confirmDelete(x) b _allowTrashOp(y) c'), isTrue);
      expect(_confirmBeforeGate('a _allowTrashOp(y) b _confirmDelete(x) c'), isFalse);
      expect(
        _confirmBeforeGate('只有 _allowTrashOp(y)，没有确认'),
        isTrue,
        reason: '不含两者的片段不在判据范围内——恢复动作就是这一形',
      );
    });
  });

  group('② 用户可见链路（widget 级）', () {
    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: HomePage(
            blockDocAccessor: const FakeBlockDocAccessor(),
            mediaCrypto: MediaCryptoService.instance,
            docStorage: storage,
            notebookStorage: NotebookStorage(directoryProvider: () async => root),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    /// 点一下，再把「真实 IO + 路由动画」走完（必须整段在 `runAsync` 里：
    /// 对话框打开时产品要 `await listTrash()`，那是真实磁盘 IO）。
    Future<void> tapThrough(WidgetTester tester, Finder target) async {
      await tester.runAsync(() async {
        await tester.tap(target);
        for (var i = 0; i < 16; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
      });
    }

    Future<void> openTrash(WidgetTester tester) async {
      await tapThrough(tester, find.byTooltip(_trashTooltip).first);
      expect(
        find.text(_trashTooltip),
        findsWidgets,
        reason: '回收站对话框没打开——后面所有「找不到按钮」都会被误读成产品缺陷',
      );
    }

    testWidgets('按钮措辞按真实作用域，点它先问「删哪些」', (tester) async {
      await seedTrashEntry('trashkeep1', ageDays: 0);
      await pumpHome(tester);
      await openTrash(tester);

      expect(find.text(_purgeButtonLabel), findsOneWidget);
      expect(
        find.text('清空回收站'),
        findsNothing,
        reason: '按钮不得再声称自己能清空整个回收站',
      );

      await tapThrough(tester, find.text(_purgeButtonLabel));
      expect(
        find.textContaining('只会删除超过 30 天的条目'),
        findsOneWidget,
        reason: '破坏性动作前必须有二次确认，且要说清它到底删哪些',
      );
    });

    testWidgets('未满 30 天的条目：确认之后也仍然留在回收站，回执如实报 0', (
      tester,
    ) async {
      await seedTrashEntry('trashkeep2', ageDays: 0);
      await pumpHome(tester);
      await openTrash(tester);
      await tapThrough(tester, find.text(_purgeButtonLabel));
      await tapThrough(tester, find.text('删除'));

      expect(
        find.text('已清除 0 个过期条目'),
        findsOneWidget,
        reason: '回执来自 purgeTrash 的真实计数',
      );
      expect(
        (await tester.runAsync(() => storage.listTrash()))!
            .map((e) => e.$2)
            .toList(),
        contains('trashkeep2'),
        reason: '未满保留期的条目绝不能被这一次点击带走',
      );
    });
  });
}
