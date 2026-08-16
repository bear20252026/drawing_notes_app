import 'dart:convert';
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

  /// 危险标签（SVG Genie 删除清单——脚本/嵌入内容）。
  static final RegExp _dangerousTags = RegExp(
    r'<(script|foreignobject|iframe|object|embed)\b',
    caseSensitive: false,
  );

  /// 事件属性（onload/onclick/onerror 等——脚本执行风险）。
  static final RegExp _eventAttributes = RegExp(
    r'\son[a-z]+\s*=',
    caseSensitive: false,
  );

  /// 预检 SVG 内容——返回错误信息（null = 通过——可进入解析/渲染）。
  static String? check(Uint8List data) {
    if (data.length > maxBytes) {
      return 'SVG 文件超过 ${maxBytes ~/ (1024 * 1024)}MB 限制';
    }
    final text = utf8.decode(data, allowMalformed: true);
    final lower = text.toLowerCase();

    // DOCTYPE/实体拒绝（XXE/Billion Laughs——OWASP + svgo 通告）。
    if (lower.contains('<!doctype') || lower.contains('<!entity')) {
      return 'SVG 禁止 DOCTYPE/实体声明（XXE/Billion Laughs 防护）';
    }
    // 危险标签（脚本/嵌入内容）。
    if (_dangerousTags.hasMatch(lower)) {
      return 'SVG 含危险标签（脚本/嵌入内容）';
    }
    // 事件属性（脚本执行风险）。
    if (_eventAttributes.hasMatch(lower)) {
      return 'SVG 含事件属性（脚本执行风险）';
    }
    // 危险 URL（javascript:/data:——SVG Genie 删除清单）。
    if (lower.contains('javascript:') || lower.contains('data:')) {
      return 'SVG 含危险 URL（javascript:/data:）';
    }
    // 复杂度上限（元素数 + 文本总量——SVG 膨胀防护）。
    final elementCount = RegExp(r'<[a-z][a-z0-9]*[\s/>]', caseSensitive: false)
        .allMatches(lower)
        .length;
    if (elementCount > maxElements) {
      return 'SVG 元素过多（超过 $maxElements——复杂度上限）';
    }
    final textSize = RegExp(r'>[^<>]{20,}<')
        .allMatches(text)
        .fold<int>(0, (sum, m) => sum + m.group(0)!.length);
    if (textSize > maxTextChars) {
      return 'SVG 文本量过大（膨胀防护）';
    }
    return null;
  }
}
