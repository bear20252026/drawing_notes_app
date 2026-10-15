import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/features/doc/presentation/table_edit_ops.dart';

void main() {
  group('TableEditOps 纯逻辑', () {
    test('insertRow 在底部插入新行', () {
      final (newRows, newTexts) = TableEditOps.insertRow(2, 3, [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ]);
      expect(newRows, 3);
      expect(newTexts, ['a', 'b', 'c', 'd', 'e', 'f', '', '', '']);
    });

    test('insertRow 在指定行后插入', () {
      final (newRows, newTexts) = TableEditOps.insertRow(2, 2, [
        'a',
        'b',
        'c',
        'd',
      ], atRow: 0);
      expect(newRows, 3);
      expect(newTexts, ['a', 'b', '', '', 'c', 'd']);
    });

    test('deleteRow 删除最后一行（默认 atRow=-1）', () {
      final (newRows, newTexts) = TableEditOps.deleteRow(3, 2, [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ]);
      // 3 行 (a,b | c,d | e,f) → 删除第 2 行 → 2 行 (a,b | c,d)
      expect(newRows, 2);
      expect(newTexts, ['a', 'b', 'c', 'd']);
    });

    test('deleteRow 删除指定行', () {
      final (newRows, newTexts) = TableEditOps.deleteRow(3, 2, [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ], atRow: 1);
      // 删除第 1 行 (c,d) → (a,b | e,f)
      expect(newRows, 2);
      expect(newTexts, ['a', 'b', 'e', 'f']);
    });

    test('deleteRow 保留至少 1 行', () {
      final (newRows, newTexts) = TableEditOps.deleteRow(1, 2, ['a', 'b']);
      expect(newRows, 1);
      expect(newTexts, ['a', 'b']);
    });

    test('insertCol 在底部插入新列', () {
      final (newCols, newTexts) = TableEditOps.insertCol(2, 2, [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(newCols, 3);
      expect(newTexts, ['a', 'b', '', 'c', 'd', '']);
    });

    test('insertCol 在指定列后插入', () {
      final (newCols, newTexts) = TableEditOps.insertCol(2, 2, [
        'a',
        'b',
        'c',
        'd',
      ], atCol: 0);
      expect(newCols, 3);
      expect(newTexts, ['a', '', 'b', 'c', '', 'd']);
    });

    test('deleteCol 删除最后一列（默认 atCol=-1）', () {
      final (newCols, newTexts) = TableEditOps.deleteCol(2, 3, [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ]);
      // 3 列 (a,b,c | d,e,f) → 删除第 2 列 (c,f) → (a,b | d,e)
      expect(newCols, 2);
      expect(newTexts, ['a', 'b', 'd', 'e']);
    });

    test('deleteCol 删除指定列', () {
      final (newCols, newTexts) = TableEditOps.deleteCol(2, 3, [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ], atCol: 0);
      // 删除第 0 列 (a,d) → (b,c | e,f)
      expect(newCols, 2);
      expect(newTexts, ['b', 'c', 'e', 'f']);
    });

    test('deleteCol 保留至少 1 列', () {
      final (newCols, newTexts) = TableEditOps.deleteCol(2, 1, ['a', 'b']);
      expect(newCols, 1);
      expect(newTexts, ['a', 'b']);
    });

    test('updateCellText 更新指定单元格', () {
      final result = TableEditOps.updateCellText(
        3,
        ['a', 'b', 'c', 'd', 'e', 'f'],
        rowIndex: 1,
        colIndex: 1,
        text: 'NEW',
      );
      expect(result, ['a', 'b', 'c', 'd', 'NEW', 'f']);
    });
  });

  // FDC-02：上限此前只存在于读侧的三处 clamp（每处字面量各写一遍），
  // 写侧一处都没有——连点「添加列」把 cols=11 落盘后，重开时读侧按
  // cols=10 重排行主序数组，每行整体错一格。下面这组用例把「写侧也认
  // 这条线」钉住；UI 侧的禁用/零动作用例见 table_editor_widget_test。
  group('TableEditOps 行列上限（写侧与读侧同源）', () {
    test('insertCol 在 colMax-1 时仍可增到上限（边界不外溢一格）', () {
      final (newCols, newTexts) = TableEditOps.insertCol(
        1,
        kNoteTableMaxCols - 1,
        List<String>.filled(kNoteTableMaxCols - 1, 'x'),
      );
      expect(newCols, kNoteTableMaxCols);
      expect(newTexts.length, kNoteTableMaxCols);
    });

    test('insertCol 已达上限时原样返回，不新增列也不新增格子', () {
      final texts = List<String>.filled(kNoteTableMaxCols, 'x');
      final (newCols, newTexts) = TableEditOps.insertCol(
        1,
        kNoteTableMaxCols,
        texts,
      );
      expect(newCols, kNoteTableMaxCols);
      expect(newTexts.length, kNoteTableMaxCols);
      expect(
        identical(newTexts, texts),
        isTrue,
        reason: '返回入参同一实例是调用方判定「什么都没变、不必发变更」的凭据',
      );
    });

    test('insertRow 在 rowMax-1 时仍可增到上限', () {
      final (newRows, newTexts) = TableEditOps.insertRow(
        kNoteTableMaxRows - 1,
        2,
        List<String>.filled((kNoteTableMaxRows - 1) * 2, 'x'),
      );
      expect(newRows, kNoteTableMaxRows);
      expect(newTexts.length, kNoteTableMaxRows * 2);
    });

    test('insertRow 已达上限时原样返回', () {
      final texts = List<String>.filled(kNoteTableMaxRows * 2, 'x');
      final (newRows, newTexts) = TableEditOps.insertRow(
        kNoteTableMaxRows,
        2,
        texts,
        atRow: 0,
      );
      expect(newRows, kNoteTableMaxRows);
      expect(identical(newTexts, texts), isTrue);
    });

    test('noteTableSize 归一：缺省 1×1、越界夹回、非法值不抛', () {
      expect(noteTableSize(const {}), (1, 1));
      expect(noteTableSize(const {'rows': 0, 'cols': -3}), (1, 1));
      expect(noteTableSize(const {'rows': 9999, 'cols': 9999}), (
        kNoteTableMaxRows,
        kNoteTableMaxCols,
      ));
    });

    test('上限字面量不得再出现在读侧（单一来源，防第四份拷贝）', () {
      // 读侧原来有三处各写一遍 `clamp(1, 50)` / `clamp(1, 10)`——数字改了
      // 其中一处就再也对不上。现在唯一的出处是 note_block.dart 的两个常量。
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains("props['rows']") || text.contains("props['cols']")) {
          // 只有定义常量的那个文件允许出现归一表达式。
          if (!entity.path.endsWith('note_block.dart')) {
            offenders.add(entity.path);
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '行列 props 的读取必须走 noteTableSize：$offenders',
      );

      // 归一函数本体之外，不得再有 50/10 的表格 clamp 字面量。
      final clamps = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final line in entity.readAsLinesSync()) {
          if (line.contains('clamp(1, 50)') || line.contains('clamp(1, 10)')) {
            clamps.add('${entity.path}: $line');
          }
        }
      }
      expect(clamps, isEmpty, reason: '残留的字面量 clamp：$clamps');
    });
  });
}
