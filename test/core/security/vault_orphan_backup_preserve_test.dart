// STO-001（第四轮全仓审计 2026-10-15）的**可观测半边**。
//
// 实测链路（三条都在代码里）：
//  · `vault_key_service.dart` 的 `isConfigured()` 只看**主文件**；
//  · `_readDoc()` 却有一条 `.bak` 回退腿（rename 期崩溃的生存设计）；
//  · `app_lock_gate.dart` 的 `_unlockVault` 按 `isConfigured()` 分叉，`else` 那一支
//    直接 `vault.initialize(pin)` —— **生成一支全新随机主密钥**。
// ⇒ 主文件被删 / 被杀软隔走 / 崩溃后只剩 `.bak` 的用户，PIN 输入框看起来和
//   「从没设过密码」完全一样。补建成功、界面正常、什么错都不报；而那支新主密钥
//   打不开任何既有密文。更狠的是 `.bak`（旧主密钥包装的最后一份副本）会在
//   **下一次**任意保险库写入时被当时的主文件覆盖掉——覆盖之后就再也没有回头路。
//
// 本批按 §5 的口径只做**可观测 + 不留销毁**那半边：补建之前先把 `.bak` **复制**成
// 保留件（复制不移动——移动会顺手拆掉 `_readDoc` 那条唯一还能解旧内容的回退腿），
// 前后各落一条审计，并把这件事说给用户听。「盘上有旧备份就**拒绝**自动补建」已由
// 业主 2026-10-16 点名（取「先试旧那一世，解不开再要显式确认」那一档），门组件那
// 半边钉在 `app_lock_gate_test.dart` 的 STO-001 组，本文件只钉服务层的判据与副本。
//
// 突变自证：
//  T1 检测到却**不保留**（去掉 `_preserveOrphanBackup()` 那一次调用）
//     ⇒ 第 1、2 条红（实测 `+2 -2`）。第 2 条才是主证据：销毁链要跑满「紧接着的第二
//       次保险库写入」才算证死——只证「当场还有一份」不够，那一份被下一次写入盖掉
//       就等于没有。
//  T2 判据只看主文件在不在（`.bak` 不参与，即改动前的形状）
//     ⇒ 第 1、2 条红（`+2 -2`，与 T1 同落点：检测与保留本就是同一后果的两环）。
//  T3 保留改成**移动**而非复制
//     ⇒ 恰好第 1 条红（`+3 -1`）：`.bak` 原位没了，`_readDoc` 那条唯一还能解旧内容的
//       回退腿被顺手拆走——这正说明「保住副本」与「别拆回退腿」是两件不同的事。
//  T4 判据降级成「有个 `.bak` 就算旧库」（不看内容、不试解析）
//     ⇒ 恰好第 4 条红（`+3 -1`）：坏文件也照留保留件、照报「检测到旧保险库备份」。
//  T5 判据恒真（不管盘上有什么都当旧库）
//     ⇒ 第 3、4 条反向锁一起红（`+2 -2`）——这两条钉的就是「别把门禁练成哭墙」。
// 反向锁（第 3、4 条用例）：正常首建、以及「`.bak` 是坏 JSON」都**不许**产生保留件、
// 不许落异常审计、不许弹提示——否则每次装新机都白留一堆文件、还给用户报障；
// 而「坏备份拖住补建」会把降级进入的入口也一起锁死。
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/vault_key_service.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tmp;
  late File vaultFile;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sto001_orphan_');
    vaultFile = File('${tmp.path}${Platform.pathSeparator}vault.key.json');
    AuditLogger.clear();
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tmp);
  });

  VaultKeyService newService() => VaultKeyService(
    vaultFileResolver: () async => vaultFile,
    iterations: 2000, // 旧数据兜底（生产 600k）
    newSlotKdf: KdfParams.testLight, // 测试提速（生产 Argon2id 64MiB t2 p2）
  );

  /// 该文件所在线程取出的保险库 JSON（不存在返回 null）。
  Map<String, dynamic>? readDoc(String path) {
    final f = File(path);
    if (!f.existsSync()) return null;
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }

  /// 「这是哪一世的主密钥」的指纹：PIN 槽里那段被包裹的主密钥密文。
  /// 每次 `initialize` 都用新盐重新包裹新随机主密钥，所以这个串就是世代编号。
  String? wrappedOf(String path) {
    final doc = readDoc(path);
    final slots = doc?['slots'];
    if (slots is! List) return null;
    for (final slot in slots) {
      if (slot is Map && slot['type'] == 'pin') return slot['wrapped'] as String?;
    }
    return null;
  }

  List<File> preservedFiles() =>
      tmp.listSync().whereType<File>().where((f) {
        final name = f.uri.pathSegments.last;
        return name.startsWith('vault.key.json.bak.preserved-');
      }).toList();

  /// 造出审计里那一格：盘上只剩 `.bak`，且它装的是**另一世**主密钥的包装。
  ///
  /// ① 建库（MK₁）→ ② 再建一次（MK₂；`_persistSlots` 这时把主文件复制成 `.bak`，
  /// 所以 `.bak` = MK₁ 那份）→ ③ 删掉主文件（用户视角：主文件不见了）。
  Future<String> seedOrphanBackup() async {
    final first = newService();
    await first.initialize('1111');
    final mkOne = wrappedOf(vaultFile.path)!;

    final second = newService();
    await second.initialize('2222'); // 主文件存在 ⇒ 落盘前把 MK₁ 复制进 .bak
    expect(wrappedOf('${vaultFile.path}.bak'), mkOne, reason: '前置条件：.bak 里是上一世');

    vaultFile.deleteSync();
    return mkOne;
  }

  group('STO-001 补建遇上旧保险库备份', () {
    test('主文件不在、.bak 是旧库 ⇒ 判成「补建盖住了旧备份」，且副本被保住', () async {
      final mkOne = await seedOrphanBackup();

      final cold = newService();
      expect(
        await cold.isConfigured(),
        isFalse,
        reason: '这条判据就是整件事的成因：上层看不见盘上那份 .bak',
      );

      final outcome = await cold.initialize('9527');
      expect(outcome, VaultInitOutcome.preservedOrphanBackup);

      expect(
        preservedFiles().map((f) => wrappedOf(f.path)),
        [mkOne],
        reason: '要有一份**内容仍是上一世**的保留件（不是新库的副本）',
      );
      expect(
        wrappedOf('${vaultFile.path}.bak'),
        mkOne,
        reason: '保留是**复制**：`.bak` 原位还在，`_readDoc` 的回退腿不能被顺手拆掉（突变 T3）',
      );
      final log = AuditLogger.snapshot();
      expect(
        log.any((l) => l.contains('vault.initialize.orphanBackupFound')),
        isTrue,
        reason: '补建之前先落一条——事后诸葛的审计在写入失败时就不存在了',
      );
      expect(
        log.any((l) => l.contains('vault.initialize.orphanBackupPreserved')),
        isTrue,
      );
    });

    test('销毁链跑满：紧接着的第二次保险库写入覆盖了 .bak，保留件仍在', () async {
      final mkOne = await seedOrphanBackup();

      final cold = newService();
      await cold.initialize('9527');
      // 这一笔才是审计里「此后不可恢复」的那一步：主文件已存在 ⇒ _persistSlots
      // 把**新**主密钥那份复制进 .bak，上一世的包装在原位置从此消失。
      await cold.changePin(oldPin: '9527', newPin: '8888');

      expect(
        wrappedOf('${vaultFile.path}.bak'),
        isNot(mkOne),
        reason: '前提：这条腿真的会毁掉原位置的旧副本（不毁就谈不上「抢救」）',
      );
      expect(
        preservedFiles().map((f) => wrappedOf(f.path)),
        contains(mkOne),
        reason: '突变 T1：去掉 _preserveOrphanBackup 的调用，这里旧那一世就再也找不回来了',
      );
    });

    test('反向锁：正常首建不产生保留件、不落异常审计', () async {
      final service = newService();
      expect(await service.initialize('9527'), VaultInitOutcome.fresh);

      expect(preservedFiles(), isEmpty);
      final log = AuditLogger.snapshot();
      expect(
        log.any((l) => l.contains('orphanBackup')),
        isFalse,
        reason: '每次装新机都报「检测到旧保险库备份」＝把门禁练成哭墙，用户会忽略真的那一次',
      );
    });

    test('反向锁：.bak 是坏 JSON ⇒ 没有值得保的东西，照常首建', () async {
      File('${vaultFile.path}.bak').writeAsStringSync('{"slots": [ 坏掉的');

      final service = newService();
      expect(await service.initialize('9527'), VaultInitOutcome.fresh);
      expect(preservedFiles(), isEmpty);
      expect(service.isUnlocked, isTrue, reason: '坏备份不能把补建本身拖住');
    });

    test('判据 API `hasOrphanBackupOnDisk`：只在孤儿那一格为真', () async {
      // 门组件靠它在**动手之前**问用户，所以判据必须与 `initialize` 内部那次检测
      // 逐字同形（同一份 `_orphanBackupDoc`），否则「问了却不必问」会反过来练成哭墙。
      expect(
        await newService().hasOrphanBackupOnDisk(),
        isFalse,
        reason: '干净首建（全新装）不许报警',
      );

      await seedOrphanBackup();
      expect(
        await newService().hasOrphanBackupOnDisk(),
        isTrue,
        reason: '主文件不在、.bak 是另一世 ⇒ 这正是必须问用户的那一格',
      );

      final cold = newService();
      await cold.initialize('9527');
      expect(
        await newService().hasOrphanBackupOnDisk(),
        isFalse,
        reason: '补建之后主文件在场 ⇒ 旧副本不再是「唯一句柄」，别再重复报警',
      );

      cold.lock();
      File(vaultFile.path).deleteSync();
      File('${vaultFile.path}.bak').writeAsStringSync('{"slots": [ 坏掉的');
      expect(
        await newService().hasOrphanBackupOnDisk(),
        isFalse,
        reason: '坏 JSON 不算「另一世主密钥」——没有值得保住的东西',
      );
    });
  });
}
