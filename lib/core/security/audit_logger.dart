import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/utils/constant_time.dart' as ct;

/// 安全审计日志（红蓝攻防 P2 修复 2026-08-15 + 哈希链强化 2026-08-16）：
/// 记录密钥加载/密码盘操作（时间戳 + 操作 + 结果），**绝不含密钥与内容**
/// （防审计日志本身成为泄露面——去敏）。
///
/// 哈希链（对应专家目标架构里的 tamper-evident「审计事件流」——Thalian
/// verify_audit_chain / Revka Merkle 链 / 掘金 Layer 6 权威模式）：每条记录含
/// prevHash（前一条哈希）+ 自身 SHA-256 哈希——任何字段篡改立即断链，
/// verifyIntegrity() 重放检出。
///
/// **保证等级（M-05 加固 2026-11-14）**：本链升级为**带密钥 HMAC-SHA256 锚**。
/// 审计锚密钥（32B CSPRNG）独立生成、持久化于 `<数据根>/security/audit.anchor`
/// （0600，**与主密钥 MK 不同源**——审计日志在解锁前即记录，且不得把 MK 暴露给
/// 日志层）。每条记录的 `hash = HMAC-SHA256(锚密钥, 世代号|prevHash|载荷)`，
/// 世代号（generation）随锚密钥持久化、每进程启动 +1 并落一条 `audit.genesis`
/// 世代标记。由此：
/// - 篡改字段 / 删除插入段中条目 → HMAC 不符或断链，立即检出（同旧链）；
/// - **整链重算 / 整段删除 / 跨段拼接** → 攻击者无锚密钥无法重算 HMAC；世代号
///   单调递增且经 HMAC 绑定，删段/拼段会使世代序列断裂而被 [_verifyFileChain]
///   检出。拿到文件写权限但**未拿到锚密钥**的攻击者不再能无痕重算。
/// - 残余边界（如实）：锚密钥与日志同盘，若攻击者**同时**取得锚密钥与文件写
///   权限，仍可整链重算——彻底防篡改需外部追加锚（远端哈希回执/异步签名收据），
///   属下一步能力，本批未实现。旧无密钥条目（无 `mac` 字段）仍按 SHA-256 校验，
///   保证升级前历史可读。
///
/// 落盘（2026-10-10，挂账轻项）：每条记录同步进内存链、异步追加写
/// `<数据根>/security/audit.log`（JSONL，含链字段），超 1 MiB 轮转为
/// audit.log.1（保留一代）。追加失败**静默吞掉**——审计永不阻断业务；内存链
/// 仍是权威实时视图。`flutter test` 环境默认**不落盘**（FLUTTER_TEST 护栏——
/// 测试不得污染用户真实数据根），测试经 [sinkOverrideForTest] 注入临时目录。
///
/// **文件侧回读重放（2026-11-10，M-05 升级 2026-11-14）**：[verifyIntegrity]
/// 同时重放内存链与落盘文件（`audit.log.1` + `audit.log`）——进程重启后的历史
/// 参与校验。带锚密钥的条目按 HMAC + 世代号校验（整段删除/跨段拼接会因世代
/// 序列断裂被检出）；旧无密钥条目按 SHA-256 校验。保证等级见文件头。
class AuditLogger {
  AuditLogger._();

  static final List<_AuditEntry> _entries = [];

  /// 审计记录内存上限（链 10 修复 2026-08-15）：长期会话高频操作防
  /// 无限增长（保留最近 [_maxEntries] 条）。
  static const int _maxEntries = 1000;

  /// 哈希链 genesis 种子（Revka 模式——固定零种子——链起点）。
  /// （final：运行期计算——const 求值不支持 String 乘法。）
  static final String _genesisHash = '0' * 64;

  static String _lastHash = _genesisHash;

  /// 滚动裁剪后的链起点锚（checkpoint）：被丢弃尾部之后、当前首条的
  /// prevHash。verifyIntegrity 的**内存链**从此处而非 genesis 重放——否则一旦
  /// 裁剪过就恒报「已篡改」（裁剪条目仍是新首条的 prevHash，genesis 重放必断）。
  /// 文件链不需要这个锚：追加行按写入顺序成链、连续性由行序保证，且进程重启
  /// 后新链从 genesis 重新起（见 [_verifyFileChain] 的多段口径）。轮转只保留
  /// 一代（`audit.log` + `audit.log.1`，再轮转即覆盖上一代）。
  static String _anchorPrevHash = _genesisHash;

  /// 累计被丢弃条数（内存内 checkpoint 分量；文件侧按行序追加、轮转只留一代，
  /// 见上）。
  static int _droppedCount = 0;

  // ==== 带密钥锚（M-05 加固 2026-11-14） ====

  /// 审计锚密钥（32B CSPRNG，HMAC-SHA256 用）。**与主密钥 MK 不同源**：
  /// 审计在解锁前即记录，且日志层不得持有 MK。首次落盘时生成并持久化于
  /// `<数据根>/security/audit.anchor`（0600）；未落盘（测试/未解析）时为 null，
  /// 此时条目退回无密钥 SHA-256（内存链仍 tamper-evident）。
  static Uint8List? _anchorKey;

  /// 当前世代号：每进程启动 +1，随锚密钥持久化。HMAC 载荷含世代号，文件侧
  /// 校验世代单调递增——整段删除/跨段拼接会使世代序列断裂而被检出。
  static int _generation = 0;

  /// 锚密钥/世代是否已加载（或本进程已新建）。同步 log() 据此决定走 HMAC
  /// 还是退回 SHA-256。加载是同步的（锚文件极小）；生产路径由组合根异步预热
  /// [warmUpAnchor]，测试注入临时 sink 时首次 log() 同步加载。
  static bool _anchorLoaded = false;

  /// 测试注入锚密钥文件（null = 用默认 sink 同目录）。
  static File? _anchorFileOverrideForTest;

  // ==== 落盘（2026-10-10） ====

  /// 落盘文件大小上限：超过即轮转为 audit.log.1（保留一代，再轮转即覆盖）。
  static const int _maxFileBytes = 1 << 20;

  /// 测试注入口：轮转阈值（生产恒 null 走 [_maxFileBytes]；与
  /// `AppLockService.testPinKdfOverride`、`LockExemption.ttlOverrideForTest`
  /// 同一先例——测试需要把物理量级压进假时钟/短用例可达范围）。
  @visibleForTesting
  static int? maxFileBytesOverrideForTest;

  /// 生产落盘文件解析器（可注入；null = 不落盘）。默认走数据根 security/
  /// （异步解析——securityFile 本身是 Future）。测试环境（FLUTTER_TEST）
  /// 默认不落盘——护栏防污染真实数据根。
  static Future<File> Function()? _sinkResolver;
  static bool _resolverChecked = false;

  /// 最近一次解析到的落盘 [File]（[_verifyFileChain] 同步回读用）。
  ///
  /// 落盘解析器是 async 的（默认 `AppDataRoot.securityFile`），而
  /// [verifyIntegrity] 是**同步** API（设置页诊断导出在异步回调里同步调用）——
  /// 无法在同步方法里等待 Future。故首次落盘拿到 [File] 后缓存于此，之后的
  /// [verifyIntegrity] 可同步回读；测试经 [sinkOverrideForTest] 注入时同步可见。
  static File? _sinkFileCache;

  /// 写入顺序链：log() 是同步 API，文件追加异步化后靠此链保序；
  /// 任一失败不断链（catchError 继续）。
  static Future<void> _writeChain = Future<void>.value();

  /// 测试注入临时落盘文件（null = 关闭落盘）。配合 [flushForTest] 等待
  /// 追加完成、[resetSinkForTest] 用例间复位。
  @visibleForTesting
  static set sinkOverrideForTest(File? file) {
    _sinkResolver = file == null ? null : () async => file;
    _sinkFileCache = file;
    _resolverChecked = true;
  }

  /// 等待全部在途文件追加完成（测试断言前用）。
  @visibleForTesting
  static Future<void> flushForTest() => _writeChain;

  /// 用例间复位 sink 注入与写链（不动内存链——clear 负责那个）。
  @visibleForTesting
  static void resetSinkForTest() {
    _sinkResolver = null;
    _sinkFileCache = null;
    _resolverChecked = true;
    maxFileBytesOverrideForTest = null;
    _writeChain = Future<void>.value();
  }

  static Future<File> Function()? _resolveSink() {
    if (!_resolverChecked) {
      _resolverChecked = true;
      final inTests = Platform.environment.containsKey('FLUTTER_TEST');
      if (!inTests) {
        _sinkResolver = () async {
          final root = AppDataRoot();
          return root.securityFile('audit.log');
        };
      }
    }
    return _sinkResolver; // 解析期失败在追加腿兜底（审计永不阻断业务）。
  }

  /// 异步追加一条 JSONL（保序、静默失败、超限轮转）。
  ///
  /// M-05：锚加载与世代标记都在同步 log() 内完成（见 [_ensureAnchorLoaded] /
  /// [_appendGenesisMarker]），本方法只负责把已定稿的条目异步落盘（保序）。
  /// 条目自带模式：锚就绪后的条目带 `gen`+`mac`（HMAC），之前的走 SHA-256。
  static void _enqueueAppend(_AuditEntry e) {
    final resolver = _resolveSink();
    if (resolver == null) return;
    final line = jsonEncode({
      'time': e.time,
      'operation': e.operation,
      'success': e.success,
      if (e.detail != null) 'detail': e.detail,
      'prevHash': e.prevHash,
      'hash': e.hash,
      if (e.gen != null) 'gen': e.gen,
      if (e.mac != null) 'mac': e.mac,
    });
    _writeChain = _writeChain.catchError((_) {}).then((_) async {
      final File sink;
      try {
        sink = await resolver();
      } catch (_) {
        return; // 解析失败 = 本次不落盘。
      }
      // 缓存供 verifyIntegrity 同步回读（解析 async、校验 sync 的桥）。
      _sinkFileCache = sink;
      try {
        final parent = sink.parent;
        if (!parent.existsSync()) await parent.create(recursive: true);
        // 轮转：超阈值 → audit.log.1（覆盖上一代）。best-effort。
        final threshold = maxFileBytesOverrideForTest ?? _maxFileBytes;
        if (sink.existsSync() && sink.lengthSync() > threshold) {
          final rotated = File('${sink.path}.1');
          if (rotated.existsSync()) await rotated.delete();
          await sink.rename(rotated.path);
        }
        await sink.writeAsString(
          '$line\n',
          mode: FileMode.append,
          flush: false,
        );
        // M3 修复（2026-11-11）：审计日志含安全事件记录，落盘后收紧到
        // 0600（仅属主可读写）。chmod 失败静默——加固不阻断业务。
        await AppDataRoot.tightenFilePermissions(sink);
      } catch (_) {
        // 落盘失败静默——审计绝不阻断业务（内存链不受影响）。
      }
    });
  }

  /// 记录一次安全操作：operation 为操作名（如 'password_disk.read_key'），
  /// success 标识结果，detail 为补充说明（**禁止传密钥/内容**）。
  static void log(String operation, {bool success = true, String? detail}) {
    // M-05：首次记录且有落盘 sink 时同步加载锚（锚文件极小，同步 IO 可忽略；
    // 测试注入 sink 同步可见，生产由组合根 warmUpAnchor 异步预热）。加载成功
    // 即落一条世代标记，本条及后续条目走 HMAC。
    _ensureAnchorLoadedSync();
    _appendEntry(operation, success: success, detail: detail);
  }

  /// 组合根预热入口（异步）：应用启动时解析数据根并加载锚密钥，使首条审计
  /// 记录即带 HMAC。失败静默（审计永不阻断业务）。
  static Future<void> warmUpAnchor() async {
    try {
      final resolver = _resolveSink();
      if (resolver == null) return;
      final sink = await resolver();
      _sinkFileCache = sink;
      _ensureAnchorLoadedSync();
    } catch (_) {
      // 预热失败 → 首次 log() 再尝试（仍失败则退回 SHA-256）。
    }
  }

  /// 追加一条记录到内存链并落盘（log 与世代标记共用——保证链尾顺序一致）。
  static void _appendEntry(
    String operation, {
    bool success = true,
    String? detail,
  }) {
    final time = DateTime.now().toIso8601String();
    final prevHash = _lastHash;
    final key = _anchorKey;
    // M-05：锚就绪 → HMAC-SHA256(锚, 世代|prevHash|载荷)；未就绪 → 无密钥
    // SHA-256。skylos: ignore —— 运行时计算值非常量。
    final String hash;
    int? gen;
    String? mac;
    if (key != null) {
      gen = _generation;
      mac = _hmac(
        key,
        _macPayload(gen, prevHash, time, operation, success, detail),
      );
      hash = mac;
    } else {
      hash = _sha256(_payload(time, operation, success, detail, prevHash));
    }
    final entry = _AuditEntry(
      time: time,
      operation: operation,
      success: success,
      detail: detail,
      prevHash: prevHash,
      hash: hash,
      gen: gen,
      mac: mac,
    );
    _entries.add(entry);
    _lastHash = hash;
    _enqueueAppend(entry);
    if (_entries.length > _maxEntries) {
      final drop = _entries.length - _maxEntries;
      _entries.removeRange(0, drop);
      // checkpoint：新链起点 = 裁剪后首条的 prevHash（即被丢弃尾部的末条 hash）。
      _droppedCount += drop;
      _anchorPrevHash = _entries.first.prevHash;
    }
  }

  /// 同步加载/新建锚密钥并推进世代，随后经 [_appendEntry] 链尾追加一条
  /// `audit.genesis` 世代标记（内存/文件顺序一致）。只执行一次；失败退回
  /// 无密钥 SHA-256（审计永不阻断业务）。
  ///
  /// 锚文件 JSON：`{"key": base64(32B), "gen": int}`。存在则读出密钥与上次
  /// 世代号，本进程世代 = 上次 + 1；不存在则 CSPRNG 新建、世代 = 1。世代标记
  /// HMAC 绑定世代号——文件侧据此校验世代单调，整段删除/跨段拼接会断裂。
  ///
  /// 同步 IO 说明：锚文件 <100B，读写各一次，开销可忽略；换取 log() 同步语义
  /// 下锚即刻就绪（避免异步加载窗口内条目漏签）。生产路径组合根 [warmUpAnchor]
  /// 已在启动时异步预热，正常运行期 log() 命中已加载态、不再触发 IO。
  static void _ensureAnchorLoadedSync() {
    if (_anchorLoaded) return;
    final sink = _sinkFileCache;
    if (sink == null) return; // sink 未解析（生产首条前未预热）→ 暂不加载。
    _anchorLoaded = true;
    try {
      final anchorFile = _resolveAnchorFileSync(sink);
      Uint8List key;
      int prevGen = 0;
      if (anchorFile.existsSync()) {
        final doc = jsonDecode(anchorFile.readAsStringSync());
        if (doc is Map<String, dynamic> && doc['key'] is String) {
          key = Uint8List.fromList(base64Decode(doc['key'] as String));
          prevGen = doc['gen'] is int ? doc['gen'] as int : 0;
        } else {
          key = _randomAnchorKey();
        }
      } else {
        key = _randomAnchorKey();
      }
      if (key.length != 32) key = _randomAnchorKey(); // 畸形 → 重建（fail-safe）。
      _anchorKey = key;
      _generation = prevGen + 1;
      // 持久化新世代（原子写：tmp + rename，同步）。
      final parent = anchorFile.parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);
      final tmp = File('${anchorFile.path}.tmp');
      tmp.writeAsStringSync(
        jsonEncode({'key': base64Encode(key), 'gen': _generation}),
        flush: true,
      );
      tmp.renameSync(anchorFile.path);
      // 世代标记：链尾追加（此时 _anchorKey 已就绪 → 走 HMAC）。
      _appendEntry('audit.genesis', detail: 'generation=$_generation');
    } catch (_) {
      _anchorKey = null; // 加载失败退回 SHA-256（审计永不阻断业务）。
    }
  }

  // ==== M-05 带密钥锚：HMAC / 随机 ====

  /// 锚密钥文件（默认与落盘 sink 同目录的 audit.anchor——生产即数据根
  /// security/，测试注入临时 sink 时锚也落临时目录，不污染真实数据根）。
  static File _resolveAnchorFileSync(File sink) {
    final injected = _anchorFileOverrideForTest;
    if (injected != null) return injected;
    return File('${sink.parent.path}/audit.anchor');
  }

  /// 32B CSPRNG 锚密钥。
  static Uint8List _randomAnchorKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
  }

  /// HMAC-SHA256 载荷：世代号|prevHash|时间|操作|结果|详情。
  static String _macPayload(
    int gen,
    String prevHash,
    String time,
    String operation,
    bool success,
    String? detail,
  ) =>
      '$gen|${_payload(time, operation, success, detail, prevHash)}';

  /// HMAC-SHA256（hex）。
  static String _hmac(Uint8List key, String input) =>
      Hmac(sha256, key).convert(utf8.encode(input)).toString();

  /// 当前审计记录快照（只读，供 UI/调试查看——display 格式兼容旧版）。
  static List<String> snapshot() =>
      List.unmodifiable(_entries.map((e) => e.display));

  /// 哈希链完整性验证（Thalian verify_audit_chain / 掘金 verify_integrity
  /// 模式）：**内存链 + 落盘文件链**两段分别重放——prevHash 链接 + 重算哈希
  /// ——任何字段篡改立即检出。内存链从当前链真实起点（_anchorPrevHash，未裁剪
  /// 时即 genesis）重放，滚动裁剪后不再假装从 genesis 起（否则正常运行的长
  /// 会话日志被误判为已篡改）。
  ///
  /// **校验范围（消费方必须如实转达——`DiagnosticsExporter` / 设置页诊断报告
  /// 的「通过」只意味着下面这一句）**：
  /// - 内存链：本进程保留的最近 ≤[_maxEntries]（1000）条；
  /// - 文件链：本进程已解析到落盘 sink 后写出的 `audit.log.1` + `audit.log`
  ///   （含进程重启前的历史；多段独立链，段内严格连续）。
  /// - 边界：全新进程在**首次 `log()` 之前**无法同步解析 async 落盘路径
  ///   （本方法是同步 API），此时文件侧跳过、只校验内存链（通常首次 log 即
  ///   触发解析，之后文件侧纳入校验）。落盘文件不存在 = 无内容可校验。
  /// - 保证等级（M-05）：带锚条目走 HMAC + 世代单调——无锚密钥的攻击者无法
  ///   整链重算/整段删除/跨段拼接；旧无密钥条目仍 SHA-256（升级前历史）。
  ///   残余边界：锚密钥与日志同盘，同时取得两者仍可重算（见文件头）。
  static bool verifyIntegrity() {
    // M-05：落盘 sink 已就绪时以**文件链为权威**——文件是持久记录，进程重启
    // 后内存链从 genesis 重新起，不应拿重置后的内存链去否定历史文件。内存链
    // 仅在无落盘（纯内存/测试）时兜底校验。
    if (_sinkFileCache != null) return _verifyFileChain();
    return _verifyMemoryChain();
  }

  // ==== 外部追加锚（M-05 残余边界补强，2026-11-15） ====

  /// 导出**外部锚凭据**：当前世代号 + 文件链尾哈希 + 条目计数。
  ///
  /// 用途：把这份凭据存到**独立介质**（另一台设备 / 打印 / 密码管理器备注），
  /// 事后用 [verifyAgainstExternalAnchor] 比对。由此覆盖 M-05 的残余边界——
  /// 「攻击者同时拿到锚密钥与文件写权限」时虽能整链重算，但**重算后的尾哈希
  /// 与世代号不可能与外部凭据吻合**（外部凭据不在其控制范围内）。
  ///
  /// 返回 null 表示当前无从导出（锚未加载 / 落盘未解析 / 无内容）。
  /// **凭据本身不含密钥**（只有 HMAC 结果与计数），可安全外传/打印。
  static Map<String, Object?>? exportExternalAnchor() {
    final sink = _sinkFileCache;
    if (sink == null || _anchorKey == null) return null;
    final tail = _fileChainTail();
    if (tail == null) return null;
    return {
      'v': 1,
      'generation': _generation,
      'tailHash': tail.$1,
      'entryCount': tail.$2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// 用外部锚凭据校验当前落盘链是否仍包含导出时那一条历史。
  ///
  /// **判据（哈希锚定，2026-11-15 实测定案）**：
  /// - 链上存在**哈希等于凭据尾哈希**的条目 → `true`：该条历史仍在且未被改写
  ///   （HMAC 输入含全部前缀载荷，重算者无法伪造这个值）。**这是本机制的核心
  ///   价值**：整链重算后必然找不到原哈希。
  /// - 找不到 → `null`：**无从判定**。因为「找不到」有两种可能且落盘信息不足
  ///   以区分：①该历史被改写/删除（真篡改）；②该历史已被日志轮转丢弃（正常
  ///   业务）。**宁可报「无从判定」也不谎报 false 或 true。**
  /// - 凭据格式非法 → `false`（这是确定的无效输入，不是判定歧义）。
  /// - 未落盘 / 锚未加载 / 读失败 / 坏行 → `null`。
  ///
  /// **三条实测教训（勿再走回头路，均已验证失败）**：
  /// 1. **按位置序号定位**：轮转是整文件搬移（`sink.rename(.1)`），`.1` 会被
  ///    新一代覆盖，「第 N 条」轮转后已是另一条记录 → 误判。
  /// 2. **条目计数下界**：轮转后剩余总数可能仍**大于**凭据计数（实测凭据 2
  ///    条、轮转后剩 4 条）→ 误判。
  /// 3. **世代号覆盖**：同一世代内也会多次轮转，世代号无法标识「这段历史是否
  ///    还在盘上」→ 误判。
  ///
  /// **消费方必须如实转达**：`null` 不等于「通过」，也不等于「被篡改」——它
  /// 意味着「凭据已过期或历史异常，请重新导出凭据」。要缩小这个歧义窗口，
  /// 需要**不轮转的归档段**或**外部存档**，属下一步能力。
  static bool? verifyAgainstExternalAnchor(Map<String, Object?> anchor) {
    final sink = _sinkFileCache;
    if (sink == null || _anchorKey == null) return null;
    final gen = anchor['generation'];
    final tailHash = anchor['tailHash'];
    final count = anchor['entryCount'];
    if (gen is! int || tailHash is! String || count is! int || count < 1) {
      return false; // 凭据格式非法（确定的无效输入）。
    }
    final found = _scanFileChainForHash(tailHash);
    if (found == null) return null; // 读失败/坏行 → 无从判定。
    // 命中 → 历史完好；未命中 → 篡改 or 轮转丢弃，落盘信息不足以区分。
    return found ? true : null;
  }

  /// 扫描落盘链查找 [target] 哈希是否命中。
  /// 读失败或坏行返回 null（无从判定，不谎报）。
  static bool? _scanFileChainForHash(String target) {
    final sink = _sinkFileCache;
    if (sink == null) return null;
    var found = false;
    for (final file in [File('${sink.path}.1'), sink]) {
      if (!file.existsSync()) continue;
      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        return null;
      }
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final map = _decodeLine(line);
        if (map == null) return null;
        final h = map['hash'];
        if (h is! String) return null;
        if (ct.constantTimeEquals(h, target)) found = true;
      }
    }
    return found;
  }

  /// 文件链尾哈希与总条目数（跨 audit.log.1 + audit.log）。
  static (String, int)? _fileChainTail() {
    final sink = _sinkFileCache;
    if (sink == null) return null;
    String? last;
    var n = 0;
    for (final file in [File('${sink.path}.1'), sink]) {
      if (!file.existsSync()) continue;
      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        return null;
      }
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final map = _decodeLine(line);
        if (map == null) return null;
        final h = map['hash'];
        if (h is! String) return null;
        last = h;
        n++;
      }
    }
    if (last == null || n == 0) return null;
    return (last, n);
  }

  /// 解析一行 JSONL（坏行返回 null）。
  static Map<String, dynamic>? _decodeLine(String line) {
    try {
      final decoded = jsonDecode(line);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// 内存链重放（从 [_anchorPrevHash] 起）。按条目自带模式重算：带 mac 走
  /// HMAC（需锚密钥），否则 SHA-256（旧条目/锚未就绪）。
  static bool _verifyMemoryChain() {
    var prev = _anchorPrevHash;
    for (final e in _entries) {
      // 链接断裂（删除/插入中间记录）——哈希是秘密值，走恒定时间比较。
      if (!ct.constantTimeEquals(e.prevHash, prev)) return false;
      if (!_entryHashMatches(e.mac, e.gen, e.time, e.operation, e.success,
          e.detail, e.prevHash, e.hash)) {
        return false; // 哈希不符（字段被篡改）。
      }
      prev = e.hash;
    }
    return true;
  }

  /// 按条目模式重算哈希并比对：[mac] 非空 → HMAC（锚密钥须在），否则 SHA-256。
  static bool _entryHashMatches(
    String? mac,
    int? gen,
    String time,
    String operation,
    bool success,
    String? detail,
    String prevHash,
    String hash,
  ) {
    // 时序侧信道收口（2026-11-15）：秘密值（HMAC / 摘要）比较一律走恒定
    // 时间工具，禁止裸 ==（短路返回会让逐字符猜解可计时）。
    if (mac != null) {
      final key = _anchorKey;
      if (key == null || gen == null) return false; // 带 mac 却无锚 → 不可信。
      return ct.constantTimeEquals(
        hash,
        _hmac(key, _macPayload(gen, prevHash, time, operation, success, detail)),
      );
    }
    return ct.constantTimeEquals(
      hash,
      _sha256(_payload(time, operation, success, detail, prevHash)),
    );
  }

  /// 文件侧回读重放：读 `audit.log.1`（轮转前代）+ `audit.log`（当前），
  /// 逐行按条目模式重算哈希（HMAC/SHA-256）并核对 prevHash 链接。
  ///
  /// M-05：带 `gen`+`mac` 的条目走 HMAC 校验，且**世代号单调不减**——每进程
  /// 启动落一条 `audit.genesis` 世代标记（世代 +1）。整段删除/跨段拼接会使
  /// 世代序列出现缺口或回退而被检出（无锚密钥无法伪造合法 HMAC 世代标记）。
  /// 旧无密钥条目（无 mac）按 SHA-256 校验、不参与世代约束（升级前历史）。
  /// sink 未解析时跳过。坏行/读失败一律 fail-closed 判为不完整。
  static bool _verifyFileChain() {
    final sink = _sinkFileCache;
    if (sink == null) return true;
    var prev = _genesisHash;
    var lastGen = 0; // 已见最大世代号（单调约束）。
    for (final file in [File('${sink.path}.1'), sink]) {
      if (!file.existsSync()) continue;
      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } catch (_) {
        return false; // 读失败 = 无法确认完整性（fail-closed）。
      }
      for (final line in lines) {
        if (line.trim().isEmpty) continue; // 容忍尾部空行。
        final Map<String, dynamic> map;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) return false;
          map = decoded;
        } catch (_) {
          return false; // 坏行 = 篡改/损坏。
        }
        final time = map['time'];
        final operation = map['operation'];
        final success = map['success'];
        final detail = map['detail'];
        final prevHash = map['prevHash'];
        final hash = map['hash'];
        final mac = map['mac'];
        final gen = map['gen'];
        if (time is! String ||
            operation is! String ||
            success is! bool ||
            (detail != null && detail is! String) ||
            prevHash is! String ||
            hash is! String ||
            (mac != null && mac is! String) ||
            (gen != null && gen is! int)) {
          return false;
        }
        // 段中断链（删除/插入）——哈希是秘密值，走恒定时间比较。
        if (!ct.constantTimeEquals(prevHash, prev) &&
            !ct.constantTimeEquals(prevHash, _genesisHash)) {
          return false;
        }
        if (!_entryHashMatches(mac as String?, gen as int?, time, operation,
            success, detail as String?, prevHash, hash)) {
          return false; // 哈希不符（字段被篡改）。
        }
        // 世代单调：带 mac 的条目世代号不得回退（整段删除/拼接会破坏单调）。
        if (mac != null) {
          final g = gen as int;
          if (g < lastGen) return false; // 世代回退 = 删段/拼段。
          lastGen = g;
        }
        prev = hash;
      }
    }
    return true;
  }

  static String _payload(
    String time,
    String operation,
    bool success,
    String? detail,
    String prevHash,
  ) =>
      '$prevHash|$time|$operation|${success ? 'OK' : 'FAIL'}'
      '${detail != null ? '|$detail' : ''}';

  static String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// 累计被丢弃条数（仅测试观测 checkpoint 锚点是否生效——非生产 API）。
  @visibleForTesting
  static int get droppedCountForTest => _droppedCount;

  /// 仅供测试：篡改第 [index] 条留存记录的 detail 而**保留旧 hash**——模拟
  /// 真实篡改者无法重算链，verifyIntegrity 重算必不匹配。非生产路径。
  @visibleForTesting
  static void tamperEntryForTest(int index, {String detail = 'TAMPERED'}) {
    final e = _entries[index];
    _entries[index] = _AuditEntry(
      time: e.time,
      operation: e.operation,
      success: e.success,
      detail: detail,
      prevHash: e.prevHash,
      hash: e.hash,
      gen: e.gen,
      mac: e.mac,
    );
  }

  /// 清空审计记录（测试用——重置哈希链）。
  ///
  /// 语义：整条链归零——anchor 回到 genesis、dropped 归 0。clear 之后重放是
  /// 一条**全新的独立链**（首条 prevHash = genesis），不会与被裁剪/清空前的
  /// 历史续接，故无法把「新链」伪造成「历史连续」。生产路径从不调用 clear
  /// （仅测试 setUp 使用）。
  static void clear() {
    _entries.clear();
    _lastHash = _genesisHash;
    _anchorPrevHash = _genesisHash;
    _droppedCount = 0;
    // M-05：锚状态归零（测试间隔离；生产从不调用 clear）。
    _anchorKey = null;
    _generation = 0;
    _anchorLoaded = false;
    _anchorFileOverrideForTest = null;
  }

  /// 测试注入锚密钥文件（null = 用默认 sink 同目录）。配合 [clear] 隔离。
  @visibleForTesting
  static set anchorFileOverrideForTest(File? file) {
    _anchorFileOverrideForTest = file;
  }

  /// 当前世代号（仅测试观测——非生产 API）。
  @visibleForTesting
  static int get generationForTest => _generation;

  /// 锚密钥是否已就绪（仅测试观测——非生产 API）。
  @visibleForTesting
  static bool get anchorLoadedForTest => _anchorKey != null;
}

/// 审计记录（含哈希链字段——prevHash 链接前一条 + hash 自身完整性）。
/// M-05：带密钥条目另含 [gen]（世代号）与 [mac]（HMAC-SHA256）；旧条目两者为 null。
class _AuditEntry {
  _AuditEntry({
    required this.time,
    required this.operation,
    required this.success,
    required this.detail,
    required this.prevHash,
    required this.hash,
    this.gen,
    this.mac,
  });

  final String time;
  final String operation;
  final bool success;
  final String? detail;
  final String prevHash;
  String hash;
  int? gen;
  String? mac;

  /// 展示格式（兼容旧版 snapshot：`[time] operation OK/FAIL detail`）。
  String get display =>
      '[$time] $operation ${success ? 'OK' : 'FAIL'}'
      '${detail != null ? ' $detail' : ''}';
}
