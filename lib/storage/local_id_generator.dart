import 'dart:math';

/// 本地持久化对象的无路径歧义 ID 生成器。
///
/// 仅使用字母、数字和下划线，适合作为文件名。时间戳确保跨进程有序，进程内
/// 序号防止同一微秒的连续创建冲突，安全随机段进一步防止并发任务碰撞。
class LocalIdGenerator {
  LocalIdGenerator._();

  static final Random _random = Random.secure();
  static int _sequence = 0;

  static String next(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final sequence = (_sequence++ & 0xFFFFFF).toRadixString(36).padLeft(4, '0');
    final entropy = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '${prefix}_${timestamp}_${sequence}_$entropy';
  }
}
