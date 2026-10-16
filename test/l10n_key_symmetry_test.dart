// l10n 对称门禁（2026-10-03 新增）。
//
// 锁三件事：
//   0) 两份 arb 都能按 JSON 解析（防止手工增补漏逗号把整份文件写坏）。
//   A) zh / en 顶层键集合必须**完全相等**。两侧手工补键最容易漏一边，运行
//      时表现为 en 下 MissingResourceException，或中文兜底串漏到英文界面。
//   B) lib/ 里按仓库兜底写法（`AppLocalizations.of(context)?.x ?? '中文'`、
//      `_l10nSafe?.x ?? '中文'`）引用的成员名 x 必须存在于 arb——防「代码先
//      引用、arb 忘补」漂在评审之外。
//   C) 兜底串必须与 zh arb 逐字一致（2026-10-09 补：25 处漂移）。
//
// B 的已知局限是**漏报不误报**，因此不会随机变红：
//   - 只认稳定接收者写法：AppLocalizations.of(...) / _l10nSafe / l10n /
//     l10n0 / _l，其它间接形式（跨行取成员等）不检查；
//   - 只扫含 `AppLocalizations` 的文件，跳过生成目录 lib/l10n/ 与注释行；
//   - 生成类自带的非消息成员（localeName；函数型字段的 call）走白名单。
//
// ── 第四轮审计 TE-TST-04/05 同族补厚（2026-10-15）────────────────────────
// B 与 C 原本各自只有一句 `expect(offenders, isEmpty)`，而**让 offenders 恒空的
// 坏法每种都绿**：`_refRe` 塌空（改接收者写法时手抖）⇒ 一条引用都抽不到；扫描面
// 塌掉（目录/后缀/豁免条件变化）⇒ 一个文件都不读；`C` 的两条跳过判据
// （`want.contains('{')` / `fb.contains(r'$')`）被放宽过头 ⇒ 全部跳过。
// 更要紧的是门禁 A：它比的是 `difference`，**两份 arb 同时被截断时照样「对称」通过**。
//
// 与 `focus_ring_coverage_test`（V-12）、`architecture_layering_test`（R8）同口径补齐：
//   ① 分母下限**先于结论**，且落到每条判据各自的输入面上（arb 键数 / 扫描文件数 /
//      含 AppLocalizations 的文件数 / 实际抽出的引用数 / 实际抽出的兜底对数）；
//   ② 判据抽成纯函数，喂人造的「引用了不存在的键」必须报、喂合法形状必须零报，
//      并把 C 那两条**跳过**判据各钉一格（它们正是这条门禁不天天误报的原因）。
//
// 突变自证（实测计数写进 commit message）：
//   N1 `_refRe` 的接收者写法改成匹配不到 ⇒ `门禁自证` + `抽取自证` 红（`+6 -2`），
//      而**门禁B 照样绿** ⇒ 正是「violators 恒空所以恒绿」的形状；
//   N2 去掉 `isCommentLine` 过滤 ⇒ `抽取自证` 红 **且门禁B 在真实库也红**（`+6 -2`，
//      注释里确实写着 arb 里没有的成员名）⇒ 这格过滤是承重的，不是洁癖；
//   N3a 去掉「arb 值含花括号就跳过」⇒ 恰好 `兜底跳过判据自证` 红（`+7 -1`），门禁C 真实库仍绿；
//   N3b 去掉「兜底含 `$` 就跳过」⇒ 同上（`+7 -1`），门禁C 真实库仍绿。
//      ⚠ 诚实交代：这两格跳过在**今天的语料上彼此冗余**（每个占位符键的兜底同时含 `$`、
//      arb 值同时含 `{`，删掉任一格真实库都不报错）。把它们各钉一格的只有这条 canary——
//      也就是说它们是**防御性分支**，不是当前被行使的判据；记下这点是因为「突变没让真实库红」
//      很容易被误读成「canary 无效」，实际是「当前还没有能触发它的形状」。
//   N4 把 `refOffenders` 的判据改成恒空 ⇒ `判据自证` 红而真实库绿 ⇒ 反向锁那半边同理。
//
// ⚠ 这批还修掉一处**作者自己的假自证**：第一版 canary 的第 3 条同时带 `{` 与 `$` 两种特征，
// N3a 跑下去**全绿**——那条 canary 什么都没钉住。是突变回放把它抓出来的（突变生效而用例不红
// ＝用例无效，不是门禁无效）。改成正交两条（一条只有 `{`、一条只有 `$`）之后 N3a/N3b 才各自红到位。
@Timeout(Duration(seconds: 180))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _zhArbPath = 'lib/l10n/app_zh.arb';
const _enArbPath = 'lib/l10n/app_en.arb';

/// AppLocalizations 生成类的非消息成员——不是 arb 键。
const _nonKeyMembers = {
  'call',
  'localeName',
  'languageCode',
  'scriptCode',
  'territoryCode',
};

/// l10n 取串写法引用的成员名（group 1）。
final _refRe = RegExp(
  r'(?:AppLocalizations\.of\([^)]*\)|_l10nSafe|l10n0|l10n|_l)'
  r'[!?]?\.\s*([A-Za-z_][A-Za-z0-9_]*)',
);

/// `key ?? '兜底串'` 的两造（2026-10-09 审计补的那条判据用）。
final _fallbackRe = RegExp(
  r"([A-Za-z_][A-Za-z0-9_]*)\s*\?\?\s*'((?:[^'\\]|\\.)*)'",
);

String relPath(String p) => p.replaceAll('\\', '/');

/// 注释行不参与引用扫描。
bool isCommentLine(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*');
}

/// 解析 arb 并取顶层键（`@` 前缀的是元数据条目，不计）。
Set<String> arbKeys(Map<String, dynamic> decoded) {
  return decoded.keys.where((k) => !k.startsWith('@')).toSet();
}

Map<String, dynamic> readArb(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}

/// 一段源码里 l10n 取串写法引用到的成员名（带行号，注释行已剔除）。
List<({int line, String name})> refsOf(String src) {
  final found = <({int line, String name})>[];
  final lines = const LineSplitter().convert(src);
  for (var i = 0; i < lines.length; i++) {
    if (isCommentLine(lines[i])) continue;
    for (final m in _refRe.allMatches(lines[i])) {
      found.add((line: i + 1, name: m.group(1)!));
    }
  }
  return found;
}

/// 一段源码里所有 `key ?? '兜底串'` 的两造（带行号，注释行已剔除）。
List<({int line, String key, String fallback})> fallbacksOf(String src) {
  final found = <({int line, String key, String fallback})>[];
  final lines = const LineSplitter().convert(src);
  for (var i = 0; i < lines.length; i++) {
    if (isCommentLine(lines[i])) continue;
    for (final m in _fallbackRe.allMatches(lines[i])) {
      found.add((line: i + 1, key: m.group(1)!, fallback: m.group(2)!));
    }
  }
  return found;
}

/// 门禁 B 的判据：代码引用了 arb 里不存在的键。
List<String> refOffenders(
  Map<String, List<({int line, String name})>> refsByFile,
  Set<String> arbKeySet,
) {
  final offenders = <String>[];
  for (final entry in refsByFile.entries) {
    for (final ref in entry.value) {
      if (arbKeySet.contains(ref.name) || _nonKeyMembers.contains(ref.name)) {
        continue;
      }
      offenders.add('${entry.key}:${ref.line} 引用了 arb 不存在的键 ${ref.name}');
    }
  }
  return offenders;
}

/// 门禁 C 的判据：兜底串与 zh arb 不一致。
///
/// 两条跳过是**承重的**：含占位符的键（`{}`）兜底写法是 Dart 插值（`$x`），形态不同；
/// 带 `$` 的兜底（含转义）同理——只锁纯文本兜底。放宽或删掉它们会立刻把这条门禁
/// 变成天天误报的哭墙，所以 `兜底跳过判据自证` 各钉了一格。
List<String> fallbackOffenders(
  Map<String, List<({int line, String key, String fallback})>> byFile,
  Map<String, String> zhValues,
) {
  final offenders = <String>[];
  for (final entry in byFile.entries) {
    for (final f in entry.value) {
      final want = zhValues[f.key];
      if (want == null) continue;
      if (want.contains('{') || f.fallback.contains(r'$')) continue;
      if (f.fallback != want) {
        offenders.add('${entry.key}:${f.line} ${f.key} 兜底与 arb 不一致');
      }
    }
  }
  return offenders;
}

/// 扫描 `lib/` 下参与本门禁的 .dart 文件（排除生成目录 lib/l10n/）。
List<File> scannedDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !relPath(f.path).startsWith('lib/l10n/'))
    .toList();

void main() {
  final zhArb = readArb(_zhArbPath);
  final enArb = readArb(_enArbPath);
  final zhKeys = arbKeys(zhArb);
  final enKeys = arbKeys(enArb);

  final files = scannedDartFiles();
  final refsByFile = <String, List<({int line, String name})>>{};
  final fallbacksByFile =
      <String, List<({int line, String key, String fallback})>>{};
  var filesWithL10n = 0;
  for (final file in files) {
    final src = file.readAsStringSync();
    final path = relPath(file.path);
    // 门禁 B 沿用原有的粗筛（只扫含 AppLocalizations 的文件）——**不顺手加宽**，
    // 加宽属于新漏口的裁决，另议；这里只把已有口径的失效风险钉住。
    if (src.contains('AppLocalizations')) {
      filesWithL10n++;
      refsByFile[path] = refsOf(src);
    }
    fallbacksByFile[path] = fallbacksOf(src);
  }

  test('门禁0：两份 arb 均为合法 JSON 对象', () {
    expect(zhArb.isNotEmpty, isTrue, reason: '$_zhArbPath 解析为空');
    expect(enArb.isNotEmpty, isTrue, reason: '$_enArbPath 解析为空');
  });

  test('门禁A：zh/en arb 键集合完全对称', () {
    final onlyZh = zhKeys.difference(enKeys);
    final onlyEn = enKeys.difference(zhKeys);
    expect(
      onlyZh,
      isEmpty,
      reason: '仅 zh 有的键（en 缺）：${(onlyZh.toList()..sort())}',
    );
    expect(
      onlyEn,
      isEmpty,
      reason: '仅 en 有的键（zh 缺）：${(onlyEn.toList()..sort())}',
    );
  });

  test('门禁B：代码引用的 l10n 键都存在于 arb', () {
    final offenders = refOffenders(refsByFile, zhKeys.union(enKeys));
    expect(
      offenders,
      isEmpty,
      reason: '在两份 arb 同时补键，或改用既有的键：\n${offenders.join('\n')}',
    );
  });

  test('门禁C：zh 兜底串与 arb 逐字一致（防漂移）', () {
    final zhValues = <String, String>{
      for (final e in zhArb.entries)
        if (!e.key.startsWith('@') && e.value is String)
          e.key: e.value as String,
    };
    final offenders = fallbackOffenders(fallbacksByFile, zhValues);
    expect(
      offenders,
      isEmpty,
      reason:
          '兜底串必须与 app_zh.arb 逐字一致（l10n 未注入时露出）：\n'
          '${offenders.join('\n')}',
    );
  });

  test('门禁自证：分母塌掉 ⇒ 红，不是「零违规」那种绿（TE-TST-04）', () {
    // 下限按 2026-10-15 实测放宽一档：arb 各 1094 键、扫描面 351 文件、
    // 含 AppLocalizations 的 92 文件、抽出引用 1283 处、抽出兜底对 986 处。
    expect(
      zhKeys.length,
      greaterThanOrEqualTo(1000),
      reason:
          'zh arb 只剩 ${zhKeys.length} 个消息键（实测基线 1094）。门禁 A 比的是'
          'difference——**两份同时被截断时照样「对称」通过**，所以键数必须有绝对下限。',
    );
    expect(
      enKeys.length,
      greaterThanOrEqualTo(1000),
      reason: 'en arb 只剩 ${enKeys.length} 个消息键，同上。',
    );
    expect(
      files.length,
      greaterThanOrEqualTo(300),
      reason:
          '只扫到 ${files.length} 个 .dart 文件（实测基线 351）——扫描根/后缀/豁免条件'
          '动了之后，B 与 C 的循环面是空的，`isEmpty` 断言毫无裁决力。',
    );
    expect(
      filesWithL10n,
      greaterThanOrEqualTo(70),
      reason:
          '只有 $filesWithL10n 个文件含 `AppLocalizations`（实测基线 92）⇒ 粗筛或扫描面'
          '塌了，门禁 B 已经不看任何代码。',
    );
    final refCount = refsByFile.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    expect(
      refCount,
      greaterThanOrEqualTo(900),
      reason:
          '读了 $filesWithL10n 个文件却只抽出 $refCount 处 l10n 引用（实测基线 1283）'
          '⇒ `_refRe` 的接收者 alternation 塌空（改写法时手抖就是这个形状），'
          '此时门禁 B 的 violators 恒空。',
    );
    final fbCount = fallbacksByFile.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    expect(
      fbCount,
      greaterThanOrEqualTo(600),
      reason:
          '全库只抽出 $fbCount 处 `key ?? <兜底串>`（实测基线 986）⇒ `_fallbackRe` 塌空，'
          '门禁 C 已被架空。',
    );
  });

  test('抽取自证：四种接收者写法都要抽到，注释行不许算（N1/N2 的落点）', () {
    const src = '''
final a = AppLocalizations.of(context)?.lockTitle ?? '标题';
final b = _l10nSafe?.lockResetOk ?? '已重置';
final c = l10n?.lockSetNewPin ?? '设置';
final d = l10n0!.lockEnabled ?? '启用';
// AppLocalizations.of(context)?.notARealKey ?? '注释里的不算';
''';
    final names = refsOf(src).map((r) => r.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'lockTitle',
        'lockResetOk',
        'lockSetNewPin',
        'lockEnabled',
      ]),
      reason: '表头承诺的四种稳定接收者写法，一种抽不到就是判据少看一片代码',
    );
    expect(
      names,
      isNot(contains('notARealKey')),
      reason: '突变 N2：去掉 isCommentLine 过滤，注释里的字样会被当真引用（天天误报）',
    );
    expect(refsOf('').map((r) => r.name), isEmpty);
  });

  test('判据自证：人造「引用了不存在的键」必须报，合法形状必须零报（N4 的落点）', () {
    final arb = <String>{'lockTitle', 'lockResetOk'};
    final illegal = <String, List<({int line, String name})>>{
      'lib/features/x.dart': [
        (line: 7, name: 'lockTypoKebrid'),
      ],
    };
    expect(
      refOffenders(illegal, arb),
      hasLength(1),
      reason: '突变 N4：把判据改成恒空，这里就零报——而真实库那两条门禁照样绿',
    );
    expect(
      refOffenders(illegal, arb).single,
      allOf(contains('lockTypoKebrid'), contains('lib/features/x.dart:7')),
      reason: '报出来要能定位到文件行，否则这条门禁无法被使用',
    );
    final legal = <String, List<({int line, String name})>>{
      'lib/features/x.dart': [
        (line: 1, name: 'lockTitle'),
        // 生成类自带的非消息成员走白名单——不是 arb 键也不该报。
        (line: 2, name: 'localeName'),
      ],
    };
    expect(refOffenders(legal, arb), isEmpty, reason: '反向锁：不是「一律报警」');
    expect(
      refOffenders(<String, List<({int line, String name})>>{}, arb),
      isEmpty,
    );
  });

  test('兜底跳过判据自证：两格跳过各钉一格，缺一格就误报（N3a/N3b 的落点）', () {
    final zhValues = <String, String>{
      'plain': '纯文本',
      // 带占位符的键：arb 值是 ICU 形态 `{count}`，兜底写法却是 Dart 插值 `$count`，
      // 两者**永远不可能逐字相等** ⇒ 必须跳过，否则这条门禁一上线就全库误报。
      'withPlaceholder': '共 {count} 项',
      // 反过来：arb 值本身没有花括号，但兜底里带了插值（拼接前缀/转义那类写法）。
      'noPlaceholderButInterp': '已选择',
    };
    final sample = <String, List<({int line, String key, String fallback})>>{
      'lib/features/x.dart': [
        // 1) 一致 ⇒ 不报。
        (line: 1, key: 'plain', fallback: '纯文本'),
        // 2) 真漂移 ⇒ 报（这条门禁存在的理由）。
        (line: 2, key: 'plain', fallback: '纯文本改老了'),
        // 3) 只有「arb 含花括号」这一格能救它：兜底里没有 $。
        (line: 3, key: 'withPlaceholder', fallback: '共 项'),
        // 4) 只有「兜底含 $」这一格能救它：arb 值里没有花括号。
        (line: 4, key: 'noPlaceholderButInterp', fallback: r'已选择 $what'),
        // 5) arb 里没有的键 ⇒ 不归本门禁管（那是门禁 B 的活）。
        (line: 5, key: 'notInArb', fallback: '随便'),
      ],
    };
    final offenders = fallbackOffenders(sample, zhValues);
    expect(
      offenders,
      hasLength(1),
      reason: '突变 N3a（去掉「arb 值含花括号就跳过」）或 N3b（去掉「兜底含 \$ 就跳过」），'
          '第 3 / 第 4 条会被当成漂移报出来 ⇒ 这条门禁立刻变成天天误报的哭墙，最后被人绕过',
    );
    expect(
      offenders.single,
      allOf(contains('plain'), contains('lib/features/x.dart:2')),
      reason: '只该报真正漂移的那一条，且要能定位到文件行',
    );
  });
}
