import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/presentation/notebook_reader_page.dart';

/// W2 翻页阅读模式测试：页码指示器 + 键盘翻页 + 点击进入编辑。
void main() {
  testWidgets('初始显示第 1 页；↓ 键翻到第 2 页', (tester) async {
    final notebook = Notebook(id: 'nb', title: '阅读测试')..pages.addAll([
      _page('p1'),
      _page('p2'),
      _page('p3'),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: NotebookReaderPage(notebook: notebook, onEditPage: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 1 页 / 共 3 页'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('第 2 页 / 共 3 页'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('第 1 页 / 共 3 页'), findsOneWidget);
  });

  testWidgets('点击页面回调 onEditPage 且携带对应页', (tester) async {
    final notebook = Notebook(id: 'nb', title: '点击测试')
      ..pages.add(_page('p1', title: '第一页'));
    NotebookPage? edited;

    await tester.pumpWidget(
      MaterialApp(
        home: NotebookReaderPage(
          notebook: notebook,
          onEditPage: (page) => edited = page,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reader-sheet-p1')));
    await tester.pump();

    expect(edited?.id, 'p1');
  });

  testWidgets('边界：末页按 ↓ 不越界', (tester) async {
    final notebook = Notebook(id: 'nb', title: '边界测试')
      ..pages.addAll([_page('p1'), _page('p2')]);

    await tester.pumpWidget(
      MaterialApp(home: NotebookReaderPage(notebook: notebook, onEditPage: (_) {})),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(find.text('第 2 页 / 共 2 页'), findsOneWidget);
  });
}

NotebookPage _page(String id, {String? title}) => NotebookPage(
  id: id,
  title: title ?? '页 $id',
  document: DrawingDocument(
    id: id,
    title: title ?? '页 $id',
    width: 640,
    height: 480,
    layers: [
      Layer(
        id: 'layer_1',
        name: '图层 1',
        strokes: [
          Stroke(
            points: const [
              StrokePoint(10, 10, 1.0),
              StrokePoint(200, 120, 1.0),
            ],
            color: const Color(0xFF000000),
            width: 4,
            type: BrushType.pen,
          ),
        ],
      ),
    ],
  ),
);
