// Edgeless 无限画布页顶栏玻璃化测试（v1.10.6）。
//
// 覆盖：玻璃顶栏在位（GlassAppBar 替换原生 AppBar）/ extendBodyBehindAppBar
// 开启（画布内容沉浸式延伸到顶栏后）/ 8 个顶栏操作按钮保留 /
// 缩放按钮回调可用（viewport 坐标系变化不炸）/ 红线：整棵树一层
// BackdropFilter。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_page.dart';
import 'package:drawing_notes_app/shared/widgets/glass_app_bar.dart';

void main() {
  // L3 罩含微光闪烁（每帧重绘），固定时长 pump，禁用 pumpAndSettle。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EdgelessPage(initialDoc: EdgelessDoc.empty('test-doc')),
      ),
    );
    await settle(tester);
  }

  testWidgets('玻璃顶栏在位 + extendBodyBehindAppBar 开启', (tester) async {
    await pumpPage(tester);

    expect(find.byType(GlassAppBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 找到持有 GlassAppBar 的外层 Scaffold，断言沉浸式开启。
    final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold));
    final scaffold = scaffolds.firstWhere((s) => s.appBar is GlassAppBar);
    expect(
      scaffold.extendBodyBehindAppBar,
      isTrue,
      reason: '画布内容必须延伸到玻璃顶栏之后，BackdropFilter 才有东西可模糊',
    );
  });

  testWidgets('8 个顶栏操作按钮保留', (tester) async {
    await pumpPage(tester);
    // 命令面板 / 新增帧 / 适应 / 缩小 / 放大 / 连线 / 多选 / 编组。
    final buttons = find.byType(IconButton);
    expect(buttons, findsAtLeastNWidgets(8));
  });

  testWidgets('缩放按钮回调可用（viewport 坐标系变化不炸）', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byIcon(Icons.zoom_in));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.zoom_out));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.fit_screen_outlined));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('红线：整棵树只允许一层 BackdropFilter', (tester) async {
    await pumpPage(tester);
    expect(
      find.byType(BackdropFilter),
      findsOneWidget,
      reason: '玻璃顶栏自带唯一模糊层；画布内容层不得再套玻璃',
    );
  });
}
