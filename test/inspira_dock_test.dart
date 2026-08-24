// InspiraDock 组件测试：渲染、点击回调、邻近放大、无障碍降级。
import 'package:drawing_notes_app/shared/widgets/inspira/inspira_dock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({bool disableAnimations = false, required Widget child}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  var taps = 0;

  final dock = InspiraDock(
    items: [
      InspiraDockItem(
        child: const Icon(Icons.brush),
        label: '画笔',
        onTap: () => taps++,
      ),
      const InspiraDockItem(child: Icon(Icons.cleaning_services), label: '橡皮'),
      const InspiraDockItem(child: Icon(Icons.text_fields), label: '文字'),
    ],
  );

  setUp(() => taps = 0);

  testWidgets('渲染全部条目并带语义标签', (tester) async {
    await tester.pumpWidget(_host(child: dock));

    expect(find.byIcon(Icons.brush), findsOneWidget);
    expect(find.byIcon(Icons.cleaning_services), findsOneWidget);
    expect(find.byIcon(Icons.text_fields), findsOneWidget);
    // Semantics 标签存在性：
    expect(
      find.bySemanticsLabel('画笔'),
      findsOneWidget,
    );
  });

  testWidgets('点击条目触发回调', (tester) async {
    await tester.pumpWidget(_host(child: dock));
    await tester.tap(find.byIcon(Icons.brush));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('悬停时正下方图标放大（高斯邻近放大）', (tester) async {
    await tester.pumpWidget(_host(child: dock));
    await tester.pump();

    // 悬停第一个图标中心（鼠标指针需要显式 addPointer 触发 hover）。
    final center = tester.getCenter(find.byIcon(Icons.brush));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(center + const Offset(2, 0));
    await tester.pumpAndSettle();

    // 找到三个 Transform，中间（非悬停）应保持 1.0，悬停中的明显大于 1。
    double scaleOf(IconData icon) {
      final t = tester.widget<Transform>(
        find.ancestor(
          of: find.byIcon(icon),
          matching: find.byWidgetPredicate((w) => w is Transform),
        ).first,
      );
      return t.transform.getMaxScaleOnAxis();
    }

    final hovered = scaleOf(Icons.brush);
    final far = scaleOf(Icons.text_fields);
    expect(hovered, greaterThan(1.1), reason: '正下方图标应放大');
    expect(far, closeTo(1.0, 0.05), reason: '远处图标不应放大');
  });

  testWidgets('disableAnimations 时保持静态尺寸', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true, child: dock));
    await tester.pump();

    final center = tester.getCenter(find.byIcon(Icons.brush));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(center + const Offset(2, 0));
    await tester.pumpAndSettle();

    double scaleOf(IconData icon) {
      final t = tester.widget<Transform>(
        find.ancestor(
          of: find.byIcon(icon),
          matching: find.byWidgetPredicate((w) => w is Transform),
        ).first,
      );
      return t.transform.getMaxScaleOnAxis();
    }

    expect(scaleOf(Icons.brush), 1.0, reason: '减弱动态效果时不放大');
  });

  testWidgets('垂直停靠（left edge）可正常布局与点击', (tester) async {
    await tester.pumpWidget(
      _host(
        child: InspiraDock(
          edge: InspiraDockEdge.left,
          items: [
            InspiraDockItem(
              child: const Icon(Icons.brush),
              label: '画笔',
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.brush));
    await tester.pump();
    expect(taps, 1);
  });
}
