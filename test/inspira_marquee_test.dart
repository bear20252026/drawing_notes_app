// InspiraMarquee 组件测试：渲染、滚动推进、悬停暂停、无障碍降级、空内容。
import 'package:drawing_notes_app/shared/widgets/inspira/inspira_marquee.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({bool disableAnimations = false, required Widget child}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(child: SizedBox(width: 400, child: child)),
        ),
      ),
    );

final items = [
  for (var i = 0; i < 3; i++)
    Container(key: ValueKey('item$i'), width: 60, height: 40, color: Colors.blue),
];

void main() {
  testWidgets('渲染全部条目', (tester) async {
    await tester.pumpWidget(_host(child: InspiraMarquee(items: items)));
    // 测量帧 + 内容帧。
    await tester.pump();
    await tester.pump();
    // 内容 264px < 视口 400px → 复制 3 份补齐，每个条目出现 3 次。
    expect(find.byKey(const ValueKey('item0')), findsNWidgets(3));
    expect(find.byKey(const ValueKey('item2')), findsNWidgets(3));
  });

  testWidgets('随时间推进滚动（offset 单调变化）', (tester) async {
    await tester.pumpWidget(_host(child: InspiraMarquee(items: items)));
    await tester.pump(); // 测量
    await tester.pump(); // 布局内容

    final stripFinder = find.ancestor(
      of: find.byKey(const ValueKey('item0')),
      matching: find.byType(Transform),
    );
    expect(stripFinder, findsWidgets);

    double dx() => tester
        .widget<Transform>(stripFinder.first)
        .transform
        .getTranslation()
        .x;

    final before = dx();
    await tester.pump(const Duration(seconds: 1));
    final after = dx();

    expect(after, lessThan(before), reason: '向左滚 → translate.dx 应减小');
    expect(before - after, closeTo(32, 8), reason: '默认速度约 32px/s');
  });

  testWidgets('鼠标悬停暂停滚动', (tester) async {
    await tester.pumpWidget(_host(child: InspiraMarquee(items: items)));
    await tester.pump();
    await tester.pump();

    Transform firstTransform() =>
        tester.widget<Transform>(find.byType(Transform).first);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await tester.pump(const Duration(milliseconds: 500)); // 先滚一段
    final pausedPos =
        tester.getCenter(find.byKey(const ValueKey('item1'), skipOffstage: false));
    await gesture.moveTo(pausedPos); // 悬停进入
    await tester.pumpAndSettle();

    final a = firstTransform().transform.getTranslation().x;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final b = firstTransform().transform.getTranslation().x;

    expect(b, a, reason: '悬停期间 offset 不应变化');
  });

  testWidgets('disableAnimations 静态展示', (tester) async {
    await tester.pumpWidget(
      _host(disableAnimations: true, child: InspiraMarquee(items: items)),
    );
    await tester.pump();
    await tester.pump();

    final t = tester.widget<Transform>(
      find.byType(Transform).first,
    );
    expect(t.transform.getTranslation().x, 0);

    await tester.pump(const Duration(seconds: 1));
    final t2 = tester.widget<Transform>(find.byType(Transform).first);
    expect(t2.transform.getTranslation().x, 0, reason: '减弱动态效果时不滚动');
  });

  testWidgets('空条目安全退化', (tester) async {
    await tester.pumpWidget(_host(child: const InspiraMarquee(items: [])));
    await tester.pump();
    expect(find.byType(InspiraMarquee), findsOneWidget);
  });
}
