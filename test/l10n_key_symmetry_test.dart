// l10n 对称门禁（2026-10-03 新增）。
//
// 锁三件事：
//   0) 两份 arb 都能按 JSON 解析（防止手工增补漏逗号把整份文件写坏）。
//   A) zh / en 顶层键集合必须**完全相等**。两侧手工补键最容易漏一边，运行
//      时表现为 en 下 MissingResourceException，或中文兜底串漏到英文界面。
//   B) lib/ 里按仓库兜底写法（`AppLocalizations.of(context)?.x ?? '中文'`、
//      `_l10nSafe?.x ?? '中文'`）引用的成员名 x 必须存在于 arb——防「代码先
//      引用、arb 忘补」漂在评审之外。
//
// B 的已知局限是**漏报不误报**，因此不会随机变红：
//   - 只认稳定接收者写法：AppLocalizations.of(...) / _l10nSafe / l10n /
//     l10n0 / _l，其它间接形式（跨行取成员等）不检查；
//   - 只扫含 `AppLocalizations` 的文件，跳过生成目录 lib/l10n/ 与注释行；
//   - 生成类自带的非消息成员（localeName；函数型字段的 call）走白名单。
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

void main() {
  final zhArb = readArb(_zhArbPath);
  final enArb = readArb(_enArbPath);
  final zhKeys = arbKeys(zhArb);
  final enKeys = arbKeys(enArb);

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
    final keys = zhKeys.union(enKeys);
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !relPath(f.path).startsWith('lib/l10n/'))
        .toList();

    final offenders = <String>[];
    for (final file in files) {
      final path = relPath(file.path);
      final src = file.readAsStringSync();
      if (!src.contains('AppLocalizations')) continue;
      final lines = const LineSplitter().convert(src);
      for (var i = 0; i < lines.length; i++) {
        if (isCommentLine(lines[i])) continue;
        for (final m in _refRe.allMatches(lines[i])) {
          final name = m.group(1)!;
          if (keys.contains(name) || _nonKeyMembers.contains(name)) continue;
          offenders.add('$path:${i + 1} 引用了 arb 不存在的键 $name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '在两份 arb 同时补键，或改用既有的键：\n${offenders.join('\n')}',
    );
  });

  test('门禁C：zh 兜底串与 arb 逐字一致（防漂移）', () {
    // 审计 2026-10-09：25 处兜底串与 zh arb 漂移（术语改名/截断/语义缺失
    // 后只改了 arb 没改兜底）。l10n 未注入的路径（测试/深链/局部 rebuild）
    // 会露出旧文案。本门禁锁「兜底 == zh arb 值」。
    final zhValues = <String, String>{
      for (final e in zhArb.entries)
        if (!e.key.startsWith('@') && e.value is String)
          e.key: e.value as String,
    };
    final fallbackRe = RegExp(
      r"([A-Za-z_][A-Za-z0-9_]*)\s*\?\?\s*'((?:[^'\\]|\\.)*)'",
    );
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !relPath(f.path).startsWith('lib/l10n/'))
        .toList();

    final offenders = <String>[];
    for (final file in files) {
      final path = relPath(file.path);
      final src = file.readAsStringSync();
      final lines = const LineSplitter().convert(src);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isCommentLine(line)) continue;
        for (final m in fallbackRe.allMatches(line)) {
          final key = m.group(1)!;
          final fb = m.group(2)!;
          final want = zhValues[key];
          if (want == null) continue;
          // 含占位符的键兜底写法是 Dart 插值（$x），形态不同，跳过；
          // 带 $ 的兜底（含转义）同样跳过——只锁纯文本兜底。
          if (want.contains('{') || fb.contains(r'$')) continue;
          if (fb != want) {
            offenders.add('$path:${i + 1} $key 兜底与 arb 不一致');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '兜底串必须与 app_zh.arb 逐字一致（l10n 未注入时露出）：\n'
          '${offenders.join('\n')}',
    );
  });
}
