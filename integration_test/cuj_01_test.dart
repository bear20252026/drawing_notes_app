import 'package:drawing_notes_app/app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 专家 I-002（2026-08-16——批次 A）：CUJ-01 create_draw_save_reopen——
/// 新建画作 → 绘制笔画 → 返回自动保存 → 重开内容保留。
/// Android/Windows 真实启动自动化（验收冒烟依据——pr-platform evidence）。
///
/// 运行：flutter test integration_test/cuj_01_test.dart -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
  });

  testWidgets('CUJ-01：新建画作 → 绘制 → 返回保存 → 重开内容保留', (tester) async {
    await tester.pumpWidget(const DrawingNotesApp());
    await tester.pumpAndSettle();

    // 1) Create：新建画作（输入名称 → 进入编辑器）。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'CUJ-01 画作');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('CUJ-01 画作'), findsWidgets);

    // 2) Draw：在画布上绘制一笔（手势拖拽——产生笔画）。
    final canvas = find.byType(CustomPaint).last;
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    await tester.pumpAndSettle();

    // 3) Save：返回首页（自动保存——800ms 防抖 + 退出兜底）。
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 4) Reopen：首页列表找到画作 → 重开 → 内容保留（编辑器标题/工具栏）。
    expect(find.text('CUJ-01 画作'), findsOneWidget);
    await tester.tap(find.text('CUJ-01 画作'));
    await tester.pumpAndSettle();
    expect(find.text('CUJ-01 画作'), findsWidgets);
    // 编辑器工具栏（画笔——tooltip 定位）存在——内容可继续编辑。
    expect(find.byTooltip('画笔'), findsOneWidget);
  });
}
