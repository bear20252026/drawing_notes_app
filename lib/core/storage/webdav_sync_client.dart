// WebDAV 同步传输客户端（P3-W2）。
// 纯 Dart，可注入 http.Client 便于单测。
// 提供 PROPFIND/GET/PUT/DELETE/MKCOL 基本操作 + Basic 认证。
// 重定向一律不跟随（3xx 判失败）：跟随会把 Basic 口令送到服务器指定的
// 下一跳，而 https 门禁只校验用户配置的 baseUrl——见 _newRequest。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:drawing_notes_app/core/utils/filename_sanitize.dart';

/// WebDAV 同步异常。
class WebDavSyncException implements Exception {
  WebDavSyncException(this.message, {this.statusCode});

  /// 错误描述。
  ///
  /// 注意：除下面两条门禁常量外，message 可能内嵌**远端可控文本**
  /// （reasonPhrase / relativePath）——UI 只能按
  /// [WebDavSyncException.isLocalGateMessage] 白名单透出，其余走静态文案。
  final String message;

  /// HTTP 状态码（如有）。
  final int? statusCode;

  /// 传输层 TLS 门禁文案（本地静态构造，不含任何远端内容）。
  static const String httpsGateMessage =
      '仅允许 https WebDAV（明文 http 会泄露认证口令与文档），本地回环除外';

  /// 重定向门禁文案（本地静态构造，**刻意不带 Location 值**——那是远端
  /// 可控文本，进 UI 即成注入面）。
  static const String redirectGateMessage =
      '服务器要求跳转到其他地址：为避免认证口令被转发到非授权站点，'
      '已停止跟随重定向。请在 WebDAV 服务端直接填写跳转后的最终地址';

  /// 白名单：只有**精确等于**本地静态门禁文案的 message 才允许原样透出到
  /// 用户界面。用全等而非 `contains('https')` 之类的关键词猜测——关键词
  /// 可被远端 reasonPhrase（例如 "Moved to https://…"）伪造，等于把任意
  /// 字符串送进 snackbar（脱敏违例）。
  static bool isLocalGateMessage(String message) =>
      message == httpsGateMessage || message == redirectGateMessage;

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
    this.operationTimeout = defaultOperationTimeout,
  }) : _client = client,
       _ownsClient = client == null;

  /// R-01（审计 2026-09-27）：单次 HTTP 操作超时。此前全链路无超时——
  /// 服务器挂起（半开连接/慢速响应）时 syncNow() 永不返回，设置页
  /// `_syncing` 永久转圈；且 humanizeWebDavSyncError 的 TimeoutException
  /// 分支因全链路无超时来源成为死分支。测试可注入更短窗口。
  static const Duration defaultOperationTimeout = Duration(seconds: 30);

  /// WebDAV 集合根目录 URL。
  final Uri baseUrl;

  /// 单次 HTTP 操作超时（覆盖请求发送与响应体读取全程）。
  final Duration operationTimeout;

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

  /// 给单次 HTTP await 套操作超时。超时抛 [TimeoutException]——设置页
  /// humanizer 已有该分支（「连不上服务器」），与 SocketException 同文案。
  Future<T> _withTimeout<T>(Future<T> future) =>
      future.timeout(operationTimeout);

  /// 远端路径段白名单（P1 修复：默认 NoopSyncCipher 下 `remotePath=id`，
  /// `id="../../.."` 经 `baseUrl.resolve` 逃逸集合——遍历写/删）。
  /// F10：规则收口到 core/utils/filename_sanitize.dart。
  static final RegExp _safeSegment = kSafeRemotePathSegment;

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
    throw WebDavSyncException(WebDavSyncException.httpsGateMessage);
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

  /// 构造单次请求：**恒定关闭自动跟随重定向**。
  ///
  /// P1 修复（重定向绕过 https 门禁）：`package:http` 的便捷方法
  /// （get/put/delete）内部建的 Request 默认 `followRedirects = true`，
  /// 于是配置的 https 地址一旦被服务器 302 到 http://attacker/，客户端会
  /// 自动跟随并把 `Authorization: Basic …` 明文送出去（回环 http 例外也被
  /// 顺着 Location 扩到非回环）。门禁只校验**配置**的 baseUrl，从不校验
  /// Location——所以正确做法是根本不发第二跳：跟随关死，3xx 判失败，
  /// 由 [_rejectRedirect] 提示用户去服务端填最终地址。
  /// 注入式 client（测试）同样收到 `followRedirects == false` 的请求。
  http.Request _newRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
  }) {
    final request = http.Request(method, url)..followRedirects = false;
    if (headers != null) request.headers.addAll(headers);
    return request;
  }

  /// 发送请求并读干响应体（两腿各自套操作超时，R-01 口径不变）。
  Future<http.Response> _send(http.Request request) async {
    final client = _activeClient;
    final streamed = await _withTimeout(client.send(request));
    return _withTimeout(http.Response.fromStream(streamed));
  }

  /// 3xx 一律判失败（不跟随、不解析 Location、不带远端文本）。
  ///
  /// 例外：MKCOL 的 301 由 [ensureCollection] 按「集合已存在」处理——那是
  /// 既有契约，且我们从不向 Location 重发，口令不外发；真正承载数据的
  /// GET/PUT/DELETE/PROPFIND 走到同一个跳转时仍会命中这里。
  void _rejectRedirect(http.Response response) {
    final code = response.statusCode;
    if (code >= 300 && code < 400) {
      throw WebDavSyncException(
        WebDavSyncException.redirectGateMessage,
        statusCode: code,
      );
    }
  }

  /// 确保集合存在（MKCOL）。
  ///
  /// - 201/200 → 创建成功，返回 true。
  /// - 405/301/409 → 已存在，返回 true。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<bool> ensureCollection() async {
    _requireHttps();
    final request = _newRequest('MKCOL', baseUrl, headers: _authHeader);
    final response = await _send(request);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return true;
    }
    if (response.statusCode == 405 ||
        response.statusCode == 301 ||
        response.statusCode == 409) {
      return true;
    }
    _rejectRedirect(response);
    throw WebDavSyncException(
      'MKCOL failed: ${response.reasonPhrase}',
      statusCode: response.statusCode,
    );
  }

  /// 下载指定路径的文件字节。
  ///
  /// - 200/207 → 返回字节。
  /// - 404 → 返回 null。
  /// - 3xx → 抛重定向门禁异常（不跟随）。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<Uint8List?> getBytes(String relativePath) async {
    final url = _resolve(relativePath);
    final response = await _send(
      _newRequest('GET', url, headers: _authHeader),
    );
    _rejectRedirect(response);

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
  /// - 3xx → 抛重定向门禁异常（绝不把文档与口令带到第二跳）。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<void> putBytes(
    String relativePath,
    List<int> bytes, {
    bool overwrite = true,
  }) async {
    final url = _resolve(relativePath);
    final headers = <String, String>{
      ..._authHeader,
      if (!overwrite) 'If-None-Match': '*',
    };
    final request = _newRequest('PUT', url, headers: headers)
      ..bodyBytes = Uint8List.fromList(bytes);
    final response = await _send(request);
    _rejectRedirect(response);

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
  /// - 3xx → 抛重定向门禁异常（不跟随）。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<bool> deleteRemaining(String relativePath) async {
    final url = _resolve(relativePath);
    final response = await _send(
      _newRequest('DELETE', url, headers: _authHeader),
    );
    _rejectRedirect(response);

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
    final url = _resolve(relativePath);

    final body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''';

    final request = _newRequest('PROPFIND', url, headers: {
      ..._authHeader,
      'Depth': '1',
      'Connection': 'close',
      'Content-Type': 'application/xml',
    });
    request.body = body;
    final response = await _send(request);
    _rejectRedirect(response);

    if (response.statusCode != 200 && response.statusCode != 207) {
      throw WebDavSyncException(
        'PROPFIND failed: ${response.reasonPhrase}',
        statusCode: response.statusCode,
      );
    }

    return _parseLeafNames(response.body, relativePath);
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
