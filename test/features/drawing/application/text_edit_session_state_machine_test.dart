import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/drawing/application/text_edit_session_state_machine.dart';

void main() {
  group('TextEditSessionStateMachine 状态转移表', () {
    test('初始阶段为 idle', () {
      final sm = TextEditSessionStateMachine();
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('idle -> begin -> editing（无副作用）', () {
      final sm = TextEditSessionStateMachine();
      final t = sm.event(TextEditSessionEvent.begin);
      expect(t.phase, TextEditSessionPhase.editing);
      expect(sm.phase, TextEditSessionPhase.editing);
      expect(t.sideEffects.shouldCommit, false);
      expect(t.sideEffects.shouldCancel, false);
      expect(t.sideEffects.shouldSnapshot, false);
      expect(t.sideEffects.shouldNotify, false);
      expect(t.sideEffects.shouldSuppressDuplicateCommit, false);
    });

    test('editing -> commitRequest -> committing（提交+快照+通知）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      final t = sm.event(TextEditSessionEvent.commitRequest);
      expect(t.phase, TextEditSessionPhase.committing);
      expect(sm.phase, TextEditSessionPhase.committing);
      expect(t.sideEffects.shouldCommit, true);
      expect(t.sideEffects.shouldSnapshot, true);
      expect(t.sideEffects.shouldNotify, true);
      expect(t.sideEffects.shouldCancel, false);
      expect(t.sideEffects.shouldSuppressDuplicateCommit, false);
    });

    test('committing -> commitSucceeded -> settled（通知一次）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      final t = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(t.phase, TextEditSessionPhase.settled);
      expect(sm.phase, TextEditSessionPhase.settled);
      expect(t.sideEffects.shouldNotify, true);
      expect(t.sideEffects.shouldCommit, false);
      expect(t.sideEffects.shouldSnapshot, false);
      expect(t.sideEffects.shouldCancel, false);
      expect(t.sideEffects.shouldSuppressDuplicateCommit, false);
    });

    test('完整流程 idle->editing->committing->settled', () {
      final sm = TextEditSessionStateMachine();
      expect(sm.phase, TextEditSessionPhase.idle);

      sm.event(TextEditSessionEvent.begin);
      expect(sm.phase, TextEditSessionPhase.editing);

      final commit = sm.event(TextEditSessionEvent.commitRequest);
      expect(sm.phase, TextEditSessionPhase.committing);
      expect(commit.sideEffects.shouldCommit, true);
      expect(commit.sideEffects.shouldSnapshot, true);
      expect(commit.sideEffects.shouldNotify, true);

      final settled = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(sm.phase, TextEditSessionPhase.settled);
      expect(settled.sideEffects.shouldNotify, true);
    });

    test('committing -> commitFailed -> editing（通知后回到编辑）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      final t = sm.event(TextEditSessionEvent.commitFailed);
      expect(t.phase, TextEditSessionPhase.editing);
      expect(sm.phase, TextEditSessionPhase.editing);
      expect(t.sideEffects.shouldNotify, true);
      expect(t.sideEffects.shouldCommit, false);
      expect(t.sideEffects.shouldSnapshot, false);
    });
  });

  group('取消流程', () {
    test('editing -> cancelRequest -> canceling（取消+通知，不生成快照）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      final t = sm.event(TextEditSessionEvent.cancelRequest);
      expect(t.phase, TextEditSessionPhase.canceling);
      expect(sm.phase, TextEditSessionPhase.canceling);
      expect(t.sideEffects.shouldCancel, true);
      expect(t.sideEffects.shouldNotify, true);
      expect(t.sideEffects.shouldSnapshot, false);
      expect(t.sideEffects.shouldCommit, false);
      expect(t.sideEffects.shouldSuppressDuplicateCommit, false);
    });

    test('canceling -> commitSucceeded -> settled（取消完成）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.cancelRequest);
      final t = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(t.phase, TextEditSessionPhase.settled);
      expect(sm.phase, TextEditSessionPhase.settled);
      expect(t.sideEffects.shouldNotify, true);
    });

    test('canceling -> commitFailed -> editing（取消失败回到编辑）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.cancelRequest);
      final t = sm.event(TextEditSessionEvent.commitFailed);
      expect(t.phase, TextEditSessionPhase.editing);
      expect(sm.phase, TextEditSessionPhase.editing);
      expect(t.sideEffects.shouldNotify, true);
    });

    test('取消不生成历史快照：整个取消流程 shouldSnapshot 始终为 false', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);

      final cancelT = sm.event(TextEditSessionEvent.cancelRequest);
      expect(cancelT.sideEffects.shouldSnapshot, false);

      // 取消完成后 settled 也不快照
      final settledT = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(settledT.sideEffects.shouldSnapshot, false);
    });
  });

  group('失焦提交', () {
    test('editing -> focusLost -> committing（与显式提交相同副作用）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      final t = sm.event(TextEditSessionEvent.focusLost);
      expect(t.phase, TextEditSessionPhase.committing);
      expect(sm.phase, TextEditSessionPhase.committing);
      expect(t.sideEffects.shouldCommit, true);
      expect(t.sideEffects.shouldSnapshot, true);
      expect(t.sideEffects.shouldNotify, true);
      expect(t.sideEffects.shouldCancel, false);
    });

    test('失焦提交流程：focusLost -> commitSucceeded -> settled', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.focusLost);
      final t = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(t.phase, TextEditSessionPhase.settled);
      expect(sm.phase, TextEditSessionPhase.settled);
    });
  });

  group('重复提交抑制', () {
    test('committing 中再次收到 commitRequest 只返回抑制意图（不提交/不通知）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);

      // 第一次提交
      final first = sm.event(TextEditSessionEvent.commitRequest);
      expect(first.sideEffects.shouldCommit, true);
      expect(first.sideEffects.shouldNotify, true);
      expect(first.sideEffects.shouldSuppressDuplicateCommit, false);

      // 重复提交
      final dup = sm.event(TextEditSessionEvent.commitRequest);
      expect(dup.phase, TextEditSessionPhase.committing);
      expect(sm.phase, TextEditSessionPhase.committing);
      expect(dup.sideEffects.shouldSuppressDuplicateCommit, true);
      expect(dup.sideEffects.shouldCommit, false);
      expect(dup.sideEffects.shouldNotify, false);
      expect(dup.sideEffects.shouldSnapshot, false);
      expect(dup.sideEffects.shouldCancel, false);
    });

    test('连续三次 commitRequest 只触发一次提交/通知', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);

      final t1 = sm.event(TextEditSessionEvent.commitRequest);
      final t2 = sm.event(TextEditSessionEvent.commitRequest);
      final t3 = sm.event(TextEditSessionEvent.commitRequest);

      expect(t1.sideEffects.shouldCommit, true);
      expect(t1.sideEffects.shouldNotify, true);

      expect(t2.sideEffects.shouldSuppressDuplicateCommit, true);
      expect(t2.sideEffects.shouldCommit, false);
      expect(t2.sideEffects.shouldNotify, false);

      expect(t3.sideEffects.shouldSuppressDuplicateCommit, true);
      expect(t3.sideEffects.shouldCommit, false);
      expect(t3.sideEffects.shouldNotify, false);
    });

    test('重复提交不影响后续 commitSucceeded 迁移', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      sm.event(TextEditSessionEvent.commitRequest); // 重复

      final t = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(t.phase, TextEditSessionPhase.settled);
      expect(t.sideEffects.shouldNotify, true);
    });
  });

  group('reset 重置', () {
    test('idle 时 reset 保持 idle', () {
      final sm = TextEditSessionStateMachine();
      final t = sm.event(TextEditSessionEvent.reset);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('editing 时 reset 回到 idle', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      final t = sm.event(TextEditSessionEvent.reset);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('committing 时 reset 回到 idle', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      final t = sm.event(TextEditSessionEvent.reset);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('canceling 时 reset 回到 idle', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.cancelRequest);
      final t = sm.event(TextEditSessionEvent.reset);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('settled 时 reset 回到 idle', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      sm.event(TextEditSessionEvent.commitSucceeded);
      expect(sm.phase, TextEditSessionPhase.settled);
      final t = sm.event(TextEditSessionEvent.reset);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('任意阶段 reset 后状态机可重新开始会话', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      sm.event(TextEditSessionEvent.reset);
      expect(sm.phase, TextEditSessionPhase.idle);

      // 重新开始
      final t = sm.event(TextEditSessionEvent.begin);
      expect(t.phase, TextEditSessionPhase.editing);
      expect(sm.phase, TextEditSessionPhase.editing);
    });
  });

  group('settled 后行为', () {
    test('settled 后非 reset 事件被忽略（保持 settled，无副作用）', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      sm.event(TextEditSessionEvent.commitRequest);
      sm.event(TextEditSessionEvent.commitSucceeded);
      expect(sm.phase, TextEditSessionPhase.settled);

      final events = [
        TextEditSessionEvent.begin,
        TextEditSessionEvent.commitRequest,
        TextEditSessionEvent.cancelRequest,
        TextEditSessionEvent.focusLost,
        TextEditSessionEvent.commitSucceeded,
        TextEditSessionEvent.commitFailed,
      ];

      for (final e in events) {
        final t = sm.event(e);
        expect(t.phase, TextEditSessionPhase.settled);
        expect(t.sideEffects.shouldCommit, false);
        expect(t.sideEffects.shouldCancel, false);
        expect(t.sideEffects.shouldSnapshot, false);
        expect(t.sideEffects.shouldNotify, false);
        expect(t.sideEffects.shouldSuppressDuplicateCommit, false);
      }
    });
  });

  group('非法迁移保持当前阶段', () {
    test('idle 时收到 commitRequest 被忽略', () {
      final sm = TextEditSessionStateMachine();
      final t = sm.event(TextEditSessionEvent.commitRequest);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('idle 时收到 cancelRequest 被忽略', () {
      final sm = TextEditSessionStateMachine();
      final t = sm.event(TextEditSessionEvent.cancelRequest);
      expect(t.phase, TextEditSessionPhase.idle);
      expect(sm.phase, TextEditSessionPhase.idle);
    });

    test('editing 时收到 commitSucceeded 被忽略', () {
      final sm = TextEditSessionStateMachine();
      sm.event(TextEditSessionEvent.begin);
      final t = sm.event(TextEditSessionEvent.commitSucceeded);
      expect(t.phase, TextEditSessionPhase.editing);
      expect(sm.phase, TextEditSessionPhase.editing);
    });
  });

  group('确定性（不可变输入 -> 确定性输出）', () {
    test('相同 (phase, event) 始终产生相同 transition', () {
      final sm1 = TextEditSessionStateMachine();
      final sm2 = TextEditSessionStateMachine();

      for (final e in TextEditSessionEvent.values) {
        final t1 = sm1.event(e);
        final t2 = sm2.event(e);
        expect(t1, equals(t2));
      }
    });
  });
}
