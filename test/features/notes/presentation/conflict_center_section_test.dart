// 冲突中心（UI）回归锁：SYNC-003 前半句的展示与改判入口。
//
// 这一层要钉死的形状：
//  ① 空台账**整块不渲染**（设置页不该为「没有冲突」这件事占地方）；
//  ② 展示的是**事实**——两端时间戳、命中了哪条判据、当时实际按什么处理的；
//  ③ 改判默认落在**现有改判**上（打开就看到当前状态，而不是每次都从建议值
//     开始，让人误以为还没设过）；
//  ④ 同步进行中按钮禁用（与 DN-002a 单飞互斥同口径）；
//  ⑤ 原因只显示**最主要的一条**——多条同时成立时全列出来会让这一行长到
//     不可读，而用户真正需要的是「为什么会被报冲突」。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_conflict.dart';
import 'package:drawing_notes_app/core/sync/sync_conflict_ledger.dart';
import 'package:drawing_notes_app/features/notes/presentation/conflict_center_section.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

const _t0 = 1700000000000;

SyncConflict _conflict({
  String docId = 'doc-a',
  ConflictResolution? resolved,
  bool remoteUntrusted = false,
  bool localUnchanged = false,
  bool unverifiable = false,
  bool tie = false,
}) => SyncConflict(
  docId: docId,
  localUpdatedAt: 17000000020000,
  localSize: 120,
  remoteUpdatedAt: 17000000010000,
  remoteSize: 140,
  remoteTimestampUntrusted: remoteUntrusted,
  localUnchangedSinceBaseline: localUnchanged,
  contentUnverifiable: unverifiable,
  fingerprintTie: tie,
  resolvedResolution: resolved,
);

ConflictLedgerEntry _entry({
  String docId = 'doc-a',
  int count = 1,
  SyncConflict? conflict,
  ConflictResolution? override,
  int? overriddenAt,
}) => ConflictLedgerEntry(
  docId: docId,
  firstDetectedAtMs: _t0,
  lastDetectedAtMs: _t0,
  count: count,
  lastConflict: conflict ?? _conflict(),
  resolutionOverride: override,
  overriddenAtMs: overriddenAt,
);

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    AppLocalizations.delegate,
  ],
  supportedLocales: const [Locale('zh'), Locale('en')],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('空台账：整块不渲染（连标题都不占位）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: const [],
          enabled: true,
          onOverride: (_, _) {},
          onClearOverride: (_) {},
        ),
      ),
    );

    expect(find.text('冲突记录'), findsNothing);
    expect(find.text('doc-a'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有条目：标题 + 正文 + 文档号 + 次数 + 当时的事实', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [_entry(count: 3)],
          enabled: true,
          onOverride: (_, _) {},
          onClearOverride: (_) {},
        ),
      ),
    );

    expect(find.text('冲突记录'), findsOneWidget);
    expect(find.text('doc-a'), findsOneWidget);
    expect(find.text('冲突过 3 次'), findsOneWidget);
    expect(
      find.text('当时未选择，按默认规则处理'),
      findsOneWidget,
      reason: '没人选过就如实说没人选，不编一个方向',
    );
    // 两端读数都在（本地较新：17000000020000 > 17000000010000）。
    expect(find.textContaining('· 120B'), findsOneWidget);
    expect(find.textContaining('· 140B'), findsOneWidget);
  });

  testWidgets('已裁决的条目：显示当时按哪个方向处理', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [
            _entry(conflict: _conflict(resolved: ConflictResolution.keepBoth)),
          ],
          enabled: true,
          onOverride: (_, _) {},
          onClearOverride: (_) {},
        ),
      ),
    );

    expect(find.text('当时按「两者皆留」处理'), findsOneWidget);
  });

  testWidgets('已改判的条目：出徽标 + 清除按钮；没改判的没有清除按钮', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [
            _entry(
              docId: 'with-override',
              override: ConflictResolution.keepRemote,
              overriddenAt: _t0 + 5,
            ),
            _entry(docId: 'without-override'),
          ],
          enabled: true,
          onOverride: (_, _) {},
          onClearOverride: (_) {},
        ),
      ),
    );

    expect(find.text('已改判'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ccClearOverride-with-override')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ccClearOverride-without-override')),
      findsNothing,
      reason: '没设过改判就没有「清除」这回事',
    );
  });

  testWidgets('同步进行中：改判与清除都禁用', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [
            _entry(
              override: ConflictResolution.keepRemote,
              overriddenAt: _t0 + 5,
            ),
          ],
          enabled: false,
          onOverride: (_, _) {},
          onClearOverride: (_) {},
        ),
      ),
    );

    final overrideBtn = tester.widget<TextButton>(
      find.byKey(const ValueKey('ccOverride-doc-a')),
    );
    final clearBtn = tester.widget<TextButton>(
      find.byKey(const ValueKey('ccClearOverride-doc-a')),
    );
    expect(overrideBtn.onPressed, isNull);
    expect(clearBtn.onPressed, isNull);
  });

  testWidgets('点改判 → 弹窗 → 选定方向 → 回调带 (条目, 方向)', (tester) async {
    final entry = _entry();
    final seen = <(ConflictLedgerEntry, ConflictResolution)>[];
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [entry],
          enabled: true,
          onOverride: (e, r) => seen.add((e, r)),
          onClearOverride: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ccOverride-doc-a')));
    await tester.pumpAndSettle();

    expect(find.text('这篇下次冲突时怎么处理？'), findsOneWidget);
    // 弹窗必须说清「不撤销上次」这条边界，否则用户会以为点完能恢复。
    expect(find.textContaining('不会撤销已经发生的那次覆盖'), findsOneWidget);

    await tester.tap(find.text('两者皆留'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '改判'));
    await tester.pumpAndSettle();

    expect(seen, hasLength(1));
    expect(seen.single.$1, entry);
    expect(seen.single.$2, ConflictResolution.keepBoth);
  });

  testWidgets('改判弹窗取消 ⇒ 不回调', (tester) async {
    final seen = <(ConflictLedgerEntry, ConflictResolution)>[];
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [_entry()],
          enabled: true,
          onOverride: (e, r) => seen.add((e, r)),
          onClearOverride: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ccOverride-doc-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(seen, isEmpty);
  });

  testWidgets('改判弹窗默认落在**现有改判**上（不是每次从建议值开始）',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [
            _entry(
              // 远端较新 ⇒ 建议是 keepRemote；现有改判是 keepLocal。
              override: ConflictResolution.keepLocal,
              overriddenAt: _t0 + 5,
            ),
          ],
          enabled: true,
          onOverride: (_, _) {},
          onClearOverride: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ccOverride-doc-a')));
    await tester.pumpAndSettle();

    final group = tester.widget<RadioGroup<ConflictResolution>>(
      find.byType(RadioGroup<ConflictResolution>),
    );
    expect(
      group.groupValue,
      ConflictResolution.keepLocal,
      reason: '打开就看到当前设定，才不会被误读成「还没设过」',
    );
  });

  testWidgets('清除改判 → 回调带条目', (tester) async {
    final entry = _entry(
      override: ConflictResolution.keepRemote,
      overriddenAt: _t0 + 5,
    );
    final cleared = <ConflictLedgerEntry>[];
    await tester.pumpWidget(
      _wrap(
        ConflictCenterSection(
          entries: [entry],
          enabled: true,
          onOverride: (_, _) {},
          onClearOverride: cleared.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ccClearOverride-doc-a')));
    await tester.pumpAndSettle();

    expect(cleared, [entry]);
  });

  group('原因只显示最主要的一条（优先级从高到低）', () {
    Future<void> pumpReason(WidgetTester tester, SyncConflict c) async {
      await tester.pumpWidget(
        _wrap(
          ConflictCenterSection(
            entries: [_entry(conflict: c)],
            enabled: true,
            onOverride: (_, _) {},
            onClearOverride: (_) {},
          ),
        ),
      );
    }

    testWidgets('远端时间戳不可信', (tester) async {
      await pumpReason(tester, _conflict(
        remoteUntrusted: true,
        localUnchanged: true,
        unverifiable: true,
        tie: true,
      ));
      expect(find.textContaining('云端时间戳不可信'), findsOneWidget);
      expect(find.textContaining('本地没改过'), findsNothing);
      expect(find.textContaining('无法确认两端内容'), findsNothing);
    });

    testWidgets('本地没改过', (tester) async {
      await pumpReason(tester, _conflict(
        localUnchanged: true,
        unverifiable: true,
        tie: true,
      ));
      expect(find.textContaining('本地没改过'), findsOneWidget);
      expect(find.textContaining('时间戳与字节数完全相同'), findsNothing);
    });

    testWidgets('无法确认内容是否相同', (tester) async {
      await pumpReason(tester, _conflict(unverifiable: true, tie: true));
      expect(find.textContaining('无法确认两端内容'), findsOneWidget);
      expect(find.textContaining('都改过'), findsNothing);
    });

    testWidgets('时间戳与字节数相同但内容不同', (tester) async {
      await pumpReason(tester, _conflict(tie: true));
      expect(find.textContaining('时间戳与字节数完全相同'), findsOneWidget);
    });

    testWidgets('都改过且内容不同（兜底那句）', (tester) async {
      await pumpReason(tester, _conflict());
      expect(find.textContaining('都改过'), findsOneWidget);
    });
  });
}
