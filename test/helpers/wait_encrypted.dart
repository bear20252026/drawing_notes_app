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
Future<Uint8List> waitEncryptedFile(File file, {String label = '明文'}) async {
  final maxSteps = waitEncryptedBudget.inMilliseconds ~/ _waitEncryptedStep.inMilliseconds;
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
  fail('${waitEncryptedBudget.inSeconds} 秒内$label未被迁移为密文');
}
