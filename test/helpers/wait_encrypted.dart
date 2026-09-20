import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// 等待懒迁移把明文重写为密文（走异步写尾队列，需轮询等落盘）。
///
/// 上限 ~60s（6000 次 × 10ms）。真 KDF（PBKDF2-HMAC-SHA256 600k）在
/// 全量套件高并发下会排队，15s 曾在 Windows CI 被击穿（run 35501293467
/// —— block_doc 懒迁移用例「15 秒内未被迁移」）。绝不能改成无限等待——
/// 真 bug 时仍要在有限时间内 fail，否则用例会挂到套件超时。
Future<Uint8List> waitEncryptedFile(File file, {String label = '明文'}) async {
  for (var i = 0; i < 6000; i++) {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      // Windows CI 竞态：懒迁移重写正持有文件句柄（errno 32）——瞬态，
      // 与"明文未迁移"同等对待，等下一轮重试。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      continue;
    }
    if (VaultFileCodec.isEncrypted(bytes)) return bytes;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('60 秒内$label未被迁移为密文');
}
