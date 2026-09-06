// M12 契约测试：DocPage（AFFiNE 式笔记页，与画板视觉/结构分离）。
//
// 验证：顶栏动作（收藏/信息/大纲/分享）、大纲条目点击跳转回调、
// 保存链路（DocController → onSave）。
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/doc/doc_controller.dart';
import 'package:drawing_notes_app/features/doc/doc_outline_rail.dart';
import 'package:drawing_notes_app/features/doc/doc_page.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';

void main() {
  final now = DateTime(2026, 8, 30, 10);

  NoteBlockDoc makeDoc() => NoteBlockDoc(
    id: 'doc-m12',
    title: '设计笔记',
    body: [
      const NoteBlock(
        id: 'h1',
        type: NoteBlockType.heading,
        text: '第一章',
        props: {'level': 1},
      ),
      const NoteBlock(id: 'p1', type: NoteBlockType.text, text: '正文'),
    ],
    createdAt: now,
    updatedAt: now,
  );

  m.Widget wrap(m.Widget child) => m.MaterialApp(home: child);

  /// 显式设定测试曲面尺寸。
  ///
  /// 默认曲面为 800x600（<900 断点），响应式用例若不设定尺寸，
  /// 桌面/移动两条分支的命中结果会随默认尺寸变化而漂移。
  void setSurface(WidgetTester tester, {required bool desktop}) {
    tester.view.physicalSize = desktop
        ? const m.Size(1440, 900)
        : const m.Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('顶栏（桌面）：标题/收藏/信息/大纲/分享按钮齐备', (tester) async {
    setSurface(tester, desktop: true);
    await tester.pumpWidget(wrap(DocPage(document: makeDoc())));
    await tester.pumpAndSettle();

    expect(find.text('设计笔记'), findsWidgets); // 顶栏 + 正文标题
    expect(find.byIcon(m.Icons.star_border_rounded), findsOneWidget);
    expect(find.byIcon(m.Icons.info_outline_rounded), findsOneWidget);
    expect(find.byIcon(m.Icons.format_list_bulleted_rounded), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });

  testWidgets('顶栏（移动端）：不溢出，次要动作收进 ⋯ 菜单', (tester) async {
    setSurface(tester, desktop: false);
    await tester.pumpWidget(wrap(DocPage(document: makeDoc())));
    await tester.pumpAndSettle();

    // 无 RenderFlex 溢出异常（顶栏在 400dp 下曾溢出 24px）
    expect(tester.takeException(), isNull);

    // 保留图标：保存 / 收藏 / 分享 / 大纲 / 更多
    expect(find.byIcon(m.Icons.save_outlined), findsOneWidget);
    expect(find.byIcon(m.Icons.star_border_rounded), findsOneWidget);
    expect(find.byIcon(m.Icons.ios_share_rounded), findsOneWidget);
    expect(find.byIcon(m.Icons.format_list_bulleted_rounded), findsOneWidget);
    expect(find.byIcon(m.Icons.more_horiz_rounded), findsOneWidget);

    // 状态文字降为标题副标题后仍在；次要动作移入 ⋯ 菜单
    await tester.tap(find.byIcon(m.Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('文档信息'), findsOneWidget);
    expect(find.text('插入页面链接'), findsOneWidget);
    expect(find.text('导出 PDF'), findsOneWidget);
  });

  testWidgets('收藏切换回调', (tester) async {
    bool? fav;
    await tester.pumpWidget(
      wrap(
        DocPage(
          document: makeDoc(),
          isFavorite: false,
          onToggleFavorite: (v) => fav = v,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(m.Icons.star_border_rounded));
    await tester.pump();
    expect(fav, isTrue);
  });

  testWidgets('大纲：桌面（≥900）展开为右缘停靠栏', (tester) async {
    setSurface(tester, desktop: true);
    await tester.pumpWidget(wrap(DocPage(document: makeDoc())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(m.Icons.format_list_bulleted_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(DocOutlineRail), findsOneWidget);
    expect(find.text('第一章'), findsWidgets); // 大纲条目 + 正文标题块
  });

  testWidgets('大纲：移动端（<900）走底部面板，正文不被挤窄', (tester) async {
    setSurface(tester, desktop: false);
    await tester.pumpWidget(wrap(DocPage(document: makeDoc())));
    await tester.pumpAndSettle();

    // 打开前：正文块占满全宽（400）
    final bodyField = find.widgetWithText(m.TextField, '正文');
    expect(tester.getSize(bodyField).width, greaterThan(300));

    await tester.tap(find.byIcon(m.Icons.format_list_bulleted_rounded));
    await tester.pumpAndSettle();

    // 240 固定窄栏不出现；改为占满全宽的底部面板
    expect(find.byType(DocOutlineRail), findsNothing);
    expect(find.byType(DocOutlinePanel), findsOneWidget);
    expect(tester.getSize(find.byType(DocOutlinePanel)).width, 400);
    expect(find.text('第一章'), findsWidgets); // 面板条目 + 正文标题块
  });

  testWidgets('正文块可编辑（输入即更新内容）', (tester) async {
    await tester.pumpWidget(
      wrap(
        DocPage(
          document: makeDoc(),
          controller: DocController(onSave: (_) async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bodyField = find.widgetWithText(m.TextField, '正文');
    expect(bodyField, findsOneWidget);
    await tester.enterText(bodyField, '正文二');
    await tester.pump();
    expect(find.text('正文二'), findsOneWidget);
  });

  test('DocController：save 转发 + dirty 标记', () async {
    NoteBlockDoc? saved;
    final c = DocController(onSave: (d) async => saved = d);
    expect(c.dirty, isFalse);
    c.markDirty();
    expect(c.dirty, isTrue);
    final doc = makeDoc();
    await c.save(doc);
    expect(saved, same(doc));
    expect(c.dirty, isFalse);
  });
}
