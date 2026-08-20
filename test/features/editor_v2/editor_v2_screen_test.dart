import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/editor_v2/presentation/editor_v2_screen.dart';

/// 批次 F 集成测试（CUJ-01 UI 层——EditorV2Screen 渲染——不崩验证）。
///
/// 验证：无限画布 + 工具栏 + 画布集成到 EditorV2Screen 后——
/// 渲染正常（无异常——不搞崩——AFFiNE/Saber 借鉴的渐进集成）。
void main() {
  testWidgets('EditorV2Screen 渲染（CUJ-01——无限画布/工具栏/画布集成——不崩）', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: EditorV2Screen(documentId: 'test-doc')),
    ));
    await tester.pumpAndSettle();

    // 工具栏存在（Draw/Select/形状工具）。
    expect(find.byTooltip('Draw'), findsOneWidget);
    expect(find.byTooltip('Select'), findsOneWidget);
    expect(find.byTooltip('Erase'), findsOneWidget);

    // 画布存在（CustomPaint——CanvasPainterV2 + InfiniteCanvasWidget 包装）。
    expect(find.byType(CustomPaint), findsWidgets);

    // AppBar 标题存在。
    expect(find.text('Editor V2 - test-doc'), findsOneWidget);

    // 无异常（不崩——集成验证）。
    expect(tester.takeException(), isNull);
  });

  testWidgets('EditorV2Screen 工具栏交互（CUJ-01——工具切换——不崩）', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: EditorV2Screen(documentId: 'test-doc')),
    ));
    await tester.pumpAndSettle();

    // 点击 Select 工具——切换（不崩）。
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 点击 Erase 工具——切换（不崩）。
    await tester.tap(find.byTooltip('Erase'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 点击 Rect 工具——切换（不崩）。
    await tester.tap(find.byTooltip('Rect'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
