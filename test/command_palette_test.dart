import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('命令面板：主菜单打开，可搜索并执行命令', (tester) async {
    // 文档标题不能是"命令面板"，否则与 AppBar 标题/菜单项文本歧义。
    final document = DrawingDocument(id: 'command_palette', title: '测试文档');
    document.layers.single.strokes.add(
      Stroke(
        points: const [StrokePoint(10, 10, 1), StrokePoint(40, 40, 0.8)],
        color: const Color(0xFF1A1A1A),
        width: 5,
        type: BrushType.pen,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(document: document)),
      ),
    );
    await tester.pumpAndSettle();

    // 通过主菜单打开命令面板（避免 sendKeyEvent 焦点时序不稳定）。
    await tester.tap(find.byTooltip('主菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('命令面板'));
    await tester.pumpAndSettle();

    expect(find.text('命令面板'), findsWidgets, reason: '主菜单应能打开命令面板');

    // 搜索过滤：输入"网格"后，匹配命令过滤进视口。
    await tester.enterText(find.byType(TextField).first, '网格');
    await tester.pumpAndSettle();
    expect(find.text('显示或隐藏网格'), findsWidgets);
    expect(find.text('导出 PNG'), findsNothing, reason: '搜索应过滤掉不匹配命令');

    // 执行"显示或隐藏网格"（纯 setState，测试安全），面板应关闭。
    await tester.tap(find.text('显示或隐藏网格').first);
    await tester.pumpAndSettle();
    expect(
      find.text('命令面板'),
      findsNothing,
      reason: '执行命令后面板应关闭',
    );
  });
}
