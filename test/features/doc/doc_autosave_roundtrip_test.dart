// AU-2 最小判据版（2026-10-05）：只问一个问题——**编辑正文之后，保存到底有没有被调度**？
//
// 背景：真机集成测试报「输入的正文没有落盘」（doc_lifecycle_test 第 167 行），
// 而带真实 store 的 widget 复现会挂住（store 走 Isolate.run / 页面有持续动画，
// pumpAndSettle 永不静息），所以这里**不接磁盘**，只把 `onSave` 换成计数器：
//  - 计数为 0 ⇒ 「编辑 → 标脏 → 调度 → 保存」这条腿在 UI 层就断了（CI 可复现的产品缺陷）；
//  - 计数 ≥1 ⇒ UI 层调度正常，问题在更下游（真实 store 写入 / 设备测试的定位），
//    据此把排查方向收敛，而不是继续在黑暗里试。
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/application/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/presentation/doc_page.dart';

void main() {
  NoteBlockDoc makeDoc() {
    final now = DateTime(2026, 10, 5, 10);
    return NoteBlockDoc(
      id: 'doc_probe',
      title: '探针',
      body: const [NoteBlock(id: 'p1', type: NoteBlockType.text, text: '正文')],
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('编辑正文后，保存回调必须被调度到（不接磁盘，只测这条腿）', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      m.MaterialApp(
        home: DocPage(
          document: makeDoc(),
          controller: DocController(
            onSave: (d) async {
              saves++;
            },
          ),
        ),
      ),
    );
    // 固定步长泵（不用 pumpAndSettle：本页有持续重绘源，静息判据不可靠）。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final bodyField = find.widgetWithText(m.TextField, '正文');
    expect(bodyField, findsOneWidget, reason: '正文块应是可编辑 TextField');

    await tester.enterText(bodyField, '探针串AU2');
    // 跨过防抖：pump(500ms) × 20 = 10s 假时钟。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(
      saves,
      greaterThan(0),
      reason:
          '输入正文后应触发自动保存调度。saves==0 意味着 P0-H1 的'
          '「编辑→标脏→调度→落盘」在 UI 层就断了。',
    );
  });
}
