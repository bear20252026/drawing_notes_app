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
      //
      // ⚠ 审计 TE-TST-04（2026-10-16）：这一整块是 `expect(x, isEmpty)` 形状，而且
      // **今天两个集合都真的是空**——`clamp(1, 50)` / `clamp(1, 10)` 在全库 0 处，
      // `props['rows'|'cols']` 只剩 1 个文件（就是定义常量那个，被豁免掉）。
      // 也就是说「扫描坏了」和「纪律守住了」在这里同形。补三件事：
      // ① 判据抽成 `_rawTableReadOffenders` / `_literalClampOffenders`，与下面那条
      //    canary **共用同一份定义**（R11 的纪律：canary 抄一份就等于什么都没验）；
      // ② 分母下限：扫到的文件数、以及豁免规则实际扫到的候选文件数；
      // ③ 正控：人造样本必须报出来。
      final sources = _readLibSources();
      expect(
        sources.length,
        greaterThanOrEqualTo(300),
        reason: '只扫到 ${sources.length} 个 .dart（实测基线 354）⇒ 扫描面塌了，下面两句 isEmpty 无裁决力',
      );
      final candidates = sources.keys
          .where((p) => !p.endsWith('note_block.dart'))
          .length;
      expect(
        candidates,
        greaterThanOrEqualTo(290),
        reason: '豁免之后只剩 $candidates 个候选文件 ⇒ 豁免条件写宽了，等于整条扫描放行',
      );

      final offenders = _rawTableReadOffenders(sources);
      expect(
        offenders,
        isEmpty,
        reason: '行列 props 的读取必须走 noteTableSize：$offenders',
      );
      final clamps = _literalClampOffenders(sources);
      expect(clamps, isEmpty, reason: '残留的字面量 clamp：$clamps');
    });

    test('判据自证：第四份拷贝与残留字面量都必须被抓到', () {
      // 正控一：又一个文件直接读 `props['rows']` 而不走归一入口（突变 K-1：
      // 把判据里的 `props['rows']` 改错，这里零报而真实库照样绿）。
      expect(
        _rawTableReadOffenders(const {
          'lib/features/doc/presentation/sneaky.dart':
              "final r = block.props['rows'] ?? 3;",
        }),
        hasLength(1),
        reason: '读侧第四份拷贝必须被拦在合入之前',
      );
      // 正控二：残留的 50 上限字面量。
      expect(
        _literalClampOffenders(const {
          'lib/features/doc/domain/x.dart': 'final cols = raw.clamp(1, 50).toInt();',
        }),
        hasLength(1),
        reason: '突变 K-2：`clamp(1, 50)` 这个字面量比对若被改成别的写法就永远零报',
      );
      // 反向锁：定义常量的那个文件允许出现归一表达式；合法入口不许误报。
      expect(
        _rawTableReadOffenders(const {
          'lib/core/documents/note_block.dart':
              "final r = props['rows']; final c = props['cols'];",
        }),
        isEmpty,
        reason: '豁免那一处定义是设计，不是漏口——反向锁钉住它，别把它改成「一律报警」',
      );
      expect(
        _literalClampOffenders(const {
          'lib/core/documents/note_block.dart':
              'const kNoteTableMaxRows = 50; // rows.clamp(1, kNoteTableMaxRows)',
        }),
        isEmpty,
      );
    });
  });
}

/// 判据一：除定义常量的 `note_block.dart` 之外，谁再直接读 `props['rows'/'cols']`。
List<String> _rawTableReadOffenders(Map<String, String> sources) {
  final offenders = <String>[];
  for (final entry in sources.entries) {
    if (!entry.value.contains("props['rows']") &&
        !entry.value.contains("props['cols']")) {
      continue;
    }
    if (entry.key.endsWith('note_block.dart')) continue;
    offenders.add(entry.key);
  }
  return offenders;
}

/// 判据二：全库不得再出现表格上限的裸字面量 clamp。
List<String> _literalClampOffenders(Map<String, String> sources) {
  final clamps = <String>[];
  for (final entry in sources.entries) {
    var lineNo = 0;
    for (final line in entry.value.split('\n')) {
      lineNo++;
      if (line.contains('clamp(1, 50)') || line.contains('clamp(1, 10)')) {
        clamps.add('${entry.key}:$lineNo $line');
      }
    }
  }
  return clamps;
}

Map<String, String> _readLibSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    sources[entity.path.replaceAll(r'\', '/')] = entity.readAsStringSync();
  }
  return sources;
}
