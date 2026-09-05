// 空态统一组件（审计二-4）契约测试：icon/标题/引导语/行动按钮渲染与缺省。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/apple_empty_state.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('渲染 icon + 标题 + 引导语 + 行动按钮', (tester) async {
    await tester.pumpWidget(
      host(
        AppleEmptyState(
          icon: Icons.inbox_outlined,
          title: '暂无收藏文档',
          tip: '点击文档行星标可添加到收藏夹',
          actions: [TextButton(onPressed: () {}, child: const Text('去收藏'))],
        ),
      ),
    );
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('暂无收藏文档'), findsOneWidget);
    expect(find.text('点击文档行星标可添加到收藏夹'), findsOneWidget);
    expect(find.text('去收藏'), findsOneWidget);
  });

  testWidgets('无 tip 与 actions 时不渲染占位', (tester) async {
    await tester.pumpWidget(
      host(const AppleEmptyState(icon: Icons.brush_outlined, title: '还没有画布')),
    );
    expect(find.byIcon(Icons.brush_outlined), findsOneWidget);
    expect(find.text('还没有画布'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    // Column 内只有 icon + 间距 + 标题三项（无 tip/按钮占位）。
    final column = tester.widget<Column>(
      find.descendant(
        of: find.byType(AppleEmptyState),
        matching: find.byType(Column),
      ),
    );
    expect(column.children.length, 3);
  });
}
