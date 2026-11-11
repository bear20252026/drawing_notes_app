import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

/// 安全审计日志（红蓝攻防 P2 修复 2026-08-15 + 哈希链强化 2026-08-16）：
/// 记录密钥加载/密码盘操作（时间戳 + 操作 + 结果），**绝不含密钥与内容**
/// （防审计日志本身成为泄露面——去敏）。
///
/// 哈希链（对应专家目标架构里的 tamper-evident「审计事件流」——Thalian
/// verify_audit_chain / Revka Merkle 链 / 掘金 Layer 6 权威模式）：每条记录含
/// prevHash（前一条哈希）+ 自身 SHA-256 哈希——任何字段篡改立即断链，
/// verifyIntegrity() 重放检出。
///
/// **保证等级（口径以代码为准，勿再对外写成防篡改）**：本链是**无密钥**
/// SHA-256（`_sha256` 直接哈希载荷，既非 HMAC 也非签名），所以只提供
/// **篡改可检测（tamper-evident）**保证，不构成防篡改（tamper-proof）——拿到
/// 文件写权限的攻击者可以从任意位置整链重算，事后无从分辨。要把保证等级提上去，
/// 需要**带密钥的日志段（HMAC / 签名链）**或**外部追加锚（append-only anchor、
/// 异步签名收据、远端哈希回执）**；这是能力升级、业主尚未裁决，本文件**刻意
/// 不实现**。
///
/// 落盘（2026-10-10，挂账轻项）：每条记录同步进内存链、异步追加写
/// `<数据根>/security/audit.log`（JSONL，含链字段），超 1 MiB 轮转为
/// audit.log.1（保留一代）。追加失败**静默吞掉**——审计永不阻断业务；内存链
/// 仍是权威实时视图。`flutter test` 环境默认**不落盘**（FLUTTER_TEST 护栏——
/// 测试不得污染用户真实数据根），测试经 [sinkOverrideForTest] 注入临时目录。
///
/// **文件侧回读重放（2026-11-10）**：[verifyIntegrity] 现在同时重放内存链与
/// 落盘文件（`audit.log.1` + `audit.log`）——进程重启后的历史参与校验，
/// 删除/插入段中条目、篡改字段都会断链。保证等级不变（仍是无密钥链，见上）。
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
    final time = DateTime.now().toIso8601String();
    final prevHash = _lastHash;
    // skylos: ignore —— 运行时 SHA-256 哈希（非硬编码凭据）——Skylos 静态
    // 高熵检测误报（熵 3.98——hash 是计算值非常量）。
    final hash = _sha256(_payload(time, operation, success, detail, prevHash));
    final entry = _AuditEntry(
      time: time,
      operation: operation,
      success: success,
      detail: detail,
      prevHash: prevHash,
      hash: hash,
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
  /// - 保证等级不变：链是**无密钥** SHA-256，能改文件的攻击者仍可整链重算
  ///   （见文件头「保证等级」）；防「整链重算」的带密钥校验/外部锚仍未实现。
  static bool verifyIntegrity() {
    if (!_verifyMemoryChain()) return false;
    return _verifyFileChain();
  }

  /// 内存链重放（从 [_anchorPrevHash] 起）。
  static bool _verifyMemoryChain() {
    var prev = _anchorPrevHash;
    for (final e in _entries) {
      if (e.prevHash != prev) return false; // 链接断裂（删除/插入中间记录）。
      if (e.hash !=
          _sha256(
            _payload(e.time, e.operation, e.success, e.detail, e.prevHash),
          )) {
        return false; // 哈希不符（字段被篡改）。
      }
      prev = e.hash;
    }
    return true;
  }

  /// 文件侧回读重放：读 `audit.log.1`（轮转前代）+ `audit.log`（当前），
  /// 逐行重算哈希并核对 prevHash 链接。
  ///
  /// 进程重启后内存链从 genesis 重新起链，故文件里允许出现**多段**独立链
  /// （每段首条 prevHash = genesis）——段内连续性仍严格校验，删除/插入段中
  /// 条目、篡改字段都会断链；整段删除无法检出（无密钥链的固有边界，见文件头）。
  /// sink 未解析（全新进程首次 log 之前）时跳过。坏行/读失败一律 fail-closed
  /// 判为不完整（篡改或损坏）。
  static bool _verifyFileChain() {
    final sink = _sinkFileCache;
    if (sink == null) return true;
    var prev = _genesisHash;
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
        if (time is! String ||
            operation is! String ||
            success is! bool ||
            (detail != null && detail is! String) ||
            prevHash is! String ||
            hash is! String) {
          return false;
        }
        if (prevHash != prev && prevHash != _genesisHash) {
          return false; // 段中断链（删除/插入）。
        }
        if (hash !=
            _sha256(_payload(time, operation, success, detail, prevHash))) {
          return false; // 哈希不符（字段被篡改）。
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
  }
}

/// 审计记录（含哈希链字段——prevHash 链接前一条 + hash 自身完整性）。
class _AuditEntry {
  const _AuditEntry({
    required this.time,
    required this.operation,
    required this.success,
    required this.detail,
    required this.prevHash,
    required this.hash,
  });

  final String time;
  final String operation;
  final bool success;
  final String? detail;
  final String prevHash;
  final String hash;

  /// 展示格式（兼容旧版 snapshot：`[time] operation OK/FAIL detail`）。
  String get display =>
      '[$time] $operation ${success ? 'OK' : 'FAIL'}'
      '${detail != null ? ' $detail' : ''}';
}
