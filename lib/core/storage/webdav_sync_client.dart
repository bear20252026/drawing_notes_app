// WebDAV 同步传输客户端（P3-W2）。
// 纯 Dart，可注入 http.Client 便于单测。
// 提供 PROPFIND/GET/PUT/DELETE/MKCOL 基本操作 + Basic 认证。
// 重定向一律不跟随（3xx 判失败）：跟随会把 Basic 口令送到服务器指定的
// 下一跳，而 https 门禁只校验用户配置的 baseUrl——见 _newRequest。
// 响应体按用途分档设累计字节闸门（DN-008 纵深加固）：边读边累计，
// 超限即取消订阅，绝不「先全收下再判长度」。

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

/// 条件写入失败（412 Precondition Failed）——DN-104。
///
/// 语义：本次 PUT 带了 `If-Match: <ETag>`，而远端在我们读取之后已被**别的
/// 设备**改过。这不是网络故障，而是「必须重新读取 → 合并 → 重试」的信号，
/// 调用方（SyncService）据此做有界重试，绝不能把它当成普通失败吞掉——
/// 吞掉就等于放弃对方的清单更新。
class WebDavPreconditionFailedException extends WebDavSyncException {
  WebDavPreconditionFailedException(String message, {int? statusCode})
    : super(message, statusCode: statusCode);
}

/// 带版本标识的 GET 结果（DN-104）。
class WebDavFetch {
  const WebDavFetch({required this.bytes, this.etag});

  /// 响应体。
  final Uint8List bytes;

  /// 远端 ETag；服务器未返回时为 null（= 不支持条件写入）。
  final String? etag;
}

/// 响应体的用途档位（DN-008 加固）：不同档位的载荷性质差别很大，
/// 一刀切的上限要么误伤合法大文档、要么挡不住 dribble 型错误响应，
/// 故按用途分档。
enum WebDavResponseBudget {
  /// 同步清单 `manifest.json`：纯元数据（每个文档一条快照）。
  manifest,

  /// 单个文档的线上字节（AES-GCM 封装后的块文档 JSON，或 Noop 明文）。
  document,

  /// PROPFIND 多状态 XML 列表。
  propfind,

  /// 控制类响应（MKCOL/PUT/DELETE、3xx/4xx/5xx，以及任何本端不消费正文的
  /// 状态码）：正文只用于 reasonPhrase 之外的调试，从不解析。
  control,
}

/// 超限的类型（错误文案里只出现档位名/类型名/数字，不出现任何远端原文）。
enum WebDavResponseLimitKind {
  /// 逐块累计字节数越过档位上限。
  accumulatedBytes,

  /// 响应自报的 Content-Length 已超上限（快速失败通道；该值由远端
  /// 自报、可以谎报，因此不参与安全判定，真闸门是逐块累计计数器）。
  declaredContentLength,

  /// PROPFIND XML 元素总数超结构预算。
  xmlElements,

  /// PROPFIND XML 嵌套深度超结构预算（递归遍历爆栈防护）。
  xmlDepth,
}

/// 各档默认上限（DN-008 加固）。
///
/// 数值全部锚在本仓既有同类预算上，不新造量级：
/// - [documentBytes]：`EncryptionService._maxEncryptedInputBytes = 10 MiB`
///   是本仓对「一个待封装载荷」的既有封顶。同步线格式是 base64-in-JSON
///   （`AesSyncCipher` 的 `{"n","c","m"}` 封装），base64 膨胀 4/3 ⇒
///   10 MiB 明文 ≈ 13.4 MiB 密文，向上取整到 **16 MiB**，保证自家合法
///   上传永远读得回来（不误伤），同时仍是远端自报体量的硬上限。
/// - [manifestBytes]：清单条目 ≈90 字节（docId + updatedAt + size），
///   **4 MiB** ≈ 3 万条快照——参照 `AuditLogger._maxFileBytes = 1 MiB`
///   的「纯 JSON 账本」量级放大一档，给多设备长期增长留余量，且始终
///   低于单文档档（清单不该是集合里最大的对象）。
/// - [propfindBytes]：每个 `<d:response>` 块约 200–300 字节，**4 MiB**
///   ≈ 1.5 万个远端对象；对齐 `SvgPreflight.maxBytes`（5 MiB）的 XML
///   预检量级并略低。
/// - [controlBytes]：对齐 `AuditLogger._maxFileBytes = 1 MiB`。真实服务器
///   的错误页在 KB 级，而这类正文本端从不解析——闸门只为堵住
///   「对 PUT 回一个 GB 级正文」这类拖延/灌内存行为。
/// - [propfindMaxElements] / [propfindMaxDepth]：XML 结构预算。深度参照
///   `SvgPreflight.maxNestingDepth = 128`（爆栈防护，`_findElementsByLocalName`
///   是递归的）；元素数参照 `SvgPreflight.maxElements = 5000` 的形态，但
///   「目录列表」每对象约 5 个元素，按列目录用途放大到 10 万元素
///   （≈2 万对象，正常场景由字节档先命中）。
class WebDavResponseLimits {
  const WebDavResponseLimits._();

  static const int documentBytes = 16 * 1024 * 1024;
  static const int manifestBytes = 4 * 1024 * 1024;
  static const int propfindBytes = 4 * 1024 * 1024;
  static const int controlBytes = 1024 * 1024;

  static const int propfindMaxElements = 100000;
  static const int propfindMaxDepth = 128;

  /// 档位 → 累计字节上限（实例可用 `responseByteCaps` 覆写，生产恒走这里）。
  static int maxBytesFor(WebDavResponseBudget budget) => switch (budget) {
    WebDavResponseBudget.manifest => manifestBytes,
    WebDavResponseBudget.document => documentBytes,
    WebDavResponseBudget.propfind => propfindBytes,
    WebDavResponseBudget.control => controlBytes,
  };
}

/// 响应超过本端限额（DN-008 加固）。
///
/// 威胁模型（按加固口径，不是漏洞口径）：WebDAV 主机是**用户自己配置**的，
/// 本闸门属于「远端不可信」的纵深防御——防的是配错/被换的主机、中间设备
/// 或恶意托管把无界响应灌进内存，不是远程可利用的缺陷。
///
/// 继承 [WebDavSyncException] 以便既有 `on WebDavSyncException` 分支照常
/// 收敛（设置页 humanizer 走静态文案）。message 全为本地构造：只有档位名、
/// 限额类型与两个数字，**不含 URL、头部、正文或任何远端文本**（脱敏红线）。
class WebDavResponseTooLargeException extends WebDavSyncException {
  WebDavResponseTooLargeException({
    required this.budget,
    required this.kind,
    required this.limit,
    required this.observed,
  }) : super(
    '远端响应超过本端限额（档位 ${budget.name}·${kind.name}，'
    '上限 $limit，实测 $observed），已中止读取',
    statusCode: null,
  );

  /// 超限的用途档位（本地枚举名，非远端可控）。
  final WebDavResponseBudget budget;

  /// 触发的限额类型。
  final WebDavResponseLimitKind kind;

  /// 该档上限（字节数或结构计数，随 [kind] 口径）。
  final int limit;

  /// 实测值（字节数或结构计数）。
  final int observed;
}

/// 读体的有界累计器（DN-008）。
///
/// 单独成类只为一件事：**整轮读取**共用一个 [_withTimeout] 截止期，
/// 而不是「每个分块 30s」——后者会让慢速 dribble 服务器把连接无限期
/// 吊住，等于把 R-01 既有超时保护改松。超时后要能取消源订阅，故把
/// 迭代器持有在对象里。
class _BoundedBodyRead {
  _BoundedBodyRead(this.stream);

  final Stream<List<int>> stream;

  StreamIterator<List<int>>? _iterator;

  /// 累计读取，越过 [maxBytes] 立刻取消订阅并抛
  /// [WebDavResponseTooLargeException]；内存封顶 ≈ `maxBytes + 一个分块`。
  Future<Uint8List> run({
    required int maxBytes,
    required WebDavResponseBudget budget,
  }) async {
    final iterator = StreamIterator<List<int>>(stream);
    _iterator = iterator;
    final collected = BytesBuilder(copy: true);
    var received = 0;
    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        if (chunk.isEmpty) continue;
        if (received + chunk.length > maxBytes) {
          await iterator.cancel();
          throw WebDavResponseTooLargeException(
            budget: budget,
            kind: WebDavResponseLimitKind.accumulatedBytes,
            limit: maxBytes,
            observed: received + chunk.length,
          );
        }
        received += chunk.length;
        collected.add(chunk);
      }
      return collected.takeBytes();
    } finally {
      // 正常结束 / 超限 / 流错误 / 外层超时都会走到这里：源必须被取消，
      // 否则「取消订阅」只是说说而已，剩余字节仍会被拉进内存。
      await iterator.cancel();
    }
  }

  /// 外层超时后收尾（`run` 的 finally 此时还挂在 await 上，取消即解锁）。
  Future<void> abort() async {
    final iterator = _iterator;
    if (iterator == null) return;
    await iterator.cancel();
  }
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
    this.responseByteCaps,
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

  /// 各档响应体字节上限的**测试注入口**（生产恒 null → 走
  /// [WebDavResponseLimits] 的档位常量）。与本仓既有形态一致：
  /// `operationTimeout` 可注入更短窗口、`AuditLogger.maxFileBytesOverrideForTest`、
  /// `AesSyncCipher.isolateThreshold` 同理——常量口径不改，只是让「超限
  /// 确实被拦 / 正常规模不被误伤」两条相反断言能压在小数值上验证。
  final Map<WebDavResponseBudget, int>? responseByteCaps;

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
    // DN-106（专家审计 2026-10-12）：解析必须用**规范化后的目录型 URI**。
    // 此前用原始 baseUrl 解析：当用户填的是 `https://dav.example.com/notes`
    // （无尾斜杠）时，URI 相对解析把 `notes` 当作文件名，`manifest.json` 被
    // 解析到上一级目录，随后被下面的逃逸校验错误拒绝 ⇒ 合法的 WebDAV 地址
    // 无法同步。这不是路径穿越（校验本身是好的），而是正常输入被误拒。
    final resolved = Uri.parse(baseDir).resolve(relativePath);
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

  /// 清单固定名（`SyncService.manifestPath` 同值，漂移由
  /// webdav_sync_client_response_budget_test 的门禁用例钉住）。
  /// 用途分档靠它区分「清单」与「文档密文」——同步侧调用点
  /// （`getBytes(manifestPath)` / `getBytes(remotePath(id))`）不带档位参数，
  /// 传输层必须自己按路径判定预算。
  static const String manifestPathName = 'manifest.json';

  /// 该相对路径对应的载荷档位：清单档 vs 文档密文档。
  WebDavResponseBudget _payloadBudgetFor(String relativePath) =>
      relativePath == manifestPathName
      ? WebDavResponseBudget.manifest
      : WebDavResponseBudget.document;

  /// 本实例生效的档位上限（覆写优先，缺省取常量）。
  int _capFor(WebDavResponseBudget budget) =>
      responseByteCaps?[budget] ?? WebDavResponseLimits.maxBytesFor(budget);

  /// 本端会消费正文的状态码（其余状态码一律降级到 [control] 档：
  /// 错误页 / 重定向页 / MKCOL-PUT-DELETE 回执的正文从不解析，
  /// 没必要给它文档级的内存预算）。
  static bool _isPayloadStatus(int statusCode) =>
      statusCode == 200 || statusCode == 207;

  /// 发送请求并**有界**读干响应体（两腿各自套操作超时，R-01 口径不变）。
  ///
  /// 旧写法 `http.Response.fromStream(streamed)` 把整包一次性拉进内存、
  /// 没有任何字节闸门（DN-008）；现在改为一边读一边累计，越过该档上限
  /// 立刻取消订阅并抛 [WebDavResponseTooLargeException]。
  /// 超时截止期覆盖**整轮读体**（不是每个分块 30s），语义与修复前一致。
  Future<http.Response> _send(
    http.Request request, {
    required WebDavResponseBudget budget,
  }) async {
    final client = _activeClient;
    final streamed = await _withTimeout(client.send(request));
    final bodyBudget = _isPayloadStatus(streamed.statusCode)
        ? budget
        : WebDavResponseBudget.control;
    final body = await _readBodyBounded(streamed, bodyBudget);
    // 与 http.Response.fromStream 逐字段等值（contentLength 取实际读到的
    // 字节数，仍是 Response.bytes 的既有口径）。
    return http.Response.bytes(
      body,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  /// 有界读取响应体：先过「自报 Content-Length」快速失败通道，再逐块累计。
  Future<Uint8List> _readBodyBounded(
    http.StreamedResponse response,
    WebDavResponseBudget budget,
  ) async {
    final maxBytes = _capFor(budget);
    // 快速失败通道：Content-Length 由远端自报、可谎报，所以它**只能让它
    // 更早被拒，不能作为放行依据**，也不是安全判定的一部分（真闸门在下面
    // 的逐块累计计数器）。
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      // 订阅后立即取消：既不再取字节，也不把源晾在那里（不消费会让底层
      // 连接滞留）。取消失败不掩盖限额判定本身。
      try {
        await response.stream.listen(null).cancel();
      } catch (_) {
        // 忽略：限额判定已经成立，取消只是收尾动作，不得掩盖它。
      }
      throw WebDavResponseTooLargeException(
        budget: budget,
        kind: WebDavResponseLimitKind.declaredContentLength,
        limit: maxBytes,
        observed: declared,
      );
    }
    final read = _BoundedBodyRead(response.stream);
    try {
      return await _withTimeout(
        read.run(maxBytes: maxBytes, budget: budget),
      );
    } on Object {
      // 超时（或其他中断）：整轮读取被放弃，源订阅必须当场取消，
      // 否则「超限即取消订阅」在超时这条腿上只是空话。
      await read.abort();
      rethrow;
    }
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
    final response = await _send(
      request,
      budget: WebDavResponseBudget.control,
    );

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
  /// - 响应体超过该路径用途档位的累计字节上限 → 抛
  ///   [WebDavResponseTooLargeException]（读一半即取消订阅）。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<Uint8List?> getBytes(String relativePath) async {
    final url = _resolve(relativePath);
    final response = await _send(
      _newRequest('GET', url, headers: _authHeader),
      budget: _payloadBudgetFor(relativePath),
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
  /// 带版本标识的 GET（DN-104）。
  ///
  /// 与 [getBytes] 的唯一差别是**同时带回远端 ETag**：调用方据此做条件写入
  /// （`If-Match`），避免多设备并发时「最后写入者覆盖」丢掉对方的清单更新。
  ///
  /// 服务器**未返回 ETag** 时 `etag` 为 null —— 这是「不支持条件写入」的信号，
  /// 调用方据此退回无条件 PUT。不能假设所有 WebDAV 服务端行为相同。
  Future<WebDavFetch?> fetchBytes(String relativePath) async {
    final url = _resolve(relativePath);
    final response = await _send(
      _newRequest('GET', url, headers: _authHeader),
      budget: _payloadBudgetFor(relativePath),
    );
    _rejectRedirect(response);

    if (response.statusCode == 200 || response.statusCode == 207) {
      final raw = response.headers['etag'];
      return WebDavFetch(
        bytes: response.bodyBytes,
        etag: (raw == null || raw.trim().isEmpty) ? null : raw.trim(),
      );
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
  /// - 412 → 抛 [WebDavPreconditionFailedException]（条件写入失败：读取之后
  ///   远端已被别的设备改过）。DN-104。
  /// - 3xx → 抛重定向门禁异常（绝不把文档与口令带到第二跳）。
  /// - 其他 → 抛 [WebDavSyncException]。
  Future<void> putBytes(
    String relativePath,
    List<int> bytes, {
    bool overwrite = true,
    String? ifMatch,
  }) async {
    final url = _resolve(relativePath);
    final headers = <String, String>{
      ..._authHeader,
      if (!overwrite) 'If-None-Match': '*',
      // DN-104：条件更新。带上读取时拿到的 ETag；远端在此期间被别的设备改过
      // 就返回 412，从而不覆盖对方的清单更新。ifMatch 为 null（服务器不给
      // ETag）时退化为无条件写——兼容不支持条件写入的服务端。
      if (ifMatch != null) 'If-Match': ifMatch,
    };
    final request = _newRequest('PUT', url, headers: headers)
      ..bodyBytes = Uint8List.fromList(bytes);
    final response = await _send(
      request,
      budget: WebDavResponseBudget.control,
    );
    _rejectRedirect(response);

    if (response.statusCode == 201 || response.statusCode == 204) {
      return;
    }
    if (response.statusCode == 412) {
      throw WebDavPreconditionFailedException(
        'PUT 条件失败：远端清单已被其他设备更新',
        statusCode: 412,
      );
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
      budget: WebDavResponseBudget.control,
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
    final response = await _send(
      request,
      budget: WebDavResponseBudget.propfind,
    );
    _rejectRedirect(response);

    if (response.statusCode != 200 && response.statusCode != 207) {
      throw WebDavSyncException(
        'PROPFIND failed: ${response.reasonPhrase}',
        statusCode: response.statusCode,
      );
    }

    return _parseLeafNames(response.body, relativePath);
  }

  /// PROPFIND 多状态 XML 的**结构**闸门（字节闸门之后的第二道，两者不可
  /// 互相替代）：字节上限管的是「读进来多少」，这里管的是「解析成多少节点、
  /// 嵌多深」。深度是刚需——[_findElementsByLocalName] 是递归实现，几百层
  /// 嵌套的合法 XML 就足以爆栈（进程级崩溃，比 OOM 更难看）。
  /// 遍历用显式栈迭代，自身不会先于被检查对象崩掉。
  void _guardXmlStructure(XmlDocument document) {
    var elements = 0;
    final pending = <(XmlNode, int)>[(document, 0)];
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (depth > WebDavResponseLimits.propfindMaxDepth) {
        throw WebDavResponseTooLargeException(
          budget: WebDavResponseBudget.propfind,
          kind: WebDavResponseLimitKind.xmlDepth,
          limit: WebDavResponseLimits.propfindMaxDepth,
          observed: depth,
        );
      }
      for (final child in node.children) {
        if (child is! XmlElement) continue;
        elements++;
        if (elements > WebDavResponseLimits.propfindMaxElements) {
          throw WebDavResponseTooLargeException(
            budget: WebDavResponseBudget.propfind,
            kind: WebDavResponseLimitKind.xmlElements,
            limit: WebDavResponseLimits.propfindMaxElements,
            observed: elements,
          );
        }
        pending.add((child, depth + 1));
      }
    }
  }

  /// 从 PROPFIND 多状态 XML 中解析叶子文件名。
  List<String> _parseLeafNames(String xmlBody, String relativePath) {
    final document = XmlDocument.parse(xmlBody);
    _guardXmlStructure(document);
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
