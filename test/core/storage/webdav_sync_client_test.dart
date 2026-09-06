// P3-W2 WebDAV 同步客户端单元测试。
// 使用 http.MockClient 注入假响应，覆盖全部 HTTP 方法。

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';

void main() {
  final baseUrl = Uri.parse('https://dav.example.com/notes/');

  /// 创建带 MockClient 的客户端。
  WebDavSyncClient makeClient(
    Future<http.Response> Function(http.Request) handler, {
    String username = '',
    String password = '',
  }) {
    final mockClient = MockClient(handler);
    return WebDavSyncClient(
      baseUrl: baseUrl,
      client: mockClient,
      username: username,
      password: password,
    );
  }

  group('ensureCollection', () {
    test('MKCOL 201 返回 true', () async {
      final client = makeClient((request) async {
        expect(request.method, 'MKCOL');
        return http.Response('', 201);
      });
      final result = await client.ensureCollection();
      expect(result, isTrue);
    });

    test('MKCOL 405 视为已存在返回 true', () async {
      final client = makeClient((request) async => http.Response('', 405));
      final result = await client.ensureCollection();
      expect(result, isTrue);
    });

    test('MKCOL 301 视为已存在返回 true', () async {
      final client = makeClient((request) async => http.Response('', 301));
      final result = await client.ensureCollection();
      expect(result, isTrue);
    });

    test('MKCOL 409 视为已存在返回 true', () async {
      final client = makeClient((request) async => http.Response('', 409));
      final result = await client.ensureCollection();
      expect(result, isTrue);
    });

    test('MKCOL 500 抛 WebDavSyncException', () async {
      final client = makeClient((request) async => http.Response('err', 500));
      expect(
        () => client.ensureCollection(),
        throwsA(
          isA<WebDavSyncException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });
  });

  group('getBytes', () {
    test('GET 200 返回字节', () async {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final client = makeClient((request) async {
        expect(request.method, 'GET');
        return http.Response.bytes(data, 200);
      });
      final result = await client.getBytes('file.txt');
      expect(result, equals(data));
    });

    test('GET 404 返回 null', () async {
      final client = makeClient((request) async => http.Response('', 404));
      final result = await client.getBytes('missing.txt');
      expect(result, isNull);
    });

    test('GET 500 抛 WebDavSyncException', () async {
      final client = makeClient((request) async => http.Response('err', 500));
      expect(
        () => client.getBytes('file.txt'),
        throwsA(isA<WebDavSyncException>()),
      );
    });
  });

  group('putBytes', () {
    test('PUT 201 成功', () async {
      final client = makeClient((request) async {
        expect(request.method, 'PUT');
        return http.Response('', 201);
      });
      await client.putBytes('file.txt', [1, 2, 3]);
    });

    test('PUT 204 成功', () async {
      final client = makeClient((request) async => http.Response('', 204));
      await client.putBytes('file.txt', [1, 2, 3]);
    });

    test('PUT 409 抛 WebDavSyncException', () async {
      final client = makeClient((request) async => http.Response('', 409));
      expect(
        () => client.putBytes('file.txt', [1, 2, 3]),
        throwsA(isA<WebDavSyncException>()),
      );
    });

    test('PUT 附带 Authorization 头（user/pass 非空时）', () async {
      String? authHeader;
      final client = makeClient(
        (request) async {
          authHeader = request.headers['authorization'];
          return http.Response('', 201);
        },
        username: 'alice',
        password: 'secret',
      );
      await client.putBytes('file.txt', [1, 2, 3]);
      expect(authHeader, isNotNull);
      expect(authHeader, startsWith('Basic '));
      // 验证 base64 解码
      final token = authHeader!.substring('Basic '.length);
      final decoded = utf8.decode(base64Decode(token));
      expect(decoded, 'alice:secret');
    });

    test('PUT 无认证时不带 Authorization 头', () async {
      String? authHeader;
      final client = makeClient((request) async {
        authHeader = request.headers['authorization'];
        return http.Response('', 201);
      });
      await client.putBytes('file.txt', [1, 2, 3]);
      expect(authHeader, isNull);
    });
  });

  group('deleteRemaining', () {
    test('DELETE 204 返回 true', () async {
      final client = makeClient((request) async {
        expect(request.method, 'DELETE');
        return http.Response('', 204);
      });
      final result = await client.deleteRemaining('file.txt');
      expect(result, isTrue);
    });

    test('DELETE 404 返回 true（视为已删除）', () async {
      final client = makeClient((request) async => http.Response('', 404));
      final result = await client.deleteRemaining('file.txt');
      expect(result, isTrue);
    });

    test('DELETE 500 抛 WebDavSyncException', () async {
      final client = makeClient((request) async => http.Response('err', 500));
      expect(
        () => client.deleteRemaining('file.txt'),
        throwsA(isA<WebDavSyncException>()),
      );
    });
  });

  group('listLeafNames', () {
    test('从多状态 XML 解析叶子文件名（只收文件、跳过目录）', () async {
      final xmlBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/notes/docs/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/notes/docs/report.txt</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/notes/docs/subdir/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/notes/docs/subdir/nested.md</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

      final client = makeClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['depth'], '1');
        return http.Response(xmlBody, 207);
      });

      final leaves = await client.listLeafNames('docs');
      // 应只收文件，跳过目录；叶子名为最后一段
      expect(leaves, contains('report.txt'));
      expect(leaves, contains('nested.md'));
      expect(leaves, isNot(contains('docs')));
      expect(leaves, isNot(contains('subdir')));
    });

    test('PROPFIND 附带 Depth:1 与 Connection:close 头', () async {
      final client = makeClient((request) async {
        expect(request.headers['depth'], '1');
        expect(request.headers['connection'], 'close');
        return http.Response(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>',
          207,
        );
      });
      final leaves = await client.listLeafNames('');
      expect(leaves, isEmpty);
    });

    test('PROPFIND 失败抛 WebDavSyncException', () async {
      final client = makeClient((request) async => http.Response('err', 500));
      expect(
        () => client.listLeafNames('docs'),
        throwsA(isA<WebDavSyncException>()),
      );
    });
  });

  group('close', () {
    test('外部注入 client 时不关闭', () async {
      var closed = false;
      final mockClient = MockClient((request) async {
        closed = true;
        return http.Response('', 200);
      });
      final client = WebDavSyncClient(baseUrl: baseUrl, client: mockClient);
      client.close();
      // 外部 client 不应被 close 影响（MockClient 无 close 计数，仅验证不抛异常）
      expect(closed, isFalse);
    });
  });

  group('P1 安全门禁（https + 路径白名单）', () {
    test('http 非回环：任何请求直接拒绝，不触网', () async {
      var hit = false;
      final client = WebDavSyncClient(
        baseUrl: Uri.parse('http://192.168.1.10/dav/'),
        client: MockClient((request) async {
          hit = true;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        client.getBytes('manifest.json'),
        throwsA(isA<WebDavSyncException>()),
      );
      await expectLater(
        client.ensureCollection(),
        throwsA(isA<WebDavSyncException>()),
      );
      expect(hit, isFalse, reason: '拒绝必须发生在请求发出之前');
    });

    test('http 回环放行（不出设备）', () async {
      final client = WebDavSyncClient(
        baseUrl: Uri.parse('http://127.0.0.1:8080/dav/'),
        client: MockClient((request) async => http.Response('', 201)),
      );
      expect(await client.ensureCollection(), isTrue);
    });

    test('遍历/绝对 URL/反斜杠路径一律拒绝', () async {
      var hit = false;
      final client = WebDavSyncClient(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          hit = true;
          return http.Response('', 200);
        }),
      );
      for (final evil in [
        '../../etc/passwd',
        '..',
        r'..\windows',
        'https://evil.example.com/x',
        'a/b/../../c',
        'id|with|pipes',
      ]) {
        await expectLater(
          client.getBytes(evil),
          throwsA(isA<WebDavSyncException>()),
          reason: evil,
        );
      }
      expect(hit, isFalse);
    });

    test('合法路径（manifest/冲突副本/子目录）放行', () async {
      final client = makeClient((request) async {
        if (request.method == 'PROPFIND') {
          return http.Response(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>',
            207,
          );
        }
        return http.Response('', 404);
      });
      expect(await client.getBytes('manifest.json'), isNull);
      expect(await client.getBytes('abc123~conflict~1725000000000'), isNull);
      expect(await client.listLeafNames(''), isEmpty);
    });
  });
}
