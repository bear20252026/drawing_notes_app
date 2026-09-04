// 全部文档列表的信息层级测试（UI 精细化第五批，2026-09-04）。
//
// 权威分工：
// - 字重 / 行高 = 静态视觉域，DESIGN.md 说了算：
//   :504「Don't set body copy at weight 500 — Apple's ladder is
//   300 / 400 / 600 / 700, with 500 deliberately absent」；
//   :506「Don't tighten line-height below 1.47 for body copy」。
// - 分隔线从文字处起 = shadcn 的信息层级做法（只抄做法不抄色）。
//
// 钉住这些值的原因：它们是**肉眼最难发现的一类退化**——分隔线从
// 8% 被二次衰减到 0.64% 之后，界面看起来只是「干净了一点」，没人会
// 意识到分隔线其实已经消失了。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_elevation.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';

void main() {
  AllDoc docWithDescription() => AllDoc(
    id: 'd1',
    title: '设计稿',
    kind: AllDocKind.blockdoc,
    folder: '',
    createdAt: DateTime(2026, 8, 1, 10),
    updatedAt: DateTime(2026, 8, 2, 10),
    description: '第二版草稿',
  );

  Future<void> pumpRow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.lightTheme(),
        home: Scaffold(
          body: AllDocRow(
            doc: docWithDescription(),
            onOpenDoc: () {},
            onToggleFavorite: () {},
          ),
        ),
      ),
    );
  }

  group('列表行排版层级', () {
    testWidgets('标题 15px / w600（不再用 w500）', (tester) async {
      await pumpRow(tester);
      final title = tester.widget<Text>(find.text('设计稿'));
      expect(title.style?.fontSize, 15);
      // DESIGN.md:504 明令字重梯子不含 500
      expect(title.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('描述行高 1.47（DESIGN.md:506）', (tester) async {
      await pumpRow(tester);
      final desc = tester.widget<Text>(find.text('第二版草稿'));
      expect(desc.style?.fontSize, 13);
      expect(desc.style?.height, AppleType.bodyLineHeight);
    });

    testWidgets('元信息不再淡到看不清（0.35 → 0.55）', (tester) async {
      await pumpRow(tester);
      // 未收藏时的星标是元信息层级的代表色
      final star = tester.widget<Icon>(find.byIcon(Icons.star_border_rounded));
      expect(
        star.color?.a,
        0.55,
        reason: '0.35 的 onSurface 对比度仅约 2.3:1，低于 WCAG 4.5:1',
      );
    });
  });

  group('分隔线', () {
    testWidgets('从文字起始处起线，且用发丝线本色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.lightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => AppleHairline.listDivider(
                context,
                indent: AllDocRow.textIndent,
              ),
            ),
          ),
        ),
      );
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, AllDocRow.textIndent);
      expect(
        divider.color,
        AppleHairline.colorFor(Brightness.light),
        reason: '不能对已经是 8% 的发丝线再乘一次透明度',
      );
    });

    test('textIndent 与行内布局一致（16 + 36 + 12）', () {
      expect(AllDocRow.textIndent, 64);
    });

    test('全库不再出现 dividerColor 二次衰减', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        var lineNo = 0;
        for (final line in entity.readAsStringSync().split('\n')) {
          lineNo++;
          final code = line.trim();
          // 注释里引用历史写法（说明「以前错在哪」）不算违规
          if (code.startsWith('//')) continue;
          if (code.contains('dividerColor.withValues')) {
            offenders.add('${entity.path}:$lineNo');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'dividerColor 本身已是 8% 发丝线，再叠乘会淡到看不见。'
            '要分隔线请直接用 AppleHairline。',
      );
    });
  });
}
