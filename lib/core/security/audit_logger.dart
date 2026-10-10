import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

/// 安全审计日志（红蓝攻防 P2 修复 2026-08-15 + 哈希链强化 2026-08-16）：
/// 记录密钥加载/密码盘操作（时间戳 + 操作 + 结果），**绝不含密钥与内容**
/// （防审计日志本身成为泄露面——去敏）。
///
/// 哈希链（专家目标架构"不可篡改审计事件流"——Thalian verify_audit_chain /
/// Revka Merkle 链 / 掘金 Layer 6 权威模式）：每条记录含 prevHash（前一条
/// 哈希）+ 自身 SHA-256 哈希——任何字段篡改立即断链，verifyIntegrity()
/// 重放检出（篡改检测——审计完整性）。
///
/// 落盘（2026-10-10，挂账轻项）：每条记录同步进内存链、异步追加写
/// `<数据根>/security/audit.log`（JSONL，含链字段，可离线重放验证），
/// 超 1 MiB 轮转为 audit.log.1（保留一代）。追加失败**静默吞掉**——审计
/// 永不阻断业务；内存链仍是权威实时视图。`flutter test` 环境默认**不落盘**
/// （FLUTTER_TEST 护栏——测试不得污染用户真实数据根），测试经
/// [sinkOverrideForTest] 注入临时目录。
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
  /// prevHash。verifyIntegrity 从此处而非 genesis 重放——否则一旦裁剪过
  /// 就恒报「已篡改」（裁剪条目仍是新首条的 prevHash，genesis 重放必断）。
  /// 文件侧无需 checkpoint：audit.log 保留全量历史，链连续性由行序保证。
  static String _anchorPrevHash = _genesisHash;

  /// 累计被丢弃条数（内存内 checkpoint 分量；文件侧保留全量，见上）。
  static int _droppedCount = 0;

  // ==== 落盘（2026-10-10） ====

  /// 落盘文件大小上限：超过即轮转为 audit.log.1（保留一代，再轮转即覆盖）。
  static const int _maxFileBytes = 1 << 20;

  /// 生产落盘文件解析器（可注入；null = 不落盘）。默认走数据根 security/
  /// （异步解析——securityFile 本身是 Future）。测试环境（FLUTTER_TEST）
  /// 默认不落盘——护栏防污染真实数据根。
  static Future<File> Function()? _sinkResolver;
  static bool _resolverChecked = false;

  /// 写入顺序链：log() 是同步 API，文件追加异步化后靠此链保序；
  /// 任一失败不断链（catchError 继续）。
  static Future<void> _writeChain = Future<void>.value();

  /// 测试注入临时落盘文件（null = 关闭落盘）。配合 [flushForTest] 等待
  /// 追加完成、[resetSinkForTest] 用例间复位。
  @visibleForTesting
  static set sinkOverrideForTest(File? file) {
    _sinkResolver = file == null ? null : () async => file;
    _resolverChecked = true;
  }

  /// 等待全部在途文件追加完成（测试断言前用）。
  @visibleForTesting
  static Future<void> flushForTest() => _writeChain;

  /// 用例间复位 sink 注入与写链（不动内存链——clear 负责那个）。
  @visibleForTesting
  static void resetSinkForTest() {
    _sinkResolver = null;
    _resolverChecked = true;
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
      try {
        final parent = sink.parent;
        if (!parent.existsSync()) await parent.create(recursive: true);
        // 轮转：超 1 MiB → audit.log.1（覆盖上一代）。best-effort。
        if (sink.existsSync() && sink.lengthSync() > _maxFileBytes) {
          final rotated = File('${sink.path}.1');
          if (rotated.existsSync()) await rotated.delete();
          await sink.rename(rotated.path);
        }
        await sink.writeAsString(
          '$line\n',
          mode: FileMode.append,
          flush: false,
        );
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
  /// 模式）：从**当前链真实起点**（_anchorPrevHash，未裁剪时即 genesis）重放
  /// ——prevHash 链接 + 重算哈希——任何字段篡改立即检出。滚动裁剪后从锚点起
  /// 重放，不再假装从 genesis 起（否则正常运行的长会话日志被误判为已篡改）。
  static bool verifyIntegrity() {
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
