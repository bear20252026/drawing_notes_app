import 'dart:io';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// DESIGN.md:336-350 的 `typography.*` 表，逐格照抄。
///
/// 改梯子任何一格都必须同步改这张表——它就是「与原表一致」的定义。
const List<(String, AppleTypeSpec)> kDesignMdTable = [
  ('display-lg', AppleTypeSpec(40, FontWeight.w600, 1.10, 0)),
  ('display-md', AppleTypeSpec(34, FontWeight.w600, 1.47, -0.374)),
  ('lead', AppleTypeSpec(28, FontWeight.w400, 1.14, 0.196)),
  ('lead-airy', AppleTypeSpec(24, FontWeight.w300, 1.5, 0)),
  ('tagline', AppleTypeSpec(21, FontWeight.w600, 1.19, 0.231)),
  ('body-strong', AppleTypeSpec(17, FontWeight.w600, 1.24, -0.374)),
  ('body', AppleTypeSpec(17, FontWeight.w400, 1.47, -0.374)),
  ('dense-link', AppleTypeSpec(17, FontWeight.w400, 2.41, 0)),
  ('caption', AppleTypeSpec(14, FontWeight.w400, 1.43, -0.224)),
  ('caption-strong', AppleTypeSpec(14, FontWeight.w600, 1.29, -0.224)),
  ('button-large', AppleTypeSpec(18, FontWeight.w300, 1.0, 0)),
  ('button-utility', AppleTypeSpec(14, FontWeight.w400, 1.29, -0.224)),
  ('fine-print', AppleTypeSpec(12, FontWeight.w400, 1.0, -0.12)),
  ('micro-legal', AppleTypeSpec(10, FontWeight.w400, 1.3, -0.08)),
  ('nav-link', AppleTypeSpec(12, FontWeight.w400, 1.0, -0.12)),
];

/// 被测梯子，键名与 [kDesignMdTable] 一一对应。
Map<String, AppleTypeSpec> get _actual => {
  'display-lg': AppleTypeScale.displayLg,
  'display-md': AppleTypeScale.displayMd,
  'lead': AppleTypeScale.lead,
  'lead-airy': AppleTypeScale.leadAiry,
  'tagline': AppleTypeScale.tagline,
  'body-strong': AppleTypeScale.bodyStrong,
  'body': AppleTypeScale.body,
  'dense-link': AppleTypeScale.denseLink,
  'caption': AppleTypeScale.caption,
  'caption-strong': AppleTypeScale.captionStrong,
  'button-large': AppleTypeScale.buttonLarge,
  'button-utility': AppleTypeScale.buttonUtility,
  'fine-print': AppleTypeScale.finePrint,
  'micro-legal': AppleTypeScale.microLegal,
  'nav-link': AppleTypeScale.navLink,
};

/// 剥掉 `//` 开头的注释行（文档注释里常会引用历史写法，会污染源码扫描）。
String _withoutComments(String src) =>
    src.split('\n').where((l) => !l.trim().startsWith('//')).join('\n');

String _fmt(AppleTypeSpec s) =>
    '${s.size}/${s.weight == FontWeight.w400
        ? 400
        : s.weight == FontWeight.w600
        ? 600
        : 300}/'
    '${s.height}/${s.tracking}';

void main() {
  group('排版梯子与 DESIGN.md:336-350 逐格一致', () {
    test('梯子的条目数与表相同（15 项，不缺不重）', () {
      expect(_actual.length, kDesignMdTable.length);
      expect(_actual.keys.toSet(), kDesignMdTable.map((r) => r.$1).toSet());
    });

    for (final (name, expected) in kDesignMdTable) {
      test('$name = ${_fmt(expected)}', () {
        final actual = _actual[name];
        expect(actual, isNotNull, reason: '梯子里缺少 $name');
        expect(_fmt(actual!), _fmt(expected), reason: '$name 与 DESIGN.md 表不一致');
        // 逐字段断言，让失败信息能直接指出是哪个维度错了。
        expect(actual.size, expected.size, reason: '$name 字号');
        expect(actual.weight, expected.weight, reason: '$name 字重');
        expect(actual.height, expected.height, reason: '$name 行高');
        expect(actual.tracking, expected.tracking, reason: '$name 字距');
      });
    }
  });

  group('DESIGN.md:362 / :369 / :379 三条原则', () {
    test(':379 正文是 17px（不是 16px）', () {
      expect(AppleTypeScale.body.size, 17);
    });

    test(':369 标题用 600，不是 700', () {
      // 表里所有 600 的条目都不允许出现 700。
      for (final entry in _actual.entries) {
        expect(
          entry.value.weight,
          isNot(FontWeight.w700),
          reason: '${entry.key} 用了 700，DESIGN.md:369 要求标题用 600',
        );
        expect(
          entry.value.weight,
          isNot(FontWeight.w500),
          reason: '${entry.key} 用了 500，DESIGN.md:504 字重梯子里 500 缺席',
        );
      }
    });

    test(':362 行高按角色区分——展示档紧（<1.2）、正文 1.47', () {
      // 40 / 28 / 21px 属展示档，行高必须收在 1.2 以内。
      expect(AppleTypeScale.displayLg.height, lessThan(1.2));
      expect(AppleTypeScale.lead.height, lessThan(1.2));
      expect(AppleTypeScale.tagline.height, lessThan(1.2));
      // 正文必须正好 1.47（:506 禁止低于这个值）。
      expect(AppleTypeScale.body.height, 1.47);
    });

    test(':366 的字距原则以「数值表」为准（散文与表自相矛盾）', () {
      // ⚠️ DESIGN.md 这里自相矛盾：:366 的散文说「Every headline at 17px
      // and up carries a slight tracking tighten (-0.12 → -0.374px)」，
      // 但 :336-350 的表里 display-lg(40px) 是 0、lead(28px) 是 **+0.196**、
      // tagline(21px) 是 **+0.231**——三个都是零或正数。
      // 裁决：**具体数值表优先于散文概括**（表是逐格量过的，散文是归纳）。
      // 上面那组「逐格一致」测试已经锁死了表里每一格的值，这里只补一条
      // 反向保护：表里明确为负的那几格，不许被改回 0 或正数。
      const negativeTracking = <String>['display-md', 'body-strong', 'body'];
      for (final name in negativeTracking) {
        expect(
          _actual[name]!.tracking,
          lessThan(0),
          reason: '$name 在 DESIGN.md 表里是负字距',
        );
      }
      // 同时记录下表里确为正数 / 零的那几格，防止有人按散文去「修正」它们。
      expect(AppleTypeScale.lead.tracking, greaterThan(0));
      expect(AppleTypeScale.tagline.tracking, greaterThan(0));
      expect(AppleTypeScale.displayLg.tracking, 0);
    });
  });

  group('AppleTypeScale.of', () {
    test('四元组全部落到 TextStyle 上', () {
      final style = AppleTypeScale.of(
        AppleTypeScale.body,
        const Color(0xFF1D1D1F),
      );
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.height, 1.47);
      expect(style.letterSpacing, -0.374);
      expect(style.color, const Color(0xFF1D1D1F));
    });

    test('color 传 null 时不覆盖，保留继承来的 DefaultTextStyle', () {
      final style = AppleTypeScale.of(AppleTypeScale.caption, null);
      expect(style.color, isNull);
    });

    test('变体参数（等宽 / 斜体 / 删除线 / 块底色）不改变四元组', () {
      final style = AppleTypeScale.of(
        AppleTypeScale.body,
        null,
        fontFamily: 'monospace',
        fontStyle: FontStyle.italic,
        decoration: TextDecoration.lineThrough,
        backgroundColor: const Color(0xFFEDEDEF),
      );
      expect(style.fontFamily, 'monospace');
      expect(style.fontStyle, FontStyle.italic);
      expect(style.decoration, TextDecoration.lineThrough);
      expect(style.backgroundColor, const Color(0xFFEDEDEF));
      // 四元组仍在。
      expect(style.fontSize, 17);
      expect(style.height, 1.47);
    });
  });

  group('单一事实来源', () {
    test('AppleType.bodyStyle 委托给梯子（字距是 -0.374，不是 -0.1）', () {
      final style = AppleType.bodyStyle(const Color(0xFF000000));
      expect(style.fontSize, AppleTypeScale.body.size);
      expect(style.height, AppleTypeScale.body.height);
      expect(style.letterSpacing, AppleTypeScale.body.tracking);
      expect(style.letterSpacing, -0.374);
    });

    test('笔记编辑器正文块走梯子，且不再用 FontWeight.bold（=700）', () {
      final src = _withoutComments(
        File('lib/features/doc/doc_editor_blocks.dart').readAsStringSync(),
      );
      // 标题此前是 FontWeight.bold（700），:369 要求 600。
      // 注释里会提到这个历史值，故必须剥掉注释再扫。
      expect(src.contains('FontWeight.bold'), isFalse);
      // 正文 / 待办 / 引用 / 标注 / 默认块都接到梯子上。
      expect(
        RegExp(
          r'AppleTypeScale\.of\(\s*AppleTypeScale\.body',
        ).allMatches(src).length,
        greaterThanOrEqualTo(4),
      );
      // 标题走 _headingSpec，其字重必须是 600。
      expect(
        RegExp(r'AppleTypeSpec\(\d+, FontWeight\.w600').allMatches(src).length,
        6,
        reason: 'h1-h6 六个档位都应为 600',
      );
    });
  });
}
