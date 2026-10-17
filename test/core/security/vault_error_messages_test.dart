// `describeVaultError` 的两条腿都要被裁决（审计 2026-10-17，TE-TST-02 复核时挖出的弱覆盖）。
//
// 原文件只有两条用例，且**全部传 `l10n: null`** ⇒ 每一句断言走的都是 Dart 侧兜底串，
// `vaultErr*` 那 13 个 arb 键在这个文件里从没被执行过一次。后果有两层：
// ① arb 键缺失/拼错时 `??` 兜底会把事故读成绿灯（与 R20 的 N3a/N3b 同族）；
// ② 映射本身是按**中文关键词**匹配 reason 串的，措辞一漂移就会静默退到兜底句——
//    实测就撞上了一条错映射：`vault_key_service.dart:444` 抛
//    `VaultUnlockException('U 盘恢复钥匙不匹配或已损坏')`，旧顺序里 `损坏` 先命中 ⇒
//    屏幕报「PIN 错误或密钥载荷被篡改」，而用户刚输入的 PIN 是对的。
// 所以下面同时钉：真实 l10n 取值、en 不残留中文、U 盘那一支的回归锁、
// 以及每条具名分支不许静默降级成兜底。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/quick_unlock_service.dart';
import 'package:drawing_notes_app/core/security/vault_error_messages.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

Future<AppLocalizations> _loadL10n(WidgetTester tester, Locale locale) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context)!;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

/// 「异常 → 具名 arb 键」的映射表，测试与下面的分母下限共用**同一份定义**。
///
/// reason 串尽量抄**生产抛出点**的原文（不自己编——编出来的串只能证明映射函数自洽，
/// 证不了生产真会走到这一支）；两处例外已在条目里注明：`为空` 那支生产暂无抛出点，
/// 以及 `版本` 那支被 `信封` 抢先（见下面两条专门的用例）。
final List<(Object?, String Function(AppLocalizations))> _namedBranches = [
  (null, (l) => l.vaultErrUnknown),
  (VaultFileLockException(), (l) => l.vaultErrLocked),
  (VaultFilePasswordLockException(), (l) => l.vaultErrFilePassword),
  (FormatException('x'), (l) => l.vaultErrCorrupt),
  (Exception('totally unmapped'), (l) => l.vaultErrUnknown),
  (
    VaultUnlockException('保险库不存在（尚未设置密码）'),
    (l) => l.vaultErrNoVault,
  ),
  // 注明：生产侧「PIN 不能为空」走的是 `ArgumentError`，不是这两个异常类型，
  // 所以这一支今天到不了（已登记为台账观察项）。此处保留是为防将来接线时判据错。
  (VaultUnlockException('PIN 为空'), (l) => l.vaultErrEmptyPin),
  (VaultUnlockException('保险库缺少 PIN 槽位'), (l) => l.vaultErrMissingSlot),
  (VaultUnlockException('信封缺少密码槽位'), (l) => l.vaultErrMissingSlot),
  (
    VaultUnlockException('PIN 错误或密钥载荷被篡改'),
    (l) => l.vaultErrWrongPin,
  ),
  (
    // 回归锁：这一支曾被 `损坏` 抢先命中，报成「PIN 错误或密钥载荷被篡改」。
    // 抛出点见 `vault_key_service.dart:444`。
    VaultUnlockException('U 盘恢复钥匙不匹配或已损坏'),
    (l) => l.vaultErrUsbKey,
  ),
  (QuickUnlockException('PIN 错误或密钥载荷被篡改'), (l) => l.vaultErrWrongPin),
  (
    VaultFileException('文件受独立密码保护'),
    (l) => l.vaultErrFilePassword,
  ),
  (VaultFileException('不是 DNV 加密信封'), (l) => l.vaultErrNotEnvelope),
  (VaultFileException('不是 v3 密码信封'), (l) => l.vaultErrNotEnvelope),
  (VaultFileException('密钥不匹配或密文被篡改'), (l) => l.vaultErrKeyMismatch),
  // 顺序造成的现状（不是笔误）：`_mapFileReason` 里 `信封` 排在 `版本` 之前，
  // 而生产抛的原文是「不支持的信封版本 N」（vault_file_codec.dart:173），
  // 所以它实际取「不是有效的加密信封」。两句都属「这信封本端处理不了」，
  // 且不会把用户误导去重试口令 ⇒ 本轮只登记、不改文案（改文案要另一次裁决）。
  (VaultFileException('不支持的信封版本 9'), (l) => l.vaultErrNotEnvelope),
];

void main() {
  test('describeVaultError 映射锁定/密码/解锁失败为非空人话', () {
    expect(
      describeVaultError(const VaultFileLockException(), null),
      isNotEmpty,
    );
    expect(
      describeVaultError(const VaultFilePasswordLockException(), null),
      isNotEmpty,
    );
    expect(
      describeVaultError(
        const VaultUnlockException('PIN 错误或密钥载荷被篡改'),
        null,
      ),
      contains('PIN'),
    );
    expect(
      describeVaultError(
        const VaultFileException('密钥不匹配或密文被篡改'),
        null,
      ),
      isNotEmpty,
    );
    expect(describeVaultError(FormatException('x'), null), isNotEmpty);
    expect(describeVaultError(null, null), isNotEmpty);
  });

  test('未知异常不透出实现细节前缀', () {
    final msg = describeVaultError(Exception('internal secret'), null);
    expect(msg, isNot(contains('secret')));
  });

  test('分母下限：映射表条目数不得塌空（空集即通过那一族）', () {
    expect(
      _namedBranches.length,
      greaterThanOrEqualTo(15),
      reason: '13 个 vaultErr* 键里至少要有 15 条具名分支在册；'
          '数量掉到 0 通常是表被误删，而不是映射都测过了',
    );
  });

  testWidgets('真实 l10n 那一半：每条具名分支都取到自己那个 arb 值', (tester) async {
    final zh = await _loadL10n(tester, const Locale('zh'));
    for (final (error, pick) in _namedBranches) {
      expect(
        describeVaultError(error, zh),
        pick(zh),
        reason: '$error 应取 arb 值，而不是兜底串',
      );
    }
    // 「具名分支不许与通用兜底同形」不能写成 `if (expected != unknown) expect(...)`
    // ——那是恒真断言（本仓栽过多次）。改成数**与兜底同形的条目有几条**：
    // 只允许那 2 条本来就以兜底为正确答案的（null 与完全未匹配的 Exception）。
    // 若哪天有人把某个 vaultErr* 的文案改成「发生未知错误」，这里立刻红。
    final sameAsFallback = _namedBranches
        .where((e) => e.$2(zh) == zh.vaultErrUnknown)
        .toList();
    expect(
      sameAsFallback,
      hasLength(2),
      reason: '15 条具名分支里只许 2 条与通用兜底同形；多一条说明那条分支在界面上已被抹平',
    );
  });

  testWidgets('en 那一半：全部具名分支都取到英文，且不得残留中文', (tester) async {
    final en = await _loadL10n(tester, const Locale('en'));
    for (final (error, pick) in _namedBranches) {
      final shown = describeVaultError(error, en);
      expect(shown, pick(en), reason: '$error 在 en 下应取到对应英文键');
      // reason 串本身是中文（异常里带的），但它**不许**被透出到界面。
      expect(
        shown,
        isNot(contains(RegExp(r'[一-鿿]'))),
        reason: '展示层泄漏中文 = 走了兜底串或直接把 e.reason 拼了出来',
      );
    }
  });

  testWidgets('U 盘那一支的回归锁：PIN 没错时不许报「PIN 错误」', (tester) async {
    final zh = await _loadL10n(tester, const Locale('zh'));
    const usbFailure = VaultUnlockException('U 盘恢复钥匙不匹配或已损坏');
    expect(describeVaultError(usbFailure, zh), zh.vaultErrUsbKey);
    expect(
      describeVaultError(usbFailure, zh),
      isNot(zh.vaultErrWrongPin),
      reason: '旧顺序里 `损坏` 先命中 ⇒ 把 U 盘问题报成 PIN 错误，'
          '会把用户推向「反复重试开屏密码」这条错的恢复路径',
    );
  });

  testWidgets('`版本` 那支的键是好的，只是生产串被 `信封` 抢先', (tester) async {
    final zh = await _loadL10n(tester, const Locale('zh'));
    // 不带「信封」二字的 reason 才能走到 `版本` 判据——这条证明 arb 键与函数都正确，
    // 上面那条则记录生产现状。两句合起来才说得清「哪个是设计、哪个是顺序造成的」。
    expect(
      describeVaultError(const VaultFileException('不支持的版本 9'), zh),
      zh.vaultErrUnsupportedVersion,
    );
  });

  testWidgets('措辞漂移不许静默降级：兜底句只留给真正无匹配的 reason', (tester) async {
    final zh = await _loadL10n(tester, const Locale('zh'));
    // 生产里真会抛的两条「无关键词」reason ⇒ 落在兜底，且这条落点要看得见。
    expect(
      describeVaultError(const QuickUnlockException('系统验证未通过'), zh),
      zh.vaultErrUnlockFail,
    );
    expect(
      describeVaultError(const QuickUnlockException('当前设备不支持系统验证'), zh),
      zh.vaultErrUnlockFail,
    );
    // 反向锁：带关键词的绝不该掉进兜底（掉了就说明判据被改坏了）。
    expect(
      describeVaultError(
        const VaultUnlockException('保险库缺少 PIN 槽位'),
        zh,
      ),
      isNot(zh.vaultErrUnlockFail),
    );
  });
}
