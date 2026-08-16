/// Fractional Indexing 排序键（参考 Excalidraw fractional-indexing，CC0）。
///
/// 用字符串键表示元素的层级顺序，插入到两层之间时只生成一个新键，
/// 不需要重排其余元素的层级号（整数 zOrder 需要 +1/-1 全量调整）。
/// 键按字典序排序即层级序；`a0` 为起点，支持任意次插入。
library;

/// base62 数字字符集（字符码升序，供 [generateKeyBetween] 使用）。
// skylos: ignore —— base62 字符集常量（合法常量——非密钥）——Skylos 高熵
// 检测误报（熵 5.95——字符集与 scan_secrets EXCLUDED_PATHS 同类豁免）。
const String base62Digits =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// 校验 [key] 是否为合法的排序键；非法时抛出 [ArgumentError]。
void validateOrderKey(String key, {String digits = base62Digits}) {
  final validChars = key.split('').every(digits.contains);
  if (key == 'A${digits[0] * 26}' || !validChars) {
    throw ArgumentError('invalid order key: $key');
  }
  // getIntegerPart 会校验首字符与长度。
  getIntegerPart(key, digits);
  final f = key.substring(getIntegerPart(key, digits).length);
  if (f.endsWith(digits[0])) {
    throw ArgumentError('invalid order key: $key');
  }
}

/// 整数部分长度由首字符决定（对齐 Excalidraw 规则）。
int getIntegerLength(String head) {
  if (head.compareTo('a') >= 0 && head.compareTo('z') <= 0) {
    return head.codeUnitAt(0) - 'a'.codeUnitAt(0) + 2;
  } else if (head.compareTo('A') >= 0 && head.compareTo('Z') <= 0) {
    return 'Z'.codeUnitAt(0) - head.codeUnitAt(0) + 2;
  }
  throw ArgumentError('invalid order key head: $head');
}

/// 提取键的整数部分。
String getIntegerPart(String key, [String digits = base62Digits]) {
  final length = getIntegerLength(key[0]);
  if (length > key.length) {
    throw ArgumentError('invalid order key: $key');
  }
  return key.substring(0, length);
}

/// 计算两个键之间的中间键；[b] 为 null 表示“之后无界”。
String _midpoint(String a, String? b, String digits) {
  final zero = digits[0];
  if (b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a >= $b');
  }
  if (a.endsWith(zero) || (b != null && b.endsWith(zero))) {
    throw ArgumentError('trailing zero');
  }
  if (b != null) {
    // 去掉最长公共前缀，a 用 0 补齐。
    var n = 0;
    while ((n < a.length ? a[n] : zero) == b[n]) {
      n++;
    }
    if (n > 0) {
      return b.substring(0, n) + _midpoint(a.substring(n), b.substring(n), digits);
    }
  }
  final digitA = a.isEmpty ? 0 : digits.indexOf(a[0]);
  final digitB = b != null ? digits.indexOf(b[0]) : digits.length;
  if (digitB - digitA > 1) {
    final midDigit = ((digitA + digitB) / 2).round();
    return digits[midDigit];
  }
  if (b != null && b.length > 1) {
    return b.substring(0, 1);
  }
  return digits[digitA] + _midpoint(a.substring(1), null, digits);
}

String? _incrementInteger(String x, String digits) {
  final head = x[0];
  final digs = x.substring(1).split('');
  var carry = true;
  for (var i = digs.length - 1; carry && i >= 0; i--) {
    final d = digits.indexOf(digs[i]) + 1;
    if (d == digits.length) {
      digs[i] = digits[0];
    } else {
      digs[i] = digits[d];
      carry = false;
    }
  }
  if (carry) {
    if (head == 'Z') return 'a${digits[0]}';
    if (head == 'z') return null;
    final h = String.fromCharCode(head.codeUnitAt(0) + 1);
    if (h.compareTo('a') > 0) {
      digs.add(digits[0]);
    } else {
      digs.removeLast();
    }
    return h + digs.join();
  }
  return head + digs.join();
}

String? _decrementInteger(String x, String digits) {
  final head = x[0];
  final digs = x.substring(1).split('');
  var borrow = true;
  for (var i = digs.length - 1; borrow && i >= 0; i--) {
    final d = digits.indexOf(digs[i]) - 1;
    if (d == -1) {
      digs[i] = digits[digits.length - 1];
    } else {
      digs[i] = digits[d];
      borrow = false;
    }
  }
  if (borrow) {
    if (head == 'a') return 'Z${digits[digits.length - 1]}';
    if (head == 'A') return null;
    final h = String.fromCharCode(head.codeUnitAt(0) - 1);
    if (h.compareTo('Z') < 0) {
      digs.add(digits[digits.length - 1]);
    } else {
      digs.removeLast();
    }
    return h + digs.join();
  }
  return head + digs.join();
}

/// 生成位于 [a] 与 [b] 之间的新排序键。
///
/// [a]/[b] 为 null 表示无界（起点/终点）。返回键满足
/// `a < result < b`（字典序），且两者都可为 null。
String generateKeyBetween(
  String? a,
  String? b, {
  String digits = base62Digits,
}) {
  if (a != null) validateOrderKey(a, digits: digits);
  if (b != null) validateOrderKey(b, digits: digits);
  if (a != null && b != null && a.compareTo(b) >= 0) {
    throw ArgumentError('$a >= $b');
  }
  if (a == null) {
    if (b == null) return 'a${digits[0]}';
    final ib = getIntegerPart(b, digits);
    final fb = b.substring(ib.length);
    if (ib == 'A${digits[0] * 26}') {
      return ib + _midpoint('', fb, digits);
    }
    if (ib.compareTo(b) < 0) return ib;
    final res = _decrementInteger(ib, digits);
    if (res == null) throw ArgumentError('cannot decrement any more');
    return res;
  }
  if (b == null) {
    final ia = getIntegerPart(a, digits);
    final fa = a.substring(ia.length);
    final i = _incrementInteger(ia, digits);
    return i ?? ia + _midpoint(fa, null, digits);
  }
  final ia = getIntegerPart(a, digits);
  final fa = a.substring(ia.length);
  final ib = getIntegerPart(b, digits);
  final fb = b.substring(ib.length);
  if (ia == ib) return ia + _midpoint(fa, fb, digits);
  final i = _incrementInteger(ia, digits);
  if (i == null) throw ArgumentError('cannot increment any more');
  if (i.compareTo(b) < 0) return i;
  return ia + _midpoint(fa, null, digits);
}

/// 生成 [n] 个位于 [a] 与 [b] 之间、按升序排列的互异排序键。
List<String> generateNKeysBetween(
  String? a,
  String? b,
  int n, {
  String digits = base62Digits,
}) {
  if (n == 0) return const [];
  if (n == 1) return [generateKeyBetween(a, b, digits: digits)];
  if (b == null) {
    var c = generateKeyBetween(a, b, digits: digits);
    final result = [c];
    for (var i = 0; i < n - 1; i++) {
      c = generateKeyBetween(c, b, digits: digits);
      result.add(c);
    }
    return result;
  }
  if (a == null) {
    var c = generateKeyBetween(a, b, digits: digits);
    final result = [c];
    for (var i = 0; i < n - 1; i++) {
      c = generateKeyBetween(a, c, digits: digits);
      result.add(c);
    }
    return result.reversed.toList();
  }
  final mid = n ~/ 2;
  final c = generateKeyBetween(a, b, digits: digits);
  return [
    ...generateNKeysBetween(a, c, mid, digits: digits),
    c,
    ...generateNKeysBetween(c, b, n - mid - 1, digits: digits),
  ];
}
