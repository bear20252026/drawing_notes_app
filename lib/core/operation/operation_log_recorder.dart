import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/operation/operation_log.dart';
import 'package:drawing_notes_app/core/operation/operation_log_store.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';

/// A2 的接线面：把会话操作流落到磁盘侧车（数据根内的 `oplog/<docId>.jsonl`）。
///
/// 三条契约，逐条有对应用例与突变自证
/// （`test/core/operation/operation_log_recorder_test.dart`）：
///  ① **只在真有新操作时碰盘**：自动保存每 5 秒跑一次，而 `append` 是整份重写
///     （批次 D 实测几 KB 的侧车单次写约 1.4–3.5 ms）。没有新操作就一个字节都不写
///     ——这是协同方案 §10 给接线开的前提条件。
///  ② **水位线只在写成功时前进**：保险库锁定（`append` 返回 0）、现有侧车读不懂、
///     写盘异常都算「这次没落」。下一轮带着**同一批**操作重试，`seq` 由这里统一
///     发号并接在盘上已用号之后 ⇒ 存储面按 `seq` 去重，重试天然幂等。
///  ③ **侧车失败绝不挡住文档保存**：正文才是用户数据，操作日志是可再生的记录面。
///     所以这里的异常一律吞掉、只留审计，不往保存链抛。
///
/// 已知边界（写清，不留错觉）：
///  - 笔记本页面模式的画布**不走这里**（那条链的保存在 `NotebookViewPage`，
///    文档也不同族）；
///  - 每篇文档一格游标，只增不减：删掉反而会让那篇的水位线归零、
///    把已经落盘的那段再落一次。一格是三个整数 + 一个 id 字符串。
class OperationLogRecorder {
  OperationLogRecorder(this._storeFactory);

  /// 每次落盘现取一份 store：「没建库 ⇒ 明文」与「建过库但锁定 ⇒ 什么都不写」
  /// 这条判据是异步的（`vaultConfigured`），必须在构造 store 之前问一次，
  /// 不能让日志变成第二条加密降级通道（§9「另外两件顺手要定的」）。
  final Future<OperationLogStore> Function() _storeFactory;

  final Map<String, _Cursor> _cursors = {};

  /// 诊断/测试用：当前记着水位线的文档数。
  int get trackedDocs => _cursors.length;

  /// 落「自上次落盘以来新增」的操作，返回实际新增的记录数。
  ///
  /// [docRevision] 必须是**正在落盘那一版**的 revision（调用方在 `save` 之前取），
  /// 理由见 [OperationLogStore.load] 的不变量①：读回时以盘上文档 revision 为界
  /// 截尾巴，`baseRev` 写得比盘上更新 = 这批记录一落地就被自己判成幻影丢掉。
  /// 调用点也必须在 `save(doc)` **之后**——文档是权威，日志跟着正文走。
  Future<int> flush(
    DrawingDocument doc,
    OperationLog log,
    int docRevision,
  ) async {
    final cursor = _cursorFor(doc.id, log);
    final pending = log.entriesSince(cursor.flushedSerial);
    if (pending.isEmpty) return 0; // 契约①

    final store = await _storeFactory();
    final seqBase = await _seqBase(store, doc.id, cursor);
    if (seqBase == null) return 0; // 号段起点都不知道 ⇒ 不能凭空发号
    final records = [
      for (var i = 0; i < pending.length; i++)
        OperationLogRecord(
          seq: seqBase + i + 1,
          baseRev: docRevision,
          operation: pending[i].operation,
        ),
    ];
    final int written;
    try {
      written = await store.append(doc.id, records);
    } on Object catch (error) {
      // 契约③：改名失败 / 回读不符 / IO 异常都不能把正文保存带下水。
      _auditFailure(cursor, doc.id, 'append', error);
      return 0;
    }
    if (written == 0) {
      // 锁定态：什么都没落。水位不动，下一轮重试同一批。
      _auditFailure(cursor, doc.id, 'locked', '保险库锁定，侧车未写');
      return 0;
    }
    cursor.seqBase = seqBase + written;
    // 用**记录自己的序号**收尾，不用 `log.lastSerial`：上面的 await 期间用户还能画，
    // 用后者会把「await 之后才记录的操作」当成已落盘而静默丢掉。
    cursor.flushedSerial = pending.last.serial;
    cursor.reportedFailure = false;
    return written;
  }

  /// 取游标。**换一个 OperationLog 实例就是换一个会话**：同一篇文档在本进程里
  /// 关掉再打开，内存日志的序号从 1 重新开始，沿用旧水位会让它永远 `pending` 为空
  /// ⇒ 这篇之后再没有日志。序号轴归零，但 `seqBase`（盘上已用号）必须留着。
  _Cursor _cursorFor(String docId, OperationLog log) {
    final cursor = _cursors.putIfAbsent(docId, _Cursor.new);
    final owner = cursor.owner;
    if (owner != null && !identical(owner, log)) {
      cursor.flushedSerial = 0;
    }
    cursor.owner = log;
    return cursor;
  }

  /// 号段起点：磁盘上已用过的最大 `seq`。null = 这一轮问不出来（锁定/损坏）。
  Future<int?> _seqBase(
    OperationLogStore store,
    String docId,
    _Cursor cursor,
  ) async {
    final known = cursor.seqBase;
    if (known != null) return known;
    try {
      final existing = await store.load(docId);
      final base = existing.isEmpty ? 0 : existing.last.seq;
      cursor.seqBase = base;
      return base;
    } on Object catch (error) {
      // 读不懂现有侧车就不能猜它用到第几号：猜小了会撞 seq，撞完被去重**静默丢掉**。
      // 与 `append` 里「读不懂就放弃写入」同一口径。
      _auditFailure(cursor, docId, 'load', error);
      return null;
    }
  }

  /// 失败要可见，但「每 5 秒重试一次」不该把审计链刷满：
  /// 同一篇文档的同一段停滞只报第一次，成功落过一次后才允许报下一段。
  void _auditFailure(_Cursor cursor, String docId, String stage, Object error) {
    if (cursor.reportedFailure) return;
    cursor.reportedFailure = true;
    AuditLogger.log('oplog.$stage', success: false, detail: '$docId: $error');
  }
}

/// 单篇文档的接线水位。
class _Cursor {
  /// 这段水位线属于哪个内存日志实例（null = 本会话还没见过这篇的操作流）。
  OperationLog? owner;

  /// 已落盘的最后一条操作的提交序号。
  int flushedSerial = 0;

  /// 磁盘上已用过的最大 `seq`；null = 还没问过这份侧车。
  int? seqBase;

  /// 是否已经为当前这段停滞报过审计。
  bool reportedFailure = false;
}
