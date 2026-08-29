// 由 Claude 团队生成 | Drawing Notes App
// EdgelessCommandPalette 测试：命令构建 + 搜索（纯函数，无 widget 依赖）。

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_command_palette.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_controller.dart';

EdgelessController _twoFrames() {
  return EdgelessController(
    doc: EdgelessDoc(
      id: 'e',
      frames: [
        NoteFrame(
          id: 'f1',
          x: 100,
          y: 100,
          w: 200,
          h: 200,
          doc: NoteBlockDoc.empty('d1'),
          zIndex: 1,
        ),
        NoteFrame(
          id: 'f2',
          x: 400,
          y: 100,
          w: 200,
          h: 200,
          doc: NoteBlockDoc.empty('d2'),
          zIndex: 1,
        ),
      ],
      camera: EdgelessCamera.initial,
    ),
  );
}

void main() {
  group('edgelessFrameTitle', () {
    test('空标题显示「未命名 N」', () {
      expect(edgelessFrameTitle('', 0), '未命名　1');
      expect(edgelessFrameTitle('   ', 2), '未命名　3');
    });

    test('有标题直接用标题', () {
      expect(edgelessFrameTitle('设计系统', 0), '设计系统');
    });
  });

  group('buildEdgelessCommands', () {
    test('包含通用命令 + 每个帧的跳转命令', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      final ids = cmds.map((e) => e.id).toList();
      expect(ids, contains('add-note'));
      expect(ids, contains('toggle-connect'));
      expect(ids, contains('group-selection'));
      expect(ids, contains('fit-content'));
      expect(ids, contains('fit-selection'));
      expect(ids, contains('zoom-in'));
      expect(ids, contains('zoom-out'));
      expect(ids, contains('toggle-multiselect'));
      expect(ids, contains('clear-selection'));
      expect(ids, contains('focus-selection'));
      expect(ids, contains('goto-frame-f1'));
      expect(ids, contains('goto-frame-f2'));
    });

    test('编组命令在选中 <2 帧时禁用', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      final group = cmds.firstWhere((e) => e.id == 'group-selection');
      expect(group.enabled, isFalse);
    });

    test('跳转命令标题取帧标题', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      final jump = cmds.firstWhere((e) => e.id == 'goto-frame-f1');
      expect(jump.label, contains('未命名'));
    });
  });

  group('searchEdgelessCommands', () {
    test('空查询返回原列表（同实例）', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      expect(searchEdgelessCommands(cmds, ''), same(cmds));
    });

    test('按分组名过滤', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      final hits = searchEdgelessCommands(cmds, '视图');
      expect(hits, isNotEmpty);
      for (final h in hits) {
        expect(h.group, '视图');
      }
    });

    test('按关键词匹配（不区分大小写）', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      final hits = searchEdgelessCommands(cmds, 'GROUP');
      expect(hits.map((e) => e.id), contains('group-selection'));
    });

    test('按标签中文匹配', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      final hits = searchEdgelessCommands(cmds, '新建');
      expect(hits.map((e) => e.id), contains('add-note'));
    });

    test('保持原顺序', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      // 查询「编」命中分组为「编辑」的 add-note 与「编组所选」，二者须保持构建顺序。
      final hits = searchEdgelessCommands(cmds, '编');
      final idxAdd = hits.indexWhere((e) => e.id == 'add-note');
      final idxGroup = hits.indexWhere((e) => e.id == 'group-selection');
      expect(idxAdd, isNonNegative);
      expect(idxGroup, isNonNegative);
      expect(idxAdd, lessThan(idxGroup));
    });

    test('无匹配返回空', () {
      final c = _twoFrames();
      final cmds = buildEdgelessCommands(c);
      expect(searchEdgelessCommands(cmds, 'zzzz'), isEmpty);
    });
  });
}
