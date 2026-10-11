// DN-003 处置入口（2026-10-12）+ DN-005 退出裁决（同日）的展示层回归锁。
//
// 钉三件事：
//   1. 中招用户**看得见也能动**：常驻说明条报出「恢复了多少笔 / 被预算丢弃多少
//      笔」并声明原文件未被改动；唯一的破坏性处置（覆盖原文件）必须二次确认，
//      未确认绝不调用放行出口。
//   2. 设计红线：画布属**内容层**，说明条一个像素的玻璃都不许加（玻璃只准在
//      浮层）——用 BackdropFilter 缺席来锁，比读注释可靠。
//   3. DN-005：强制保存失败后的退出裁决是「留下 / 仍要离开」，默认焦点留在
//      安全一侧；截断态的措辞必须解释原因并指向处置入口，而不是重复一句
//      「保存失败，请重试」。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/document_budgets.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/drawing/presentation/components/editor_budget_truncation_banner.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/shared/widgets/apple_pressable.dart';
import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';

/// 造一份「被单层笔画预算截断」的解码完整性统计。
///
/// 走 [DocumentDecodeStats] 累加器再 `toReport`——[DocumentDecodeReport] 的构造
/// 有 24 个必填参数，逐个写死会让本测试与无关字段一起腐烂。
DocumentDecodeReport truncatedReport({
  int restored = 12,
  int droppedStrokes = 7,
  int droppedObjects = 0,
  int droppedPoints = 0,
}) {
  final stats = DocumentDecodeStats()
    ..strokesRestored = restored
    ..strokesDroppedByLayerBudget = droppedStrokes
    ..shapesDroppedByCountBudget = droppedObjects
    ..pointsDroppedByStrokeBudget = droppedPoints;
  return stats.toReport('doc_truncated', 4096);
}

Widget host(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  theme: AppDesign.lightTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Widget bannerHost({
  Locale locale = const Locale('zh'),
  required DocumentDecodeReport report,
  required VoidCallback onOverride,
}) => host(
  locale,
  Builder(
    builder: (context) => EditorBudgetTruncationBanner(
      report: report,
      // 复刻 `editor_page_persistence._overrideBudgetTruncation` 的接线：说明条
      // 只把「处置」交给宿主，宿主必须先过二次确认才放行。直接把 onOverride
      // 接到计数器等于测组件不测组合——首版正是这样写的，红因在 harness。
      onOverride: () {
        unawaited(
          confirmBudgetTruncationOverride(context, report).then((confirmed) {
            if (confirmed) onOverride();
          }),
        );
      },
    ),
  ),
);

/// 当前屏上所有 Text 的可见文案（含对话框）。
List<String> visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  final cjk = RegExp(r'[一-鿿]');
  group('DN-003：预算截断态的常驻说明条', () {
    testWidgets('报出恢复数与丢弃数，并明确原文件未被改动', (tester) async {
      await tester.pumpWidget(
        bannerHost(report: truncatedReport(), onOverride: () {}),
      );
      final joined = visibleTexts(tester).join('\n');
      expect(joined, contains('12'), reason: '恢复了 12 笔必须说出来');
      expect(joined, contains('7'), reason: '被预算丢弃 7 笔必须说出来');
      expect(joined, contains('磁盘上的原文件没有被改动'));
      expect(joined, contains('自动保存与手动保存都已停止覆盖它'));
    });

    testWidgets('内容层零玻璃：说明条子树里没有 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        bannerHost(report: truncatedReport(), onOverride: () {}),
      );
      // 玻璃材质的实现载体就是 BackdropFilter（glass_surface / liquid_glass）；
      // 画布是内容层，DESIGN_SYSTEM §5 一个像素都不给。
      expect(
        find.descendant(
          of: find.byType(EditorBudgetTruncationBanner),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(find.byType(ApplePressable), findsOneWidget);
      // 反向自证（防恒真）：同一 finder 在浮层 GlassSurface 上必须命中——
      // 玻璃只准用在浮层这条边界确实是可判的，不是空断言。
      await tester.pumpWidget(
        host(const Locale('zh'), const GlassSurface(child: Text('浮层'))),
      );
      expect(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(BackdropFilter),
        ),
        findsWidgets,
      );
    });

    testWidgets('只有真被丢弃的维度才追加那一行（正常路径不制造噪声）', (
      tester,
    ) async {
      await tester.pumpWidget(
        bannerHost(report: truncatedReport(), onOverride: () {}),
      );
      expect(visibleTexts(tester).join('\n'), isNot(contains('此外还有')));

      await tester.pumpWidget(
        bannerHost(
          report: truncatedReport(droppedObjects: 3, droppedPoints: 900),
          onOverride: () {},
        ),
      );
      final joined = visibleTexts(tester).join('\n');
      expect(joined, contains('此外还有'));
      expect(joined, contains('3'));
      expect(joined, contains('900'));
    });

    testWidgets('点按钮只弹二次确认，未确认不放行（acknowledge 零调用）', (
      tester,
    ) async {
      var overridden = 0;
      await tester.pumpWidget(
        bannerHost(
          report: truncatedReport(),
          onOverride: () => overridden++,
        ),
      );
      await tester.tap(find.text('用当前内容覆盖原文件'));
      await tester.pumpAndSettle();
      expect(overridden, 0, reason: '说明条本身不放行，必须过确认框');
      final joined = visibleTexts(tester).join('\n');
      expect(joined, contains('确认用当前内容覆盖原文件？'));
      expect(joined, contains('7'), reason: '确认文案要重复会丢失的数量');
      expect(joined, contains('不可恢复'));

      // 取消侧：闸门必须原样留着。
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(overridden, 0);
    });

    testWidgets('确认之后才放行，且只放行一次', (tester) async {
      var overridden = 0;
      await tester.pumpWidget(
        bannerHost(
          report: truncatedReport(),
          onOverride: () => overridden++,
        ),
      );
      await tester.tap(find.text('用当前内容覆盖原文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('覆盖原文件'));
      await tester.pumpAndSettle();
      expect(overridden, 1);
      // 对话框已关：说明条回到屏上（处置入口是一次性的，不留下过期模态）。
      expect(find.text('确认用当前内容覆盖原文件？'), findsNothing);
    });

    testWidgets('en locale 下说明条与确认框无中文残留', (tester) async {
      await tester.pumpWidget(
        bannerHost(
          locale: const Locale('en'),
          report: truncatedReport(),
          onOverride: () {},
        ),
      );
      expect(
        cjk.hasMatch(visibleTexts(tester).join('\n')),
        isFalse,
        reason: 'en 下不得出现 CJK（本仓反向锁门禁同口径）',
      );
      await tester.tap(find.text('Overwrite the file with this content'));
      await tester.pumpAndSettle();
      expect(
        cjk.hasMatch(visibleTexts(tester).join('\n')),
        isFalse,
        reason: '确认框同样不得漏中文',
      );
    });
  });

  group('DN-005：未落盘改动的退出裁决', () {
    testWidgets('默认留在安全一侧：点「留下继续编辑」= 不放行', (tester) async {
      Future<bool>? handle;
      await tester.pumpWidget(
        host(
          const Locale('zh'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => handle = confirmLeaveWithUnsavedChanges(
                context,
                blockedByBudgetTruncation: false,
              ),
              child: const Text('launch'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      final joined = visibleTexts(tester).join('\n');
      expect(joined, contains('还有改动没有保存到磁盘'));
      expect(joined, contains('这次保存失败了'));
      expect(joined, isNot(contains('截断态')), reason: '一般失败不该扯上闸门');
      await tester.tap(find.text('留下继续编辑'));
      await tester.pumpAndSettle();
      expect(await handle!, isFalse, reason: '留下 = 拦住 pop，改动不得静默丢');
    });

    testWidgets('截断态措辞解释原因并指向处置入口；显式确认才放行', (
      tester,
    ) async {
      Future<bool>? handle;
      await tester.pumpWidget(
        host(
          const Locale('zh'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => handle = confirmLeaveWithUnsavedChanges(
                context,
                blockedByBudgetTruncation: true,
              ),
              child: const Text('launch'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();
      final joined = visibleTexts(tester).join('\n');
      expect(joined, contains('截断态'));
      expect(joined, contains('用当前内容覆盖原文件'), reason: '必须指向处置入口');
      expect(joined, isNot(contains('稍后会再试一次')), reason: '闸门不是重试能解决的');
      await tester.tap(find.text('仍要离开'));
      await tester.pumpAndSettle();
      expect(await handle!, isTrue);
    });
  });
}
