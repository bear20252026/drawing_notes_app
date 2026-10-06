// 同步进度文案的本地化回归（审计 P1-2，2026-10-06）。
//
// 修复前 `SyncProgress.description` 在 core 层写死中文并被设置页直接渲染，
// en 用户整条同步进度全程中文。本文件钉住三件事：
// ① 每个阶段在 en 下都取到英文；② 中文路径不回归；
// ③ 缺 l10n 时确实回落到 core 的中文兜底（而不是空串或异常）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/sync/sync_progress.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

Future<AppLocalizations> _loadL10n(WidgetTester tester, Locale locale) async {
  late AppLocalizations l10n;
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
        builder: (context) {
          l10n = AppLocalizations.of(context)!;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

/// 一条进度事件的全部取值组合（含带计数与不带计数两种）。
List<SyncProgress> _everyPhaseSample() => [
  for (final phase in SyncProgressPhase.values) ...[
    SyncProgress(phase: phase),
    SyncProgress(phase: phase, doneCount: 3, totalCount: 7),
  ],
];

void main() {
  testWidgets('en 环境：每个阶段的进度文案都不得含中文', (tester) async {
    final en = await _loadL10n(tester, const Locale('en'));
    for (final progress in _everyPhaseSample()) {
      final label = syncProgressLabel(progress, en);
      expect(
        label,
        isNot(contains(RegExp(r'[一-鿿]'))),
        reason: 'phase=${progress.phase} 在 en 下仍输出中文：$label',
      );
      expect(label, isNotEmpty, reason: 'phase=${progress.phase} 文案为空');
    }
  });

  testWidgets('en 环境：具体字串与计数占位正确', (tester) async {
    final en = await _loadL10n(tester, const Locale('en'));
    expect(
      syncProgressLabel(const SyncProgress(phase: SyncProgressPhase.started), en),
      'Starting sync…',
    );
    expect(
      syncProgressLabel(
        const SyncProgress(phase: SyncProgressPhase.uploading, doneCount: 3, totalCount: 7),
        en,
      ),
      'Uploading 3/7…',
    );
    expect(
      syncProgressLabel(const SyncProgress(phase: SyncProgressPhase.uploading), en),
      'Uploading…',
      reason: 'totalCount=0 表示总数未知，不得输出 0/0',
    );
    expect(
      syncProgressLabel(const SyncProgress(phase: SyncProgressPhase.done), en),
      'Sync complete',
    );
    expect(
      syncProgressLabel(const SyncProgress(phase: SyncProgressPhase.failed), en),
      'Sync failed',
    );
  });

  testWidgets('zh 环境：沿用中文文案（不回归）', (tester) async {
    final zh = await _loadL10n(tester, const Locale('zh'));
    expect(
      syncProgressLabel(
        const SyncProgress(phase: SyncProgressPhase.downloading, doneCount: 2, totalCount: 5),
        zh,
      ),
      '正在下载 2/5…',
    );
    expect(
      syncProgressLabel(const SyncProgress(phase: SyncProgressPhase.done), zh),
      '同步完成',
    );
  });

  testWidgets('失败原因存在时优先展示原因（已按语言与脱敏处理）', (tester) async {
    final en = await _loadL10n(tester, const Locale('en'));
    expect(
      syncProgressLabel(
        const SyncProgress(
          phase: SyncProgressPhase.failed,
          message: 'Sync failed: wrong username or password',
        ),
        en,
      ),
      'Sync failed: wrong username or password',
    );
  });

  test('缺 l10n 时回落 core 中文兜底，而不是空串', () {
    const progress = SyncProgress(
      phase: SyncProgressPhase.writingManifest,
    );
    expect(syncProgressLabel(progress, null), progress.description);
    expect(syncProgressLabel(progress, null), isNotEmpty);
  });
}
