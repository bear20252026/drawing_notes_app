// 侧车「保住了一份原件」的可见回执（STO-004 / DOC-12 乙，业主 2026-10-16 点名）。
//
// 修复前：标签注册表或收藏集合「文件在、但读不出来」时，覆盖前抢救出的 `.corrupt-*`
// 原件**只进审计**——用户看到的是「标签/收藏全空了」，与「旧内容保住了一份可恢复的
// 原件」是两码事。本文件钉三件事：
// ① zh 下真的弹出那句话且带上保留件文件名；② en 下不残留中文（P1-2 同一条反向锁）；
// ③ 没抢救过时**一个字都不说**（反向锁：把门禁练成哭墙，用户会忽略真的那一次）。
//
// 判据为什么只有一处：两个 store 各交出事实（`salvagedOriginalName`），句子只在
// `AppSnack.showSidecarSalvage` 组装一遍——本仓头号复发形态是「一份判据 N 份副本」。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/app_snack.dart';

const _keptName = 'all_docs_tags.json.corrupt-20261016000000-abcd1234';

Future<void> _pumpHost(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => AppSnack.showSidecarSalvage(context, _keptName),
            child: const Text('GO'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zh：保住原件这件事要说出来，且带上保留件的文件名', (tester) async {
    await _pumpHost(tester, const Locale('zh'));

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    final shown = (snack.content as Text).data ?? '';
    expect(shown, contains(_keptName));
    expect(shown, startsWith('旧内容读不出来'), reason: '句子要说清「读不出来」而不是只报文件名');
    expect(shown, contains('没有删掉它'), reason: '用户最需要知道的是原件还在');
  });

  testWidgets('en：同一句话不得残留中文（P1-2 反向锁同形）', (tester) async {
    await _pumpHost(tester, const Locale('en'));

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    final shown = (snack.content as Text).data ?? '';
    expect(shown, isNot(contains(RegExp(r'[一-鿿]'))));
    expect(shown, contains(_keptName));
  });

  testWidgets('反向锁：没抢救出原件时一个字都不说', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              // 正常路径：store 的 `salvagedOriginalName` 是 null。
              onPressed: () => AppSnack.showSidecarSalvage(context, null),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('兜底文案与 arb 同源：l10n 缺席时仍要说同一句话', (tester) async {
    // 不带 AppLocalizations.delegate：`AppLocalizations.of(context)` 返回 null，
    // 走 Dart 侧兜底串——这条把「兜底串」也钉住，防止它哪天与 arb 分叉。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppSnack.showSidecarSalvage(context, _keptName),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(
      (snack.content as Text).data,
      '旧内容读不出来，已另存一份原件（$_keptName），本次覆盖没有删掉它。',
    );
  });
}
