// 由 Claude 团队生成 | Drawing Notes App
// save_schedule_decision.dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/saving/save_schedule_decision.dart';

void main() {
  group('SaveScheduleDecisioner', () {
    const debounce = Duration(seconds: 3);
    final now = DateTime(2026, 1, 1, 12, 0, 0);
    final decisioner = SaveScheduleDecisioner();

    test('非 dirty → skip', () {
      final input = SaveScheduleInput(
        dirty: false,
        now: now,
        debounce: debounce,
      );
      expect(decisioner.decide(input), SaveScheduleDecision.skip);
    });

    test('isExiting + dirty → saveNow（退出兜底）', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        isExiting: true,
      );
      expect(decisioner.decide(input), SaveScheduleDecision.saveNow);
    });

    test('isExiting + 非 dirty → skip（退出但无改动不保存）', () {
      final input = SaveScheduleInput(
        dirty: false,
        now: now,
        debounce: debounce,
        isExiting: true,
      );
      expect(decisioner.decide(input), SaveScheduleDecision.skip);
    });

    test('dirty + 从未保存 → saveNow', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        lastSaveAt: null,
      );
      expect(decisioner.decide(input), SaveScheduleDecision.saveNow);
    });

    test('dirty + 距上次保存 >= debounce → saveNow', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        lastSaveAt: now.subtract(const Duration(seconds: 5)),
      );
      expect(decisioner.decide(input), SaveScheduleDecision.saveNow);
    });

    test('dirty + 距上次保存 < debounce → defer（防抖未到）', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        lastSaveAt: now.subtract(const Duration(seconds: 1)),
      );
      expect(decisioner.decide(input), SaveScheduleDecision.defer);
    });

    test('dirty + saveInFlight → defer（合并为一次）', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        saveInFlight: true,
      );
      expect(decisioner.decide(input), SaveScheduleDecision.defer);
    });

    test('isExiting 优先于 saveInFlight（退出兜底）', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        saveInFlight: true,
        isExiting: true,
      );
      expect(decisioner.decide(input), SaveScheduleDecision.saveNow);
    });

    test('确定性：相同输入多次调用结果一致', () {
      final input = SaveScheduleInput(
        dirty: true,
        now: now,
        debounce: debounce,
        lastSaveAt: now.subtract(const Duration(seconds: 1)),
      );
      final first = decisioner.decide(input);
      final second = decisioner.decide(input);
      expect(first, second);
      expect(first, SaveScheduleDecision.defer);
    });
  });
}
