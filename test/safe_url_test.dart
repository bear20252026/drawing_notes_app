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

  group('sanitizeImageSrc（P1：Image.network 远端图片门禁）', () {
    test('仅 https 通过', () {
      expect(
        sanitizeImageSrc('https://cdn.example.com/a.png'),
        'https://cdn.example.com/a.png',
      );
      expect(sanitizeImageSrc('http://192.168.1.1/a.png'), isNull);
      expect(sanitizeImageSrc('http://169.254.169.254/x'), isNull);
      expect(sanitizeImageSrc('javascript:alert(1)'), isNull);
      expect(sanitizeImageSrc('data:image/png;base64,AAA'), isNull);
      expect(sanitizeImageSrc('file:///etc/passwd'), isNull);
    });

    test('拒绝 userinfo/无 host/空白/超长', () {
      expect(sanitizeImageSrc('https://u:p@h.com/a.png'), isNull);
      expect(sanitizeImageSrc('https:///a.png'), isNull);
      expect(sanitizeImageSrc('https://h.com/a b.png'), isNull);
      expect(sanitizeImageSrc('https://h.com/${'a' * 4096}'), isNull);
      expect(sanitizeImageSrc(null), isNull);
      expect(sanitizeImageSrc(''), isNull);
    });

    test('签名 URL（% 编码）放行——不走 cmd', () {
      expect(
        sanitizeImageSrc('https://cdn.example.com/a%20b.png?sig=x%3D1'),
        'https://cdn.example.com/a%20b.png?sig=x%3D1',
      );
    });
  });
}
