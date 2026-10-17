// Provider 读者棘轮（EUI-12 重采 R43 新增）。
//
// 重采时抓到一条形状很新的谎：`di_providers.dart` 里 `notebookAccessorProvider` 的注释写着
// 「正式装配由 app 层 override 注入真实 NotebookAccessorImpl」——全仓没有任何 override、
// 也没有任何人 watch 它，于是它恒落 `_EmptyNotebookAccessor`。**注释描述的是装配意图，
// 而装配从来没发生**，这类话没有任何门禁看得到（§4 第 1 条的另一面：不是读不出来答成没有，
// 是没接上却写成接上了）。
//
// 判据（窄，只紧不松）：`lib/**` 里每个 `final xProvider = ...` 都必须至少被
// lib 或 test 的**别的行**引用一次。今天唯一的违规进具名基线，基线本身有上限——
// 新增一个没人读的 provider 当场红；把已有那格真的接上后，基线里那行也必须删掉
// （反向锁：基线不许变成没人管的存档区）。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 今天已知「没人读」的 provider —— 具名基线，**只许变短不许变长**。
const List<String> _baseline = <String>['notebookAccessorProvider'];

final RegExp _declaration = RegExp(r'^\s*final\s+(\w*Provider\w*)\s*=');

/// 抽取一个源文件里声明的 provider 名（`final xProvider = Provider...`）。
List<String> providersDeclaredIn(String source) {
  final out = <String>[];
  for (final line in source.split('\n')) {
    // `case final m` 会把 null 也绑进来（变量模式恒匹配），所以这里用显式判空：
    // 换成 `case final RegExpMatch m` 才有类型收窄的效果。
    final name = _declaration.firstMatch(line)?.group(1);
    if (name != null) out.add(name);
  }
  return out;
}

/// 注释行不算读者。这一格不是洁癖：`di_providers.dart` 与本文件的注释里都**写着**
/// `notebookAccessorProvider` 这个名字（正在解释它没人读），按整行匹配就会把它算成
/// 「有人读」⇒ 基线反向锁假红（第一次跑就是这样红的）。跨全文源扫匹到注释、匹到别处同名，
/// 是 trap 53 的复发形状。
bool isCodeLine(String line) {
  final t = line.trimLeft();
  return !(t.startsWith('//') || t.startsWith('/*') || t.startsWith('*'));
}

/// 名字 [name] 是否出现在这些行里（按整词匹配，避免 `fooProvider2` 被算成 `fooProvider` 的读者）。
bool referencesProvider(String name, List<String> lines) {
  final pattern = RegExp('\\b$name\\b');
  return lines.any((line) => pattern.hasMatch(line));
}

void main() {
  /// (文件, 行号, 文本) 三元组——引用判定要能认出「这就是那行声明」。
  /// 每个文件只读一次（早前的写法在推导式里重复 readAsLinesSync，会退化成 O(行数×文件读)）。
  ///
  /// **本文件自己不算读者**：基线常量 `_baseline` 里就写着 `notebookAccessorProvider`
  /// 这串字面量，不排掉的话「基线只许变短」那条反向锁会假红（第一次跑正是这样——
  /// 扫描型门禁被自己扫到，trap 56）。排除范围只有这一个文件，不影响任何真实引用。
  List<(String, int, String)> readAllLines() {
    final out = <(String, int, String)>[];
    for (final dir in ['lib', 'test']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('provider_reader_ratchet_test')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          out.add((entity.path, i, lines[i]));
        }
      }
    }
    return out;
  }

  // 只读一遍盘：两条用例共用同一份行集（main 体内不能声明 getter，所以用闭包缓存）。
  List<(String, int, String)>? cachedLines;
  List<(String, int, String)> lines() => cachedLines ??= readAllLines();

  /// 每个 provider 的声明位置集合（`path::line`）。
  Map<String, Set<String>> declarations() {
    final byName = <String, Set<String>>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final m = _declaration.firstMatch(lines[i]);
        if (m == null) continue;
        byName
            .putIfAbsent(m.group(1)!, () => <String>{})
            .add('${entity.path}::$i');
      }
    }
    return byName;
  }

  test('分母下限：扫到的 provider 数与扫过的行数都不许塌掉', () {
    final declared = declarations();
    expect(
      declared.length,
      greaterThanOrEqualTo(11),
      reason:
          '实测 lib/ 里声明了 11 个 `final *Provider`；读出个位数以下说明抽取正则失效——'
          '那时下一条判据会「空集通过」（TE-TST-04 同族）',
    );
    expect(
      lines().length,
      greaterThanOrEqualTo(20000),
      reason:
          '实测 lib + test 的 dart 行数近四万（39881）；塌到两万以下说明扫描根错了——'
          '那时「没人读」的集合会凭空变空',
    );
  });

  test('判据：除了具名基线，每个 provider 都得有人读', () {
    final declared = declarations();
    final violations = <String>[];
    final nowClean = <String>[];
    for (final entry in declared.entries) {
      final name = entry.key;
      final hasReader = lines().any((l) {
        // 声明行自己不算读者——这是这条判据唯一真正要小心的地方。
        if (entry.value.contains('${l.$1}::${l.$2}')) return false;
        // 注释里提到它也不算读者（见 isCodeLine 的理由：本仓的注释正在解释它没人读）。
        if (!isCodeLine(l.$3)) return false;
        return referencesProvider(name, [l.$3]);
      });
      if (!hasReader && !_baseline.contains(name)) {
        violations.add('$name（声明于 ${entry.value.join(', ')}）没有任何引用方');
      }
      if (hasReader && _baseline.contains(name)) nowClean.add(name);
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
    expect(
      nowClean,
      isEmpty,
      reason:
          '${nowClean.join(', ')} 已经有人读了 ⇒ 基线里那行必须删掉；'
          '留着等于给这条棘轮开后门',
    );
    expect(
      _baseline.length,
      lessThanOrEqualTo(1),
      reason: '基线只许变短（今天 1 格）⇒ 变长这一步必须先在台账里过一遍理由',
    );
  });

  test('判据自证：整词匹配、声明行与注释行都不算读者、五种形状各判对', () {
    // ① `fooProvider2` 不算 `fooProvider` 的读者（整词边界）。
    expect(
      referencesProvider('fooProvider', ['  final a = fooProvider2;']),
      isFalse,
    );
    // ② 真读了就算数。
    expect(
      referencesProvider('fooProvider', ['  ref.watch(fooProvider);']),
      isTrue,
    );
    // ③ 抽声明：只认 `final X = ...`，注释里的不算。
    expect(
      providersDeclaredIn(
        'final barProvider = Provider<int>((r) => 1);\n'
        '// final commentedProvider = x\n  final other = 2;',
      ),
      <String>['barProvider'],
    );
    // ④ 注释行不算读者——本仓的注释里正写着 `notebookAccessorProvider`，
    //    少了这一半，那条「基线只许变短」的反向锁会假红（第一次跑就是这样）。
    expect(
      isCodeLine('/// 正式装配由 app 层 override 注入真实 NotebookAccessorImpl。'),
      isFalse,
    );
    expect(isCodeLine('  // 见 notebookAccessorProvider 的说明'), isFalse);
    expect(isCodeLine('  ref.watch(notebookAccessorProvider);'), isTrue);
    // ⑤ 基线里没有第二个名字的位置：加一格就会被上一条用例的长度上限抓住。
    expect(_baseline, <String>['notebookAccessorProvider']);
  });
}
