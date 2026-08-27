import 'package:drawing_notes_app/features/drawing/application/document_commands.dart';
import 'package:drawing_notes_app/features/drawing/application/document_edit_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('命令入栈、撤销与重做保持游标和未保存状态', () {
    final events = <String>[];
    final history = DocumentEditHistory(maxEntries: 3);
    final first = _RecordingCommand('first', events);
    final second = _RecordingCommand('second', events);

    expect(history.isDirty, isFalse);
    history.push(first);
    history.push(second);
    expect(history.isDirty, isTrue);
    expect(history.position, 2);
    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);

    history.markSaved();
    expect(history.isDirty, isFalse);
    expect(history.undo(), isTrue);
    expect(events, <String>['undo:second']);
    expect(history.position, 1);
    expect(history.canRedo, isTrue);

    expect(history.redo(), isTrue);
    expect(events, <String>['undo:second', 'redo:second']);
    expect(history.position, 2);
    expect(history.isDirty, isFalse);

    history.markDirty();
    expect(history.isDirty, isTrue);
  });

  test('撤销后录入新命令会裁剪旧重做分支', () {
    final events = <String>[];
    final history = DocumentEditHistory(maxEntries: 4);
    final first = _RecordingCommand('first', events);
    final second = _RecordingCommand('second', events);
    final replacement = _RecordingCommand('replacement', events);

    history
      ..push(first)
      ..push(second);
    history.undo();
    history.push(replacement);

    expect(history.entryCount, 2);
    expect(history.position, 2);
    expect(history.canRedo, isFalse);
    history.undo();
    history.undo();
    expect(events, <String>['undo:second', 'undo:replacement', 'undo:first']);
  });

  test('超过容量时裁剪最早命令并保留剩余命令的撤销顺序', () {
    final events = <String>[];
    final history = DocumentEditHistory(maxEntries: 2);
    final first = _RecordingCommand('first', events);
    final second = _RecordingCommand('second', events);
    final third = _RecordingCommand('third', events);

    history
      ..push(first)
      ..push(second)
      ..push(third);

    expect(history.entryCount, 2);
    expect(history.position, 2);
    expect(history.undo(), isTrue);
    expect(history.undo(), isTrue);
    expect(history.undo(), isFalse);
    expect(events, <String>['undo:third', 'undo:second']);

    expect(history.redo(), isTrue);
    expect(history.redo(), isTrue);
    expect(events, <String>[
      'undo:third',
      'undo:second',
      'redo:second',
      'redo:third',
    ]);
  });
}

class _RecordingCommand extends DocCommand {
  _RecordingCommand(this.name, this.events);

  final String name;
  final List<String> events;

  @override
  void redo() => events.add('redo:$name');

  @override
  void undo() => events.add('undo:$name');
}
