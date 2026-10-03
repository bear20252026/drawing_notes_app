/// P2 回归锁（审计 2026-10-04）：笔记本设密路径的开屏密码同码探测口径。
///
/// 缺陷形状：`notebook_view_page_imports.dart` 的 `_enablePasswordEncryption`
/// 用 bool 型 `AppLockService.matchesAppLockPin`（底层走 `verify`）——
/// ①每设一次独立密码就给开屏锁白记一次「猜错」，累计即触发防爆破冷却；
/// ②冷却期内 verify 恒 false ⇒ 探测被静默放行同码，两层保护边界消失。
/// home/doc/reset 三处本轮已统一为三态 `probeMatchesAppLockPin`（只读比对、
/// 不计次；null = 判定不了 ⇒ fail-closed 拒绝设密并提示稍后重试），本锁
/// 钉住笔记本这第四处，防止回退。
///
/// 静态部分用 [maskDartLexically] 遮蔽注释与字符串（口径同
/// `test/l10n_key_symmetry_test.dart` 的「注释行不算引用」），只裁决代码。
/// 行为部分注入轻量 KDF + 同 isolate 直派生（口径同
/// `test/password_input_hardening_test.dart`），不新增真 KDF 慢用例。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';

import 'helpers/dart_lexical_mask.dart';

const _notebookImportsPath =
    'lib/features/notes/presentation/notebook_view_page_imports.dart';

/// 遮蔽后的源码里按 [definition] 匹配方法定义并取其方法体（含首尾花括号）。
/// 用「定义式」正则而非裸方法名：`_setPassword` 里也调用同名方法，按首次
/// 出现取会把调用点之后的下一段代码当成方法体。
String _methodBody(String maskedSrc, RegExp definition) {
  final match = definition.firstMatch(maskedSrc);
  expect(match, isNotNull, reason: '找不到方法定义 ${definition.pattern}');
  final open = maskedSrc.indexOf('{', match!.start);
  var depth = 0;
  for (var i = open; i < maskedSrc.length; i++) {
    if (maskedSrc[i] == '{') {
      depth++;
    } else if (maskedSrc[i] == '}') {
      depth--;
      if (depth == 0) return maskedSrc.substring(open, i + 1);
    }
  }
  return maskedSrc.substring(open);
}

void main() {
  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  group('笔记本设密路径：探测口径静态锁', () {
    // 顶层读文件与 `test/l10n_key_symmetry_test.dart` 同模式（flutter test
    // 的工作目录恒为包根）；文件缺失时整个套件红——比静默跳过诚实。
    final masked = maskDartLexically(
      File(_notebookImportsPath).readAsStringSync(),
    );

    test('设密走三态 probe，且冷却期（null）有 fail-closed 分支', () {
      final body = _methodBody(
        masked,
        RegExp(r'_enablePasswordEncryption\(\)\s*(async\s*)?\{'),
      );
      expect(
        body,
        contains('AppLockService.probeMatchesAppLockPin'),
        reason: '笔记本设密须与 home/doc/reset 同口径：只读三态探测',
      );
      // 三态必须三分：同码拒绝与「判定不了」拒绝各一条。bool 语义下二者合一
      // ⇒ 冷却期静默放行同码（本项缺陷的第二半）。局部变量名与三处姊妹实现
      // 一致（home_page_password / doc_page_password 同写法）。
      expect(body, contains('sameAsLock == true'));
      expect(
        body,
        contains('sameAsLock == null'),
        reason: '「判定不了」必须有独立分支',
      );
      expect(
        body,
        contains('lockTemporarilyLocked'),
        reason: '冷却期须提示稍后重试并拒绝设密',
      );
    });

    test('笔记本设密路径不再调用 bool 型 matchesAppLockPin', () {
      expect(
        masked,
        isNot(contains('AppLockService.matchesAppLockPin')),
        reason: 'bool 入口会消耗防爆破计数并在冷却期静默放行同码',
      );
    });

    test('全仓 lib/ 已无 bool 型同码探测调用（四入口口径统一）', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        // 粗筛（含注释/字符串）后必须用遮蔽文本裁决，注释里的历史说明不算调用。
        if (!src.contains('AppLockService.matchesAppLockPin')) continue;
        if (maskDartLexically(src)
            .contains('AppLockService.matchesAppLockPin')) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '新代码一律用 probeMatchesAppLockPin 并处理 null 分支：$offenders',
      );
    });
  });

  group('笔记本设密路径：探测行为锁（防爆破计数 / 冷却期）', () {
    test('静态探测（笔记本路径调用的入口）反复错码零计次', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.load();
      await service.setPin('9527');

      for (var i = 0; i < 12; i++) {
        expect(await AppLockService.probeMatchesAppLockPin('000$i'), isFalse);
      }

      final after = AppLockService();
      await after.load();
      expect(
        after.failedAttempts,
        0,
        reason: '旧实现走 verify：12 次设密探测=12 次「开屏密码猜错」',
      );
      expect(after.isLockedOut, isFalse);
      // 惩罚通道未被绕过：真正的登录校验照常计次。
      expect(await service.verify('0000'), isFalse);
      expect((await _reload()).failedAttempts, 1);
      expect(await service.verify('9527'), isTrue);
    });

    test('冷却期：探测返回 null（不是 false）——笔记本路径据此拒绝设密', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AppLockService();
      await service.load();
      await service.setPin('9527');
      for (var i = 0; i < 10; i++) {
        expect(await service.verify('wrong-$i'), isFalse);
      }
      expect(service.isLockedOut, isTrue);

      expect(
        await AppLockService.probeMatchesAppLockPin('9527'),
        isNull,
        reason: '三态：null = 判定不了，收集方须拒绝本次设密',
      );
      // 对照旧入口：bool 语义下「冷却期判不了」与「确实不同码」同为 false，
      // 同码会被静默放行——这正是本项缺陷的第二半。
      expect(await AppLockService.matchesAppLockPin('9527'), isFalse);
    });
  });
}

Future<AppLockService> _reload() async {
  final fresh = AppLockService();
  await fresh.load();
  return fresh;
}
