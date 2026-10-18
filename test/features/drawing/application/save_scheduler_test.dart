import 'dart:async';

import 'package:drawing_notes_app/core/saving/save_failure_policy.dart';
import 'package:drawing_notes_app/core/saving/save_schedule_decision.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_clock.dart';

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
  late FakeClock clock;
  late _TimerBoard board;
  late _SaveProbe save;
  late SaveScheduler scheduler;
  final savedEvents = <String>[];
  final errorEvents = <Object>[];

  SaveScheduler build({
    Duration debounce = const Duration(milliseconds: 800),
    SaveFailurePolicy? failurePolicy,
  }) {
    clock = FakeClock();
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
    clock.advanceBy(const Duration(milliseconds: 200));
    scheduler.markDirty();
    board.fireLast();
    await Future<void>.delayed(Duration.zero);
    // 决策器判定 defer → 重新调度，不落盘。
    expect(save.calls, 1, reason: '未到 debounce 不应落盘');
    expect(board.pending(), hasLength(1), reason: 'defer 后留一个待执行的定时器');

    // 时钟再前进 800ms，触发落盘。
    clock.advanceBy(const Duration(milliseconds: 800));
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

  test('flushIfDirty() 干净退出：零等待、不触发保存（v1.17.18）', () async {
    scheduler = build();
    await scheduler.flushIfDirty();
    expect(save.calls, 0, reason: '无未落盘改动不应触发保存');
    expect(savedEvents, isEmpty);
    expect(scheduler.isDirty, isFalse);
  });

  test('flushIfDirty() 脏退出：与 flush 等价（立即保存并等待落盘）', () async {
    scheduler = build();
    save.gate = Completer<void>();
    scheduler.markDirty();
    final flushed = scheduler.flushIfDirty();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1, reason: '有未落盘改动时应立即落盘');
    save.gate!.complete();
    save.gate = null;
    await flushed;
    expect(scheduler.isDirty, isFalse);
    expect(savedEvents, ['saved']);
  });

  test('flushIfDirty() 保存链飞行中：等待链收敛（含合并补写）', () async {
    scheduler = build();
    save.gate = Completer<void>();
    scheduler.markDirty();
    final first = scheduler.flush();
    await Future<void>.delayed(Duration.zero); // 让保存链启动
    // 飞行中调用：委托 flush → 标记补写（防丢失语义）并等待同一链收敛。
    final second = scheduler.flushIfDirty();
    save.gate!.complete();
    save.gate = null;
    await second;
    // 补写一次最新快照（此时无新变更，快照内容一致）。
    expect(save.calls, 2);
    expect(scheduler.isDirty, isFalse);
    await first;
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
    unawaited(scheduler.saveNow()); // 忽略
    expect(save.calls, 1, reason: 'dispose 后不应再启动新保存');

    save.gate!.complete();
    save.gate = null;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    // 飞行中链收敛（不再有 queued 补写）。
    expect(save.calls, 1);
  });

  // 用户可见面（2026-10-06）：失败此前只进 AuditLogger + `onError`，
  // 画布编辑器把它用来写日志，用户界面一点痕迹都没有——AW8 那个 P0
  // （无 PIN 用户完全存不了画布）能潜伏两个月，直接原因就在这里。
  group('saveFailure 用户可见通知', () {
    test('首次失败就挂出通知，且 gaveUp=false（改动已不在盘上，不等放弃才报）',
        () async {
      scheduler = build();
      save.shouldFail = true;

      await scheduler.saveNow(); // 首次失败 → retry → 第二次失败 → backoff

      final notice = scheduler.saveFailure.value;
      expect(notice, isNotNull, reason: '第一次失败起就该让用户知道没落盘');
      expect(notice!.gaveUp, isFalse, reason: '仍在退避重试，措辞不该是「手动保存」');
      expect(notice.failureCount, greaterThanOrEqualTo(2));
    });

    test('保存成功后通知自动撤下（不留过期的「失败」状态）', () async {
      scheduler = build();
      save.shouldFail = true;
      await scheduler.saveNow();
      expect(scheduler.saveFailure.value, isNotNull);

      save.shouldFail = false;
      await scheduler.saveNow();
      expect(
        scheduler.saveFailure.value,
        isNull,
        reason: '已经落盘成功却还挂着失败提示，比不提示更误导',
      );
    });

    test('持续失败到 giveUp：通知升级为「已停止自动重试」', () async {
      scheduler = build();
      save.shouldFail = true;
      await scheduler.saveNow(); // 1 → retry, 2 → backoff
      for (var i = 0; i < 2; i++) {
        board.pending().single.fire();
        await Future<void>.delayed(Duration.zero);
      }

      final notice = scheduler.saveFailure.value;
      expect(notice, isNotNull);
      expect(
        notice!.gaveUp,
        isTrue,
        reason: 'giveUp 后只有下一次内容变更才会再试，措辞必须跟上',
      );
      expect(scheduler.isDirty, isTrue, reason: '升级措辞的同时脏标记不得被清掉');
    });

    test('通知只带类型代码，不带 message（H-04 不泄漏路径与凭据）', () async {
      scheduler = build();
      save.shouldFail = true;

      await scheduler.saveNow();

      final notice = scheduler.saveFailure.value!;
      // R50：这里从 `StateError`（运行时读的类型名）换成 `errorCode()` 推的字面码——
      // 开 `--obfuscate` 之后类型名是每次出包都不同的随机串，这条断言就没法写了。
      expect(notice.errorKind, 'core_state');
      expect(
        notice.errorKind.contains('save-failure'),
        isFalse,
        reason: '异常 message 可能含路径/远端文本，一律不得外带',
      );
    });

    test('dispose 后飞行中的失败不再触碰 notifier（不抛已释放断言）', () async {
      scheduler = build();
      save.shouldFail = true; // 让链在 dispose 之后以「失败」收敛
      save.gate = Completer<void>();
      scheduler.markDirty();
      board.fireLast();
      await Future<void>.delayed(Duration.zero);

      scheduler.dispose();
      save.gate!.complete();
      save.gate = null;
      // 让挂起的保存链跑到失败分支（修复前会 dispose 之后再写 notifier）。
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(scheduler.isDirty, isTrue, reason: '从未成功落盘，脏标记必须保留');
      // notifier 已被 dispose：写它会触发 debug 断言 ⇒ 走到这里没抛即为通过。
      // 不要再读 saveFailure 的任何状态——它本身已经释放，读了反而炸在这个断言上。
    });
  });

  // DN-005（2026-10-12）：强制保存的 Future 正常完成**从不**代表已落盘——
  // `_runDrain` 在退避/放弃时同样收敛且不外抛，`Future<void>` 把「失败」读成
  // 「成功」，于是 `editor_page` / `doc_page` 两个 pop 点在 await 之后无条件退出，
  // 未落盘的改动随页面销毁静默蒸发（AW13 那颗失败芯片也跟着没了）。现在落不落盘
  // 是返回值里可裁决的事实。
  group('DN-005：flush/saveNow 的落盘结果契约', () {
    test('giveUp 之后 flush() = failedStillDirty，且 isDirty 仍为 true', () async {
      scheduler = build();
      save.shouldFail = true;
      // 先把状态推到「已停止自动重试」（与上方 giveUp 用例同一序列）。
      await scheduler.saveNow(); // 1 → retry, 2 → backoff
      for (var i = 0; i < 2; i++) {
        board.pending().single.fire(); // 3 → backoff, 4 → giveUp
        await Future<void>.delayed(Duration.zero);
      }
      expect(scheduler.saveFailure.value!.gaveUp, isTrue);

      final result = await scheduler.flush();

      expect(result.outcome, SaveFlushOutcome.failedStillDirty);
      expect(
        result.isSafeToLeave,
        isFalse,
        reason: '退出点据此必须拦住 pop——这正是本批要修的静默丢失',
      );
      expect(result.failure, isNotNull);
      expect(result.failure!.gaveUp, isTrue, reason: '带上最后一颗通知供措辞');
      expect(scheduler.isDirty, isTrue, reason: '从未落盘，脏标记不得被结果掩盖');
    });

    test('backoff（还会重试）同样算 failedStillDirty：此刻改动不在盘上', () async {
      scheduler = build();
      save.shouldFail = true;
      scheduler.markDirty();

      final result = await scheduler.flush(); // 1 → retry, 2 → backoff

      expect(result.outcome, SaveFlushOutcome.failedStillDirty);
      expect(
        result.failure!.gaveUp,
        isFalse,
        reason: '还在退避重试，但「没落盘」这一事实已经成立',
      );
      expect(board.pending(), hasLength(1), reason: '退避定时器行为不变');
      expect(scheduler.isDirty, isTrue);
    });

    test('反向钉：flush 打在**无待写改动**的文档上而写入失败，不得报 saved', () async {
      // `EditorViewModel.saveNow()` 委托的就是 flush()——用户在没有改动时点保存
      // 也会真的发起一次写入。它失败时若按 `_dirty` 单条件裁决，就会被读成
      // 「已落盘」，正是本批要杜绝的谎。此刻既没写成功、也没有待写内容，
      // 诚实的答案是「没有需要落盘的改动」+ 带上那颗失败通知。
      scheduler = build();
      final ok = await scheduler.flush();
      expect(ok.outcome, SaveFlushOutcome.saved, reason: '先钉住成功写入=有写盘');

      save.shouldFail = true;
      final failed = await scheduler.flush();
      expect(failed.outcome, SaveFlushOutcome.nothingToSave);
      expect(
        failed.failure,
        isNotNull,
        reason: '没有待写内容 ≠ 这次写成功了：失败事实必须仍然可见',
      );
      expect(scheduler.isDirty, isFalse);
    });

    test('成功落盘 → saved（钉住既有成功路径语义不变）', () async {
      scheduler = build();
      save.gate = Completer<void>();
      scheduler.markDirty();
      final flushed = scheduler.flush();
      await Future<void>.delayed(Duration.zero);
      save.gate!.complete();
      save.gate = null;

      final result = await flushed;

      expect(result.outcome, SaveFlushOutcome.saved);
      expect(result.isSafeToLeave, isTrue);
      expect(result.failure, isNull);
      expect(scheduler.isDirty, isFalse);
      expect(savedEvents, ['saved'], reason: '既有 onSaved 回调不受影响');
    });

    test('saveNow() 成功 → saved；失败 → failedStillDirty（同一契约）', () async {
      scheduler = build();
      expect(
        (await scheduler.saveNow()).outcome,
        SaveFlushOutcome.saved,
        reason: '干净态被 saveNow 强制写一次，写了就是 saved',
      );
      expect(save.calls, 1);

      save.shouldFail = true;
      final failed = await scheduler.saveNow();
      expect(failed.outcome, SaveFlushOutcome.failedStillDirty);
      expect(scheduler.isDirty, isTrue);
    });

    test('无改动 → nothingToSave，且一次写入都不发起', () async {
      scheduler = build();

      final result = await scheduler.flushIfDirty();

      expect(result.outcome, SaveFlushOutcome.nothingToSave);
      expect(result.isSafeToLeave, isTrue);
      expect(save.calls, 0, reason: '零卡顿退出路径不得被结果契约改写');
      expect(scheduler.isDirty, isFalse);
    });

    test('飞行中加入的 flush 与 flushIfDirty 拿到同一条链的结果（无双轨）', () async {
      scheduler = build();
      save.gate = Completer<void>();
      scheduler.markDirty();
      final first = scheduler.flush();
      await Future<void>.delayed(Duration.zero);
      final second = scheduler.flushIfDirty();
      save.gate!.complete();
      save.gate = null;

      final secondResult = await second;
      final firstResult = await first;

      expect(secondResult.outcome, SaveFlushOutcome.saved);
      expect(
        identical(firstResult, secondResult),
        isTrue,
        reason: '两个调用等的是同一条链、同一个结果对象，不是各自再算一遍',
      );
      expect(scheduler.isDirty, isFalse);
    });

    test('dispose 之后的 flush 不得谎称已落盘', () async {
      scheduler = build();
      scheduler.markDirty();
      scheduler.dispose();

      final dirty = await scheduler.flush();
      expect(dirty.outcome, SaveFlushOutcome.failedStillDirty);
      expect(
        dirty.failure,
        isNull,
        reason: 'notifier 已释放，结果里不得再带出已 dispose 的对象',
      );

      final clean = build();
      clean.dispose();
      expect(
        (await clean.flush()).outcome,
        SaveFlushOutcome.nothingToSave,
        reason: '已释放且无待写改动：放行，但没有写过盘',
      );
    });
  });
}
