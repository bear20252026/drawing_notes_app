import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_history.dart';

void main() {
  /// 创建测试文档工厂。
  NoteBlockDoc buildTestDoc({
    String id = 'doc1',
    String title = 'Test',
    List<NoteBlock>? body,
    DateTime? now,
  }) {
    final ts = now ?? DateTime(2026, 8, 28);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: body ?? [NoteBlock.textBlock('b0', text: 'initial')],
      createdAt: ts,
      updatedAt: ts,
    );
  }

  /// 创建可控时钟（从 start 开始，每次调用 +step）。
  int Function() buildClock({int start = 1000, int step = 100}) {
    var current = start;
    return () {
      final v = current;
      current += step;
      return v;
    };
  }

  group('NoteBlockHistory 基本操作', () {
    test('push 后 canUndo 为 true，canRedo 为 false', () {
      final history = NoteBlockHistory(clock: buildClock());
      history.push(buildTestDoc());
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
    });

    test('undo 返回上一快照，canRedo 变为 true', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc1 = buildTestDoc();
      final doc2 = doc1.copyWith(title: 'Second');
      history.push(doc1);
      history.push(doc2);

      final result = history.undo();
      expect(result, isNotNull);
      expect(result!.title, 'Test');
      expect(history.canRedo, isTrue);
    });

    test('redo 返回下一个快照', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc1 = buildTestDoc();
      final doc2 = doc1.copyWith(title: 'Second');
      history.push(doc1);
      history.push(doc2);

      history.undo();
      final result = history.redo();
      expect(result, isNotNull);
      expect(result!.title, 'Second');
    });

    test('clear 后 canUndo 为 false', () {
      final history = NoteBlockHistory(clock: buildClock());
      history.push(buildTestDoc());
      history.clear();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });
  });

  group('NoteBlockHistory 去重', () {
    test('相同文档不重复压栈', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc = buildTestDoc();
      history.push(doc);
      history.push(doc); // 相同文档
      // undo 应返回 null（只有一个条目）
      final result = history.undo();
      expect(result, isNull);
    });

    test('相等但不同实例的文档不去重失败', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc1 = buildTestDoc();
      final doc2 = buildTestDoc(); // 内容相同，不同实例
      history.push(doc1);
      history.push(doc2);
      // 两个文档相等，应去重
      history.undo();
      expect(history.canUndo, isFalse);
    });
  });

  group('NoteBlockHistory 上限', () {
    test('超过 maxSteps 丢弃最旧', () {
      final history = NoteBlockHistory(
        maxSteps: 3,
        clock: buildClock(),
      );
      final doc = buildTestDoc();
      // push 5 个不同文档（每次 push 标题不同）
      for (int i = 0; i < 5; i++) {
        history.push(doc.copyWith(title: 'V$i'));
      }
      // 应只保留最后 3 步：V2, V3, V4
      // undo 2 次应回到 V2（最旧的保留）
      final r1 = history.undo(); // → V3
      expect(r1!.title, 'V3');
      final r2 = history.undo(); // → V2
      expect(r2!.title, 'V2');
      // 再 undo 应为 null（V2 是最旧，已无更早）
      expect(history.undo(), isNull);
      expect(history.canUndo, isFalse);
    });
  });

  group('NoteBlockHistory 时间窗合并', () {
    test('同块连续文本编辑（时间窗内）合并为一次历史', () {
      final history = NoteBlockHistory(
        mergeWindowMs: 800,
        clock: buildClock(start: 1000, step: 100), // 每次+100ms
      );
      final doc = buildTestDoc();
      history.push(doc);

      // 模拟连续打字：每次改同一块的文本，间隔 100ms < 800ms
      for (int i = 1; i <= 5; i++) {
        history.push(doc.copyWith(
          body: [NoteBlock.textBlock('b0', text: 'text$i')],
        ));
      }

      // 应合并为一次历史：undo 回到初始
      final result = history.undo();
      expect(result, isNotNull);
      expect(result!.body.first.text, 'initial');
    });

    test('跨时间窗不合并', () {
      final history = NoteBlockHistory(
        mergeWindowMs: 800,
        clock: buildClock(start: 1000, step: 1000), // 每次+1000ms > 800ms
      );
      final doc = buildTestDoc();
      history.push(doc);

      // 模拟打字：间隔 1000ms > 800ms 不合并
      for (int i = 1; i <= 3; i++) {
        history.push(doc.copyWith(
          body: [NoteBlock.textBlock('b0', text: 'text$i')],
        ));
      }

      // 不合并：undo 应逐步回退
      final r1 = history.undo();
      expect(r1!.body.first.text, 'text2');
      final r2 = history.undo();
      expect(r2!.body.first.text, 'text1');
      final r3 = history.undo();
      expect(r3!.body.first.text, 'initial');
    });

    test('不同块编辑不合并', () {
      final history = NoteBlockHistory(
        mergeWindowMs: 800,
        clock: buildClock(start: 1000, step: 100),
      );
      final doc = buildTestDoc();
      history.push(doc);

      // 编辑块 b0
      history.push(doc.copyWith(
        body: [NoteBlock.textBlock('b0', text: 'edit_b0')],
      ));
      // 编辑块 b1（不同块）
      history.push(doc.copyWith(
        body: [
          NoteBlock.textBlock('b0', text: 'initial'),
          NoteBlock.textBlock('b1', text: 'new'),
        ],
      ));

      // 不同块编辑不合并：undo 回到上一次
      final r1 = history.undo();
      expect(r1, isNotNull);
      expect(r1!.body.length, 1); // 回到只有 b0 的状态
    });

    test('结构变化（增删块）不合并', () {
      final history = NoteBlockHistory(
        mergeWindowMs: 800,
        clock: buildClock(start: 1000, step: 100),
      );
      final doc = buildTestDoc();
      history.push(doc);

      // 添加新块（结构变化）
      history.push(doc.copyWith(
        body: [
          NoteBlock.textBlock('b0', text: 'initial'),
          NoteBlock.textBlock('b1', text: 'new'),
        ],
      ));

      // 纯文本编辑
      history.push(doc.copyWith(
        body: [NoteBlock.textBlock('b0', text: 'edited')],
      ));

      // 结构变化后不能合并：undo 应回到结构变化后的状态
      final r1 = history.undo();
      expect(r1, isNotNull);
      expect(r1!.body.length, 2); // 有 b0 和 b1
    });
  });

  group('NoteBlockHistory redo 分支管理', () {
    test('undo 后 push 清空 redo 分支', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc = buildTestDoc();
      history.push(doc);
      history.push(doc.copyWith(title: 'Second'));
      history.push(doc.copyWith(title: 'Third'));

      history.undo(); // 回到 Second
      expect(history.canRedo, isTrue);

      // push 新文档应清空 redo
      history.push(doc.copyWith(title: 'NewBranch'));
      expect(history.canRedo, isFalse);
    });

    test('redo 后 undo 再 redo 正确', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc = buildTestDoc();
      history.push(doc);
      history.push(doc.copyWith(title: 'Second'));

      history.undo();
      history.redo();
      final result = history.current;
      expect(result, isNotNull);
      expect(result!.title, 'Second');
    });
  });

  group('NoteBlockHistory 边界情况', () {
    test('空栈 undo 返回 null', () {
      final history = NoteBlockHistory(clock: buildClock());
      expect(history.undo(), isNull);
    });

    test('空栈 redo 返回 null', () {
      final history = NoteBlockHistory(clock: buildClock());
      expect(history.redo(), isNull);
    });

    test('canUndo 初始为 false', () {
      final history = NoteBlockHistory(clock: buildClock());
      expect(history.canUndo, isFalse);
    });

    test('current 返回栈顶', () {
      final history = NoteBlockHistory(clock: buildClock());
      final doc = buildTestDoc();
      history.push(doc);
      expect(history.current, equals(doc));
    });
  });
}
