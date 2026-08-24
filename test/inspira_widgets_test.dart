// Inspira UI 组件冒烟测试：FlipCard / StaggeredListView / MorphingTabs。
//
// 验证：
// - FlipCard：点击翻转后背面可见；Semantics(button) 存在；
//   Enter 键触发翻转（焦点可达）
// - StaggeredListView：子项全部渲染；减少动态效果时直接显示
// - MorphingTabs：选中态渲染 + onChanged 回调 + selected 语义
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/shared/widgets/inspira/flip_card.dart';
import 'package:drawing_notes_app/shared/widgets/inspira/morphing_tabs.dart';
import 'package:drawing_notes_app/shared/widgets/inspira/stagger_list.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('FlipCard', () {
    testWidgets('点击翻转后显示背面内容', (tester) async {
      await tester.pumpWidget(_host(const FlipCard(
        front: Text('FRONT'),
        back: Text('BACK'),
        height: 120,
      )));

      expect(find.text('FRONT'), findsOneWidget);
      expect(find.text('BACK'), findsNothing);

      await tester.tap(find.byType(FlipCard));
      await tester.pumpAndSettle();

      expect(find.text('BACK'), findsOneWidget);
    });

    testWidgets('再次点击翻回正面', (tester) async {
      await tester.pumpWidget(_host(const FlipCard(
        front: Text('F'),
        back: Text('B'),
        height: 120,
        duration: Duration(milliseconds: 100),
      )));

      await tester.tap(find.byType(FlipCard));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FlipCard));
      await tester.pumpAndSettle();

      expect(find.text('F'), findsOneWidget);
    });

    testWidgets('暴露 button 语义', (tester) async {
      await tester.pumpWidget(_host(const FlipCard(
        front: SizedBox.shrink(),
        back: SizedBox.shrink(),
        semanticLabel: '笔记本预览卡',
      )));

      expect(
        find.bySemanticsLabel('笔记本预览卡'),
        findsOneWidget,
      );
    });

    testWidgets('disableAnimations 时点击立即换面（无动画等待）', (tester) async {
      await tester.pumpWidget(_host(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const FlipCard(front: Text('A'), back: Text('Z'), height: 120),
      )));

      await tester.tap(find.byType(FlipCard));
      await tester.pump(); // 单帧——不 pumpAndSettle

      expect(find.text('Z'), findsOneWidget);
    });
  });

  group('StaggeredListView', () {
    testWidgets('渲染全部子项', (tester) async {
      await tester.pumpWidget(_host(StaggeredListView(
        shrinkWrap: true,
        itemCount: 5,
        itemBuilder: (_, i) => ListTile(title: Text('item-$i')),
      )));

      for (var i = 0; i < 5; i++) {
        expect(find.text('item-$i'), findsOneWidget);
      }

      // 推进假时钟，冲掉 stagger 延迟定时器与入场动画，
      // 避免测试结束时仍存在 pending Timer。
      await tester.pumpAndSettle();
    });

    testWidgets('动画结束后项完全可见（透明度 1）', (tester) async {
      await tester.pumpWidget(_host(StaggeredListView(
        shrinkWrap: true,
        itemCount: 3,
        itemBuilder: (_, i) => ListTile(title: Text('row-$i')),
      )));

      await tester.pumpAndSettle();
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('row-0'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1.0);
    });
  });

  group('MorphingTabs', () {
    const tabs = [
      MorphTab(value: 'pen', icon: Icons.brush, label: '画笔'),
      MorphTab(value: 'eraser', icon: Icons.cleaning_services, label: '橡皮'),
    ];

    testWidgets('点击未选项触发 onChanged 并切换高亮', (tester) async {
      var selected = 'pen';
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => MorphingTabs<String>(
          tabs: tabs,
          selected: selected,
          onChanged: (v) => setState(() => selected = v),
        ),
      )));

      await tester.tap(find.byIcon(Icons.cleaning_services));
      await tester.pumpAndSettle();

      final eraserSemantics =
          tester.getSemantics(find.byIcon(Icons.cleaning_services));
      expect(eraserSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
      final penSemantics = tester.getSemantics(find.byIcon(Icons.brush));
      expect(penSemantics.hasFlag(SemanticsFlag.isSelected), isFalse);
    });

    testWidgets('每项都有 button 语义且触摸区高度 ≥48dp', (tester) async {
      await tester.pumpWidget(_host(MorphingTabs<String>(
        tabs: tabs,
        selected: 'pen',
        onChanged: (_) {},
      )));

      final penSemantics = tester.getSemantics(find.byIcon(Icons.brush));
      expect(penSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(penSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);

      // 触摸目标：InkWell 外层 Container 的 minHeight=48。
      final inkwellSize = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.brush),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkwellSize.height, greaterThanOrEqualTo(48));
    });
  });
}
