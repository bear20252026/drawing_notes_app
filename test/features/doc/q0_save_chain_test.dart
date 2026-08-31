// Q0 附加回归：正文输入 → 自动保存链 → store 内容含输入文本（完整生命周期）。
//
// 背景：真机集成测试发现"输入正文后保存快照为空"（架构审计 2026-08-31）。
// 本测试用 FakeAsync pump 推进防抖 Timer，覆盖 DocPage→DocController→store 全链。

import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

class _MemStore {
  final Map<String, NoteBlockDoc> docs = {};
  Future<void> save(NoteBlockDoc d) async => docs[d.id] = d;
}

void main() {
  testWidgets('正文输入 → 防抖保存 → store 内容含输入文本', (tester) async {
    final mem = _MemStore();
    final doc = NoteBlockDoc(
      id: 'q0-repro',
      title: '',
      body: [NoteBlock.textBlock('b1', text: '')],
      createdAt: DateTime(2026, 8, 31),
      updatedAt: DateTime(2026, 8, 31),
    );
    var saved = false;
    await tester.pumpWidget(
      m.MaterialApp(
        theme: AppDesign.lightTheme(),
        home: DocPage(
          document: doc,
          controller: DocController(
            onSave: (d) async {
              await mem.save(d);
              saved = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bodyField = find.byType(m.TextField).last;
    await tester.enterText(bodyField, 'Q0 复现文本');
    // 推进防抖（1.2s）+ 合帧（0.5s）+ 写盘余量。
    // 注意：pumpAndSettle 在保存 Timer（无帧调度）场景会提前停止，
    // 必须用固定步长 pump 推进 fake clock 触发到期 Timer。
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(saved, isTrue, reason: '防抖保存应已触发');
    final stored = mem.docs['q0-repro']!;
    expect(
      stored.body.first.text,
      'Q0 复现文本',
      reason: '保存快照必须包含输入的正文文本（真机曾保存为空）',
    );
  });
}
