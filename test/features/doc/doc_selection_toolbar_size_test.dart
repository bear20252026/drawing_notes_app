// 回归测试：浮动选区工具条不得撑满全屏（黑幕 bug）。
// 根因：Overlay 对未 Positioned 包裹的子项施加 tight 全屏约束
// （Flutter overlay.dart: nonPositionedChildConstraints = tight(size)），
// 深色胶囊被拉成覆盖全屏的黑幕。修复：CompositedTransformFollower 外包 Positioned。
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/features/doc/doc_editor.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

void main() {
  testWidgets('选中块文字后浮动工具条应为小胶囊而非全屏黑幕', (tester) async {
    final doc = NoteBlockDoc(
      id: 'sel-tb',
      title: '',
      body: [NoteBlock.textBlock('b1', text: '选我选我选我')],
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await tester.pumpWidget(
      m.MaterialApp(
        home: m.Scaffold(
          body: DocEditor(document: doc, showChrome: false, onDirty: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(m.TextField).last, '选我选我选我');
    await tester.pump(const Duration(milliseconds: 100));

    // 构造非折叠选区（模拟鼠标划选），触发浮动工具条显示。
    final editable = tester.state<m.EditableTextState>(
      find.byType(m.EditableText).last,
    );
    editable.widget.controller.selection = const m.TextSelection(
      baseOffset: 0,
      extentOffset: 6,
    );
    await tester.pump(const Duration(milliseconds: 100));

    final pillFinder = find.byWidgetPredicate(
      (w) =>
          w is m.Container &&
          w.decoration is m.BoxDecoration &&
          // 深色胶囊 = AppleColor.ink（0xFF1D1D1F，2026-09-07 令牌化）。
          (w.decoration as m.BoxDecoration).color == AppleColor.ink,
    );
    expect(pillFinder, findsOneWidget, reason: '深色胶囊应已出现在 overlay 中');

    final size = tester.getSize(pillFinder);
    // 修复前：tight 全屏约束 → 800x600（测试默认表面）。
    // 修复后：Positioned 松约束 → 胶囊贴合内容。
    // U4a 触控铁律（≥44 热区）：6 图标 44px = 264 + 分隔线 9 + 内边距 4
    // ≈ 277，宽度上限相应放宽到 340——仍远小于 800（黑幕回归立即触发）。
    expect(size.width, lessThan(340), reason: '工具条宽度应贴合按钮行，而非被撑满全屏');
    expect(size.height, lessThan(80), reason: '工具条高度应贴合单行图标，而非被撑满全屏');
  });
}
