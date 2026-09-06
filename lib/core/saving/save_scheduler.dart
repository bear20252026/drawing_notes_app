import 'dart:async';

import 'save_failure_policy.dart';
import 'save_schedule_decision.dart';

/// 可取消的一次性延迟定时器抽象。
///
/// 生产实现包一层 [Timer]；测试可注入一个假实现，靠手动触发回调来驱动防抖逻辑，
/// 从而无需真实等待自动保存间隔。
abstract interface class SaveTimerHandle {
  void cancel();
}

/// 定时器工厂：延迟 [delay] 后执行 [callback]，返回可取消句柄。
typedef SaveTimerFactory =
    SaveTimerHandle Function(Duration delay, void Function() callback);

/// 默认生产定时器工厂：用 [Timer] 实现。
SaveTimerHandle _defaultTimerFactory(Duration delay, void Function() callback) {
  final timer = Timer(delay, callback);
  return _TimerWrapper(timer);
}

class _TimerWrapper implements SaveTimerHandle {
  _TimerWrapper(this._timer);
  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

/// 统一保存 / 自动保存 / 失败重试调度门面（P0-3b）。
///
/// 把原先散落在 ViewModel（防抖 Timer）与 page（`_autosaving`/`_autosaveQueued`
/// 串行化、`_doAutosave` 保存循环）里的保存编排逻辑，聚合成一个纯 Dart 协调器，
/// 避免“大杂烩耦合”。它消费两个纯决策器：
///
/// - [SaveScheduleDecisioner]：决定**什么时候**保存（skip / defer / saveNow）。
/// - [SaveFailurePolicy]：决定**保存失败后**怎么办（retry / backoff / giveUp）。
///
/// 职责边界：
/// - 防抖：`markDirty()` 之后积累 [debounce] 时长再落盘。
/// - 串行化：同一时刻最多一个保存链在飞行；期间的变更合并为一次补写（`_saveQueued`）。
/// - 退出兜底：`flush()` 强制保存并等待落盘完成（页面退出前调用）。
/// - 失败重试：复用 [SaveFailurePolicy] 的退避 / 放弃策略。
/// - 通知合并：`onError` 只发出最新一次失败，避免连续失败刷屏。
class SaveScheduler {
  SaveScheduler({
    required Future<void> Function() save,
    this.onSaved,
    this.onError,
    DateTime Function()? clock,
    SaveTimerFactory? timerFactory,
    this.debounce = autoSaveInterval,
    SaveScheduleDecisioner decisioner = const SaveScheduleDecisioner(),
    SaveFailurePolicy failurePolicy = const SaveFailurePolicy(),
  }) // 保留公共命名参数名；私有域通过初始化列表赋值（见下逐行 ignore）。
  : _save = save, // ignore: prefer_initializing_formals
       _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? _defaultTimerFactory,
       _decisioner = decisioner, // ignore: prefer_initializing_formals
       _failurePolicy = failurePolicy; // ignore: prefer_initializing_formals

  /// 自动保存最小间隔（2026-09-06 用户要求：改动后最多每 5 秒落盘一次；
  /// 无修改不保存——决策器 skip 分支；手动保存/退出兜底不受此限）。
  /// 此前 800ms 对整页重绘 + 重加密的保存模型过于激进。
  static const Duration autoSaveInterval = Duration(seconds: 5);

  /// 实际把当前文档快照落盘的函数（由集成方注入，拥有 I/O 与缩略图逻辑）。
  final Future<void> Function() _save;

  /// 一次保存成功后的回调（用于把文档标记为已保存，如 `markSaved`）。
  final void Function()? onSaved;

  /// 一次保存失败后的回调（用于 UI 提醒；已做合并，只会在失败状态变化时触发）。
  final void Function(Object error, StackTrace stackTrace)? onError;

  final DateTime Function() _clock;
  final SaveTimerFactory _timerFactory;
  final Duration debounce;
  final SaveScheduleDecisioner _decisioner;
  final SaveFailurePolicy _failurePolicy;

  // ---------------- 运行时状态 ----------------

  bool _dirty = false;
  DateTime? _lastSaveAt;
  bool _exiting = false;
  bool _disposed = false;

  bool _saveInFlight = false;
  bool _saveQueued = false;
  Future<void>? _activeDrain;

  int _failureCount = 0;
  DateTime? _firstFailureAt;

  int _generation = 0;
  SaveTimerHandle? _pendingTimer;

  // ---------------- 公共 API ----------------

  /// 标记文档有变更：调度一次防抖保存。保存进行中则合并为一次补写。
  void markDirty() {
    if (_disposed) return;
    _dirty = true;
    // 已有保存链在飞行：只标记补写，由当前循环结束后再保存最新快照。
    if (_saveInFlight) {
      _saveQueued = true;
      return;
    }
    _scheduleDebounce();
  }

  /// 立即保存并等待落盘完成（手动保存 / 页面退出前强制写入）。
  ///
  /// 若已有保存链在飞行，则合并为一次补写并等待该链完成后返回。
  Future<void> saveNow() {
    if (_disposed) return Future<void>.value();
    _dirty = true;
    _cancelTimer();
    if (_saveInFlight) {
      _saveQueued = true;
      return _activeDrain ?? Future<void>.value();
    }
    return _coalescedSave();
  }

  /// 退出兜底：进入退出态、取消防抖，强制保存当前快照并等待落盘。
  Future<void> flush() {
    if (_disposed) return Future<void>.value();
    _exiting = true;
    _cancelTimer();
    if (_saveInFlight) {
      _saveQueued = true;
      return _activeDrain ?? Future<void>.value();
    }
    return _coalescedSave();
  }

  /// 释放调度器：取消尚未执行的防抖。已在飞行中的保存链会自然收敛。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelTimer();
  }

  /// 是否尚有待落盘的更改（供调用方判断是否需要保存）。
  bool get isDirty => _dirty;

  // ---------------- 内部编排 ----------------

  /// 立即（或作为补写）启动一个串行化保存链。若已有链在飞行，只排队补写。
  Future<void> _coalescedSave() {
    final active = _activeDrain;
    if (active != null) {
      _saveQueued = true;
      return active;
    }
    final completer = Completer<void>();
    _activeDrain = completer.future;
    _saveInFlight = true;
    // 用微任务启动，确保 _activeDrain 先就绪，避免同帧重入。
    scheduleMicrotask(() {
      _runDrain().whenComplete(() {
        _saveInFlight = false;
        _activeDrain = null;
        completer.complete();
      });
    });
    return _activeDrain!;
  }

  /// 串行化保存链：保存一次；若期间又有变更（`_saveQueued`）或失败要求立即重试，
  /// 则继续保存，直到快照稳定。成功/退避/放弃时收敛。
  Future<void> _runDrain() async {
    while (true) {
      _saveQueued = false;
      final retryImmediately = await _saveOnce();
      if (retryImmediately) continue;
      if (_saveQueued) continue;
      break;
    }
  }

  /// 执行一次保存，并处理成功与失败策略。
  ///
  /// 返回 `true` 表示失败策略要求立即重试（外层循环继续）；
  /// 返回 `false` 表示成功、或失败策略已安排退避/放弃（外层循环收敛）。
  Future<bool> _saveOnce() async {
    try {
      await _save();
      _onSaveSuccess();
      return false;
    } catch (error, stackTrace) {
      return _handleFailure(error, stackTrace);
    }
  }

  void _onSaveSuccess() {
    _failureCount = 0;
    _firstFailureAt = null;
    // 保存完成即更新最近一次落盘时间；但若保存期间又有变更，仍保持脏，
    // 由外层循环补写最新快照，避免把“未落盘的更改”误标为已保存。
    _lastSaveAt = _clock();
    if (!_saveQueued) {
      _dirty = false;
    }
    onSaved?.call();
  }

  bool _handleFailure(Object error, StackTrace stackTrace) {
    _failureCount++;
    _firstFailureAt ??= _clock();
    final elapsed = _clock().difference(_firstFailureAt!);
    // 通知合并：只上报“失败事件本身”，策略由这里统一处理。
    onError?.call(error, stackTrace);
    switch (_failurePolicy.decide(
      SaveFailureInput(failureCount: _failureCount, elapsed: elapsed),
    )) {
      case SaveRetryDecision.retry:
        return true;
      case SaveRetryDecision.backoff:
        _scheduleDebounce();
        return false;
      case SaveRetryDecision.giveUp:
        // 放弃本轮自动重试：保留脏标记，下一次内容变更会重新触发保存。
        return false;
    }
  }

  /// 安排一次防抖落盘。用一代号（[generation]）使过期回调失效，
  /// 保证 cancel 之后迟到的 Timer 回调不会误触发保存。
  void _scheduleDebounce() {
    if (_disposed) return;
    _cancelTimer();
    final generation = _generation;
    _pendingTimer = _timerFactory(debounce, () {
      _pendingTimer = null;
      if (_disposed) return;
      if (generation != _generation) return;
      unawaited(_attemptSave());
    });
  }

  void _cancelTimer() {
    _generation++;
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  /// 防抖到点后，依据 [SaveScheduleDecisioner] 决定是否立即保存。
  Future<void> _attemptSave() async {
    if (_disposed) return;
    final decision = _decisioner.decide(
      SaveScheduleInput(
        dirty: _dirty,
        now: _clock(),
        debounce: debounce,
        lastSaveAt: _lastSaveAt,
        saveInFlight: _saveInFlight,
        isExiting: _exiting,
      ),
    );
    switch (decision) {
      case SaveScheduleDecision.skip:
        return;
      case SaveScheduleDecision.defer:
        _scheduleDebounce();
        return;
      case SaveScheduleDecision.saveNow:
        await _coalescedSave();
    }
  }
}
