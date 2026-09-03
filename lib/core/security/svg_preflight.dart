import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// SVG 导入预检器（导入网关隔离器——专家目标架构 IG，2026-08-16）。
///
/// OWASP XXE Prevention Cheat Sheet（DTD 禁用 + 实体扩展限制——Billion
/// Laughs）+ SVG Genie 上传安全清单（拒绝 DOCTYPE/脚本/事件属性/
/// javascript: + 复杂度上限）+ lw-enable 模式（5MB 大小限制）+ svgo
/// 安全通告实证（811 字节 SVG 实体膨胀可崩溃解析器）——低权限解析前
/// 预检——拒绝恶意 SVG（脚本/XXE/膨胀）。
class SvgPreflight {
  const SvgPreflight._();

  /// 文件大小上限（lw-enable 模式——5MB）。
  static const int maxBytes = 5 * 1024 * 1024;

  /// 元素数上限（SVG Genie cap complexity——SVG 膨胀防护）。
  static const int maxElements = 5000;

  /// 文本总量上限（路径/文本膨胀防护）。
  static const int maxTextChars = 100000;

  /// 文本总量上限（路径/文本膨胀防护）。
  static const int maxNestingDepth = 128;

  /// 危险标签（SVG Genie 删除清单——脚本/嵌入内容）。
  ///
  /// P0 修复：可选命名空间前缀 `(?:ns:)?`——`<svg:script>` 等此前同时
  /// 逃过拦截与元素计数（`:` 不在旧字符类中）。
  static final RegExp _dangerousTags = RegExp(
    r'<(?:[a-zA-Z][\w.\-]*:)?(script|foreignobject|iframe|object|embed|handler|listener)\b',
    caseSensitive: false,
  );

  /// 事件属性（onload/onclick/onerror 等——脚本执行风险）。
  static final RegExp _eventAttributes = RegExp(
    r'\son[a-z]+\s*=',
    caseSensitive: false,
  );

  /// 外部包含 / 样式外联（XXE/SSRF/数据外泄通道——渲染前拒绝）。
  static final RegExp _externalIncludes = RegExp(
    r'<(?:[a-zA-Z][\w.\-]*:)?xi:include\b|@import\s|{-moz-binding|behavior\s*:',
    caseSensitive: false,
  );

  /// 数字字符引用（`&#106;` / `&#x6A;`）：渲染器先解实体再解析 URL，
  /// 预检必须在同一归一化文本上匹配，否则编码即绕过。
  static final RegExp _numericEntity = RegExp(r'&#(x?[0-9a-fA-F]+);');

  static const _namedEntities = <String, String>{
    '&lt;': '<',
    '&gt;': '>',
    '&amp;': '&',
    '&quot;': '"',
    '&apos;': "'",
  };

  /// 实体解码 + 空白/控制字符归一化：与渲染器站在同一视角检查。
  static String _normalize(String lower) {
    var s = lower.replaceAllMapped(_numericEntity, (m) {
      final body = m.group(1)!;
      try {
        final code = body.startsWith('x')
            ? int.parse(body.substring(1), radix: 16)
            : int.parse(body);
        if (code <= 0 || code > 0x10FFFF) return m.group(0)!;
        return String.fromCharCode(code);
      } catch (_) {
        return m.group(0)!;
      }
    });
    _namedEntities.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  /// 嵌套深度扫描（元素数上限防不住 `((((<g>×4999` 爆栈——递归解析器）。
  static int _maxDepth(String text) {
    final tagRe = RegExp(r'<(/?)([a-zA-Z!?][\w.:-]*)[^<>]*?(/?)>');
    var depth = 0;
    var peak = 0;
    for (final m in tagRe.allMatches(text)) {
      final name = m.group(2)!;
      if (name.startsWith('!') || name.startsWith('?')) continue;
      if (m.group(1) == '/') {
        depth = max(0, depth - 1);
      } else if (m.group(3) != '/') {
        depth++;
        peak = max(peak, depth);
      }
    }
    return peak;
  }

  /// 预检 SVG 内容——返回错误信息（null = 通过——可进入解析/渲染）。
  static String? check(Uint8List data) {
    if (data.length > maxBytes) {
      return 'SVG 文件超过 ${maxBytes ~/ (1024 * 1024)}MB 限制';
    }
    // P0 修复：畸形字节直接拒绝——此前 allowMalformed:true 把非法序列
    // 映射为 U+FFFD 检查，而宽松渲染器可能解出另一语义（差分解码）。
    final String text;
    try {
      text = utf8.decode(data, allowMalformed: false);
    } catch (_) {
      return 'SVG 编码异常（拒绝畸形字节——差分解码防护）';
    }
    final lower = text.toLowerCase();
    // 与渲染器同视角：先实体解码，再做全部字面匹配。
    final norm = _normalize(lower);
    // 危险 URL 匹配在压缩文本上进行——`java\tscript:`、`java&#x09;script:`
    // 去空白/控制符后现形（fail-closed：误伤仅拒绝文件）。
    final compact = norm.replaceAll(RegExp(r'[\s\x00-\x1F\x7F]'), '');

    // DOCTYPE/实体拒绝（XXE/Billion Laughs——OWASP + svgo 通告）。
    if (norm.contains('<!doctype') || norm.contains('<!entity')) {
      return 'SVG 禁止 DOCTYPE/实体声明（XXE/Billion Laughs 防护）';
    }
    // 危险标签（脚本/嵌入内容，含命名空间变体）。
    if (_dangerousTags.hasMatch(norm)) {
      return 'SVG 含危险标签（脚本/嵌入内容）';
    }
    // 事件属性（脚本执行风险）。
    if (_eventAttributes.hasMatch(norm)) {
      return 'SVG 含事件属性（脚本执行风险）';
    }
    // 外部包含 / 样式外联。
    if (_externalIncludes.hasMatch(norm)) {
      return 'SVG 含外部包含/样式外联（SSRF/外泄防护）';
    }
    // 危险 URL（javascript:/data:——SVG Genie 删除清单）。
    if (compact.contains('javascript:') || compact.contains('data:')) {
      return 'SVG 含危险 URL（javascript:/data:）';
    }
    // 嵌套深度上限（爆栈防护）。
    if (_maxDepth(lower) > maxNestingDepth) {
      return 'SVG 嵌套过深（超过 $maxNestingDepth——爆栈防护）';
    }
    // 复杂度上限（元素数 + 文本总量——SVG 膨胀防护；元素计数含 `:`）。
    final elementCount = RegExp(
      r'<[a-z][a-z0-9.:-]*[\s/>]',
      caseSensitive: false,
    ).allMatches(lower).length;
    if (elementCount > maxElements) {
      return 'SVG 元素过多（超过 $maxElements——复杂度上限）';
    }
    final textSize = RegExp(
      r'>[^<>]{20,}<',
    ).allMatches(text).fold<int>(0, (sum, m) => sum + m.group(0)!.length);
    if (textSize > maxTextChars) {
      return 'SVG 文本量过大（膨胀防护）';
    }
    return null;
  }
}
