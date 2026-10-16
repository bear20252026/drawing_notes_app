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

  /// [next] 产出的 id 的**形状**：`<前缀>_<时间戳36>_<序号>_<7 位随机段>`。
  ///
  /// 为什么把形状也暴露出来（审计 2026-10-16）：写腿用 `next(...)` 命名临时文件
  /// （前缀有 `write`/`thumb`/`oplog` 三家），崩溃遗留的孤儿要靠这同一个形状被认出来。
  /// 若清扫侧自己抄一份「前缀白名单」，新增一家前缀就自动漏一家——正是本仓「一份判据
  /// N 份副本、修一条漏五条」那一族。判据只有这一份定义。
  static final RegExp generatedIdPattern = RegExp(
    r'^[a-z][a-z0-9]*_[0-9a-z]{6,12}_[0-9a-z]{4,6}_[0-9a-z]{7}$',
  );

  /// [generatedIdPattern] 的可读别名：这一段是不是本生成器产出的 id。
  static bool isGeneratedId(String segment) => generatedIdPattern.hasMatch(segment);
}
