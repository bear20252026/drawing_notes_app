/// 恒定时间比较（防时序侧信道）——**单一事实来源**。
///
/// 背景：普通 `==` / `List.equals` 比较一旦发现首个不等元素就短路返回，
/// 攻击者可通过测量「返回耗时」逐字符猜解秘密值（MAC / 摘要 / 口令哈希）。
/// 本工具无论输入是否相等都遍历完整长度，把逐字符猜解的成本抬到不可行。
///
/// **实现口径（取三处历史实现中最严谨的一版，2026-11-15 收敛）**：
/// - **不因长度不等提前返回**：长度差折算进 `diff`，循环按两者较长者遍历——
///   否则「长度是否相等」这一点点时间差本身就是侧信道。
/// - 按 UTF-8 字节比较（对 ASCII hex 与 codeUnit 等价，且对任意输入成立）。
/// - 累积异或（`diff |= x ^ y`）而非逐位比较，无数据相关分支。
///
/// **保证边界（如实声明，勿对外写成强恒定时间）**：Dart 的 `String` 不可变、
/// `codeUnitAt` / 列表索引存在 JIT 优化空间，语言层**无法提供** C 的
/// `CRYPTO_memcmp` 那种带编译器屏障的严格恒定时间保证。本工具是**纵深防御**：
/// 对「本地文件攻击者 / 远程计时攻击」威胁模型有效抬高成本，但不声称抵抗
/// 高精度微架构侧信道（缓存/分支预测）。需要强保证的场景应走平台原生
/// `CRYPTO_memcmp`（Windows）/ `timingsafe_bcmp`（POSIX）——属独立专项。
///
/// **使用纪律**：一切「秘密值 vs 期望值」的比较（HMAC / 摘要 / 口令哈希 /
/// 认证侧车）必须走本工具，禁止裸 `==`。门禁见
/// `test/architecture/constant_time_gate_test.dart`。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 恒定时间比较两个字符串（MAC hex / 摘要 / 口令哈希等秘密值）。
///
/// 长度不等**不提前返回**：长度差折进 diff，按较长者遍历。
bool constantTimeEquals(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  return constantTimeBytesEqual(aBytes, bBytes);
}

/// 恒定时间比较两个字节序列（MAC / 摘要 / 密钥校验值）。
///
/// 长度不等**不提前返回**：长度差折进 diff，按较长者遍历。
bool constantTimeBytesEqual(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

/// 恒定时间比较字节序列与 hex 摘要字符串（便利入口）。
///
/// [digestHex] 为小写 hex；[bytes] 先转 hex 再按字符串恒定时间比较。
bool constantTimeHexEquals(Uint8List bytes, String digestHex) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return constantTimeEquals(sb.toString(), digestHex);
}