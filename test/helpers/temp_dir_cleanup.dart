import 'dart:io';

/// Windows CI 兼容的测试临时目录清理。
///
/// 懒迁移/加密重写走异步写尾队列，测试结束时可能仍持文件句柄——
/// Windows 上立即 `delete(recursive: true)` 会抛 PathAccessException
/// （errno 32，文件被另一进程占用）。带 100ms 退避重试，总宽限 ~3s；
/// 仍失败则最后一次不吞错抛出（真实句柄泄漏应当响）。
Future<void> deleteTempDirWithRetry(Directory dir) async {
  for (var i = 0; i < 30; i++) {
    try {
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  await dir.delete(recursive: true);
}
