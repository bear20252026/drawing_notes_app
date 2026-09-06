// 对话框统一入口的排版与平台按钮顺序测试（UI 精细化第二批，2026-09-04）。
//
// 权威分工（`docs/DESIGN_SYSTEM.md` 六来源按域分权）：
// - 排版（字号 / 字重 / 行高）= 静态视觉域，`DESIGN.md` 说了算；
// - 按钮先后顺序 = **平台行为域**，`DESIGN.md` 表决权为零，由
//   Microsoft win-dev-skills（Windows：主按钮在左）与 Apple HIG
//   （macOS：主按钮在右）各自主导。
//
// 钉住这些行为的原因：按钮顺序是肌肉记忆层面的东西，Windows 用户预期
// 「确定」在左，一旦被统一成 Apple 顺序，误点率会上升，而且没人会想到
// 是主题层改的。
//
// 平台切换用 `TargetPlatformVariant`：**不能**在测试体内直接给
// `debugDefaultTargetPlatformOverride` 赋值——框架会在测试体结束后检查
// 该变量是否被改动过并直接判红（"The value of a foundation debug variable
// was changed by the test"），addTearDown 里恢复也来不及。

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.lightTheme(),
        home: Builder(
          builder: (context) {
            rootContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    unawaited(
      AppleDialog.confirm(
        rootContext,
        title: '彻底删除',
        content: '删除后不可恢复。',
        confirmText: '删除',
        cancelText: '取消',
      ),
    );
    await tester.pumpAndSettle();
  }

  group('对话框按钮顺序（平台域裁决 C1）', () {
    testWidgets('Windows：主按钮在左', (tester) async {
      await pumpDialog(tester);
      expect(
        tester.getCenter(find.text('删除')).dx,
        lessThan(tester.getCenter(find.text('取消')).dx),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Linux：主按钮在左', (tester) async {
      await pumpDialog(tester);
      expect(
        tester.getCenter(find.text('删除')).dx,
        lessThan(tester.getCenter(find.text('取消')).dx),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('macOS：主按钮在右（Apple HIG 顺序）', (tester) async {
      await pumpDialog(tester);
      expect(
        tester.getCenter(find.text('删除')).dx,
        greaterThan(tester.getCenter(find.text('取消')).dx),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Android：主按钮在右（M3 顺序）', (tester) async {
      await pumpDialog(tester);
      expect(
        tester.getCenter(find.text('删除')).dx,
        greaterThan(tester.getCenter(find.text('取消')).dx),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('AppleDialog.actions（裸 AlertDialog 的迁移入口）', () {
    final secondary = const Text('取消');
    final primary = const Text('确定');

    testWidgets('Windows / Linux = 倒序，macOS / Android = 原序', (tester) async {
      final ordered = AppleDialog.actions(<Widget>[secondary, primary]);
      switch (defaultTargetPlatform) {
        case TargetPlatform.windows:
        case TargetPlatform.linux:
          expect(ordered.first, primary);
        case TargetPlatform.macOS:
        case TargetPlatform.iOS:
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
          expect(ordered.first, secondary);
      }
    }, variant: TargetPlatformVariant.all());
  });

  group('对话框排版（DESIGN.md 排版梯子）', () {
    testWidgets('标题 17px / w600，正文 15px / 行高 1.47', (tester) async {
      await pumpDialog(tester);

      // 注意：对话框的标题/正文样式来自 DefaultTextStyle（dialogTheme
      // 注入），不会挂在 Text.style 上，因此要把继承到的样式与
      // 控件自带样式合并后才是最终生效值。
      TextStyle styleOf(String text) {
        final element = tester.element(find.text(text));
        return DefaultTextStyle.of(
          element,
        ).style.merge(tester.widget<Text>(find.text(text)).style);
      }

      final title = styleOf('彻底删除');
      expect(title.fontSize, AppleType.title); // 17
      expect(title.fontWeight, FontWeight.w600);

      final content = styleOf('删除后不可恢复。');
      expect(content.fontSize, 15);
      // DESIGN.md:506「Don't tighten line-height below 1.47 for body copy」
      expect(content.height, AppleType.bodyLineHeight); // 1.47
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    test('对话框走 overlay 档阴影，圆角 = AppleRadius.lg', () {
      final theme = AppDesign.lightTheme();
      final shape = theme.dialogTheme.shape! as RoundedRectangleBorder;
      final radius = shape.borderRadius as BorderRadius;
      expect(radius.topLeft.x, AppleRadius.lg); // 18
    });
  });
}
