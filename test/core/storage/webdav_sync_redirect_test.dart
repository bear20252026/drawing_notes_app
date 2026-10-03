// P1 修复回归锁（审计 2026-10）：跟随重定向 = https 门禁旁路。
//
// 客户端必须：①每个请求都关闭自动跟随；②3xx 判失败并只给静态脱敏文案
// （不解析 Location、不把远端文本带进异常 message）；③**绝不发出第二跳**，
// 因此 Basic 口令不可能被带到用户没配过的站点（回环例外也不得被扩出去）。
//
// 两条路径都要覆盖：注入式 MockClient（单测口径）与真实 IOClient +
// 本地回环 HTTP 服务器（生产口径，验证 dart:io 真的没跟随）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';

/// 记录每一次「离开客户端」的请求（含 method/url/headers/followRedirects）。
class _Recorder {
  final List<http.Request> requests = [];

  MockClient client(int status, {String? location}) =>
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          '',
          status,
          headers: {'location': ?location},
          reasonPhrase: 'Found',
        );
      });

  int get count => requests.length;
  Uri? get firstUrl => requests.isEmpty ? null : requests.first.url;
}

void main() {
  // 刻意不装 TestWidgetsFlutterBinding：binding 会把 HttpClient 劫持成
  // 400，本文件要用真实回环 HTTP 验证生产 client 的跟随行为。
  final baseUrl = Uri.parse('https://good.example.com/notes/');
  const attacker = 'http://attacker.example.com/steal';

  group('注入式 client：3xx 不跟随、不带 Authorization 出第二跳', () {
    test('GET 302 → http 目标：抛重定向门禁、只有 1 个请求、无第二跳', () async {
      final rec = _Recorder();
      final client = WebDavSyncClient(
        baseUrl: baseUrl,
        client: rec.client(302, location: attacker),
        username: 'alice',
        password: 'secret',
      );

      WebDavSyncException? caught;
      try {
        await client.getBytes('manifest.json');
      } on WebDavSyncException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.statusCode, 302);
      // 脱敏：本地静态门禁文案，绝不含远端给的 Location。
      expect(caught.message, WebDavSyncException.redirectGateMessage);
      expect(caught.message, isNot(contains('attacker')));
      expect(caught.message, isNot(contains('http://')));
      // 关键断言①：只有一个请求，Location 目标从未被访问 ⇒ 没有第二跳。
      expect(rec.count, 1);
      expect(
        rec.requests.every((r) => r.url.toString().contains('good.example.com')),
        isTrue,
        reason: '口令只发给用户配置的那个 https 站点',
      );
      // 关键断言②：唯一那次请求发往用户配置的 https 站点（口令只给它）。
      expect(rec.firstUrl, baseUrl.resolve('manifest.json'));
    });

    test('五个方法（MKCOL/GET/PUT/DELETE/PROPFIND）全部 followRedirects = false', () async {
      final rec = _Recorder();
      // 各方法返回自己的成功码，确保跑到「成功路径」也要带上新请求。
      final okClient = MockClient((request) async {
        rec.requests.add(request);
        switch (request.method) {
          case 'MKCOL':
            return http.Response('', 201);
          case 'GET':
            return http.Response.bytes(const [1, 2], 200);
          case 'PUT':
            return http.Response('', 201);
          case 'DELETE':
            return http.Response('', 204);
          default:
            return http.Response(
              '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>',
              207,
            );
        }
      });
      final client = WebDavSyncClient(
        baseUrl: baseUrl,
        client: okClient,
        username: 'alice',
        password: 'secret',
      );
      await client.ensureCollection();
      await client.getBytes('a.txt');
      await client.putBytes('a.txt', [1, 2, 3]);
      await client.deleteRemaining('a.txt');
      await client.listLeafNames('docs');

      expect(
        rec.requests.map((r) => r.method).toSet(),
        {'MKCOL', 'GET', 'PUT', 'DELETE', 'PROPFIND'},
      );
      for (final r in rec.requests) {
        expect(
          r.followRedirects,
          isFalse,
          reason: '${r.method} 必须关掉自动跟随',
        );
      }
    });

    test('PUT 307 / DELETE 308 同样判失败（写/删不跨站点重放）', () async {
      final putRec = _Recorder();
      final putClient = WebDavSyncClient(
        baseUrl: baseUrl,
        client: putRec.client(307, location: attacker),
        username: 'alice',
        password: 'secret',
      );
      await expectLater(
        putClient.putBytes('a.txt', [1]),
        throwsA(isA<WebDavSyncException>()),
      );
      expect(putRec.count, 1);

      final delRec = _Recorder();
      final delClient = WebDavSyncClient(
        baseUrl: baseUrl,
        client: delRec.client(308, location: attacker),
        username: 'alice',
        password: 'secret',
      );
      await expectLater(
        delClient.deleteRemaining('a.txt'),
        throwsA(isA<WebDavSyncException>()),
      );
      expect(delRec.count, 1);
    });

    test('PROPFIND 302 走重定向门禁（而不是带远端 reasonPhrase 的裸文本）', () async {
      final rec = _Recorder();
      final client = WebDavSyncClient(
        baseUrl: baseUrl,
        client: rec.client(302, location: attacker),
        username: 'alice',
        password: 'secret',
      );
      await expectLater(
        client.listLeafNames('docs'),
        throwsA(
          isA<WebDavSyncException>().having(
            (e) => e.message,
            'message',
            WebDavSyncException.redirectGateMessage,
          ),
        ),
      );
      expect(rec.count, 1);
    });

    test('回环 http 例外不被扩展：Location 指向别处也不跟随', () async {
      final rec = _Recorder();
      final client = WebDavSyncClient(
        baseUrl: Uri.parse('http://127.0.0.1:8080/dav/'),
        client: rec.client(302, location: 'http://10.0.0.9/dav/'),
        username: 'alice',
        password: 'secret',
      );
      await expectLater(
        client.getBytes('manifest.json'),
        throwsA(isA<WebDavSyncException>()),
      );
      expect(rec.count, 1);
      expect(rec.requests.single.url.toString(), contains('127.0.0.1'));
    });

    test('门禁文案白名单：远端 reasonPhrase 无法冒充本地文案', () {
      expect(
        WebDavSyncException.isLocalGateMessage(
          WebDavSyncException.httpsGateMessage,
        ),
        isTrue,
      );
      expect(
        WebDavSyncException.isLocalGateMessage(
          WebDavSyncException.redirectGateMessage,
        ),
        isTrue,
      );
      // 含 https 字样的远端文本一律不透出（旧实现靠 contains 猜，会被绕过）。
      expect(
        WebDavSyncException.isLocalGateMessage(
          'GET failed: move to https://attacker.example.com/',
        ),
        isFalse,
      );
      expect(WebDavSyncException.isLocalGateMessage('非法远端路径：a'), isFalse);
    });
  });

  group('生产 client（真实 IOClient + 本地回环服务器）', () {
    test('302 到另一台回环服务器：目标一台请求都收不到 ⇒ 口令没出第二跳', () async {
      var trapHits = 0;
      var originHits = 0;
      final trap = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      trap.listen((req) async {
        trapHits++;
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
      });
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin.listen((req) async {
        originHits++;
        // 恶意/误配的服务器：把客户端支到另一个端口（同一台机器、换个站点）。
        req.response
          ..statusCode = HttpStatus.movedTemporarily
          ..headers.set('location', 'http://127.0.0.1:${trap.port}/steal');
        await req.response.close();
      });
      addTearDown(() async {
        await origin.close(force: true);
        await trap.close(force: true);
      });

      final client = WebDavSyncClient(
        baseUrl: Uri.parse('http://127.0.0.1:${origin.port}/dav/'),
        username: 'alice',
        password: 'secret',
        operationTimeout: const Duration(seconds: 5),
      );
      addTearDown(client.close);

      await expectLater(
        client.getBytes('manifest.json'),
        throwsA(
          isA<WebDavSyncException>()
              .having((e) => e.statusCode, 'statusCode', HttpStatus.movedTemporarily)
              .having(
                (e) => e.message,
                'message',
                WebDavSyncException.redirectGateMessage,
              ),
        ),
      );
      expect(originHits, 1);
      // 真正的判据：重定向目标从未被请求过。
      expect(trapHits, 0);
    });

    test('非回环 http 配置仍在请求前就被拒（门禁 fail-closed）', () async {
      final client = WebDavSyncClient(
        baseUrl: Uri.parse('http://192.168.1.20/dav/'),
        username: 'alice',
        password: 'secret',
      );
      addTearDown(client.close);
      await expectLater(
        client.getBytes('manifest.json'),
        throwsA(
          isA<WebDavSyncException>().having(
            (e) => e.message,
            'message',
            WebDavSyncException.httpsGateMessage,
          ),
        ),
      );
    });
  });
}
