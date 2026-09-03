import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// 等待懒迁移把明文重写为密文（走异步写尾队列，需轮询等落盘）。
///
/// 上限 ~15s（1500 次 × 10ms）。原先三处测试各存一份 2s 版本的同构 helper：
/// CI 慢机器上 2s 会被击穿（run 33786175092 —— notebook_encryption 的懒迁移
/// 用例红），真 KDF 重写在高并发下远超 2s。但绝不能改成无限等待——真 bug
/// 时仍要在有限时间内 fail，否则用例会挂到套件超时。
Future<Uint8List> waitEncryptedFile(
  File file, {
  String label = '明文',
}) async {
  for (var i = 0; i < 1500; i++) {
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
  fail('15 秒内$label未被迁移为密文');
}
