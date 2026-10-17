// DocPage 各入口的装配门禁（R42，EUI-12 重采时抓到的真实缺口）。
//
// `DocPage.blockDocStore` 的注释（`doc_page.dart:113-115`）承诺：
// 「各入口（搜索/笔记本管理/首页）无需各自接线即可获得完整能力」。
// 但 EUI-12 重采时发现首页**新建**那条腿（`home_page_create.dart:239`）当年一个参数都没传 ⇒
// 刚建好的笔记里没有「管理密码」入口（门控 `doc_page.dart:260`），也没有反向链接面板
// （`doc_page_link_outline.dart:75/93`）。注释说的「各入口」和实际接线的入口数，从来没人对过。
//
// 所以这条门禁判的是**那句承诺本身**：每个构造 `DocPage(...)` 的地方，要么交出
// `blockDocStore`（兜底腿自己生成数据源与路由），要么显式给齐 `allDocsLoader` + `onOpenDocById`。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 取出 `DocPage(` 构造调用的实参文本（含首尾括号）；命中构造函数**声明**时返回 null。
///
/// 声明的写法是 `const DocPage({`（左括号紧跟花括号），构造点后面跟的是空白或换行——
/// 用这一条区分，不靠文件名特判。
String? _captureConstruction(String source, int openParenAt) {
  if (openParenAt + 1 >= source.length) return null;
  if (source[openParenAt + 1] == '{') return null; // 声明，不是调用
  final buffer = StringBuffer('(');
  var depth = 0;
  for (var i = openParenAt; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') depth++;
    buffer.write(ch);
    if (ch == ')') {
      depth--;
      if (depth == 0) return buffer.toString();
    }
  }
  return null; // 括号不配对 ⇒ 抽取失效，交给分母下限那条用例去红
}

/// 判定：这个构造点有没有拿到「反向链接 + 密码管理」这两项能力。
bool _wiredEnough(String args) =>
    args.contains('blockDocStore:') ||
    (args.contains('allDocsLoader:') && args.contains('onOpenDocById:'));

List<String> _scanLibForUnwiredDocPages() {
  final violations = <String>[];
  var sites = 0;
  var viaFallback = 0;
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    if (!source.contains('DocPage(')) continue;
    for (
      var i = source.indexOf('DocPage(');
      i >= 0;
      i = source.indexOf('DocPage(', i + 1)
    ) {
      final args = _captureConstruction(source, i + 'DocPage'.length);
      if (args == null) continue; // 声明
      sites++;
      if (!_wiredEnough(args)) {
        violations.add(
          '${entity.path}: 位置 $i 构造 DocPage 时既没传 blockDocStore，'
          '也没给齐 allDocsLoader + onOpenDocById',
        );
      } else if (args.contains('blockDocStore:')) {
        viaFallback++;
      }
    }
  }
  _lastScan = (sites, viaFallback);
  return violations;
}

(int sites, int viaFallback) _lastScan = (0, 0);

void main() {
  test('分母下限：扫到的构造点数与走兜底那条腿的数都不许塌掉', () {
    _scanLibForUnwiredDocPages();
    final (sites, viaFallback) = _lastScan;
    expect(
      sites,
      greaterThanOrEqualTo(8),
      reason:
          '实测 lib/ 里有 8 个 DocPage 构造点：app_shell_routes.dart:86/388/486、'
          'doc_page_link_outline.dart:134、home_page_create.dart:239、'
          'home_page_tabs.dart:281、notebook_view_page_manage.dart:169、'
          'search_page.dart:153。读出小于 8 说明抽取失效——'
          '那时下一条判据会「空集通过」（TE-TST-04 同族）',
    );
    expect(
      viaFallback,
      greaterThanOrEqualTo(1),
      reason:
          '「只交 blockDocStore 就走兜底」这一半判据必须真的被执行过，'
          '否则它塌了也没人知道',
    );
  });

  test('判据：每个 DocPage 入口都得有反向链接与密码管理能力', () {
    expect(_scanLibForUnwiredDocPages(), isEmpty);
  });

  test('判据自证：声明不算调用，三种实参形状各判对', () {
    // ① 声明必须被跳过。
    expect(
      _captureConstruction(
        '  const DocPage({\n    this.blockDocStore,\n  });',
        15,
      ),
      isNull,
    );
    // ② 只交 store ⇒ 合规。
    const withStore = 'DocPage(\n  document: doc,\n  blockDocStore: store,\n)';
    expect(_wiredEnough(_captureConstruction(withStore, 7)!), isTrue);
    // ③ 给齐显式两项 ⇒ 合规。
    const explicit =
        'DocPage(\n  allDocsLoader: load,\n  onOpenDocById: open,\n)';
    expect(_wiredEnough(_captureConstruction(explicit, 7)!), isTrue);
    // ④ 只给一项（正是 R42 修掉的那种）⇒ 必须判不合规。
    const halfWired = 'DocPage(\n  allDocsLoader: load,\n  controller: c,\n)';
    expect(_wiredEnough(_captureConstruction(halfWired, 7)!), isFalse);
    expect(_captureConstruction(halfWired, 7)!, contains('controller: c'));
  });
}
