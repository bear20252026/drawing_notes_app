// InspiraFluidCursor 组件测试：粒子生成、生命周期衰减、无障碍禁用。
import 'package:drawing_notes_app/shared/widgets/inspira/inspira_fluid_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  bool disableAnimations = false,
  required Widget child,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: 400, height: 300, child: child),
          ),
        ),
      ),
    );

int particleCount(WidgetTester tester) =>
    (tester.state<InspiraFluidCursorState>(
      find.byType(InspiraFluidCursor),
    )).debugParticleCount;

void main() {
  testWidgets('指针移动生成拖尾粒子', (tester) async {
    await tester.pumpWidget(
      _host(child: const InspiraFluidCursor(child: ColoredBox(color: Colors.black))),
    );
    expect(particleCount(tester), 0);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final area = tester.getRect(find.byType(InspiraFluidCursor));
    await gesture.moveTo(area.center - const Offset(60, 0));
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(area.center + Offset(-60.0 + i * 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(particleCount(tester), greaterThan(0),
        reason: '移动后应产生粒子');
  });

  testWidgets('粒子随时间衰减消亡', (tester) async {
    await tester.pumpWidget(
      _host(child: const InspiraFluidCursor(child: SizedBox.expand())),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final area = tester.getRect(find.byType(InspiraFluidCursor));
    await gesture.moveTo(area.center);
    await tester.pump();
    expect(particleCount(tester), greaterThan(0));

    // 寿命 0.55s，推进足够时间后应全部消亡。
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(particleCount(tester), 0, reason: '寿命结束后粒子应清空');
  });

  testWidgets('disableAnimations 完全不生成粒子', (tester) async {
    await tester.pumpWidget(
      _host(
        disableAnimations: true,
        child: const InspiraFluidCursor(child: SizedBox.expand()),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final area = tester.getRect(find.byType(InspiraFluidCursor));
    await gesture.moveTo(area.center);
    await gesture.moveTo(area.center + const Offset(30, 0));
    await tester.pump();

    expect(particleCount(tester), 0, reason: '减弱动态效果时不产生粒子');
  });

  testWidgets('子内容正常交互（粒子层不拦截手势）', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: InspiraFluidCursor(
          child: Center(
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('tap'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    expect(taps, 1);
  });
}
