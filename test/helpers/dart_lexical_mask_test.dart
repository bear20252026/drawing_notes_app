// 遮蔽器词法回归自测（P1 修正，审计 2026-10-04）。
//
// 为什么单独立一份：C-06（security_static_access_gate_test）与 V-12
// （focus_ring_coverage_test）两条门禁的判定完全建立在「等长遮蔽后的纯代码
// 文本」上——遮蔽器一退化，两条门禁就静默失明（不报错、直接放行），比断言
// 写坏更难发现。故把词法要点逐条钉成断言，并对实证出错的文件
// （conflict_resolution_dialog.dart:92 的嵌套引号插值把 :95-99 的纯代码整段
// 抹成空格）做真实回归。
//
// 本文件只测遮蔽器本身，不改任何产品代码。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_lexical_mask.dart';

void main() {
  group('遮蔽器不变量', () {
    test('等长：偏移与行号逐字符对齐', () {
      const src = "final a = 'VaultService.instance'; // InkWell(\nfinal b = 1;";
      final masked = maskDartLexically(src);
      expect(masked.length, src.length);
      expect('\n'.allMatches(masked).length, '\n'.allMatches(src).length);
    });

    test('注释与字符串里的被禁字样被抹掉', () {
      const src = '''
/// 生产由组合根注入，不再直取 `VaultService.instance`。
final a = 'MediaCryptoService.instance';
final b = "KekSessionCache.instance";
/* VaultService.instance */
final c = AppleFocusRing(child: InkWell());
''';
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains('VaultService.instance')));
      expect(masked, isNot(contains('MediaCryptoService.instance')));
      expect(masked, isNot(contains('KekSessionCache.instance')));
      // 末行是真实代码，必须留着（否则 V-12 看不见 InkWell）。
      expect(masked, contains('InkWell('));
      expect(masked, contains('AppleFocusRing('));
    });
  });

  group('注释', () {
    test('行注释里的撇号不再骗走字符串态', () {
      const src = "// don't — 撇号\nfinal keep = 1;";
      expect(maskDartLexically(src), contains('keep'));
    });

    test('块注释可嵌套：内层 `*/` 不提前结束', () {
      const src =
          "/* outer /* VaultService.instance */ still comment */\nfinal keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains('VaultService')));
      expect(masked, contains('keep'));
    });

    test('块注释里的未闭合引号不影响其后代码', () {
      const src = "/* '未闭合 */ final keep = 1;";
      expect(maskDartLexically(src), contains('keep'));
    });

    test('字符串里的 `//` 不是注释', () {
      const src = "final url = 'https://example.com/x'; final keep = 1;";
      expect(maskDartLexically(src), contains('keep'));
    });
  });

  group('字符串', () {
    test('三引号跨行串结束后的代码仍可见', () {
      const src = "final m = '''\nInkWell(\n'''; final keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains('InkWell(')));
      expect(masked, contains('keep'));
    });

    test('转义引号不提前终止字符串', () {
      const src = r'''final s = 'a\'b'; final keep = 1;''';
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains("'a")));
      expect(masked, contains('keep'));
    });

    test(r'raw 字符串（含 \ 与撇号）按字面量整体遮蔽', () {
      const src = r'''final p = r'C:\dir\InkWell('; final keep = 1;''';
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains('InkWell(')));
      expect(masked, contains('keep'));
    });

    test('raw 三引号串含单引号', () {
      const src = "final p = r'''it's ''' + x; final keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains("it's")));
      expect(masked, contains('keep'));
    });

    test('未闭合字符串按行收束，不吞掉后续代码', () {
      const src = "final s = '未闭合\nfinal keep = 1;";
      expect(maskDartLexically(src), contains('keep'));
    });
  });

  group('插值', () {
    test(r'$ident 只保留标识符，其后的点是字面文本', () {
      const src = r"final s = '$VaultService.instance'; final keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, isNot(contains('VaultService.instance')));
      expect(masked, contains(r'$VaultService'));
      expect(masked, contains('keep'));
    });

    test('插值内是代码：嵌套引号不弄错字符串态', () {
      const src = r"final s = '${a ?? 'b'}'; final keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, contains('a ??'));
      expect(masked, isNot(contains("'b'")));
      expect(masked, contains('keep'));
    });

    test('插值内花括号深度与递归字符串', () {
      const src = r"final s = '${{'k': '}'}.length}'; final keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, contains('.length'));
      expect(masked, contains('keep'));
    });

    test('插值内的嵌套插值', () {
      const src = r"final s = '${'${x}'}'; final keep = 1;";
      expect(maskDartLexically(src), contains('keep'));
    });

    test('插值内的调用括号可见（供 AppleFocusRing 求覆盖区间）', () {
      const src = r"final s = '${f(a, b)}'; final keep = 1;";
      final masked = maskDartLexically(src);
      expect(masked, contains('f(a, b)'));
      expect(masked, contains('keep'));
    });
  });

  group('实证回归：conflict_resolution_dialog.dart', () {
    test('嵌套引号插值之后的三元式纯代码仍可见', () {
      final file = File(
        'lib/features/notes/presentation/conflict_resolution_dialog.dart',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: '该文件是遮蔽器错位的实证样本，位移/改名须同步本回归',
      );
      final raw = file.readAsStringSync();
      final masked = maskDartLexically(raw);
      expect(masked.length, raw.length);
      // :92 的 `'... ?? '本地 …'}'` 曾使字符串态错位，把 :95-99 整段抹成空格。
      expect(masked, contains('c.localNewer'));
      expect(masked, matches(RegExp(r':\s+c\.remoteNewer')));
      // 遮蔽后仍不得漏出被禁字样（本文件本就没有，命中即说明态机又错位）。
      expect(masked, isNot(contains('VaultService.instance')));
      expect(masked, isNot(contains('InkWell(')));
    });
  });
}
