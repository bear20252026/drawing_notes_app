// M8-2 note_block_doc_to_frames.dart 单元测试。

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc_to_frames.dart';

void main() {
  group('noteBlockDocToFrames', () {
    test('无 heading → 单帧含全部块', () {
      final doc = NoteBlockDoc(
        id: 'doc1',
        title: '无标题',
        body: [
          NoteBlock.textBlock('b1', text: '第一段'),
          NoteBlock.textBlock('b2', text: '第二段'),
          NoteBlock.textBlock('b3', text: '第三段'),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const initialRect = Rect.fromLTWH(100, 200, 300, 400);
      final frames = noteBlockDocToFrames(
        doc,
        docId: 'doc1',
        initialRect: initialRect,
      );

      expect(frames.length, 1);
      expect(frames.first.doc.body.length, 3);
      expect(frames.first.doc.title, '无标题');
      expect(frames.first.x, 100);
      expect(frames.first.y, 200);
      expect(frames.first.w, 300);
      expect(frames.first.h, 400);
      expect(frames.first.zIndex, 0);
    });

    test('多个 heading → 按 heading 拆成多帧', () {
      final doc = NoteBlockDoc(
        id: 'doc2',
        title: '文档标题',
        body: [
          NoteBlock.textBlock('b1', text: '前导文本'),
          NoteBlock.headingBlock('h1', level: 1, text: '标题一'),
          NoteBlock.textBlock('b2', text: '内容一'),
          NoteBlock.headingBlock('h2', level: 2, text: '标题二'),
          NoteBlock.textBlock('b3', text: '内容二'),
          NoteBlock.textBlock('b4', text: '内容三'),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const initialRect = Rect.fromLTWH(0, 0, 250, 350);
      final frames = noteBlockDocToFrames(
        doc,
        docId: 'doc2',
        initialRect: initialRect,
      );

      // 应拆成 3 个帧：[前导文本], [标题一, 内容一], [标题二, 内容二, 内容三]
      expect(frames.length, 3);

      // 第一帧：前导块 + 继承 doc.title
      expect(frames[0].doc.body.length, 1);
      expect(frames[0].doc.body.first.id, 'b1');
      expect(frames[0].doc.title, '文档标题');

      // 第二帧：heading 为首块
      expect(frames[1].doc.body.length, 2);
      expect(frames[1].doc.body.first.type, NoteBlockType.heading);
      expect(frames[1].doc.body.first.text, '标题一');
      expect(frames[1].doc.title, '标题一');

      // 第三帧：heading 为首块
      expect(frames[2].doc.body.length, 3);
      expect(frames[2].doc.body.first.type, NoteBlockType.heading);
      expect(frames[2].doc.body.first.text, '标题二');
      expect(frames[2].doc.title, '标题二');
    });

    test('heading 级联排布：y 递增、zIndex 递增', () {
      final doc = NoteBlockDoc(
        id: 'doc3',
        title: 'T',
        body: [
          NoteBlock.headingBlock('h1', level: 1, text: 'A'),
          NoteBlock.textBlock('b1', text: 'a1'),
          NoteBlock.headingBlock('h2', level: 2, text: 'B'),
          NoteBlock.textBlock('b2', text: 'b1'),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const initialRect = Rect.fromLTWH(10, 20, 200, 300);
      final frames = noteBlockDocToFrames(
        doc,
        docId: 'doc3',
        initialRect: initialRect,
        baseZ: 5,
      );

      expect(frames.length, 2);
      // 第一帧
      expect(frames[0].x, 10);
      expect(frames[0].y, 20);
      expect(frames[0].zIndex, 5);
      // 第二帧：y = 20 + 1*(300+64) = 384
      expect(frames[1].x, 10);
      expect(frames[1].y, 384);
      expect(frames[1].zIndex, 6);
    });

    test('前导块归入第一个帧', () {
      final doc = NoteBlockDoc(
        id: 'doc4',
        title: 'T',
        body: [
          NoteBlock.textBlock('lead1', text: '前导1'),
          NoteBlock.textBlock('lead2', text: '前导2'),
          NoteBlock.headingBlock('h1', level: 1, text: '标题'),
          NoteBlock.textBlock('b1', text: '内容'),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const initialRect = Rect.fromLTWH(0, 0, 200, 300);
      final frames = noteBlockDocToFrames(
        doc,
        docId: 'doc4',
        initialRect: initialRect,
      );

      expect(frames.length, 2);
      // 第一帧含前导块
      expect(frames[0].doc.body.length, 2);
      expect(frames[0].doc.body.map((b) => b.id).toList(), ['lead1', 'lead2']);
      // 第二帧以 heading 开头
      expect(frames[1].doc.body.first.type, NoteBlockType.heading);
    });
  });

  group('createBlankFrame', () {
    test('无 doc 时用 NoteBlockDoc.empty', () {
      const rect = Rect.fromLTWH(50, 60, 200, 300);
      final frame = createBlankFrame(docId: 'nb', rect: rect, zIndex: 3);

      expect(frame.id, 'nb_blank');
      expect(frame.x, 50);
      expect(frame.y, 60);
      expect(frame.zIndex, 3);
      expect(frame.doc.body, isNotEmpty); // empty doc 有一个空 text block
    });

    test('传入 doc 时使用该 doc', () {
      final customDoc = NoteBlockDoc(
        id: 'custom',
        title: '自定义',
        body: [NoteBlock.textBlock('c1', text: '内容')],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      const rect = Rect.fromLTWH(0, 0, 100, 100);
      final frame = createBlankFrame(
        docId: 'nb',
        rect: rect,
        zIndex: 0,
        doc: customDoc,
      );

      expect(frame.doc.title, '自定义');
      expect(frame.doc.body.length, 1);
    });
  });

  group('mergeFramesToDoc', () {
    test('保序 round-trip（无 heading 时 frames 拼回 == 原 body）', () {
      final originalBody = [
        NoteBlock.textBlock('b1', text: '第一段'),
        NoteBlock.textBlock('b2', text: '第二段'),
        NoteBlock.textBlock('b3', text: '第三段'),
      ];
      final doc = NoteBlockDoc(
        id: 'doc_rt',
        title: '原始',
        body: originalBody,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      const initialRect = Rect.fromLTWH(0, 0, 200, 300);
      final frames = noteBlockDocToFrames(
        doc,
        docId: 'doc_rt',
        initialRect: initialRect,
      );
      // 无 heading → 单帧
      expect(frames.length, 1);

      final merged = mergeFramesToDoc(frames, id: 'merged', title: '拼合');
      expect(merged.body.length, 3);
      expect(merged.body.map((b) => b.id).toList(), ['b1', 'b2', 'b3']);
      expect(merged.body.map((b) => b.text).toList(), ['第一段', '第二段', '第三段']);
      expect(merged.title, '拼合');
    });

    test('按 zIndex 升序拼合', () {
      final frame1 = NoteFrame(
        id: 'f1',
        x: 0,
        y: 0,
        w: 100,
        h: 100,
        zIndex: 2,
        doc: NoteBlockDoc(
          id: 'fd1',
          title: '',
          body: [NoteBlock.textBlock('c', text: '后')],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      final frame0 = NoteFrame(
        id: 'f0',
        x: 0,
        y: 0,
        w: 100,
        h: 100,
        zIndex: 0,
        doc: NoteBlockDoc(
          id: 'fd0',
          title: '',
          body: [NoteBlock.textBlock('a', text: '先')],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      final frame2 = NoteFrame(
        id: 'f2',
        x: 0,
        y: 0,
        w: 100,
        h: 100,
        zIndex: 1,
        doc: NoteBlockDoc(
          id: 'fd2',
          title: '',
          body: [NoteBlock.textBlock('b', text: '中')],
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      final merged = mergeFramesToDoc([frame1, frame0, frame2], id: 'm');
      // 应按 zIndex 0,1,2 排序 → a, b, c
      expect(merged.body.map((b) => b.text).toList(), ['先', '中', '后']);
    });

    test('空帧列表返回空 body', () {
      final merged = mergeFramesToDoc([], id: 'empty');
      expect(merged.body, isEmpty);
    });
  });
}
