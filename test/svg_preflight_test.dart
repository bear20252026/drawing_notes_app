import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/svg_preflight.dart';

/// SVG 导入预检器单测（专家目标架构 IG——2026-08-16）：
/// 正常 SVG 通过 + 恶意 SVG（DOCTYPE/实体/脚本/事件属性/危险 URL/膨胀）拒绝。
void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('预检：正常 SVG 通过', () {
    final svg = bytes('''<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">
  <rect x="10" y="10" width="80" height="30" fill="#336699"/>
</svg>''');
    expect(SvgPreflight.check(svg), isNull);
  });

  test('预检：DOCTYPE/实体拒绝（XXE/Billion Laughs）', () {
    final svg = bytes('''<?xml version="1.0"?>
<!DOCTYPE svg [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;">]>
<svg xmlns="http://www.w3.org/2000/svg"/>''');
    expect(SvgPreflight.check(svg), contains('DOCTYPE'));
  });

  test('预检：script 标签拒绝', () {
    final svg = bytes('''<svg xmlns="http://www.w3.org/2000/svg">
  <script>alert(1)</script>
</svg>''');
    expect(SvgPreflight.check(svg), contains('危险标签'));
  });

  test('预检：事件属性拒绝（onload）', () {
    final svg = bytes('''<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>''');
    expect(SvgPreflight.check(svg), contains('事件属性'));
  });

  test('预检：javascript: URL 拒绝', () {
    final svg = bytes('''<svg xmlns="http://www.w3.org/2000/svg">
  <a href="javascript:alert(1)"><rect width="10" height="10"/></a>
</svg>''');
    expect(SvgPreflight.check(svg), contains('危险 URL'));
  });

  test('预检：超大文件拒绝（5MB 限制）', () {
    final big = Uint8List(SvgPreflight.maxBytes + 1);
    expect(SvgPreflight.check(big), contains('限制'));
  });

  test('预检：元素膨胀拒绝（复杂度上限）', () {
    final buffer = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg">');
    for (var i = 0; i < SvgPreflight.maxElements + 100; i++) {
      buffer.write('<rect width="1" height="1"/>');
    }
    buffer.write('</svg>');
    expect(SvgPreflight.check(bytes(buffer.toString())), contains('元素过多'));
  });
}
