// U5 审计残留回归（P1-19）：反向链接数据源 Future 缓存。
//
// 审计发现：反链面板每次保存（updatedAt 变化 → didUpdateWidget → _reload）
// 都经 getter 新建 Future——全量 listIds + 逐文档读盘解密，保存越频繁 IO
// 越重。U5b 修复：DocPage 首次访问后缓存 Future，保存触发的重算只做
// 内存 backlinksOf，零 IO。本测试用计数 loader 验证「多次保存仅一次加载」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

NoteBlockDoc _doc(String id, String title, List<String> texts) {
  return NoteBlockDoc(
    id: id,
    title: title,
    body: [
      for (final t in texts)
        NoteBlock.textBlock('b_${t.hashCode}_$id', text: t),
    ],
    createdAt: DateTime(2026, 9, 2),
    updatedAt: DateTime(2026, 9, 2, 12),
  );
}

void main() {
  testWidgets('多次保存后 allDocsLoader 仅调用一次（数据源缓存）', (tester) async {
    var loaderCalls = 0;
    final doc = _doc('u5-cache', 'U5 缓存验证', ['第一段']);

    await tester.pumpWidget(
      MaterialApp(
        home: DocPage(
          document: doc,
          controller: DocController(onSave: (_) async {}),
          allDocsLoader: () {
            loaderCalls++;
            return Future.value([doc]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loaderCalls, 1, reason: '首次 build 消费反链数据源应恰好加载一次');

    // 输入正文触发保存链（防抖 1.2s + 合帧——q0 同款固定步长 pump）。
    // 保存回写 updatedAt → _BacklinksPanel.didUpdateWidget → _reload：
    // 修复前此处会再次经 getter 新建 Future（loaderCalls 增长）；修复后
    // 复用缓存 Future，零加载。
    final bodyField = find.byType(TextField).last;
    await tester.enterText(bodyField, 'U5 缓存验证文本');
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(loaderCalls, 1, reason: '保存触发的反链重算必须复用缓存数据源（审计 P1-19）');
  });
}
