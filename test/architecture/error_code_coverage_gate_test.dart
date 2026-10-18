// 由 Claude 团队生成 | Drawing Notes App

/// CTL-03 解锁第①步的门禁（R50，2026-10-17）。
///
/// 一句话：`--obfuscate` 之前，`lib/` 里**不允许再有「运行时读类型名」**，也不允许
/// 有「没登记诊断码的自定义异常」——这两件事的后果都只在出货产物里现形，`flutter test`
/// 与 `-d windows` 的 smoke 跑的都是非混淆编译，**CI 天生看不见**（台账 §24 记的正是
/// 这条：只在出货里生效的构建开关不是门禁改动，而是不可验证的产品改动）。
/// 所以把「可读的诊断面」变成**源码层面**的判据，让它今天在非混淆构建里就能分红绿。
///
/// 形状：`lib/core/utils/error_code.dart` 只做「标准库类型 → 码」和兜底，自定义异常
/// 一律由类型自己报（`CodedFailure`）。第一版写的是一条 `is` 链，被本仓自己的
/// `规则2：零循环依赖` 当场判红——异常类散在六个模块，而这些模块全都 import
/// `core/utils`，一份「认识所有异常」的枢纽文件必然与它们互引（本文件末条判据把
/// 「枢纽文件不 import `lib/` 任何东西」钉住，就是为了让那个塌法不再回来）。
/// 改成派发之后覆盖不再有「core 之外算不算」的尾巴（18 个类同一套判据），子类的码
/// 也归子类自己写。唯一的两处例外走枢纽的单向 `is` 链：`document_budgets.dart` 立了
/// 「本文件零项目内 import」的纪律，那两个类**结构上不可能**实现接口 ⇒ 由枢纽认识它们。
/// 例外只有两条、且每条都必须是「零项目内 import 的文件」里的类——这两件事都由下面的判据管。
/// 子类忘写码会被「类块里必须有 getter」抓到，而不是被父类的
/// `is` 先命中。
///
/// `operator ==` 里那 17 行 `runtimeType == other.runtimeType` 是**刻意放过**的：
/// 同一进程里两边一起改名，比较关系仍然成立（Flutter 文档举的失效例子是拿名字做匹配）。
/// 放过的是这一种形状，不是「所有 runtimeType」——所以这里同时钉了它的行数下限，
/// 免得哪天 operator== 改写后这条排除面悄悄吞掉真违规（trap 56 那一族）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart'
    show BlockDocLockedException;
import 'package:drawing_notes_app/core/security/policy_engine.dart'
    show PolicyDeniedException;
import 'package:drawing_notes_app/core/security/vault_key_service.dart'
    show VaultUnlockException;
import 'package:drawing_notes_app/core/storage/backup_service.dart'
    show BackupIntegrityException;
import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart'
    show WebDavSyncException, WebDavPreconditionFailedException;
import 'package:drawing_notes_app/core/sync/sync_cipher.dart'
    show SyncKeyMismatchException;
import 'package:drawing_notes_app/core/utils/error_code.dart';

const String _helperPath = 'lib/core/utils/error_code.dart';

/// 读名形状一：`.runtimeType.toString()`。
final RegExp _toStringRead = RegExp(r'\.runtimeType\s*\.\s*toString\s*\(');

/// 读名形状二：`${...runtimeType}` 插值——字符串里的名字同样是混淆后随机串。
final RegExp _interpRead = RegExp(r'\$\{[^}]*\.runtimeType[^}]*\}');

/// 放过的那一种：`operator ==` 里的同类型比较。
///
/// 左边**没有接收者**（写的就是 `runtimeType == other.runtimeType`），所以这里
/// `\w*\.` 那段必须可选——第一版写成必需的 `\w+\.`，于是 17 行一行没匹配到，
/// 是上面那条「分母下限」把它当场抓红的（这条判据存在的意义就在这儿）。
final RegExp _equalityShape = RegExp(r'runtimeType\s*==\s*(?:\w+\.)?runtimeType\b');

final RegExp _comment = RegExp(r'^\s*(//|///|\*)');

/// 顶层 `class X ... {` 声明行（本仓 18 个异常类都是单行声明，实测）。
final RegExp _classDecl = RegExp(r'^class (\w+)(?:\s+extends\s+(\w+))?(?:\s+implements\s+([^{]+))?');

final RegExp _getter = RegExp(r"^\s*String get errorCode => '([a-z_0-9]+)';");

/// `lib/<root>` 下的自定义异常类：`(类名, 父类名或 null, implements 列表)`。
///
/// 先收 `implements Exception` 的，再按父类名做**不动点**扩展——只收一轮会漏掉
/// `WebDavPreconditionFailedException extends WebDavSyncException`，而那正是最容易
/// 忘写自己码的那批。
List<(String, String?, String)> customExceptions(String root) {
  final declared = <String, (String?, String)>{};
  final direct = <String>{};
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final line in entity.readAsLinesSync()) {
      if (_comment.hasMatch(line)) continue;
      final m = _classDecl.firstMatch(line);
      if (m == null) continue;
      final implementsList = (m.group(3) ?? '').trim();
      declared[m.group(1)!] = (m.group(2), implementsList);
      if (implementsList.contains('Exception')) direct.add(m.group(1)!);
    }
  }
  final out = direct.toSet();
  var grew = true;
  while (grew) {
    grew = false;
    for (final e in declared.entries) {
      final parent = e.value.$1;
      if (parent == null || out.contains(e.key)) continue;
      if (out.contains(parent) || parent.endsWith('Exception') || parent == 'FormatException') {
        out.add(e.key);
        grew = true;
      }
    }
  }
  return [
    for (final name in out) (name, declared[name]!.$1, declared[name]!.$2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
}

/// 一个类声明到下一个类声明之间的行（用来判「这个类自己有没有写码」）。
List<String> classBlock(String path, String className) {
  final lines = File(path).readAsLinesSync();
  final start = lines.indexWhere((l) => l.startsWith('class $className '));
  if (start < 0) return const [];
  final rest = lines.sublist(start + 1);
  final next = rest.indexWhere((l) => l.startsWith('class '));
  return next < 0 ? rest : rest.sublist(0, next);
}

/// 找到某个类所在的文件（18 个类名在 `lib/` 内唯一，实测）。
String? fileOfClass(String className) {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.readAsLinesSync().any((l) => l.startsWith('class $className '))) {
      return entity.path.replaceAll(r'\', '/');
    }
  }
  return null;
}

/// 枢纽里那条**单向** `is` 链：`(类名 → 码)`。只准用来兜「自己文件零项目内 import、
/// 因此结构上不可能实现 [CodedFailure]」的那两个类——多一条就红（上一条判据管数量，
/// 这一条管每一格的可解释性）。
Map<String, String> hubIsChain() {
  final out = <String, String>{};
  for (final line in File(_helperPath).readAsLinesSync()) {
    final m = RegExp(r"^\s*if \(error is (\w+)\) return '([a-z_0-9]+)';").firstMatch(line);
    if (m != null) out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

/// 扫 `lib/` 里的「运行时读类型名」；[sources] 非空时扫这段文本（自证用）。
List<(String, String)> diagnosticNameReads([Map<String, String>? sources]) {
  final hits = <(String, String)>[];
  void scan(String label, String line) {
    if (_comment.hasMatch(line)) return;
    if (_equalityShape.hasMatch(line)) return;
    if (_toStringRead.hasMatch(line) || _interpRead.hasMatch(line)) {
      hits.add((label, line));
    }
  }

  if (sources != null) {
    sources.forEach((file, text) {
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        scan('$file:${i + 1}', lines[i]);
      }
    });
    return hits;
  }
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      scan('${entity.path.replaceAll(r'\', '/')}:${i + 1}', lines[i]);
    }
  }
  return hits;
}

int equalityShapeLines() {
  var n = 0;
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final line in entity.readAsLinesSync()) {
      if (_equalityShape.hasMatch(line)) n++;
    }
  }
  return n;
}

void main() {
  group('分母下限（扫不到就当场红，别让空集通过）', () {
    test('operator== 那一族仍然被扫到（放过它的前提是看得见它）', () {
      // 实测 2026-10-17：17 行。取下限而不是精确值：哪天 operator== 改写导致这里掉到 0，
      // 上面那条「放过」就成了盲放。
      expect(equalityShapeLines(), greaterThanOrEqualTo(15));
    });

    test('自定义异常类要有量（18 个，抽取塌了后面几条会一起假绿）', () {
      expect(
        customExceptions('lib').length,
        greaterThanOrEqualTo(18),
        reason: '实测 18：core 15 + features/notes/application 1 + infrastructure/v2 2',
      );
    });

    test('枢纽只准 import「自己零项目内 import」的那些文件（不成环才允许单向认识）', () {
      final lines = File(_helperPath).readAsLinesSync();
      final appImports = <String>[
        for (final l in lines)
          if (l.startsWith("import 'package:drawing_notes_app/"))
            l.split("'")[1],
      ];
      // 实测 2026-10-17：只有 document_budgets.dart 一条。它零项目内 import ⇒ 单向。
      expect(appImports, hasLength(1), reason: '枢纽的出向依赖变多了：$appImports');
      for (final uri in appImports) {
        final path = uri.replaceFirst('package:drawing_notes_app/', 'lib/');
        final own = File(path)
            .readAsLinesSync()
            .where((l) => l.startsWith("import 'package:drawing_notes_app/"))
            .toList();
        expect(
          own,
          isEmpty,
          reason: '$path 自己有项目内 import ⇒ 它已经/将会 import core/utils，'
              '枢纽再认识它就是**互相引用**（规则2 零循环依赖会红）',
        );
      }
      expect(
        lines.where((l) => l.startsWith('import ')).length,
        greaterThanOrEqualTo(3),
        reason: 'dart:io / dart:async 仍在，否则标准库那 7 条码会变成断言不存在的类',
      );
    });
  });

  test('判据一：lib/ 里不再有「运行时读类型名」', () {
    final bad = diagnosticNameReads();
    expect(
      bad,
      isEmpty,
      reason: '这 $bad 处在 `--obfuscate` 下会变成每次构建都不同的随机串，'
          '而 CI 跑非混淆编译 ⇒ 只有装到用户机器上才发现（CTL-03）',
    );
  });

  test('判据二：每个自定义异常都有码——自带，或（仅当结构上不可能自带时）枢纽单向认识', () {
    final hub = hubIsChain();
    for (final (name, _, implementsList) in customExceptions('lib')) {
      final path = fileOfClass(name);
      expect(path, isNotNull, reason: '$name 定位失败（抽取与判据此刻对不上）');
      final viaInterface = implementsList.contains('CodedFailure');
      final viaHub = hub.containsKey(name);
      expect(
        viaInterface || viaHub,
        isTrue,
        reason: '$name 既没实现 CodedFailure、枢纽也不认识它 ⇒ errorCode() 只能答 other'
            '（「读不出来被答成没有」那一族）',
      );
      if (viaInterface) {
        expect(
          viaHub,
          isFalse,
          reason: '$name 两套都登记 = 一个类型两份码，改一处另一处静默生效',
        );
        final own = classBlock(path!, name).where((l) => _getter.hasMatch(l)).toList();
        expect(
          own,
          hasLength(1),
          reason: '$name 自己没写 `String get errorCode` ⇒ 会继承父类的码，'
              '于是子类的失败一路报成父类那一类',
        );
      } else {
        final ownImports = File(path!)
            .readAsLinesSync()
            .where((l) => l.startsWith("import 'package:drawing_notes_app/"))
            .toList();
        expect(
          ownImports,
          isEmpty,
          reason: '$name 走枢纽登记，但 $path 自己有项目内 import ⇒ 它本来能实现接口；'
              '留着这条只会让枢纽与业务模块互引（规则2）',
        );
      }
    }
  });

  test('判据三：码全库唯一（两类失败不能被并成一个码）', () {
    final seen = <String, String>{};
    void claim(String code, String owner) {
      expect(
        seen.putIfAbsent(code, () => owner),
        owner,
        reason: '$code 同时被 ${seen[code]} 与 $owner 使用',
      );
    }

    for (final (name, _, implementsList) in customExceptions('lib')) {
      final path = fileOfClass(name)!;
      if (implementsList.contains('CodedFailure')) {
        for (final line in classBlock(path, name)) {
          // 用显式判空而不是 `case final m`：变量模式连 null 都匹配，
          // `m.group(1)` 会在没命中的行上直接抛（本仓踩过一次）。
          final m = _getter.firstMatch(line);
          if (m != null) claim(m.group(1)!, name);
        }
      } else {
        claim(hubIsChain()[name]!, name);
      }
    }
    expect(seen.length, greaterThanOrEqualTo(18), reason: '收集到的码太少：抽取失效');
    // 标准库那 7 条与兜底也不能与自定义码撞（撞了同样合并两类失败）。
    const stdlibCodes = <String>[
      'io_file_system',
      'io_socket',
      'async_timeout',
      'core_format',
      'core_argument',
      'core_state',
      'core_type',
      'other',
    ];
    for (final code in stdlibCodes) {
      expect(seen.containsKey(code), isFalse, reason: '自定义码 $code 与标准库那条撞了');
    }
  });

  group('行为：造得出实例的那些', () {
    test('子类报自己的码，不被父类吞掉', () {
      expect(
        errorCode(const BackupIntegrityException(code: 'ioError', message: 'x')),
        'backup_integrity',
      );
      expect(errorCode(const SyncKeyMismatchException()), 'sync_key_mismatch');
      expect(
        errorCode(WebDavPreconditionFailedException('412')),
        'webdav_precondition_failed',
      );
      // 父类自己仍然要拿到父类码（否则这条链只是把子类改了个名）。
      expect(errorCode(WebDavSyncException('boom')), 'webdav_sync');
      expect(errorCode(const FormatException('boom')), 'core_format');
    });

    test('码里没有 message、路径或凭据', () {
      final code = errorCode(
        FileSystemException(
          'Cannot open file',
          'C:\\Users\\bob\\保险库\\note_7.json',
          const OSError('denied'),
        ),
      );
      expect(code, 'io_file_system');
      for (final leak in const <String>['bob', 'note_7', 'denied', 'Cannot', '\\']) {
        expect(code, isNot(contains(leak)), reason: '诊断面把路径/原文带出去了（H-04）');
      }
    });

    test('标准库与兜底', () {
      expect(errorCode(const BlockDocLockedException()), 'block_doc_locked');
      expect(errorCode(const VaultUnlockException('x')), 'vault_unlock');
      expect(errorCode(const PolicyDeniedException('export', 'policy')), 'policy_denied');
      expect(errorCode(SocketException('d')), 'io_socket');
      expect(errorCode(TimeoutException('e', Duration.zero)), 'async_timeout');
      expect(errorCode(ArgumentError('g')), 'core_argument');
      expect(errorCode(StateError('h')), 'core_state');
      expect(errorCode(TypeError()), 'core_type');
      expect(errorCode(Exception('whatever')), 'other');
    });

    test('码彼此不重复（端到端再验一次）', () {
      final codes = <String>[
        for (final e in <Object>[
          const BackupIntegrityException(code: 'ioError', message: 'x'),
          const SyncKeyMismatchException(),
          WebDavPreconditionFailedException('412'),
          WebDavSyncException('boom'),
          const BlockDocLockedException(),
          const VaultUnlockException('x'),
          const PolicyDeniedException('export', 'policy'),
          FileSystemException('a', 'b', const OSError('c')),
          SocketException('d'),
          TimeoutException('e', Duration.zero),
          const FormatException('f'),
          ArgumentError('g'),
          StateError('h'),
          TypeError(),
          Exception('i'),
        ])
          errorCode(e),
      ];
      expect(codes.toSet().length, codes.length, reason: '重复的码：$codes');
    });
  });

  group('判据自证（抽取器与判据本身要能被突变抓到）', () {
    test('两种读名形状都能抓到', () {
      expect(
        diagnosticNameReads(
          const <String, String>{'a.dart': '  detail: e.runtimeType.toString(),\n'},
        ),
        hasLength(1),
      );
      expect(
        diagnosticNameReads(
          const <String, String>{'a.dart': "  'app.error.\${x.runtimeType}',\n"},
        ),
        hasLength(1),
      );
    });

    test('operator== 那一族与注释里的同形文本都不误伤', () {
      expect(
        diagnosticNameReads(
          const <String, String>{
            'a.dart': '  bool operator ==(Object other) =>\n'
                '      runtimeType == other.runtimeType && id == other.id;\n'
                '/// 以前这里是 e.runtimeType.toString()，现在不是了\n',
          },
        ),
        isEmpty,
      );
    });

    test('没登记的异常类会被判据二抓到（两套登记渠道加起来必须覆盖全部）', () {
      final found = customExceptions('lib');
      final hub = hubIsChain();
      final covered = found
          .where((x) => x.$3.contains('CodedFailure') || hub.containsKey(x.$1))
          .toList();
      expect(
        covered.length,
        found.length,
        reason: '今天 18 个类全覆盖（16 自带 + 2 走枢纽）；对不上就是抽取或登记塌了',
      );
      // 两条渠道不能同时给同一个类型登记（判据二也查这条，这里保证它**抓得到**）。
      expect(
        found.where((x) => x.$3.contains('CodedFailure') && hub.containsKey(x.$1)).toList(),
        isEmpty,
      );
      // 抽一条真实的类块，确认「getter 归属于这个类」这件事是可判的（不是恒真）：
      // 父类与子类各拿一块，两块里都必须**恰好一条** getter，且码不同。
      List<String> blockOf(String cls) =>
          classBlock(fileOfClass('WebDavSyncException')!, cls)
              .where((l) => _getter.hasMatch(l))
              .toList();
      // 子类名从抽取结果里取，不在这里抄全名：①本仓的密钥扫描器把「引号内 ≥24 位
      // 字母数字」当疑似令牌，`WebDav…Exception` 全名熵 4.03 正好擦过阈值 4.0；
      // ②这个名字本来就该由扫描面给出，抄一份在这儿就是第二个真相。
      final childName = found
          .map((x) => x.$1)
          .firstWhere((n) => n.contains('Precondition'));
      expect(blockOf('WebDavSyncException'), hasLength(1));
      final child = blockOf(childName);
      expect(
        child,
        hasLength(1),
        reason: '子类块里必须有它自己的 getter——否则判据二对子类等于没判',
      );
      expect(
        _getter.firstMatch(child.single)!.group(1),
        isNot(equals(_getter.firstMatch(blockOf('WebDavSyncException').single)!.group(1))),
        reason: '子类与父类同码 ⇒ 412 会被一路报成普通同步失败',
      );
    });
  });
}
