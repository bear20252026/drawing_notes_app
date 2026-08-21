// editor_core——RecoveryKeyService 恢复密钥（用户需求——2026-08-22）。
//
// 用户需求：生成恢复密钥说可以复制，还问"Have I copied it"，
// 但窗口没提供复制功能——没把密钥放进可一键复制的输入框。
//
// 框架级设计：恢复密钥生成 + 一键复制（分组显示——易读易抄）。
// 纯 Dart 不可变——可独立测试——不搞崩。
library;

import 'dart:math' as math;

/// 恢复密钥（不可变——分组显示——可一键复制）。
class RecoveryKey {
  const RecoveryKey({required this.key, required this.groups});

  /// 原始密钥（去空格——32 字符）。
  final String key;

  /// 分组（每组 4 字符——易读——共 8 组）。
  final List<String> groups;

  /// 显示格式（分组——空格分隔——用于输入框显示）。
  String get formatted => groups.join(' ');

  /// 一键复制文本（分组——便于恢复）。
  String get copyText => formatted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RecoveryKey && key == other.key;

  @override
  int get hashCode => key.hashCode;
}

/// 恢复密钥服务（用户需求修复——积木式纯 Dart）。
///
/// 功能：
/// - 生成恢复密钥（随机 32 字符——分组显示）
/// - 一键复制（formatted 文本——可直接复制）
/// - 校验（恢复时输入校验——去空格/大小写不敏感）
/// - 输入规范化（粘贴时去空格/统一小写）
class RecoveryKeyService {
  const RecoveryKeyService();

  /// 恢复密钥字符集（去掉易混淆字符——0/O/1/l/I）。
  static const String _charset =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  /// 生成恢复密钥（随机 32 字符——8 组 × 4 字符——可一键复制）。
  RecoveryKey generate({int groups = 8, int charsPerGroup = 4}) {
    final rng = math.Random.secure();
    final totalChars = groups * charsPerGroup;
    final key = List.generate(totalChars, (_) {
      return _charset[rng.nextInt(_charset.length)];
    }).join();

    final groupList = List.generate(groups, (i) {
      return key.substring(i * charsPerGroup, (i + 1) * charsPerGroup);
    });

    return RecoveryKey(key: key, groups: groupList);
  }

  /// 一键复制文本（分组显示——用户可粘贴）。
  String formatForCopy(RecoveryKey key) => key.copyText;

  /// 输入规范化（粘贴时——去空格/换行/统一小写——便于校验）。
  String normalizeInput(String input) {
    return input.replaceAll(RegExp(r'[\s\-]'), '').toLowerCase();
  }

  /// 校验恢复密钥（输入 vs 生成密钥——去空格/大小写不敏感）。
  bool validate(String input, RecoveryKey key) {
    return normalizeInput(input) == key.key.toLowerCase();
  }
}
