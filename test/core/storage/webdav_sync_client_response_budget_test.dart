// DN-008 加固回归锁：WebDAV 响应体的「按用途分档 + 累计字节闸门」。
//
// 威胁模型（按加固口径，不是漏洞口径）：WebDAV 主机是**用户自己配置**的，
// 本闸门属于「远端不可信」的纵深防御——挡的是配错/被换的主机、中间设备或
// 恶意托管把无界响应灌进内存；不是远程可利用漏洞。
//
// 风格照抄 test/core/storage/webdav_sync_client_test.dart：手写 fake
// http.Client（MockClient / MockClient.streaming）注入，零网络。
// 正反两向都钉：超限确实被拦（且**边读边判**，不是整包入库后再判长度）/
// 正常规模不被误伤。

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/core/sync/sync_service.dart' show SyncService;

/// 慢速 dribble 源：一次只吐 [chunkSize] 字节，订阅被取消即停止生成。
/// [onPulled] 记录源实际产出多少字节——用它断言「闸门后没有整包入库」。
Stream<List<int>> _dribble(
  int totalBytes,
  int chunkSize,
  void Function(int bytes) onPulled,
) async* {
  var produced = 0;
  while (produced < totalBytes) {
    final n = math.min(chunkSize, totalBytes - produced);
    produced += n;
    onPulled(n);
    yield Uint8List(n);
  }
}

/// 捕获限额异常（不吞其他异常：其他异常本文件一律当失败）。
Future<WebDavResponseTooLargeException?> _captureTooLarge(
  Future<Object?> Function() body,
) async {
  try {
    await body();
    return null;
  } on WebDavResponseTooLargeException catch (e) {
    return e;
  }
}

void main() {
  final baseUrl = Uri.parse('https://dav.example.com/notes/');

  /// 整包假响应（MockClient 内部转成单块 ByteStream）。
  WebDavSyncClient mockBytes(
    List<int> body, {
    int status = 200,
    Map<WebDavResponseBudget, int>? caps,
  }) => WebDavSyncClient(
    baseUrl: baseUrl,
    client: MockClient((request) async => http.Response.bytes(body, status)),
    responseByteCaps: caps,
  );

  /// 分块流式假响应（可注入自报 Content-Length）。
  WebDavSyncClient mockStream(
    Stream<List<int>> Function() body, {
    int status = 200,
    int? declaredLength,
    Map<WebDavResponseBudget, int>? caps,
  }) => WebDavSyncClient(
    baseUrl: baseUrl,
    client: MockClient.streaming(
      (request, bodyStream) async =>
          http.StreamedResponse(body(), status, contentLength: declaredLength),
    ),
    responseByteCaps: caps,
  );

  group('档位常量与命名门禁', () {
    test('清单常量与 SyncService.manifestPath 同值（分档判定依赖它）', () {
      // 传输层按路径判档，路径常量与同步器必须一字不差——本用例是唯一
      // 允许 core/storage 与 core/sync 互相引用的地方（只在测试里）。
      expect(WebDavSyncClient.manifestPathName, SyncService.manifestPath);
    });

    test('各档默认上限锁定（阈值口径单点可审）', () {
      expect(WebDavResponseLimits.documentBytes, 16 * 1024 * 1024);
      expect(WebDavResponseLimits.manifestBytes, 4 * 1024 * 1024);
      expect(WebDavResponseLimits.propfindBytes, 4 * 1024 * 1024);
      expect(WebDavResponseLimits.controlBytes, 1024 * 1024);
      expect(WebDavResponseLimits.propfindMaxElements, 100000);
      expect(WebDavResponseLimits.propfindMaxDepth, 128);
      // 分档排序是设计口径：控制档最小、清单低于文档。
      expect(
        WebDavResponseLimits.controlBytes,
        lessThan(WebDavResponseLimits.manifestBytes),
      );
      expect(
        WebDavResponseLimits.manifestBytes,
        lessThan(WebDavResponseLimits.documentBytes),
      );
      expect(
        WebDavResponseLimits.maxBytesFor(WebDavResponseBudget.document),
        WebDavResponseLimits.documentBytes,
      );
    });
  });

  group('超限方向：拦截 + 取消订阅 + 不物化整包', () {
    test('清单档逐块累计越界：抛类型化错误，读到的字节不超过 cap+1', () async {
      const cap = 1024;
      const totalBytes = 1024 * 1024; // 1 MiB「清单」——远超上限
      var pulled = 0;
      final client = mockStream(
        () => _dribble(totalBytes, 1, (n) => pulled += n),
        caps: {WebDavResponseBudget.manifest: cap},
      );

      final thrown = await _captureTooLarge(
        () => client.getBytes('manifest.json'),
      );
      expect(thrown, isNotNull, reason: '超档必须被拦');
      expect(thrown!.budget, WebDavResponseBudget.manifest);
      expect(thrown.kind, WebDavResponseLimitKind.accumulatedBytes);
      expect(thrown.limit, cap);
      expect(
        thrown.observed,
        cap + 1,
        reason: '越界那一块只多拉 1 字节即停：不是先收完整包再判长度',
      );
      expect(thrown.statusCode, isNull);
      expect(pulled, lessThanOrEqualTo(cap + 1));
      // 订阅确实被取消：给源一点时间后产出不得增长。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        pulled,
        lessThanOrEqualTo(cap + 1),
        reason: 'cancel 之后一个字节都不该再被拉走',
      );
    });

    test('错误文案只含档位与数字，不外带 URL/正文（脱敏红线）', () async {
      const cap = 64;
      final marker = utf8.encode('secret-marker http://dav.example.com');
      final body = [for (var i = 0; i < cap * 4; i++) ...marker];
      final client = mockBytes(body, caps: {WebDavResponseBudget.document: cap});

      final thrown = await _captureTooLarge(() => client.getBytes('doc-1'));
      expect(thrown, isNotNull);
      expect(thrown!.budget, WebDavResponseBudget.document);
      expect(thrown.message, contains('document'));
      expect(thrown.message, contains('$cap'));
      expect(thrown.message, isNot(contains('secret-marker')));
      expect(thrown.message, isNot(contains('http')));
      expect(thrown.message, isNot(contains('dav.example.com')));
      expect(
        WebDavSyncException.isLocalGateMessage(thrown.message),
        isFalse,
        reason: '非白名单文案：UI 侧不得原样透出，只能走静态文案',
      );
    });

    test('自报 Content-Length 超档：快速失败通道，正文基本不读', () async {
      const cap = 512;
      var pulled = 0;
      final client = mockStream(
        () => _dribble(4096, 16, (n) => pulled += n),
        declaredLength: 4096,
        caps: {WebDavResponseBudget.document: cap},
      );

      final thrown = await _captureTooLarge(() => client.getBytes('doc-1'));
      expect(thrown, isNotNull);
      expect(thrown!.kind, WebDavResponseLimitKind.declaredContentLength);
      expect(thrown.limit, cap);
      expect(thrown.observed, 4096);
      expect(
        pulled,
        lessThanOrEqualTo(16),
        reason: '自报长度已越界：最多因取消订阅而漏进一个分块，不整包入库',
      );
    });

    test('谎报小 Content-Length 不放行：逐块累计闸门仍生效', () async {
      const cap = 256;
      var pulled = 0;
      final client = mockStream(
        () => _dribble(4096, 8, (n) => pulled += n),
        declaredLength: 8, // 远端谎报
        caps: {WebDavResponseBudget.document: cap},
      );
      final thrown = await _captureTooLarge(() => client.getBytes('doc-1'));
      expect(
        thrown,
        isNotNull,
        reason: '闸门信任的是累计计数器，不是自报长度',
      );
      expect(thrown!.kind, WebDavResponseLimitKind.accumulatedBytes);
      expect(pulled, lessThanOrEqualTo(cap + 8));
    });

    test('分档各自生效：同一路径规则下清单超限不影响文档', () async {
      final body = Uint8List(200);
      final client = WebDavSyncClient(
        baseUrl: baseUrl,
        client: MockClient((request) async => http.Response.bytes(body, 200)),
        responseByteCaps: {
          WebDavResponseBudget.manifest: 64,
          WebDavResponseBudget.document: 4096,
        },
      );
      final asManifest = await _captureTooLarge(
        () => client.getBytes('manifest.json'),
      );
      expect(asManifest, isNotNull);
      expect(asManifest!.budget, WebDavResponseBudget.manifest);
      expect(await client.getBytes('doc-1'), hasLength(200));
    });

    test('非载荷状态码降级到控制档（错误页不给文档级预算）', () async {
      final client = mockBytes(
        Uint8List(2000),
        status: 500,
        caps: {
          WebDavResponseBudget.document: 4096, // 文档档放宽：不该命中
          WebDavResponseBudget.control: 64, // 控制档收紧：应当命中
        },
      );
      final thrown = await _captureTooLarge(() => client.getBytes('doc-1'));
      expect(
        thrown,
        isNotNull,
        reason: 'GET 的 500 响应正文本端不消费，按控制档封顶',
      );
      expect(thrown!.budget, WebDavResponseBudget.control);
    });

    test('PROPFIND XML 深度闸门：字节档放行、深度档拒绝（爆栈防护）', () async {
      // 200 层嵌套 ≈ 3 KB，远低于默认 4 MiB 字节档 → 只能由结构闸门拦下。
      final deep = StringBuffer('<d:multistatus xmlns:d="DAV:">');
      for (var i = 0; i < 200; i++) {
        deep.write('<d:x>');
      }
      for (var i = 0; i < 200; i++) {
        deep.write('</d:x>');
      }
      deep.write('</d:multistatus>');
      final encoded = utf8.encode(deep.toString());
      expect(encoded.length, lessThan(WebDavResponseLimits.propfindBytes));
      final client = mockBytes(encoded, status: 207);

      final thrown = await _captureTooLarge(() => client.listLeafNames('docs'));
      expect(thrown, isNotNull);
      expect(thrown!.kind, WebDavResponseLimitKind.xmlDepth);
      expect(thrown.budget, WebDavResponseBudget.propfind);
      expect(thrown.limit, WebDavResponseLimits.propfindMaxDepth);
    });

    test('PROPFIND XML 元素数闸门：紧凑结构同样被拦', () async {
      // 12 万个自闭合元素 ≈ 600 KB，仍在 4 MiB 字节档内 → 由元素预算拦。
      final many = StringBuffer('<d:multistatus xmlns:d="DAV:">');
      for (var i = 0; i < 120000; i++) {
        many.write('<d:a/>');
      }
      many.write('</d:multistatus>');
      final encoded = utf8.encode(many.toString());
      expect(encoded.length, lessThan(WebDavResponseLimits.propfindBytes));
      final client = mockBytes(encoded, status: 207);

      final thrown = await _captureTooLarge(() => client.listLeafNames('docs'));
      expect(thrown, isNotNull);
      expect(thrown!.kind, WebDavResponseLimitKind.xmlElements);
      expect(thrown.observed, greaterThan(WebDavResponseLimits.propfindMaxElements));
    });
  });

  group('放行方向：限额内的正常规模不得被误伤', () {
    test('真实规模清单（5000 条快照 ≈ 400 KB）默认档照常返回', () async {
      final entries = <String, dynamic>{
        for (var i = 0; i < 5000; i++)
          'doc-$i': {'updatedAt': 1700000000000 + i, 'size': 4096},
      };
      final manifest = utf8.encode(jsonEncode({'entries': entries}));
      expect(manifest.length, lessThan(WebDavResponseLimits.manifestBytes));
      final client = mockBytes(manifest);
      expect(await client.getBytes('manifest.json'), hasLength(manifest.length));
    });

    test('1 MiB 文档密文（远低于 16 MiB 文档档）照常返回', () async {
      final doc = Uint8List(1024 * 1024);
      final client = mockBytes(doc);
      expect(await client.getBytes('doc-1'), hasLength(doc.length));
    });

    test('分块流式载荷在 cap 内：累计不越界即完整返回', () async {
      const cap = 4096;
      var pulled = 0;
      final client = mockStream(
        () => _dribble(cap - 16, 64, (n) => pulled += n),
        caps: {WebDavResponseBudget.manifest: cap},
      );
      final bytes = await client.getBytes('manifest.json');
      expect(bytes, hasLength(cap - 16));
      expect(pulled, cap - 16);
    });

    test('正常 PROPFIND（2000 个对象、深度 ≤6）照常解析叶子名', () async {
      final xml = StringBuffer('<d:multistatus xmlns:d="DAV:">');
      for (var i = 0; i < 2000; i++) {
        xml.write(
          '<d:response><d:href>/notes/docs/file-$i.dnv</d:href>'
          '<d:propstat><d:prop><d:resourcetype/></d:prop>'
          '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
        );
      }
      xml.write('</d:multistatus>');
      final encoded = utf8.encode(xml.toString());
      expect(encoded.length, lessThan(WebDavResponseLimits.propfindBytes));
      final client = mockBytes(encoded, status: 207);
      final leaves = await client.listLeafNames('docs');
      expect(leaves, hasLength(2000));
      expect(leaves, contains('file-1999.dnv'));
    });

    test('控制档小正文不改变既有状态码语义（限额异常不冒充 HTTP 错误）', () async {
      final created = mockBytes(utf8.encode('<html>created</html>'), status: 201);
      expect(await created.ensureCollection(), isTrue);
      final gone = mockBytes(utf8.encode('gone'), status: 204);
      expect(await gone.deleteRemaining('doc-1'), isTrue);
      await mockBytes(utf8.encode('ok'), status: 204).putBytes('doc-1', [1, 2, 3]);
      // 500 仍按 HTTP 语义抛 WebDavSyncException(500)：statusCode 必须还在。
      await expectLater(
        mockBytes(utf8.encode('boom'), status: 500).getBytes('doc-1'),
        throwsA(
          isA<WebDavSyncException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test('404 空正文照旧返回 null（闸门不改变缺文件语义）', () async {
      final client = mockBytes(const <int>[], status: 404);
      expect(await client.getBytes('manifest.json'), isNull);
    });
  });
}
