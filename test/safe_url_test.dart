import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/utils/safe_url.dart';

void main() {
  group('sanitizeHref（审计修复：命令注入面 scheme 白名单）', () {
    test('合法 http/https 链接原样返回（含 & 查询参数不误杀）', () {
      expect(sanitizeHref('https://example.com'), 'https://example.com');
      expect(sanitizeHref('http://a.b/c?x=1&y=2'), 'http://a.b/c?x=1&y=2');
      expect(sanitizeHref('  https://a.com  '), 'https://a.com', reason: 'trim');
      expect(sanitizeHref('mailto:test@example.com'), 'mailto:test@example.com');
    });

    test('拒绝危险 scheme（javascript:/file:/data:）', () {
      expect(sanitizeHref('javascript:alert(1)'), isNull);
      expect(sanitizeHref('file:///C:/Windows/System32/cmd.exe'), isNull);
      expect(sanitizeHref('data:text/html,<script>1</script>'), isNull);
      expect(sanitizeHref('JaVaScRiPt:alert(1)'), isNull, reason: '大小写不敏感');
    });

    test('拒绝引号注入（cmd 引号边界）', () {
      expect(sanitizeHref('https://a.com/" & calc'), isNull);
      expect(sanitizeHref('https://a.com/";start calc'), isNull);
    });

    test('拒绝 % 变量展开（cmd 环境变量注入，链 F）', () {
      expect(sanitizeHref('https://a.com/%PATH%'), isNull);
      expect(sanitizeHref('https://a.com/%PATH:~0,1%'), isNull);
      expect(sanitizeHref('https://a.com/%USERNAME%'), isNull);
      // 安全取舍：百分号编码 URL 也被拒绝（防 cmd 展开）。
      expect(sanitizeHref('https://a.com/a%20b'), isNull);
    });

    test('空/空白返回 null（清除链接语义）', () {
      expect(sanitizeHref(null), isNull);
      expect(sanitizeHref(''), isNull);
      expect(sanitizeHref('   '), isNull);
    });

    test('无效 URI 返回 null', () {
      expect(sanitizeHref('not a url at all!!'), isNull);
    });
  });
}
