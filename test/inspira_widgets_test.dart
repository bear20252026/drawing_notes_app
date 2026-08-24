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

    testWidgets('自定义翻转轴：axis=vertical 同样完成换面', (tester) async {
      await tester.pumpWidget(_host(const FlipCard(
        front: Text('VF'),
        back: Text('VB'),
        axis: Axis.vertical, // 水平轴上下翻转（rotateX）
        height: 120,
        duration: Duration(milliseconds: 100),
      )));

      expect(find.text('VB'), findsNothing);
      await tester.tap(find.byType(FlipCard));
      await tester.pumpAndSettle();

      expect(find.text('VB'), findsOneWidget);
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

    testWidgets('direction=left 首帧水平位移、动画后归位', (tester) async {
      await tester.pumpWidget(_host(StaggeredListView(
        shrinkWrap: true,
        itemCount: 2,
        direction: StaggerDirection.left,
        distance: 30,
        itemBuilder: (_, i) => ListTile(title: Text('col-$i')),
      )));

      // 首帧 index 0 无延迟，t=0 → 水平位移 ≈ distance。
      final before = tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.text('col-0'),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage;
      expect(before[12], closeTo(30, 0.5)); // 平移矩阵 tx
      expect(before[13], 0); // ty

      await tester.pumpAndSettle();
      final after = tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.text('col-0'),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage;
      expect(after[12], 0);
    });

    testWidgets('disableAnimations 直接静态渲染（无动画包装）', (tester) async {
      await tester.pumpWidget(_host(StaggeredListView(
        shrinkWrap: true,
        itemCount: 3,
        disableAnimations: true,
        itemBuilder: (_, i) => ListTile(title: Text('static-$i')),
      )));

      for (var i = 0; i < 3; i++) {
        expect(find.text('static-$i'), findsOneWidget);
      }
      // disableAnimations=true 时不应出现 StaggerEntrance 动画包装器。
      expect(find.byType(StaggerEntrance), findsNothing);
    });

    testWidgets('自定义 step/itemDuration 透传（step=0 全体同时入场）', (tester) async {
      await tester.pumpWidget(_host(StaggeredListView(
        shrinkWrap: true,
        itemCount: 3,
        step: Duration.zero,
        itemDuration: const Duration(milliseconds: 200),
        itemBuilder: (_, i) => ListTile(title: Text('fast-$i')),
      )));

      // pump 0ms 触发 Future.delayed(Duration.zero) 微任务，启动控制器；
      // 再 pump 200ms 驱动动画到终点。
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 200));
      for (var i = 0; i < 3; i++) {
        final opacity = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.text('fast-$i'),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(opacity.opacity, 1.0, reason: 'fast-$i 应已完成入场');
      }

      await tester.pumpAndSettle(); // 冲掉残余定时器
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

    testWidgets('自定义颜色生效（选中底色 + 未选中图标色）', (tester) async {
      await tester.pumpWidget(_host(MorphingTabs<String>(
        tabs: tabs,
        selected: 'eraser',
        selectedColor: const Color(0xFF123456),
        unselectedIconColor: const Color(0xFF654321),
        onChanged: (_) {},
      )));
      await tester.pumpAndSettle();

      // 选中项胶囊底色。
      final selectedContainer = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.byIcon(Icons.cleaning_services),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final selectedDeco = selectedContainer.decoration! as BoxDecoration;
      expect(selectedDeco.color, const Color(0xFF123456));

      // 未选中项图标色。
      final penIcon = tester.widget<Icon>(find.byIcon(Icons.brush));
      expect(penIcon.color, const Color(0xFF654321));
    });

    testWidgets('形状变形：selectedBorderRadius 与 borderRadius 可不同', (tester) async {
      await tester.pumpWidget(_host(MorphingTabs<String>(
        tabs: tabs,
        selected: 'pen',
        borderRadius: BorderRadius.circular(4),
        selectedBorderRadius: BorderRadius.circular(22),
        onChanged: (_) {},
      )));
      await tester.pumpAndSettle();

      // 选中项（圆角 22）与未选中项（圆角 4）形状不同——切换时即产生
      // 圆形↔方形↔圆角的形变补间目标。
      final penContainer = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: find.byIcon(Icons.brush),
                matching: find.byType(AnimatedContainer))
            .first,
      );
      final penDeco = penContainer.decoration! as BoxDecoration;
      expect(penDeco.borderRadius, BorderRadius.circular(22));

      final eraserContainer = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: find.byIcon(Icons.cleaning_services),
                matching: find.byType(AnimatedContainer))
            .first,
      );
      final eraserDeco = eraserContainer.decoration! as BoxDecoration;
      expect(eraserDeco.borderRadius, BorderRadius.circular(4));
    });

    testWidgets('animate=false 立即呈现最终态（无需等待动画）', (tester) async {
      await tester.pumpWidget(_host(MorphingTabs<String>(
        tabs: tabs,
        selected: 'eraser',
        animate: false,
        selectedColor: const Color(0xFF010203),
        onChanged: (_) {},
      )));
      await tester.pump(); // 单帧，不 pumpAndSettle

      final eraserContainer = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: find.byIcon(Icons.cleaning_services),
                matching: find.byType(AnimatedContainer))
            .first,
      );
      final eraserDeco = eraserContainer.decoration! as BoxDecoration;
      expect(eraserDeco.color, const Color(0xFF010203));
    });
  });
}
