import 'package:drawing_notes_app/app.dart';
// 防抖阈值引用产品常量本身（见下方 realWait 注释），不再抄数字。
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'real_wait.dart';
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
    await tester.pumpWidget(ProviderScope(child: const DrawingNotesApp()));
    await tester.pumpAndSettle();

    // 1) Create：新建画作（输入名称 → 进入编辑器）。
    // 起始目的地是 AllDocs（app_shell.dart:158 `_index = 0`），其 FAB 仅窄屏
    // 存在（all_docs_page.dart:200-206）且打开三选项 bottom sheet——不弹命名
    // 框。带命名框的无限画布入口在「画布·笔记」：HomePage 的 GlassFab.extended
    // （home_page.dart:368-373，label 为 arb docsNewCanvas）→ _createCanvas
    // 弹两选项（home_page_create.dart:44-78）→ _createDrawing 弹 _NameDialog
    // （:90）。FAB 限定在 HomePage 子树内，避免窄屏与 AllDocs 的 FAB 同树撞车。
    await tester.tap(find.text('画布·笔记').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(HomePage),
        matching: find.byType(FloatingActionButton),
      ),
    );
    await tester.pumpAndSettle();
    // arb homeNewInfiniteCanvas（home_page_create.dart:57 SimpleDialog 选项）。
    await tester.tap(find.text('新建无限画布'));
    await tester.pumpAndSettle();
    // arb homeNameHint（home_page_widgets.dart:447 _NameDialog 的 hintText）。
    expect(find.text('请输入名称'), findsOneWidget);
    // 按占位文案定位（语义选择器）：`byType(TextField).last` 依赖树中顺序，
    // 桌面开屏锁的键盘输入框（app_lock_gate 的 _DesktopPinField）一旦同树
    // 存在就会命中错的字段。
    // 按「当前对话框里的输入框」定位：不依赖树中 TextField 的出现顺序
    // （桌面开屏锁的 _DesktopPinField 也是同类型），也不依赖 hint 文案。
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'CUJ-01 画作',
    );
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
    // 返回 tooltip 来自 AppBar 自动植入的 BackButton：编辑器顶栏未写
    // leading/automaticallyImplyLeading（editor_page_appbar.dart:83-179），
    // 框架取其默认 backButtonTooltip（action_buttons.dart:199-200），zh 值为
    // 「返回」（generated_material_localizations.dart:45002），App 已注册
    // GlobalMaterialLocalizations 且 supportedLocales 含 zh（app.dart:189-193）。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // AU-2/AV 定性（2026-10-05）：自动保存阈值是 `SaveScheduler.autoSaveInterval`
    // = **5 秒**（save_scheduler.dart:69，2026-09-06 起；更早是 800ms）。本用例
    // 原先只 pumpAndSettle（LiveTest binding 下不消耗真实时间），补 2 秒仍不够
    // ⇒ 列表里看不到刚建的画作，症状与「丢数据」一模一样。等待时长改为**引用常量**，
    // 产品再调阈值时本用例自动跟随。
    await realWait(
      tester,
      SaveScheduler.autoSaveInterval + const Duration(seconds: 3),
    );

    // 4) Reopen：首页列表找到画作 → 重开 → 内容保留（编辑器标题/工具栏 +
    // 画布仍有内容——U-001 契约断言 same_stroke_id/same_point_count 由
    // 真实存储往返验证（设备测试 P-002——integration_test/contracts/cuj01.json）。
    expect(find.text('CUJ-01 画作'), findsOneWidget);
    await tester.tap(find.text('CUJ-01 画作'));
    await tester.pumpAndSettle();
    expect(find.text('CUJ-01 画作'), findsWidgets);
    // 编辑器工具栏（画笔——tooltip 定位）存在——内容可继续编辑。
    // EditorLeftToolbar 硬编码字面量 '画笔 (P)'（editor_left_toolbar.dart:81，
    // 非 arb；旧横栏的裸「画笔」字样已随 247f3b1 删除）。
    expect(find.byTooltip('画笔 (P)'), findsOneWidget);
    // 重开后画布仍有内容（painter 非空——笔画保留——P-001 内容断言）。
    final canvasAfter = find.byType(CustomPaint).last;
    final painterAfter = tester.widget<CustomPaint>(canvasAfter).painter;
    expect(painterAfter, isNotNull, reason: '重开后画布 painter 应存在（笔画内容保留）');
  });
}
