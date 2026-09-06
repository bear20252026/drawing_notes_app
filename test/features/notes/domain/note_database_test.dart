// P3-1 契约测试：NoteDatabase 数据库块领域模型（表/看板/列表视图 + 字段/记录/排序/筛选）。
// 由 lead 先写（锁定 API 契约），队友 A 实现 lib/features/notes/domain/note_database.dart 使其通过。
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_database.dart';

void main() {
  group('NoteFieldDef', () {
    test('默认 options 为空', () {
      const f = NoteFieldDef(id: 'name', name: '名称', type: NoteFieldType.text);
      expect(f.id, 'name');
      expect(f.name, '名称');
      expect(f.type, NoteFieldType.text);
      expect(f.options, isEmpty);
    });

    test('copyWith 只更新给定字段', () {
      const f = NoteFieldDef(
        id: 'status',
        name: '状态',
        type: NoteFieldType.select,
        options: ['A', 'B'],
      );
      final f2 = f.copyWith(name: '优先级', options: ['P0', 'P1']);
      expect(f2.id, 'status');
      expect(f2.name, '优先级');
      expect(f2.type, NoteFieldType.select);
      expect(f2.options, ['P0', 'P1']);
      expect(f.options, ['A', 'B'], reason: '不可变：原对象不被改写');
    });

    test('序列化往返', () {
      const f = NoteFieldDef(
        id: 's',
        name: '阶段',
        type: NoteFieldType.select,
        options: ['待办', '进行中'],
      );
      final back = NoteFieldDef.fromJson(f.toJson());
      expect(back, f);
    });

    test('相等性（含 options 顺序）', () {
      const a = NoteFieldDef(
        id: 's',
        name: '阶段',
        type: NoteFieldType.select,
        options: ['A', 'B'],
      );
      const b = NoteFieldDef(
        id: 's',
        name: '阶段',
        type: NoteFieldType.select,
        options: ['A', 'B'],
      );
      const c = NoteFieldDef(
        id: 's',
        name: '阶段',
        type: NoteFieldType.select,
        options: ['B', 'A'],
      );
      expect(a, b);
      expect(a == c, isFalse);
    });
  });

  group('NoteRecord', () {
    test('默认 cells 为空，cell() 返回 null', () {
      const r = NoteRecord(id: 'r1');
      expect(r.cells, isEmpty);
      expect(r.cell('name'), isNull);
    });

    test('cell() 返回字段值', () {
      const r = NoteRecord(id: 'r1', cells: {'name': '张三', 'age': 18});
      expect(r.cell('name'), '张三');
      expect(r.cell('age'), 18);
    });

    test('copyWith 替换 cells', () {
      const r = NoteRecord(id: 'r1', cells: {'name': '张三'});
      final r2 = r.copyWith(cells: {'name': '李四'});
      expect(r2.cells['name'], '李四');
      expect(r.cells['name'], '张三', reason: '不可变');
    });

    test('序列化往返', () {
      const r = NoteRecord(id: 'r1', cells: {'name': '张三', 'n': 3});
      final back = NoteRecord.fromJson(r.toJson());
      expect(back, r);
    });
  });

  group('NoteDatabase.empty', () {
    test('空字段/空记录/默认表视图', () {
      final db = NoteDatabase.empty();
      expect(db.fields, isEmpty);
      expect(db.records, isEmpty);
      expect(db.viewType, DatabaseViewType.table);
      expect(db.sortFieldId, isNull);
      expect(db.sortAscending, isTrue);
      expect(db.title, isEmpty);
    });
  });

  group('字段 CRUD', () {
    test('addField 追加字段', () {
      final db = NoteDatabase.empty().addField(
        const NoteFieldDef(id: 'name', name: '名称', type: NoteFieldType.text),
      );
      expect(db.fields.length, 1);
      expect(db.fields.first.id, 'name');
      expect(NoteDatabase.empty().fields, isEmpty, reason: '不可变');
    });

    test('renameField 更新字段名', () {
      final db = NoteDatabase.empty()
          .addField(
            const NoteFieldDef(id: 'n', name: '名称', type: NoteFieldType.text),
          )
          .renameField('n', '标题');
      expect(db.fieldById('n')!.name, '标题');
    });

    test('updateFieldOptions 更新 select 选项', () {
      final db = NoteDatabase.empty()
          .addField(
            const NoteFieldDef(
              id: 's',
              name: '状态',
              type: NoteFieldType.select,
              options: ['A', 'B'],
            ),
          )
          .updateFieldOptions('s', ['P0', 'P1', 'P2']);
      expect(db.fieldById('s')!.options, ['P0', 'P1', 'P2']);
    });

    test('removeField 删除字段并清掉所有记录里的对应 cell', () {
      var db = NoteDatabase.empty()
          .addField(
            const NoteFieldDef(id: 'n', name: '名称', type: NoteFieldType.text),
          )
          .addField(
            const NoteFieldDef(id: 'a', name: '年龄', type: NoteFieldType.number),
          )
          .addRecord(const NoteRecord(id: 'r1', cells: {'n': '张三', 'a': 18}));
      db = db.removeField('a');
      expect(db.fieldById('a'), isNull);
      expect(db.records.first.cell('a'), isNull);
      expect(db.records.first.cell('n'), '张三', reason: '其他字段保留');
    });
  });

  group('记录 CRUD', () {
    test('addRecord 追加记录', () {
      final db = NoteDatabase.empty().addRecord(const NoteRecord(id: 'r1'));
      expect(db.records.length, 1);
      expect(db.records.first.id, 'r1');
    });

    test('updateCell 更新单元格', () {
      final db = NoteDatabase.empty()
          .addRecord(const NoteRecord(id: 'r1', cells: {'n': '张三'}))
          .updateCell('r1', 'n', '李四');
      expect(db.recordById('r1')!.cell('n'), '李四');
    });

    test('updateCell 不存在的记录原样返回', () {
      final db = NoteDatabase.empty().updateCell('ghost', 'n', 'x');
      expect(db.records, isEmpty);
    });

    test('removeRecord 删除记录', () {
      final db = NoteDatabase.empty()
          .addRecord(const NoteRecord(id: 'r1'))
          .addRecord(const NoteRecord(id: 'r2'))
          .removeRecord('r1');
      expect(db.records.length, 1);
      expect(db.recordById('r1'), isNull);
      expect(db.recordById('r2'), isNotNull);
    });

    test('insertRecordAt 按索引插入', () {
      final db = NoteDatabase.empty()
          .addRecord(const NoteRecord(id: 'r1'))
          .addRecord(const NoteRecord(id: 'r2'))
          .insertRecordAt(1, const NoteRecord(id: 'r3'));
      expect(db.records.map((r) => r.id).toList(), ['r1', 'r3', 'r2']);
    });
  });

  group('视图与排序', () {
    NoteDatabase db() => NoteDatabase.empty()
        .addField(
          const NoteFieldDef(id: 'name', name: '名称', type: NoteFieldType.text),
        )
        .addField(
          const NoteFieldDef(id: 'n', name: '数量', type: NoteFieldType.number),
        )
        .addRecord(const NoteRecord(id: 'a', cells: {'name': '香蕉', 'n': 3}))
        .addRecord(const NoteRecord(id: 'b', cells: {'name': '苹果', 'n': 1}))
        .addRecord(const NoteRecord(id: 'c', cells: {'name': '橙子', 'n': 2}));

    test('setViewType 切换视图', () {
      final d = db().setViewType(DatabaseViewType.kanban);
      expect(d.viewType, DatabaseViewType.kanban);
      expect(db().viewType, DatabaseViewType.table, reason: '不可变');
    });

    test('setSort 数字升序/降序', () {
      final asc = db().setSort('n').sortedRecords;
      expect(asc.map((r) => r.id).toList(), ['b', 'c', 'a']);
      final desc = db().setSort('n', ascending: false).sortedRecords;
      expect(desc.map((r) => r.id).toList(), ['a', 'c', 'b']);
    });

    test('setSort 文本升序', () {
      final asc = db().setSort('name').sortedRecords;
      expect(asc.map((r) => r.id).toList(), ['c', 'b', 'a']); // 橙/苹/香 (拼音序)
    });

    test('clearSort 恢复原始顺序', () {
      final d = db().setSort('n', ascending: false).clearSort();
      expect(d.sortFieldId, isNull);
      expect(d.sortedRecords.map((r) => r.id).toList(), ['a', 'b', 'c']);
    });

    test('数字字段用数值比较，非数字回退字符串', () {
      final d = NoteDatabase.empty()
          .addField(
            const NoteFieldDef(id: 'n', name: '数量', type: NoteFieldType.number),
          )
          .addRecord(const NoteRecord(id: 'x', cells: {'n': 10}))
          .addRecord(const NoteRecord(id: 'y', cells: {'n': 9}));
      expect(d.setSort('n').sortedRecords.map((r) => r.id).toList(), [
        'y',
        'x',
      ], reason: '10 与 9 应按数字而非字典序（10 不会排在 9 前）');
    });
  });

  group('筛选', () {
    NoteDatabase db() => NoteDatabase.empty()
        .addField(
          const NoteFieldDef(id: 'name', name: '名称', type: NoteFieldType.text),
        )
        .addField(
          const NoteFieldDef(id: 'n', name: '数量', type: NoteFieldType.number),
        )
        .addRecord(const NoteRecord(id: 'a', cells: {'name': '香蕉', 'n': 3}))
        .addRecord(const NoteRecord(id: 'b', cells: {'name': '苹果', 'n': 1}));

    test('filterRecords 按字段文本 contains（大小写不敏感）', () {
      final hits = db().filterRecords(query: '苹果');
      expect(hits.map((r) => r.id).toList(), ['b']);
    });

    test('filterRecords 空 query 返回全部', () {
      expect(db().filterRecords().length, 2);
      expect(db().filterRecords(query: '').length, 2);
    });

    test('filterRecords 无命中返回空', () {
      expect(db().filterRecords(query: '不存在'), isEmpty);
    });
  });

  group('displayValue 显示字符串', () {
    NoteDatabase db() => NoteDatabase.empty()
        .addField(
          const NoteFieldDef(id: 't', name: '文本', type: NoteFieldType.text),
        )
        .addField(
          const NoteFieldDef(id: 'n', name: '数字', type: NoteFieldType.number),
        )
        .addField(
          const NoteFieldDef(id: 's', name: '选项', type: NoteFieldType.select),
        )
        .addField(
          const NoteFieldDef(id: 'c', name: '勾选', type: NoteFieldType.checkbox),
        )
        .addField(
          const NoteFieldDef(id: 'd', name: '日期', type: NoteFieldType.date),
        )
        .addRecord(
          const NoteRecord(
            id: 'r',
            cells: {
              't': '你好',
              'n': 42,
              's': 'P1',
              'c': true,
              'd': '2026-01-01',
            },
          ),
        );

    test('各字段类型的字符串形式', () {
      final dbx = db();
      expect(dbx.displayValue(dbx.recordById('r')!, dbx.fieldById('t')!), '你好');
      expect(dbx.displayValue(dbx.recordById('r')!, dbx.fieldById('n')!), '42');
      expect(dbx.displayValue(dbx.recordById('r')!, dbx.fieldById('s')!), 'P1');
      expect(dbx.displayValue(dbx.recordById('r')!, dbx.fieldById('c')!), '✓');
      expect(
        dbx.displayValue(dbx.recordById('r')!, dbx.fieldById('d')!),
        '2026-01-01',
      );
    });

    test('checkbox 为 false/null 显示空', () {
      final dbx = db().updateCell('r', 'c', false);
      expect(dbx.displayValue(dbx.recordById('r')!, dbx.fieldById('c')!), '');
    });

    test('空值显示空字符串', () {
      final dbx = db();
      const rec = NoteRecord(id: 'r2');
      expect(dbx.displayValue(rec, dbx.fieldById('t')!), '');
    });
  });

  group('序列化与相等', () {
    test('toJson/fromJson 往返保持全量', () {
      var db = NoteDatabase.empty(title: '任务表');
      db = db
          .addField(
            const NoteFieldDef(id: 'n', name: '名称', type: NoteFieldType.text),
          )
          .addField(
            const NoteFieldDef(
              id: 's',
              name: '状态',
              type: NoteFieldType.select,
              options: ['待办', '完成'],
            ),
          )
          .addRecord(const NoteRecord(id: 'r1', cells: {'n': '写文档', 's': '待办'}))
          .addRecord(const NoteRecord(id: 'r2', cells: {'n': '复盘', 's': '完成'}))
          .setSort('n', ascending: false);
      final j = db.toJson();
      final back = NoteDatabase.fromJson(j);
      expect(back, db);
      expect(back.title, '任务表');
      expect(back.viewType, DatabaseViewType.table);
      expect(back.sortFieldId, 'n');
      expect(back.sortAscending, isFalse);
    });

    test('相等性基于全字段', () {
      final a = NoteDatabase.empty().addRecord(const NoteRecord(id: 'r1'));
      final b = NoteDatabase.empty().addRecord(const NoteRecord(id: 'r1'));
      final c = NoteDatabase.empty().addRecord(const NoteRecord(id: 'r2'));
      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
