// 由 Claude 团队生成 | Drawing Notes App

/// 第五轮 UI 采集落地的两条「点了没反应」（R52b，2026-10-18）。
///
/// 两条都是**业主硬性约定**（AGENTS.md §3「三输入兼容」+ §7 体验面）被破：
///  - 全部文档行的 ⋮「更多操作」以前只有 `onTapUp`。`InkWell` 的键盘激活
///    （Enter/Space → `activateOnIntent`）与读屏的 `Semantics.onTap` 都**只回调 `onTap`**
///    ⇒ V-05 那次「改 InkWell 自带焦点」只补上了 Tab 焦点：焦点环亮着、按 Enter 没反应，
///    而这颗钮正是被指定为「长按/右键等价入口」的那一颗。
///  - 从全部文档/反向链接点开一篇**刚被会话锁定**的笔记时，路由层把「锁了」和「没有」
///    折叠成同一个 null 后静默 `return` ⇒ 看起来就是条目坏了。笔记本那条腿在审计一-3
///    已经修过同一个坑（`notebook_view_page_manage.dart` 那句「但不再静默消失」），
///    这条腿漏了——本仓的「一修就漏九处」。
/// 第一半是真键盘事件；第二半只能做源码级判据（要走通它得造一个受密库 + 清会话 DEK，
/// 那属于存储层用例的范围），所以判据里同时钉**返回类型带 locked**与**必须引用那条文案**，
/// 并给了合成形状的自证，避免它长成一条恒真的正则。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/all_doc.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';

void main() {
  AllDoc rowDoc() => AllDoc(
    id: 'd1',
    title: '设计稿',
    kind: AllDocKind.blockdoc,
    folder: '',
    createdAt: DateTime(2026, 8, 1, 10),
    updatedAt: DateTime(2026, 8, 2, 10),
  );

  Future<void> pumpRow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.lightTheme(),
        home: Scaffold(
          body: AllDocRow(
            doc: rowDoc(),
            onOpenDoc: () {},
            onToggleFavorite: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('⋮ 更多操作：键盘与读屏必须按得动', () {
    testWidgets('判据：那颗 InkWell 有 onTap、且不再并存 onTapUp', (tester) async {
      await pumpRow(tester);
      // 整行本身也是一颗 InkWell（点行=打开），`widgetWithIcon` 是祖先查找 ⇒ 会一次
      // 抓到两颗。按那层 `Semantics(label: 更多操作)` 圈定，才是 ⋮ 自己那颗。
      final moreSem = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '更多操作',
      );
      expect(moreSem, findsOneWidget, reason: '找不到 ⋮ 的语义层 ⇒ 布局变了，下面的判据就没意义了');
      final ink = tester.widget<InkWell>(
        find.descendant(of: moreSem, matching: find.byType(InkWell)).first,
      );
      expect(
        ink.onTap,
        isNotNull,
        reason: 'InkWell 的 activateOnIntent 与 Semantics.onTap 都只回调 onTap——'
            '只给 onTapUp 就是「焦点环亮着、Enter 是死的」',
      );
      expect(
        ink.onTapUp,
        isNull,
        reason: '两条路径并存时一次指针点击会同时命中 onTap 与 onTapUp ⇒ 弹两个菜单',
      );
    });

    testWidgets('真按一次 Enter ⇒ 上下文菜单开出来', (tester) async {
      await pumpRow(tester);
      final moreSem = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '更多操作',
      );
      final inkCtx = find
          .descendant(of: moreSem, matching: find.byIcon(Icons.more_horiz_rounded))
          .evaluate()
          .first;
      Focus.of(inkCtx).requestFocus();
      await tester.pump();
      expect(Focus.of(inkCtx).hasFocus, isTrue, reason: 'Tab 可达这一步不能假设成立');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 菜单项文案取自 `showAllDocContextMenu`（本 harness 未挂 l10n ⇒ 走兜底中文）。
      expect(
        find.text('打开'),
        findsOneWidget,
        reason: 'Enter 没能打开菜单 ⇒ 键盘用户仍然只能靠鼠标点 ⋮',
      );
    });
  });

  group('受密笔记打不开时必须出声（源码级判据）', () {
    const target = 'lib/app/app_shell_routes.dart';
    // 在每条用例里读，而不是在 group 体里读：文件读不到时应当是**某条用例红**，
    // 不是整个套件加载失败（那时报的是栈，不是「这条判据要看住什么」）。
    String code() => File(target)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('helper 必须把「锁了」与「没有」分成两态', () {
      expect(
        RegExp(r'Future<\(\{NoteBlockDoc\? doc, bool locked\}\)>')
            .hasMatch(code()),
        isTrue,
        reason: '折叠成同一个 null，调用点就只能静默 return',
      );
    });

    test('锁定那一格必须引用既有文案键，而不是新造一句或干脆不说', () {
      final src = code();
      expect(
        src.contains('nbNoteEncryptedLocked'),
        isTrue,
        reason: '同一件事不该有两个说法（笔记本那条腿用的就是这个键），更不该退回静默',
      );
      expect(
        src.contains('if (loaded.locked)') && src.contains('showSnackBar'),
        isTrue,
        reason: '有 locked 分支但不出声，等于这条判据白做',
      );
    });

    test('判据自证：两种塌法都要能被抓住', () {
      // ① 退回折叠成 null 的旧形状 ⇒ 第一条红。
      expect(
        RegExp(r'Future<\(\{NoteBlockDoc\? doc, bool locked\}\)>')
            .hasMatch('Future<NoteBlockDoc?> _loadBlockDocGuarded(store, id)'),
        isFalse,
      );
      // ② 有 locked 分支但忘了出声 ⇒ 第二条红。
      const silent = '''
if (loaded.locked) {
  return;
}
final doc = loaded.doc;''';
      expect(
        silent.contains('showSnackBar') && silent.contains('nbNoteEncryptedLocked'),
        isFalse,
      );
    });
  });
}
