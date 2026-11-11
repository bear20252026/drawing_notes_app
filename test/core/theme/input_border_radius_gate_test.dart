// `OutlineInputBorder` 必须显式声明圆角档位门禁（审计 UX 轮次 P1-3 遗留 + 2026-11 回潮）。
//
// 背景：`OutlineInputBorder` 的 `borderRadius` 默认值是
// `BorderRadius.all(Radius.circular(4.0))`（Flutter 框架常量），而 **4 不在
// DESIGN.md:127-135 的合法档位里**（`none 0 / xs 5 / sm 8 / md 11 / lg 18 /
// pill 9999 / full 9999`）。也就是说：谁写了一个不带 `borderRadius` 的
// `OutlineInputBorder`，谁就悄悄引入了非法圆角——而它**看起来完全正常**，
// 没有编译错误、没有 lint、也没有既有门禁报警。
//
// 这不是假想：2026-09-18 的批次修过一批（原列 9 处），但
// `lib/features/notes/presentation/home_page_widgets.dart` 的命名对话框里
// 又留了 3 处（`border` / `enabledBorder` / `focusedBorder`），
// 2026-11-11 才被发现并修掉。**同类回潮必须由机器拦住**，否则每次
// 「补一个输入框」都可能再犯一次。
//
// 判定口径：
// - 命中形态 = `OutlineInputBorder(` 的**调用点**（类型注解不算）。
// - 从调用的 `(` 起做括号配对，直到深度归零；该区间内没有 `borderRadius`
//   即为违规。
// - 扫描前做**等长遮蔽**（`helpers/dart_lexical_mask.dart`）：注释与字符串
//   里的字样不计。
// - 本门禁是**硬零**（不是棘轮）：存量已清零，新增一律拦住。
//
// 反向锁用例见 `main()` 后半：本门禁与全部静态门禁共有的病灶是「恒绿」
// （扫描面塌成 0、遮蔽器把真代码抹空、括号配对写错都会让 isEmpty 白过），
// 故用内联样本从两个相反方向钉判定链路，并给被扫描文件数设下限。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/dart_lexical_mask.dart';

/// 被扫描文件数下限（封堵「扫描根写错 → 扫 0 文件而恒绿」）。
///
/// 依据：立卡时实测 `lib/**/*.dart` 共 **320** 个文件进入扫描（同
/// `spacing_token_ratchet_test.dart` 的实测），取 **180**（≈56%）。
const int _minScannedFiles = 180;

/// 违规调用点：`相对路径:行号`。
class _Hit {
  const _Hit(this.file, this.line, this.excerpt);

  final String file;
  final int line;
  final String excerpt;

  @override
  String toString() => '$file:$line  ${excerpt.trim()}';
}

/// 在单个文件的**遮蔽后**源码里找 `OutlineInputBorder(` 调用点，
/// 返回其中缺少 `borderRadius` 的那些。
List<_Hit> _scanDartSource(String src, {required String label}) {
  final masked = maskDartLexically(src);
  final hits = <_Hit>[];
  final lines = masked.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final matches = RegExp(r'OutlineInputBorder\s*\(').allMatches(line);
    for (final m in matches) {
      // 从 `(` 起做括号配对，扫到深度归零为止（可跨行），同时收集区间文本。
      var depth = 0;
      final span = StringBuffer();
      var closed = false;
      var j = i;
      var k = m.end - 1; // 指向 `(`
      while (j < lines.length) {
        final text = lines[j];
        for (; k < text.length; k++) {
          final ch = text[k];
          span.write(ch);
          if (ch == '(') {
            depth++;
          } else if (ch == ')') {
            depth--;
            if (depth == 0) {
              closed = true;
              break;
            }
          }
        }
        if (closed) break;
        span.write('\n');
        j++;
        k = 0;
      }
      // 区间内没有 borderRadius 即违规。整段一起判，故 `borderSide` 在前、
      // `borderRadius` 在后（或同行）的写法都不会被误判。
      if (!RegExp(r'\bborderRadius\b').hasMatch(span.toString())) {
        hits.add(_Hit(label, i + 1, line));
      }
    }
  }
  return hits;
}

/// 扫全仓 `lib/`，返回违规清单与进入扫描的文件清单。
({List<_Hit> hits, List<String> scanned}) _measureRepo() {
  final hits = <_Hit>[];
  final scanned = <String>[];
  final lib = Directory('lib');
  if (!lib.existsSync()) return (hits: hits, scanned: scanned);
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.replaceAll('\\', '/');
    scanned.add(rel);
    hits.addAll(
      _scanDartSource(entity.readAsStringSync(), label: rel),
    );
  }
  return (hits: hits, scanned: scanned);
}

// ── 自证夹具 ──────────────────────────────────────────────────────────

/// 必须被抓到的形态：不带 `borderRadius` 的调用（含多行、含 `const`）。
const String _sampleShouldCatch = '''
class A {
  final border = OutlineInputBorder(
    borderSide: BorderSide(color: Color(0xFF000000)),
  );
  final border2 = const OutlineInputBorder(
    borderSide: BorderSide(),
  );
}
''';

/// 不该被误伤的形态：带了 `borderRadius` 的调用。
const String _sampleShouldPass = '''
class B {
  final a = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppleRadius.xs),
    borderSide: BorderSide(),
  );
  final b = OutlineInputBorder(
    borderSide: BorderSide(),
    borderRadius: BorderRadius.all(Radius.circular(AppleRadius.lg)),
  );
  // 同行写法：早期版本漏判过这一形态（区间文本没收集，只在不闭合的行尾检查）。
  final c = OutlineInputBorder(borderRadius: BorderRadius.circular(AppleRadius.md));
}
''';

/// 注释与字符串里的字样不算。
const String _sampleCommentsOnly = '''
// 这里曾经写过 OutlineInputBorder(borderSide: BorderSide())，已修。
/// 文档里也提一句 OutlineInputBorder(borderSide: BorderSide())。
class C {
  static const String doc = 'OutlineInputBorder(borderSide: BorderSide())';
}
''';

void main() {
  test('OutlineInputBorder 必须显式声明圆角档位（硬零门禁）', () {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason: '找不到 lib/ 目录：测试的工作目录必须是仓库根（见 AGENTS.md 的 shell 目录铁律）。',
    );

    final scan = _measureRepo();
    final scannedFiles = scan.scanned.length;

    // 分母下限先于结论：扫描面塌掉时「零违规」是失明而非合规。
    expect(
      scannedFiles,
      greaterThanOrEqualTo(_minScannedFiles),
      reason:
          '扫描面异常：只扫到 $scannedFiles 个 .dart 文件（下限 $_minScannedFiles，'
          '立卡实测 320）。说明扫描根/后缀判定/遮蔽器出了问题，'
          '此时下面的 isEmpty 断言毫无裁决力。必须修口径，绝不能放宽下限变绿。',
    );
    // 哨兵：确认扫到的是本仓源码树（与有没有违规无关——否则将来把该文件
    // 清理干净后本断言会假红）。
    expect(
      scan.scanned,
      containsAll(['lib/core/theme/apple_design.dart', 'lib/main.dart']),
      reason: '哨兵文件未进入扫描面：扫描根目录或后缀判定已失配（工作目录必须是仓库根）。',
    );

    expect(
      scan.hits,
      isEmpty,
      reason:
          '发现 ${scan.hits.length} 处未声明圆角的 OutlineInputBorder：\n'
          '${scan.hits.join('\n')}\n\n'
          '默认值 4.0 不在 DESIGN.md:127-135 的合法档位里。请补 '
          '`borderRadius: BorderRadius.circular(AppleRadius.xs)`（或同族档位），'
          '与同文件其他输入框保持一致。',
    );
  });

  test('反向锁 A：不带 borderRadius 的调用必须被抓到（含 const 与多行）', () {
    final hits = _scanDartSource(_sampleShouldCatch, label: '<inline>');
    expect(
      hits,
      hasLength(2),
      reason:
          '期望 2 个违规点（普通 + const 多行），实测 ${hits.length}：$hits。'
          '少了说明括号配对或判定链路失明，门禁会恒绿。',
    );
    expect(
      hits.map((h) => h.line).toSet(),
      equals({2, 5}),
      reason: '行号必须与原文对齐（三引号后紧跟的首个换行不计入内容），否则 reason 会指错地方。',
    );
  });

  test('反向锁 B：带 borderRadius 的调用不被误伤（含 borderRadius 在后的写法）', () {
    final hits = _scanDartSource(_sampleShouldPass, label: '<inline>');
    expect(
      hits,
      isEmpty,
      reason:
          '合法样本被判违规：$hits。注意第二个样本是 `borderSide` 在前、'
          '`borderRadius` 在后的写法——区间检查若只看首行就会误判。',
    );
  });

  test('反向锁 C：注释与字符串里的字样不计入', () {
    final hits = _scanDartSource(_sampleCommentsOnly, label: '<inline>');
    expect(
      hits,
      isEmpty,
      reason:
          '注释/文档/字符串里的 `OutlineInputBorder(...)` 被当成真实代码：'
          '等长遮蔽已失效，任何人写一句用法注释都会假红。',
    );
  });
}
