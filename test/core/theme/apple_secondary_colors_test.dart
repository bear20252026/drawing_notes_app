import 'dart:io';
import 'dart:math' as math;

// ── 第四轮审计 TE-TST-04 / R11（2026-10-16）：三条「expect(hits, 0)」原本没有裁决力 ──
// `hits` 恒空有两种成因，而这两种在断言层**完全同形**：① 真的没有违规；② 扫描本身坏了
// （`_libDartFiles` 的根/后缀/令牌文件豁免被改动，或 `_countOccurrences` 的样式漂移）。
// 实测到 2026-10-16：`FontWeight.w500` 全库命中 **0** 处——也就是说这条门禁今天的绿，
// 和它坏掉时的绿，长得一模一样。
// 补两件事（与 R8 层级门禁、R9 l10n 门禁、R10 棘轮同口径）：
//   ① `分母下限`：扫到的 .dart 文件数 ≥300（实测基线 353）；
//   ② `正控/反向锁`：判据本体抽成 `_countInLines`，各喂一段必中样本（含 `Variant` 那一支
//      可选分组）证明正则没塌空，再喂一段**注释里的同形写法**证明它仍然不算命中。
// 突变自证：Q-1 `_libDartFiles` 的扫描根换成小目录 ⇒ 三条真实判据**全绿**，只有 `门禁自证` 红
// （实测 `+10 -1`，扫到 3 个文件）——这正是「恒绿的扫描门禁」；
// Q-2 `_countInLines` 不跳注释行 ⇒ `门禁自证` 红（实测 `+10 -1`），三条真实判据仍绿；
// Q-3 三条共用的 `_manualAlphaRe` 丢掉 `(?:Variant)?` 分组 ⇒ 只有那条正控红。
// ⚠ Q-3 第一次跑的时候**没红**，原因不是判据坏而是 canary 坏：那版 `门禁自证` 里另抄了一份
// 局部正则，于是它验证的是自己的副本，不是门禁实际使用的那一份。改成三条判据与 canary 共用
// 顶层常量（`_manualAlphaRe` / `_manualPanelLiteral` / `_missingWeightLiteral`）之后 Q-3 才有效。
// ⇒ 记一条纪律：**canary 必须与判据共用同一份定义**，否则「canary 绿」什么都不保证。
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
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
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
final String _kTokenFile =
    'core${Platform.pathSeparator}theme'
    '${Platform.pathSeparator}apple_design.dart';

List<File> _libDartFiles({bool includeTokenFile = false}) {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  if (includeTokenFile) return files;
  return files
      .where(
        (f) => !f.path
            .replaceAll('/', Platform.pathSeparator)
            .endsWith(_kTokenFile),
      )
      .toList();
}

/// 三条禁用手写形态——**只在这里定义一次**，真实扫描与 `门禁自证` 共用同一份。
/// （把判据抄两份正是审计 §4 第 2 条「一份判据 N 份副本」的形状：canary 会验证它自己那份，
/// 而不是门禁实际用的那一份。）
final RegExp _manualAlphaRe = RegExp(r'onSurface(?:Variant)?\.withValues\(');
const String _manualPanelLiteral = 'surfaceContainerHighest.withValues(';
const String _missingWeightLiteral = 'FontWeight.w500';

/// 逐行扫描，跳过注释行（避免命中文档里引用的历史写法）。
///
/// 抽成两层（`_countOccurrences` 只负责读盘，`_countInLines` 是判据本体）是为了
/// **能喂人造样本**：这三条都是 `expect(hits, 0)` 的形状，`hits` 恒空既可以是
/// 「真的没有违规」，也可以是「扫描本身坏了」——审计 TE-TST-04 说的就是这两种在断言层
/// 完全同形。分开之后 `门禁自证` 那条能用一段含违规写法的文本证明计数器会数、能跳过注释。
int _countOccurrences(List<File> files, Pattern pattern) =>
    _countInLines([for (final f in files) ...f.readAsLinesSync()], pattern);

/// 判据本体：数出非注释行里 [pattern] 的命中数。
int _countInLines(List<String> lines, Pattern pattern) {
  var hits = 0;
  for (final line in lines) {
    if (line.trim().startsWith('//')) continue;
    hits += pattern.allMatches(line).length;
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
          reason:
              'mutedOf 在 ${scheme.brightness} 档仅 ${ratio.toStringAsFixed(2)}:1',
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
          reason:
              'subtleOf 在 ${scheme.brightness} 档仅 ${ratio.toStringAsFixed(2)}:1',
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
      final hits = _countOccurrences(_libDartFiles(), _manualAlphaRe);
      expect(
        hits,
        0,
        reason: '发现 $hits 处；调用点应改用 AppleColor.mutedOf / subtleOf',
      );
    });

    test('不得再手写 surfaceContainerHighest 的 alpha 变体', () {
      final hits = _countOccurrences(_libDartFiles(), _manualPanelLiteral);
      expect(hits, 0, reason: '发现 $hits 处；应改用 AppleColor.panelOf / fillOf');
    });

    test('lib 内不得出现 FontWeight.w500（DESIGN.md:504 字重梯子缺席 500）', () {
      final hits = _countOccurrences(_libDartFiles(), _missingWeightLiteral);
      expect(hits, 0, reason: '发现 $hits 处；正文用 w400，强调/标题用 w600');
    });

    test('门禁自证：扫描面与三个计数器自己得能响（审计 TE-TST-04）', () {
      // ── ① 分母下限先于结论 ──
      // 三条判据都是 `expect(hits, 0)`：hits 恒空既可以是「真没违规」，也可以是
      // 「扫描本身坏了」，两者在断言层**完全同形**。今天 FontWeight.w500 实测就是 0 命中，
      // 与「计数器坏掉」不可区分——所以先把扫描面钉住。
      final scanned = _libDartFiles();
      expect(
        scanned.length,
        greaterThanOrEqualTo(300),
        reason:
            '只扫到 ${scanned.length} 个 .dart（实测基线 353，含排除令牌文件）⇒ 扫描根/后缀/'
            '令牌文件豁免任一格动了都可能把面塌成空集，此时三条 `hits == 0` 全部无裁决力。',
      );

      // ── ② 三个计数器各喂一段必中样本（正控）+ 一段注释样本（反向锁）──
      // 用的是**门禁自己那一份**判据常量（`_manualAlphaRe` 等），不是这里的副本——
      // 第一版这里抄了一份局部正则，Q-3 突变跑下去「canary 红而门禁照绿」才暴露出：
      // canary 验证它自己那份，就等于什么都没验证。
      expect(
        _countInLines(['color: scheme.onSurface.withValues(alpha: 0.45),'], _manualAlphaRe),
        1,
        reason: '手写 alpha 变体必须被数到——数不到就是正则塌空（TE-TST-05）',
      );
      expect(
        _countInLines([
          'color: scheme.onSurfaceVariant.withValues(alpha: 0.5),',
        ], _manualAlphaRe),
        1,
        reason: '突变 Q-3：正则若丢掉 `(?:Variant)?` 可选分组，这一格红',
      );
      expect(
        _countInLines([
          '// 历史写法：scheme.onSurface.withValues(alpha: 0.6)',
        ], _manualAlphaRe),
        0,
        reason: '反向锁：注释行不算命中，否则这条门禁会被自己的说明文档搞红',
      );
      expect(
        _countInLines([
          'x: Colors.surfaceContainerHighest.withValues(alpha: 0.2)',
        ], _manualPanelLiteral),
        1,
      );
      expect(
        _countInLines(['style: TextStyle(fontWeight: FontWeight.w500)'],
            _missingWeightLiteral),
        1,
      );
      expect(_countInLines(<String>[], _manualAlphaRe), 0, reason: '空表不报错（下限那条负责抓空表）');
    });
  });
}
