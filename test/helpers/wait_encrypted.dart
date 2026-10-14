import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// 轮询步长与总预算。
///
/// **不变式（P2-4，审计 2026-10-05）**：本预算必须**严格小于**调用方库级
/// `@Timeout`。原先预算 180s 与 `notebook_encryption_test` /
/// `storage_encryption_test` 的库级 `@Timeout(3 分钟)` **等长**，于是
/// per-test timeout 永远先炸，失败呈现为裸「Test timed out after 3 minutes」，
/// 下面那句「谁在多少秒内没被迁移」的诊断**从来没有机会说话**
/// （2026-10-05 CI attempt 1 的 Real-KDF 超时就是这么糊成一团的）。
/// 现在 120s < 库级 `@Timeout(3 分钟)`（AGENTS.md §7 对真 KDF 用例的明文约定，
/// 不去动它），诊断信息因此能先于 per-test timeout 出现。
/// **残余局限（诚实记录）**：单条用例最多有两次调用
/// （`storage_encryption_test` 的列表批量迁移），两次都打满 = 240s > 180s，
/// 那种双病态情形下仍是裸超时先炸。要彻底根治得把预算做成「按用例剩余
/// 时间」而非固定值——flutter_test 不暴露那个信息，故留作已知局限。
const Duration waitEncryptedBudget = Duration(seconds: 120);
const Duration _waitEncryptedStep = Duration(milliseconds: 10);

/// 等待懒迁移把明文重写为密文（走异步写尾队列，需轮询等落盘）。
///
/// 上限 = [waitEncryptedBudget]。真 KDF（PBKDF2-HMAC-SHA256 600k /
/// Argon2id 64MiB）在全量套件高并发下会排队：15s 曾在 Windows CI 被击穿
/// （run 35501293467），放宽到 60s 后仍被击穿（run 36089891365——CI 默认
/// 并发下多套件真 KDF 并行排队）。绝不能改成无限等待——真 bug 时仍要在
/// 有限时间内 fail，否则用例会挂到套件超时。
/// KDF 套件在 CI 里按 `--tags kdf --concurrency=1` 串行跑，排队压力小于
/// 满并发全量，120s 是留过余量的。
Future<Uint8List> waitEncryptedFile(
  File file, {
  String label = '明文',
  Future<void>? pendingWrite,
}) async {
  final sw = Stopwatch()..start();
  var drainNote = '未提供确定信号（纯轮询）';
  var drainCompleted = false;
  if (pendingWrite != null) {
    // 先等「这条腿自己排队的写」落完——这是**确定信号**，不是掐表。上限取预算
    // 的一半，剩下的留给下面的轮询兜底，因此总时长仍严格不超过
    // [waitEncryptedBudget]（P2-4 不变式：预算必须小于库级 @Timeout，否则
    // 诊断信息永远被裸「Test timed out」挡在后面）。
    final drainCap = Duration(
      milliseconds: waitEncryptedBudget.inMilliseconds ~/ 2,
    );
    try {
      await pendingWrite.timeout(drainCap);
      drainNote = '排队写 ${sw.elapsedMilliseconds}ms 内跑完';
      drainCompleted = true;
    } on TimeoutException {
      drainNote = '排队写超过 ${drainCap.inSeconds}s 仍未跑完（写尾队列被卡住？）';
    }
  }
  var remaining = waitEncryptedBudget - sw.elapsed;
  if (drainCompleted) {
    // 排队写已经跑完而盘上仍是明文 ⇒ 答案就出来了，不必把剩下的预算轮询完。
    // 只留一个**短宽限**（防「队列取早了、迁移还在后面排队」这类顺序意外把
    // 好代码判成红），于是真缺陷在 ~秒级就失败，而不是拖满 120s 才报。
    final grace = const Duration(seconds: 5);
    if (grace < remaining) remaining = grace;
  }
  final budgeted = remaining.inMilliseconds ~/ _waitEncryptedStep.inMilliseconds;
  final maxSteps = budgeted < 1 ? 1 : budgeted;
  for (var i = 0; i < maxSteps; i++) {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      // Windows CI 竞态：懒迁移重写正持有文件句柄（errno 32）——瞬态，
      // 与"明文未迁移"同等对待，等下一轮重试。
      await Future<void>.delayed(_waitEncryptedStep);
      continue;
    }
    if (VaultFileCodec.isEncrypted(bytes)) return bytes;
    await Future<void>.delayed(_waitEncryptedStep);
  }
  var lastLook = '读不到文件';
  try {
    lastLook = VaultFileCodec.isEncrypted(await file.readAsBytes())
        ? '已是密文'
        : '仍是明文';
  } on FileSystemException {
    // 句柄占用等瞬态：诊断措辞降级为「读不到」，不影响失败结论。
  }
  // 报**实际用时**而不是预算：加了宽限上限之后，真缺陷往往是几秒就判出来的，
  // 文案还写「120 秒内」就是在对读者说谎（诊断信息假比没有诊断更糟）。
  fail(
    '$label未被迁移为密文（实际等待 ${sw.elapsed.inSeconds}s / '
    '预算 ${waitEncryptedBudget.inSeconds}s；$drainNote；最后一次读盘$lastLook）',
  );
}
