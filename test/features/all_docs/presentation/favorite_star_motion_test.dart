// 收藏星标弹跳的曲线/时长令牌化（动效令牌接线，2026-11-12）。
//
// 为什么单独一个文件：这处是全库**最后一处裸动画时长**（原 240ms），也是
// 唯一一处「注释写的曲线与实际跑的不一致」——注释说 easeOut，而
// `AnimationController.forward` 没有 curve 参数、默认 `Curves.linear`
// （SDK animation_controller.dart:470 → _animateToInternal 的 curve 默认值）。
//
// 断言口径说明（两条都刻意绕开「读控件属性」的取巧路径）：
// - **曲线用行为断言**：`Curve` 的 `Cubic` 子类不实现 ==（curves.dart:365），
//   `expect(curve, AppleMotion.easeOut)` 只在恰好是同一个 const 实例时成立，
//   换个写法就假绿。这里改为在动画中点读**实际渲染的 scale**：ease-out 在
//   t=0.5 已走过约 0.97 的路程，linear 恰好 0.5——两者差得足够远，不会被
//   帧粒度或实现细节糊过去。
// - **时长用完成时刻断言**：控制器是 private 的，读不到 duration。改为观察
//   「240ms 时是否已到位」——原实现是 240ms，令牌化后是 250ms，这个时刻
//   恰好把两者分开，且不受帧粒度影响（elapse 只推进到 ≤ 目标值的帧）。
//
// scale 的读法：`ScaleTransition` → `MatrixTransition.build` 返回
// `Transform(transform: Matrix4.diagonal3Values(v, v, 1.0))`，故
// `transform.storage[0]` 就是当前的 scale。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/all_doc.dart';
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_motion.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_doc_row.dart';

AllDoc _doc({bool favorite = false}) => AllDoc(
  id: 'd1',
  title: '设计稿',
  kind: AllDocKind.blockdoc,
  folder: '',
  createdAt: DateTime(2026, 8, 1, 10),
  updatedAt: DateTime(2026, 8, 2, 10),
  isFavorite: favorite,
);

Widget _wrap(AllDoc doc) => MaterialApp(
  theme: AppDesign.lightTheme(),
  home: Scaffold(
    body: AllDocRow(doc: doc, onOpenDoc: () {}, onToggleFavorite: () {}),
  ),
);

double _scaleOf(WidgetTester tester) {
  // 星标**最外层的 Transform 祖先**就是 ScaleTransition 的那一个
  // （`MatrixTransition.build` 把 Transform 作为自己的根，Icon 是其子树）。
  // 不能用 `descendant(of: ScaleTransition)`——Icon 子树里还另有
  // 两个 Transform（一个退化矩阵、一个 45° 旋转），会撞成多个匹配。
  final transform = tester.widget<Transform>(
    find.ancestor(
      of: find.byIcon(Icons.star_rounded),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.storage[0];
}

void main() {
  testWidgets('收藏点亮弹跳：曲线 = AppleMotion.easeOut，时长 = AppleMotion.modal', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_doc()));
    // 先在未收藏态建树，再翻成收藏——didUpdateWidget 只在 false→true 时起弹跳。
    await tester.pumpWidget(_wrap(_doc(favorite: true)));
    await tester.pump();

    // 起点：控制器归零 → scale 落在 Tween 的 begin。
    expect(_scaleOf(tester), closeTo(0.6, 0.001));

    // 中点（125ms）：ease-out 已走过约 0.97 的路程 ⇒ scale ≈ 1.03；
    // linear 此刻只有 0.825。这条断言同时排除 linear 与 ease-in。
    await tester.pump(const Duration(milliseconds: 125));
    expect(
      _scaleOf(tester),
      greaterThan(0.9),
      reason: '若退化成 linear（原实现的实际行为），弹跳会是匀速爬升',
    );

    // 走到 240ms 仍未到位——原实现（240ms）在这一刻就已 complete。
    await tester.pump(const Duration(milliseconds: 115));
    expect(_scaleOf(tester), lessThan(1.05));

    // 再走 10ms（合计 250ms = AppleMotion.modal）→ 刚好到位。
    await tester.pump(const Duration(milliseconds: 10));
    expect(_scaleOf(tester), closeTo(1.05, 0.001));

    await tester.pumpAndSettle();
  });

  testWidgets('未收藏态不渲染 ScaleTransition（保持既有语义树结构）', (tester) async {
    await tester.pumpWidget(_wrap(_doc()));
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    // 限定在星标子树内：Scaffold/MaterialApp 自身也带 ScaleTransition
    // （抽屉/转场），全树找会把它们算进来。
    expect(
      find.ancestor(
        of: find.byIcon(Icons.star_border_rounded),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
      reason: '弹跳只在点亮时出现；裸 Icon 直出是读屏断言依赖的结构',
    );
  });

  test('令牌表本身：modal 是 250ms，easeOut 控制点为 (0.23,1,0.32,1)', () {
    // 上面两条行为断言的正确性依赖这两个常量——把它们钉在这里，
    // 令牌被改动时会有明确的失败点，而不是让上面的断言静默失准。
    expect(AppleMotion.modal, const Duration(milliseconds: 250));
    final curve = AppleMotion.easeOut as Cubic;
    expect((curve.a, curve.b, curve.c, curve.d), (0.23, 1.0, 0.32, 1.0));
  });
}
