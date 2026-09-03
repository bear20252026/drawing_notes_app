// WebDAV 同步传输客户端（P3-W2）。
// 纯 Dart，可注入 http.Client 便于单测。
// 提供 PROPFIND/GET/PUT/DELETE/MKCOL 基本操作 + Basic 认证。

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// WebDAV 同步异常。
class WebDavSyncException implements Exception {
  WebDavSyncException(this.message, {this.statusCode});

  /// 错误描述。
  final String message;

  /// HTTP 状态码（如有）。
  final int? statusCode;

  @override
  String toString() =>
      'WebDavSyncException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}

/// WebDAV 同步传输客户端。
///
/// 所有 HTTP 操作均通过可注入的 [http.Client] 执行，便于单测替换为
/// `http.MockClient`。外部传入的 client 不会被 [close] 释放。
class WebDavSyncClient {
  WebDavSyncClient({
    required this.baseUrl,
    http.Client? client,
    this.username = '',
    this.password = '',
  }) : _client = client,
       _ownsClient = client == null;

  /// WebDAV 集合根目录 URL。
  final Uri baseUrl;

  /// 认证用户名。
  final String username;

  /// 认证密码。
  final String password;

  /// HTTP 客户端（可注入）。
  final http.Client? _client;

  /// 是否由本类拥有 client（需 close 时释放）。
  final bool _ownsClient;

  /// 内部懒建的 client（仅当未注入时使用）。
  http.Client? _lazyClient;

  /// 获取或懒建 HTTP 客户端。
  http.Client get _activeClient {
    final injected = _client;
    if (injected != null) return injected;
    return _lazyClient ??= http.Client();
  }

  /// 是否已配置认证。
  bool get _hasAuth => username.isNotEmpty || password.isNotEmpty;

  /// 远端路径段白名单（P1 修复：默认 NoopSyncCipher 下 `remotePath=id`，
  /// `id="../../.."` 经 `baseUrl.resolve` 逃逸集合——遍历写/删）。
  /// 允许路由分隔 `/`；每段仅 `[A-Za-z0-9_.~\-]`（覆盖冲突副本 `~`）。
  static final RegExp _safeSegment = RegExp(r'^[A-Za-z0-9_.~\-]+$');

  /// 是否本地回环（http 仅在此放行——不出设备，无嗅探面）。
  static bool _isLoopback(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '[::1]';
  }

  /// 传输层 TLS 门禁（P1 修复）：非 https 一律拒绝（Basic 口令 + 文档
  /// 明文传输），本地回环 http 除外。fail-closed：抛异常，不发起请求。
  void _requireHttps() {
    final scheme = baseUrl.scheme.toLowerCase();
    if (scheme == 'https') return;
    if (scheme == 'http' && _isLoopback(baseUrl.host)) return;
    throw WebDavSyncException(
      '仅允许 https WebDAV（明文 http 会泄露认证口令与文档），本地回环除外',
    );
  }

  /// 安全解析远端路径：先过 TLS 门禁，再拒绝 `..`/反斜杠/绝对 URL/
  /// 非法字符，最后校验解析结果仍落在集合根下（防 resolve 逃逸）。
  Uri _resolve(String relativePath) {
    _requireHttps();
    for (final seg in relativePath.split('/')) {
      if (seg.isEmpty) continue;
      if (seg == '.' || seg == '..' || !_safeSegment.hasMatch(seg)) {
        throw WebDavSyncException('非法远端路径：$relativePath');
      }
    }
    final base = baseUrl.toString();
    final baseDir = base.endsWith('/') ? base : '$base/';
    final resolved = baseUrl.resolve(relativePath);
    final target = resolved.toString();
    if (target != base && !target.startsWith(baseDir)) {
      throw WebDavSyncException('远端路径逃逸集合根：$relativePath');
    }
    return resolved;
  }

  /// 生成 Basic 认证头。
  Map<String, String> get _authHeader {
    if (!_hasAuth) return {};
    final token = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $token'};
  }

  /// 确保集合存在（MKCOL）。
  ///
  /// - 201/200 → 创建成功，返回 true。
  /// - 405/301/409 → 已存在，返回 true。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<bool> ensureCollection() async {
    _requireHttps();
    final client = _activeClient;
    final request = http.Request('MKCOL', baseUrl);
    request.headers.addAll(_authHeader);
    final streamed = await client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return true;
    }
    if (response.statusCode == 405 ||
        response.statusCode == 301 ||
        response.statusCode == 409) {
      return true;
    }
    throw WebDavSyncException(
      'MKCOL failed: ${response.reasonPhrase}',
      statusCode: response.statusCode,
    );
  }

  /// 下载指定路径的文件字节。
  ///
  /// - 200/207 → 返回字节。
  /// - 404 → 返回 null。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<Uint8List?> getBytes(String relativePath) async {
    final client = _activeClient;
    final url = _resolve(relativePath);
    final response = await client.get(url, headers: _authHeader);

    if (response.statusCode == 200 || response.statusCode == 207) {
      return response.bodyBytes;
    }
    if (response.statusCode == 404) {
      return null;
    }
    throw WebDavSyncException(
      'GET failed: ${response.reasonPhrase}',
      statusCode: response.statusCode,
    );
  }

  /// 上传字节到指定路径（PUT）。
  ///
  /// - 201/204 → 成功。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<void> putBytes(
    String relativePath,
    List<int> bytes, {
    bool overwrite = true,
  }) async {
    final client = _activeClient;
    final url = _resolve(relativePath);
    final headers = <String, String>{
      ..._authHeader,
      if (!overwrite) 'If-None-Match': '*',
    };
    final response = await client.put(url, headers: headers, body: bytes);

    if (response.statusCode == 201 || response.statusCode == 204) {
      return;
    }
    throw WebDavSyncException(
      'PUT failed: ${response.reasonPhrase}',
      statusCode: response.statusCode,
    );
  }

  /// 删除指定路径的文件（DELETE）。
  ///
  /// - 204/404 → 成功（404 视为已删除）。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<bool> deleteRemaining(String relativePath) async {
    final client = _activeClient;
    final url = _resolve(relativePath);
    final response = await client.delete(url, headers: _authHeader);

    if (response.statusCode == 204 || response.statusCode == 404) {
      return true;
    }
    throw WebDavSyncException(
      'DELETE failed: ${response.reasonPhrase}',
      statusCode: response.statusCode,
    );
  }

  /// 列出指定路径下的叶子文件名（PROPFIND Depth:1）。
  ///
  /// 返回相对当前路径的叶子文件名（不含目录名与父路径）；
  /// 只收普通文件，跳过目录。失败返回空列表或抛异常。
  Future<List<String>> listLeafNames(String relativePath) async {
    final client = _activeClient;
    final url = _resolve(relativePath);

    final body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''';

    final request = http.Request('PROPFIND', url);
    request.headers.addAll({
      ..._authHeader,
      'Depth': '1',
      'Connection': 'close',
      'Content-Type': 'application/xml',
    });
    request.body = body;

    final streamed = await client.send(request);
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200 && resp.statusCode != 207) {
      throw WebDavSyncException(
        'PROPFIND failed: ${resp.reasonPhrase}',
        statusCode: resp.statusCode,
      );
    }

    return _parseLeafNames(resp.body, relativePath);
  }

  /// 从 PROPFIND 多状态 XML 中解析叶子文件名。
  List<String> _parseLeafNames(String xmlBody, String relativePath) {
    final document = XmlDocument.parse(xmlBody);
    // 按本地名查找（忽略命名空间前缀），递归遍历全部后代。
    final responses = _findElementsByLocalName(document, 'response');
    final leaves = <String>[];

    // 规范化相对路径前缀（用于剥离 href 中的父路径）。
    final normalizedBase = relativePath.endsWith('/')
        ? relativePath
        : '$relativePath/';

    for (final response in responses) {
      final href = _findElementsByLocalName(
        response,
        'href',
      ).firstOrNull?.innerText;
      if (href == null || href.isEmpty) continue;

      // 解析 resourcetype：含 <collection/> 则为目录，跳过。
      final resourceType = _findElementsByLocalName(
        response,
        'resourcetype',
      ).firstOrNull;
      final isCollection =
          resourceType != null &&
          _findElementsByLocalName(resourceType, 'collection').isNotEmpty;
      if (isCollection) continue;

      // 从 href 中剥离目录前缀，取叶子文件名。
      final leaf = _extractLeafName(href, normalizedBase);
      if (leaf != null && leaf.isNotEmpty) {
        leaves.add(leaf);
      }
    }

    return leaves;
  }

  /// 递归查找指定本地名的全部子元素（忽略命名空间前缀）。
  List<XmlElement> _findElementsByLocalName(XmlNode node, String localName) {
    final results = <XmlElement>[];
    for (final child in node.children) {
      if (child is XmlElement) {
        if (child.name.local == localName) {
          results.add(child);
        }
        results.addAll(_findElementsByLocalName(child, localName));
      }
    }
    return results;
  }

  /// 从 href 中剥离目录前缀，返回叶子文件名。
  String? _extractLeafName(String href, String normalizedBase) {
    // href 可能是绝对 URL 或相对路径；统一取路径部分。
    var path = href;
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      path = uri.path;
    }

    // 去掉 base 前缀。
    if (path.startsWith(normalizedBase)) {
      path = path.substring(normalizedBase.length);
    } else if (path.startsWith('/')) {
      // 尝试从末尾匹配。
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return segments.last;
      }
    }

    // 去掉末尾斜杠，取最后一段。
    path = path.replaceAll(RegExp(r'/+$'), '');
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? null : segments.last;
  }

  /// 释放内部资源（仅当 client 由本类拥有时关闭）。
  void close() {
    if (_ownsClient) {
      _lazyClient?.close();
      _lazyClient = null;
    }
  }
}
