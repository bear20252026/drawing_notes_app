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
import 'package:drawing_notes_app/core/all_doc.dart';
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
      final sources = _readLibSources();
      // 分母下限先于结论（审计 TE-TST-04）：`offenders` 恒空有两种成因——真的都改干净了，
      // 或者扫描面塌了（2026-10-16 实测该字面量在 lib 里本来就只剩注释中的历史说明），
      // 而这两种在断言层**完全同形**。
      expect(
        sources.length,
        greaterThanOrEqualTo(300),
        reason:
            '只扫到 ${sources.length} 个 .dart（实测基线 354）⇒ 扫描根或后缀判定动了，'
            '此时下面那句 `isEmpty` 没有裁决力。',
      );
      final offenders = _hairlineOffenders(sources);
      expect(
        offenders,
        isEmpty,
        reason:
            'dividerColor 本身已是 8% 发丝线，再叠乘会淡到看不见。'
            '要分隔线请直接用 AppleHairline。\n$offenders',
      );
    });

    test('判据自证：代码行里的二次衰减必须报，注释里的历史说明不许报', () {
      // 正控（突变 H-1：把判据里的 `dividerColor.withValues` 打错一个字母 ⇒ 这里零报，
      // 而真实库那条照样绿——那正是这条扫描坏掉而无人察觉的形状）。
      expect(
        _hairlineOffenders(const {
          'lib/a.dart': 'Divider(color: c.dividerColor.withValues(alpha: 0.5))',
        }),
        hasLength(1),
        reason: '代码行里的 `dividerColor.withValues` 必须被报出来',
      );
      // 反向锁（突变 H-2：去掉注释过滤 ⇒ 这里误报）。
      expect(
        _hairlineOffenders(const {
          'lib/b.dart': '// 以前写 dividerColor.withValues(alpha: .5)，现在用 AppleHairline',
        }),
        isEmpty,
        reason: '注释里引用历史写法是说明，不是违规——误报会把这条门禁练成哭墙',
      );
      expect(_hairlineOffenders(const <String, String>{}), isEmpty);
    });
  });
}

/// 判据本体：给定「路径 → 源码」，报出代码行里的 `dividerColor.withValues`。
/// 抽成函数只为让上面那条 canary 与真实扫描**共用同一份定义**（R11 记下的纪律：
/// canary 若另抄一份判据，它验证的是自己的副本，等于什么都没验证）。
List<String> _hairlineOffenders(Map<String, String> sources) {
  final offenders = <String>[];
  for (final entry in sources.entries) {
    var lineNo = 0;
    for (final line in entry.value.split('\n')) {
      lineNo++;
      final code = line.trim();
      // 注释里引用历史写法（说明「以前错在哪」）不算违规
      if (code.startsWith('//')) continue;
      if (code.contains('dividerColor.withValues')) {
        offenders.add('${entry.key}:$lineNo');
      }
    }
  }
  return offenders;
}

Map<String, String> _readLibSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    sources[entity.path.replaceAll(r'\', '/')] = entity.readAsStringSync();
  }
  return sources;
}
