import 'dart:io';
import 'dart:math' as math;

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把带 alpha 的前景合成到不透明背景上，得到实际观感色。
///
/// 注意 Flutter 的 `Color.r/g/b` 返回 0..1 分量，而 `Color.fromARGB` 要
/// 0-255，合成后必须乘回去（此处曾漏乘，导致对比度算出来全是错的）。
Color _composite(Color fg, Color bg) {
  final a = fg.a;
  int mix(double f, double b) => ((f * a + b * (1 - a)) * 255).round();
  return Color.fromARGB(255, mix(fg.r, bg.r), mix(fg.g, bg.g), mix(fg.b, bg.b));
}

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG 2.1 对比度（1..21）。
double _contrast(Color fg, Color bg) {
  final l1 = _luminance(_composite(fg, bg));
  final l2 = _luminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 主题令牌文件：唯一允许"定义" alpha 的地方（subtleOf 与状态层实现）。
final String _kTokenFile = 'core${Platform.pathSeparator}theme'
    '${Platform.pathSeparator}apple_design.dart';

List<File> _libDartFiles({bool includeTokenFile = false}) {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  if (includeTokenFile) return files;
  return files
      .where((f) => !f.path.replaceAll('/', Platform.pathSeparator)
          .endsWith(_kTokenFile))
      .toList();
}

/// 逐行扫描，跳过注释行（避免命中文档里引用的历史写法）。
int _countOccurrences(List<File> files, Pattern pattern) {
  var hits = 0;
  for (final file in files) {
    for (final line in file.readAsLinesSync()) {
      if (line.trim().startsWith('//')) continue;
      hits += pattern.allMatches(line).length;
    }
  }
  return hits;
}

void main() {
  group('AppleColor 次级信息两级配色', () {
    test('mutedOf 走语义色 onSurfaceVariant（不手工叠 alpha）', () {
      final light = AppDesign.lightThemeFor(false).colorScheme;
      final dark = AppDesign.darkTheme().colorScheme;

      expect(AppleColor.mutedOf(light), light.onSurfaceVariant);
      expect(AppleColor.mutedOf(dark), dark.onSurfaceVariant);
      // 必须是完全不透明——叠 alpha 会让深浅模式下的观感不可预测。
      expect(AppleColor.mutedOf(light).a, 1.0);
      expect(AppleColor.mutedOf(dark).a, 1.0);
    });

    test('mutedOf 在明暗两档都满足文本 4.5:1', () {
      for (final scheme in <ColorScheme>[
        AppDesign.lightThemeFor(false).colorScheme,
        AppDesign.darkTheme().colorScheme,
      ]) {
        final ratio = _contrast(AppleColor.mutedOf(scheme), scheme.surface);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'mutedOf 在 ${scheme.brightness} 档仅 ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('subtleOf 是 55% onSurface，且满足非文本 3:1', () {
      final light = AppDesign.lightThemeFor(false).colorScheme;
      final subtle = AppleColor.subtleOf(light);

      expect(subtle.r, light.onSurface.r);
      expect(subtle.g, light.onSurface.g);
      expect(subtle.b, light.onSurface.b);
      expect(subtle.a, closeTo(0.55, 0.001));

      for (final scheme in <ColorScheme>[
        light,
        AppDesign.darkTheme().colorScheme,
      ]) {
        final ratio = _contrast(AppleColor.subtleOf(scheme), scheme.surface);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: 'subtleOf 在 ${scheme.brightness} 档仅 ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('两级配色确实有层级差（未退化成同一色）', () {
      final scheme = AppDesign.lightThemeFor(false).colorScheme;
      final muted = _contrast(AppleColor.mutedOf(scheme), scheme.surface);
      final subtle = _contrast(AppleColor.subtleOf(scheme), scheme.surface);
      expect(muted, greaterThan(subtle));
    });
  });

  group('AppleColor 容器底色', () {
    test('panelOf 取 M3 的 surfaceContainerLow', () {
      final scheme = AppDesign.lightThemeFor(false).colorScheme;
      expect(AppleColor.panelOf(scheme), scheme.surfaceContainerLow);
    });

    test('fillOf 取 surfaceContainerHighest 满底（M3 输入框 / 代码高亮规范）', () {
      final scheme = AppDesign.lightThemeFor(false).colorScheme;
      expect(AppleColor.fillOf(scheme), scheme.surfaceContainerHighest);
      expect(AppleColor.fillOf(scheme).a, 1.0);
    });

    test('panelOf 与填充底不是同一档（面板更浅）', () {
      final scheme = AppDesign.lightThemeFor(false).colorScheme;
      expect(AppleColor.panelOf(scheme), isNot(AppleColor.fillOf(scheme)));
    });
  });

  group('单一事实来源（防石山复发）', () {
    test('调用点不得再手写 onSurface / onSurfaceVariant 的 alpha 变体', () {
      // 历史债：同一「次要信息」语义曾被写成 0.4/0.45/0.5/0.52/0.55/0.6
      // 六种 alpha、共 20+ 处。令牌文件自身（subtleOf、状态层）不在扫描范围。
      final hits = _countOccurrences(
        _libDartFiles(),
        RegExp(r'onSurface(?:Variant)?\.withValues\('),
      );
      expect(
        hits,
        0,
        reason: '发现 $hits 处；调用点应改用 AppleColor.mutedOf / subtleOf',
      );
    });

    test('不得再手写 surfaceContainerHighest 的 alpha 变体', () {
      final hits = _countOccurrences(
        _libDartFiles(),
        'surfaceContainerHighest.withValues(',
      );
      expect(
        hits,
        0,
        reason: '发现 $hits 处；应改用 AppleColor.panelOf / fillOf',
      );
    });

    test('lib 内不得出现 FontWeight.w500（DESIGN.md:504 字重梯子缺席 500）', () {
      final hits = _countOccurrences(_libDartFiles(), 'FontWeight.w500');
      expect(
        hits,
        0,
        reason: '发现 $hits 处；正文用 w400，强调/标题用 w600',
      );
    });
  });
}
