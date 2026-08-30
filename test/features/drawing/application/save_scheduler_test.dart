import 'dart:async';

import 'package:drawing_notes_app/core/saving/save_failure_policy.dart';
import 'package:drawing_notes_app/core/saving/save_schedule_decision.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可控假时钟：测试中手动推进时间。
class _FakeClock {
  DateTime _now = DateTime(2026, 1, 1, 8, 0, 0);
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

/// 可控假定时器：记录调度，测试中手动触发回调。
class _TestTimer implements SaveTimerHandle {
  _TestTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  void fire() {
    if (cancelled) return;
    fired = true;
    callback();
  }
}

class _TimerBoard {
  final List<_TestTimer> planned = [];
  SaveTimerHandle create(Duration delay, void Function() callback) {
    final t = _TestTimer(delay, callback);
    planned.add(t);
    return t;
  }

  /// 触发最后一个尚未取消的定时器。
  void fireLast() => planned.last.fire();

  /// 尚未触发且未取消的定时器（真正的“待执行”）。
  Iterable<_TestTimer> pending() =>
      planned.where((t) => !t.fired && !t.cancelled);
}

/// 记录保存调用的假保存函数，可切换为成功/抛错。
class _SaveProbe {
  int calls = 0;
  bool shouldFail = false;
  Completer<void>? gate; // 不为空时，保存挂起直至 gate.complete()

  Future<void> call() async {
    calls++;
    if (gate != null) {
      await gate!.future;
    }
    if (shouldFail) {
      throw StateError('save-failure-$calls');
    }
  }
}

void main() {
  late _FakeClock clock;
  late _TimerBoard board;
  late _SaveProbe save;
  late SaveScheduler scheduler;
  final savedEvents = <String>[];
  final errorEvents = <Object>[];

  SaveScheduler build({
    Duration debounce = const Duration(milliseconds: 800),
    SaveFailurePolicy? failurePolicy,
  }) {
    clock = _FakeClock();
    board = _TimerBoard();
    save = _SaveProbe();
    savedEvents.clear();
    errorEvents.clear();
    return SaveScheduler(
      save: save.call,
      onSaved: () => savedEvents.add('saved'),
      onError: (e, _) => errorEvents.add(e),
      clock: clock.call,
      timerFactory: board.create,
      debounce: debounce,
      failurePolicy: failurePolicy ?? const SaveFailurePolicy(),
      decisioner: const SaveScheduleDecisioner(),
    );
  }

  test('首次 markDirty 后防抖到点即保存（从未保存 → saveNow）', () async {
    scheduler = build();
    scheduler.markDirty();
    expect(save.calls, 0, reason: '防抖期内不应立即保存');
    expect(board.planned, hasLength(1));
    expect(board.planned.single.delay, const Duration(milliseconds: 800));

    board.fireLast();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);
    expect(savedEvents, ['saved']);
    expect(scheduler.isDirty, isFalse);
  });

  test('多次 markDirty 只保留一个防抖定时器（去抖合并）', () async {
    scheduler = build();
    scheduler.markDirty();
    scheduler.markDirty();
    scheduler.markDirty();
    // 每次 markDirty 都 cancel 旧定时器并重新调度，最终只留一个在飞行。
    expect(save.calls, 0);
    final active = board.planned.where((t) => !t.cancelled);
    expect(active, hasLength(1));

    active.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);
  });

  test('防抖到点但距上次保存不足 debounce → defer 并重新调度', () async {
    scheduler = build();
    // 先成功保存一次，建立 lastSaveAt。
    scheduler.markDirty();
    board.fireLast();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);
    expect(scheduler.isDirty, isFalse);

    // 时钟仅前进 200ms（< 800ms），再次变更。
    clock.advance(const Duration(milliseconds: 200));
    scheduler.markDirty();
    board.fireLast();
    await Future<void>.delayed(Duration.zero);
    // 决策器判定 defer → 重新调度，不落盘。
    expect(save.calls, 1, reason: '未到 debounce 不应落盘');
    expect(board.pending(), hasLength(1), reason: 'defer 后留一个待执行的定时器');

    // 时钟再前进 800ms，触发落盘。
    clock.advance(const Duration(milliseconds: 800));
    board.pending().single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 2);
    expect(scheduler.isDirty, isFalse);
  });

  test('保存进行中再变更 → 合并补写最新快照（串行化）', () async {
    scheduler = build();
    // 首次保存挂起，模拟 I/O 尚未完成。
    save.gate = Completer<void>();
    scheduler.markDirty();
    board.fireLast(); // 启动保存链，save() 挂起
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);

    // 保存中又发生变更。
    scheduler.markDirty();
    expect(save.calls, 1, reason: '飞行中不应重入保存');
    expect(scheduler.isDirty, isTrue, reason: '补写期间仍视为脏');

    // 放行首保存 → 外层循环发现 _saveQueued → 再次保存最新快照。
    save.gate!.complete();
    save.gate = null;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 2);
    expect(scheduler.isDirty, isFalse);
  });

  test('flush() 退出兜底：取消防抖、立即保存并等待落盘', () async {
    scheduler = build();
    save.gate = Completer<void>();
    scheduler.markDirty();
    // 未到防抖，直接 flush。不应等待定时器；保存链在微任务里启动。
    final flushed = scheduler.flush();
    await Future<void>.delayed(Duration.zero); // 让保存链启动
    expect(save.calls, 1, reason: 'flush 立即落盘，不等防抖');
    expect(scheduler.isDirty, isTrue, reason: '保存尚未完成');

    save.gate!.complete();
    save.gate = null;
    await flushed;
    expect(scheduler.isDirty, isFalse);
    expect(savedEvents, ['saved']);
  });

  test('首次失败 → 立即重试（failureCount==1 → retry）', () async {
    scheduler = build();
    save.shouldFail = true;
    // 用 saveNow 直接触发，避免防抖干扰。
    await scheduler.saveNow();
    expect(save.calls, 2, reason: '首次失败后应立刻重试一次');
    expect(errorEvents, hasLength(2), reason: '两次失败各上报一次');
    expect(scheduler.isDirty, isTrue, reason: '仍失败则保持脏');
  });

  test('持续失败 → 退避（backoff）而非无界紧耦合重试', () async {
    scheduler = build();
    save.shouldFail = true;
    await scheduler.saveNow();
    // 第 1 次失败 → count==1 → retry（立即重试）；第 2 次失败 → count 2-3 且 elapsed<5s → backoff。
    // 退避会安排一个后续定时器（而非继续在同一保存链里紧耦合重试）。
    expect(save.calls, 2);
    expect(errorEvents, hasLength(2));
    expect(board.pending(), hasLength(1), reason: 'backoff 应安排后续定时器');
  });

  test('持续失败 count>=4 → giveUp，停止重试并保持脏', () async {
    scheduler = build();
    save.shouldFail = true;
    // 触发首次保存链（retry → 首次 backoff）。
    await scheduler.saveNow();
    expect(save.calls, 2);
    // 依次触发退避定时器：第 3 次仍 backoff，第 4 次达到 count>=4 → giveUp。
    for (var i = 0; i < 2; i++) {
      expect(board.pending(), hasLength(1), reason: '退避后应有一个待触发定时器');
      board.pending().single.fire();
      await Future<void>.delayed(Duration.zero);
    }
    expect(save.calls, 4);
    expect(errorEvents, hasLength(4));
    expect(board.pending(), hasLength(0), reason: 'giveUp 后不再安排重试定时器');
    expect(scheduler.isDirty, isTrue, reason: '保存从未成功，保持脏');
  });

  test('cancel 后迟到的定时器回调不触发保存（代号失效）', () async {
    scheduler = build();
    scheduler.markDirty();
    expect(board.planned, hasLength(1));
    final first = board.planned.last;
    // 在触发前 cancel（如又 markDirty 重新调度，或 dispose）。
    scheduler.markDirty();
    // 触发旧定时器：其代号已失效 → 不保存。
    first.fire();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 0, reason: '过期回调不应保存');

    // 最新定时器触发 → 保存。
    board.planned.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);
    expect(scheduler.isDirty, isFalse);
  });

  test('dispose 后 markDirty/saveNow 不再生效，但飞行中链自然收敛', () async {
    scheduler = build();
    save.gate = Completer<void>();
    scheduler.markDirty();
    board.fireLast();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);

    scheduler.dispose();
    scheduler.markDirty(); // 忽略
    scheduler.saveNow(); // 忽略
    expect(save.calls, 1, reason: 'dispose 后不应再启动新保存');

    save.gate!.complete();
    save.gate = null;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    // 飞行中链收敛（不再有 queued 补写）。
    expect(save.calls, 1);
  });
}
