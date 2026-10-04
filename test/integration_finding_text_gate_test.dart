// 集成测试运行时文案门禁（2026-10-04）：integration_test 里的**定位用**字面量
// 必须能在「两份 arb 的 zh/en 值 ∪ lib/ 里的字符串字面量」中找到。
//
// 缘起（宿主确证）：集成测试**不在** CI 覆盖内——`flutter test` 不含
// integration_test，跑它要真机/模拟器。lib 侧改名后，测试里硬编码的
// `find.text('新建笔记（打字）')` 这类字面量不会有任何信号（本轮实测漂移：
// arb docsNewNote 现值「新建笔记」）。`flutter analyze` 也抓不到——
// `find.text('X')` 是运行时匹配，analyze 只看语法与类型。本门禁把
// 「改名 → 测试静默失效」这条链路改成静态可裁决。
//
// 口径（什么算「定位用字面量」）：
// - 文本类匹配 finder 的实参：`find.text` / `textContaining` / `byTooltip` /
//   `bySemanticsLabel`——运行时拿它跟界面渲染文案做相等/包含比较，归本门禁管。
// - `tester.enterText(finder, '值')` 的第二参是**用户输入**而非文案匹配，
//   反而登记为「测试自备数据」，让 `find.text('同一个值')` 这类输入回显断言
//   放行（cuj_01 / smoke_test 的画作名即此类）。
// - 经本地转发器间接传给 finder 的字面量同样要管（如
//   `isToolSelected(tester, '画笔 (P)')` 内部 `find.byTooltip(tooltip)`）——
//   这类文案漂移最隐蔽，故把「形参被直接当作文本 finder 实参」的函数调用
//   区间一并纳入分母。
// - 实参是变量时静态取不到运行时值 → 记为动态实参；是插值/拼接片段时 →
//   记为缺口并**报警**（不许静默绕过门禁）。
//
// 遮蔽：所有正则与取位都在 `maskDartLexically` 的等长遮蔽文本上做（偏移与
// 原文一一对应），否则文档注释里的示例 `find.text('X')` 会被当成真实匹配点
// （同批 focus_ring_coverage_test 首跑就栽在这）。字面量起点判定＝该位被遮蔽
// 且往前第一个非空格位仍是代码位：注释里的引号（`// 'x'` 再往前是被遮蔽的
// `/`）据此排除，字符串内部的空格片段（`'a b'` 的 `b'` 前一位 'b' 也被遮蔽）
// 据此不误断。
//
// 分母加固（同 V-12 的教训）：扫描文件数 / 命中字面量数 / arb 与 lib 语料
// 规模都设下限——扫描面塌成 0 时「零 offender」是失明而非合规。反向锁 A–F
// 证明判定链路真的会响（不存在的文案必红、注释与字符串里的字样不误报、
// 转发器不漏、插值不静默放行），门禁不是恒真。
//
// 已知口径局限（不是豁免）：语料只回答「这个串在 lib/arb 里存在吗」，不回答
// 「在被 pump 的那个页面上会不会渲染」。故 toolbar_test.dart 的
// `find.byTooltip('插入图片')`（旧横栏 editor_toolbar.dart:162 随 247f3b1
// 删除、`_insertImage` 现无 UI 消费方）能过门禁但真机必红——属产品入口缺口，
// 已在该用例注释留证据并交宿主裁决，不在文案门禁里伪装成合规。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_lexical_mask.dart';

/// 豁免表：**默认为空**。条目形如 `integration_test/foo_test.dart:123`
/// （posix 相对路径 + 遮蔽后行号），登记时必须同处写明理由与证据。
/// 只允许「静态可证、但本门禁口径确实覆盖不到」的情形；为了让门禁变绿而加
/// 豁免＝拆门禁，不接受。
const Set<String> _exempt = {};

/// 被扫描的 integration_test 下 .dart 文件数下限。实测 2026-10-04 为 **5**
/// （cuj_01 / doc_lifecycle / feature_test / smoke_test / toolbar_test）。
/// 取下限 4：新增文件不会让门禁变松，而扫描根写错/后缀判定失效会塌到 0。
const int _minScannedFiles = 4;

/// 命中「定位用字面量」总数下限。实测 2026-10-04 为 **50** 处（5 个文件），
/// 取下限 20：若 finder 正则或遮蔽器失明，计数会掉到个位数而不是「少几个」。
const int _minCheckedLiterals = 20;

/// arb 值集合规模下限。实测 2026-10-04：app_zh / app_en 各 **1077** 键，两份
/// 合并去重后 **1891** 条。取 900：arb 路径、JSON 解析或「跳过 @ 元数据」的
/// 口径出错时整体塌掉。
const int _minArbValues = 900;

/// lib/ 字面量语料规模下限。实测 2026-10-04 为 **3029** 条（320 个 .dart 去重
/// 后）。取 1500（≈50%）：语料骤降会把大量测试字面量判成 offender（假红、
/// 响亮），但取位实现与反向锁共用一份，必须先自证语料非空。
const int _minLibLiterals = 1500;

/// 文本类匹配 finder 调用（实参与界面渲染文案比较）。
final RegExp _finderCall = RegExp(
  r'\bfind\s*\.\s*(?:text|textContaining|byTooltip|bySemanticsLabel)\s*\(',
);

/// 用户输入所在调用（其字符串实参是输入值，不是文案匹配）。
final RegExp _enterTextCall = RegExp(r'\benterText\s*\(');

/// 一次扫描的结果。
typedef _Scan = ({
  int checked,
  int dynamicArgs,
  List<String> offenders,
  List<String> gaps,
  Set<String> testInputs,
});

void main() {
  final arbValues = _loadArbValues();
  final libLiterals = _loadLibLiterals();
  final allowed = <String>{...arbValues, ...libLiterals};

  test('门禁：集成测试的定位用字面量必须仍存在于 arb/lib 语料中', () {
    // 语料自身先验规模：语料为空 → 全员假红；口径错位 → 全员假绿。
    expect(
      arbValues.length,
      greaterThanOrEqualTo(_minArbValues),
      reason:
          'arb 语料规模异常：只取到 ${arbValues.length} 个非 @ 元数据值（下限 '
          '$_minArbValues，实测去重后 1891）。说明 arb 路径、JSON 解析或'
          '「跳过 @key 元数据」的口径出了问题。',
    );
    expect(
      libLiterals.length,
      greaterThanOrEqualTo(_minLibLiterals),
      reason:
          'lib/ 字面量语料规模异常：只取到 ${libLiterals.length} 条（下限 '
          '$_minLibLiterals，实测 3029）。说明扫描根目录、后缀判定或遮蔽器取位'
          '出了问题——此时任何漂移都可能被误判。',
    );

    final offenders = <String>[];
    final gaps = <String>[];
    var checked = 0;
    var dynamicArgs = 0;
    var scannedFiles = 0;

    for (final entity in Directory(
      'integration_test',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(r'\', '/');
      scannedFiles++;
      final scan = _scanIntegrationSource(
        entity.readAsStringSync(),
        label: rel,
        allowed: allowed,
      );
      checked += scan.checked;
      dynamicArgs += scan.dynamicArgs;
      offenders.addAll(scan.offenders);
      gaps.addAll(scan.gaps);
    }

    expect(
      scannedFiles,
      greaterThanOrEqualTo(_minScannedFiles),
      reason:
          '扫描面异常：只扫到 $scannedFiles 个 integration_test 下的 .dart 文件'
          '（下限 $_minScannedFiles，实测 5）。此时「零 offender」是失明而非合规。',
    );
    expect(
      checked,
      greaterThanOrEqualTo(_minCheckedLiterals),
      reason:
          '分母异常：扫了 $scannedFiles 个文件却只命中 $checked 个定位用字面量'
          '（下限 $_minCheckedLiterals，实测 50）。finder 正则或遮蔽器已失明，'
          '下面的 isEmpty 断言此时没有裁决力。',
    );
    expect(
      gaps,
      isEmpty,
      reason:
          '以下定位实参是插值/拼接表达式，本门禁取不到其运行时值：\n'
          '${gaps.join('\n')}\n'
          '改成完整字面量（或 arb 键当前值）后由本门禁裁决——留动态实参等于'
          '给文案漂移开后门。',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          '集成测试里的定位字面量在 lib/ 与 arb 语料中都找不到——即「lib 改了'
          '文案、集成测试静默腐烂」（不在 CI 覆盖内，只有真机才会发现）。逐条'
          '回读渲染点后改成语义化定位或 arb 键的当前值，并在注释写明对应 arb 键'
          '与 file:line 证据。\n'
          '命中 ${offenders.length} 处 / 共 $checked 处定位字面量'
          '（另有 $dynamicArgs 处动态实参）：\n${offenders.join('\n')}',
    );
  });

  // ---------- 反向锁：证明判定链路会响，不是恒真 ----------
  // 样本走内存字符串、不落盘；主用例与反向锁共用 _scanIntegrationSource。

  test('反向锁 A：语料里没有的文案必须报 offender（门禁不恒绿）', () {
    const src = """
void main() {
  await tester.tap(find.text('绝对不存在XYZ'));
}
""";
    final scan = _scanIntegrationSource(
      src,
      label: '<inline>',
      allowed: const {'新建笔记'},
    );
    expect(scan.checked, 1, reason: '分母失明：find.text 的字面量没被取到。');
    expect(
      scan.offenders,
      hasLength(1),
      reason: '「绝对不存在XYZ」不在语料里却不报警，说明判定链路恒真。',
    );
    expect(scan.offenders.single, contains('绝对不存在XYZ'));
    expect(scan.offenders.single, startsWith('<inline>:2'));
  });

  test('反向锁 B：语料里存在的文案不得误报', () {
    const src = """
void main() {
  expect(find.text('新建笔记'), findsOneWidget);
  expect(find.byTooltip('画笔 (P)'), findsOneWidget);
}
""";
    final scan = _scanIntegrationSource(
      src,
      label: '<inline>',
      allowed: const {'新建笔记', '画笔 (P)'},
    );
    expect(scan.checked, 2, reason: '两个定位字面量都该进分母。');
    expect(scan.offenders, isEmpty);
    expect(scan.gaps, isEmpty);
  });

  test('反向锁 C：注释与字符串里的字样不得当成匹配点', () {
    const src = r"""
void main() {
  // 历史漂移样本：find.text('绝对不存在XYZ') —— 注释不是匹配点。
  /* 同样 find.byTooltip('绝对不存在QQQ') 也不算 */
  String s = 'find.text(绝对不存在WWW)';
  expect(find.text('新建笔记'), findsOneWidget);
}
""";
    final scan = _scanIntegrationSource(
      src,
      label: '<inline>',
      allowed: const {'新建笔记'},
    );
    expect(scan.checked, 1, reason: '注释/字符串里的三处 finder 不该进分母。');
    expect(scan.offenders, isEmpty);
    expect(scan.dynamicArgs, 0);
  });

  test('反向锁 D：本地转发器的实参同样要判（漏了就会静默腐烂）', () {
    const src = """
void main() {
  expect(isToolSelected(tester, '绝对不存在WWW'), isTrue);
}

bool isToolSelected(WidgetTester tester, String tooltip) {
  return find.byTooltip(tooltip).evaluate().isNotEmpty;
}
""";
    final scan = _scanIntegrationSource(
      src,
      label: '<inline>',
      allowed: const {'画笔 (P)'},
    );
    expect(
      scan.checked,
      1,
      reason: '转发器 isToolSelected 的 tooltip 实参没进分母＝转发器口径失明。',
    );
    expect(
      scan.offenders.single,
      contains('绝对不存在WWW'),
      reason: '只经转发器出现的文案正是漂移最隐蔽的一类，必须报警。',
    );
    expect(
      scan.dynamicArgs,
      1,
      reason: '函数体内的 find.byTooltip(tooltip) 应记为一处动态实参。',
    );
  });

  test('反向锁 E：enterText 第二参是输入值，不是文案匹配', () {
    const src = """
void main() {
  await tester.enterText(field, '我起的画作名');
  expect(find.text('我起的画作名'), findsWidgets);
  expect(find.text('界面上根本没有的名字'), findsOneWidget);
}
""";
    final scan = _scanIntegrationSource(
      src,
      label: '<inline>',
      allowed: const <String>{},
    );
    expect(scan.testInputs, contains('我起的画作名'));
    // 回显断言按「测试自备数据」放行，另一条必须红。
    expect(
      scan.offenders,
      hasLength(1),
      reason: 'offenders=${scan.offenders}——只有真漂移的那条该报警。',
    );
    expect(scan.offenders.single, contains('界面上根本没有的名字'));
    expect(scan.checked, 2);
  });

  test('反向锁 F：变量实参记动态、插值与拼接记缺口，都不静默放行', () {
    const src = r"""
void main() {
  await tester.tap(find.text(label));
  await tester.tap(find.text('前缀${x}后缀'));
  await tester.tap(find.text('甲' + '乙'));
}
""";
    final scan = _scanIntegrationSource(
      src,
      label: '<inline>',
      allowed: const {'甲', '乙'},
    );
    expect(scan.dynamicArgs, 1, reason: 'find.text(label) 是变量实参。');
    expect(
      scan.gaps,
      hasLength(2),
      reason: '插值与拼接实参都要显式报缺口，不能当成合规：\n${scan.gaps.join('\n')}',
    );
    expect(scan.checked, 2, reason: '拼接的两个片段仍是静态字面量，应进分母。');
    expect(scan.offenders, isEmpty);
  });
}

/// 对**单个集成测试源文件**跑判定：遮蔽 → 求定位区间 → 取区间内字面量 →
/// 与语料比对。主用例与反向锁共用这一份实现（反向锁另写逻辑就测不到主路径）。
_Scan _scanIntegrationSource(
  String source, {
  required String label,
  required Set<String> allowed,
}) {
  final code = maskDartLexically(source);
  final literals = _literalsOf(source, code);

  final finderRegions = _callRegions(code, _finderCall);
  final helperRegions = <(int, int)>[
    for (final name in _forwardingHelperNames(code))
      ..._callRegions(code, RegExp(r'\b' + _escapeRegExp(name) + r'\s*\(')),
  ];

  // enterText 的字符串实参＝测试自备输入值（非界面文案）。
  final testInputs = <String>{
    for (final r in _callRegions(code, _enterTextCall))
      for (final lit in literals)
        if (lit.start > r.$1 && lit.start < r.$2) lit.text,
  };

  final offenders = <String>[];
  final gaps = <String>[];
  final counted = <int>{};
  var checked = 0;
  var dynamicArgs = 0;

  /// 判定一批落在同一区间内的字面量（同一串被 finder 区间与转发器区间重复
  /// 命中时只计一次）。
  void check((int, int) r) {
    for (final lit in literals) {
      if (lit.start <= r.$1 || lit.start >= r.$2) continue;
      if (!counted.add(lit.start)) continue;
      checked++;
      final where = '$label:${_lineOf(source, lit.start)}';
      // 拼接片段先判：即便两个片段各自都在语料里，运行时值也不是它们中的
      // 任何一个——必须报缺口，不能靠语料命中蒙过去。
      if (_isConcatenated(source, lit.end)) {
        gaps.add('$where 「${lit.text}」 是拼接表达式片段');
        continue;
      }
      if (allowed.contains(lit.text)) continue;
      if (testInputs.contains(lit.text)) continue;
      if (_exempt.contains(where)) continue;
      offenders.add('$where 「${lit.text}」');
    }
  }

  for (final r in finderRegions) {
    if (!_hasLiteral(literals, r)) {
      // 区间内没有静态字面量：区分「变量实参」与「插值字面量」。
      final first = _skipSpaces(source, r.$1 + 1, r.$2);
      if (first < r.$2 && _isLiteralHead(source, first)) {
        gaps.add('$label:${_lineOf(source, first)} 插值实参，取不到完整静态值');
      } else {
        dynamicArgs++;
      }
      continue;
    }
    check(r);
  }
  // 转发器调用区间只贡献字面量（其声明处的形参列表本就没有字面量，跳过）。
  for (final r in helperRegions) {
    if (_hasLiteral(literals, r)) check(r);
  }

  return (
    checked: checked,
    dynamicArgs: dynamicArgs,
    offenders: offenders,
    gaps: gaps,
    testInputs: testInputs,
  );
}

bool _hasLiteral(
  List<({int start, int end, String text})> literals,
  (int, int) region,
) => literals.any((l) => l.start > region.$1 && l.start < region.$2);

/// 等长遮蔽文本 → 原文件里的**静态**字符串字面量清单（起止偏移 + 运行时值）。
/// 命中一个字面量后整段跳过，避免把闭合引号或转义引号当成新的起点。
List<({int start, int end, String text})> _literalsOf(String src, String code) {
  final out = <({int start, int end, String text})>[];
  var i = 0;
  while (i < src.length) {
    if (!_startsLiteralAt(src, code, i)) {
      i++;
      continue;
    }
    final lit = _readLiteral(src, code, i);
    if (lit == null) {
      i++;
      continue;
    }
    if (lit.text != null) out.add((start: i, end: lit.end, text: lit.text!));
    i = lit.end;
  }
  return out;
}

/// [i] 是否是一个字符串字面量的起始位。
bool _startsLiteralAt(String src, String code, int i) {
  if (!_isBlanked(src, code, i)) return false;
  var p = i - 1;
  while (p >= 0 && (src[p] == ' ' || src[p] == '\t')) {
    p--;
  }
  if (p < 0) return _isLiteralHead(src, i);
  // 往前第一个非空格位必须是**保留的代码位**：落在被遮蔽段里（注释文本、
  // 或同一字符串的前半段）就不算字面量开头。
  return !_isBlanked(src, code, p) && _isLiteralHead(src, i);
}

/// 字面量开头字符：引号，或 raw 串前缀 `r` + 引号。
bool _isLiteralHead(String src, int i) {
  if (i < 0 || i >= src.length) return false;
  if (_isQuote(src[i])) return true;
  return src[i] == 'r' && i + 1 < src.length && _isQuote(src[i + 1]);
}

/// 遮蔽位：原文件非空格、遮蔽文本是空格（遮蔽器只写空格并原样保留换行）。
bool _isBlanked(String src, String code, int i) =>
    code[i] == ' ' && src[i] != ' ';

/// 从 [start] 读一个字面量：返回结束偏移与静态值（含插值时 text 为 null）。
({int end, String? text})? _readLiteral(String src, String code, int start) {
  var q = start;
  var raw = false;
  if (src[q] == 'r' && q + 1 < src.length && _isQuote(src[q + 1])) {
    raw = true;
    q++;
  }
  if (q >= src.length || !_isQuote(src[q])) return null;
  final quote = src[q];
  final triple = quote * 3;
  final term = src.startsWith(triple, q) ? triple : quote;
  var k = q + term.length;
  while (k < src.length) {
    if (!raw && src[k] == r'\') {
      k += 2;
      continue;
    }
    if (src.startsWith(term, k)) {
      final bodyFrom = q + term.length;
      final inner = src.substring(bodyFrom, k);
      final end = k + term.length;
      if (raw) return (end: end, text: inner);
      return (
        end: end,
        text: _isStaticBody(src, code, bodyFrom, k) ? _unescape(inner) : null,
      );
    }
    // 单引号串不跨行：遇换行按未闭合处理，避免越界吞掉后续代码。
    if (term.length == 1 && src[k] == '\n') return null;
    k++;
  }
  return null;
}

/// 字面量体是否全是字面文本（没有 `${...}` / `$ident` 这类被保留的代码位）。
bool _isStaticBody(String src, String code, int from, int to) {
  for (var i = from; i < to; i++) {
    if (_isSpace(src[i])) continue;
    if (!_isBlanked(src, code, i)) return false;
  }
  return true;
}

/// [end] 之后紧跟 `+` 或另一个引号 → 该字面量是拼接片段，运行时值不等于本段。
bool _isConcatenated(String src, int end) {
  final j = _skipSpaces(src, end, src.length);
  if (j >= src.length) return false;
  final c = src[j];
  if (c == '+' || _isQuote(c)) return true;
  return c == 'r' && j + 1 < src.length && _isQuote(src[j + 1]);
}

/// [pattern] 命中处「左括号 → 配对右括号」的开区间（在遮蔽文本上配对，
/// 避开注释/字符串里的假括号；偏移与原文一一对应）。
List<(int, int)> _callRegions(String code, RegExp pattern) {
  final regions = <(int, int)>[];
  for (final m in pattern.allMatches(code)) {
    final open = m.start + m.group(0)!.length - 1;
    final close = _matchParen(code, open);
    if (close > open) regions.add((open, close));
  }
  return regions;
}

int _matchParen(String code, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < code.length; i++) {
    final c = code[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 找出「把 String 形参直接当作文本 finder 实参」的本地函数名。
Set<String> _forwardingHelperNames(String code) {
  final names = <String>{};
  for (final d in RegExp(r'\bString\s+(\w+)').allMatches(code)) {
    final param = d.group(1)!;
    var forwarded = false;
    for (final r in _callRegions(code, _finderCall)) {
      if (code.substring(r.$1 + 1, r.$2).trim() == param) {
        forwarded = true;
        break;
      }
    }
    if (!forwarded) continue;
    final fn = _enclosingFunctionName(code, d.start);
    if (fn != null) names.add(fn);
  }
  return names;
}

/// 由形参位置回溯到其所在形参列表的左括号，取括号前的标识符＝函数名。
String? _enclosingFunctionName(String code, int offset) {
  var depth = 0;
  for (var i = offset; i >= 0; i--) {
    final c = code[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth == 0) {
        var j = i - 1;
        while (j >= 0 && _isSpace(code[j])) {
          j--;
        }
        final end = j;
        while (j >= 0 && _isWord(code[j])) {
          j--;
        }
        return end > j ? code.substring(j + 1, end + 1) : null;
      }
      depth--;
    }
  }
  return null;
}

int _skipSpaces(String src, int from, int to) {
  var i = from;
  while (i < to && _isSpace(src[i])) {
    i++;
  }
  return i;
}

int _lineOf(String src, int offset) =>
    src.substring(0, offset).split('\n').length;

bool _isQuote(String c) => c == "'" || c == '"';

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

bool _isWord(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x30 && u <= 0x39) ||
      (u >= 0x41 && u <= 0x5a) ||
      (u >= 0x61 && u <= 0x7a) ||
      u == 0x5f ||
      u == 0x24 ||
      u > 0x7f;
}

String _escapeRegExp(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => r'\' + m[0]!);

String _unescape(String s) {
  if (!s.contains(r'\')) return s;
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      i++;
      final nx = s[i];
      b.write(switch (nx) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        _ => nx,
      });
      continue;
    }
    b.write(c);
  }
  return b.toString();
}

/// arb 的 zh/en 值集合（跳过 `@@locale` 与 `@key` 元数据）。含占位符的模板
/// （如「插入图片失败：{error}」）原样收录：`find.text` 精确匹配不可能命中
/// 带 `{x}` 的模板，收录它只会让语料更宽，不会把漂移判成合规。
Set<String> _loadArbValues() {
  final values = <String>{};
  for (final name in const ['app_zh.arb', 'app_en.arb']) {
    final file = File('lib/l10n/$name');
    if (!file.existsSync()) continue;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in json.entries) {
      if (entry.key.startsWith('@')) continue;
      final v = entry.value;
      if (v is String) values.add(v);
    }
  }
  return values;
}

/// lib/ 全量字符串字面量（同样经遮蔽器取位，注释里的字样不进语料）。
Set<String> _loadLibLiterals() {
  final literals = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final src = entity.readAsStringSync();
    for (final lit in _literalsOf(src, maskDartLexically(src))) {
      literals.add(lit.text);
    }
  }
  return literals;
}
