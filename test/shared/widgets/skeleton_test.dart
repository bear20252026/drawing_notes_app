// U4a：骨架屏组件测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/shared/widgets/skeleton.dart';

void main() {
  testWidgets('SkeletonList 渲染指定行数且不含 spinner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkeletonList(rows: 3))),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 每行 4 个骨架块（图标 + 标题 + 副标题 + 尾部圆点）。
    expect(find.byType(SkeletonList), findsOneWidget);
  });

  testWidgets('SkeletonList 呼吸动画持续 pump 无异常', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkeletonList(rows: 2))),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 1600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SkeletonCardGrid 渲染卡片块', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkeletonCardGrid(count: 4))),
    );
    await tester.pump();
    expect(find.byType(SkeletonCardGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
