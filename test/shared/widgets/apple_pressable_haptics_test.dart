// ApplePressable v1.11.0 触感与语义升级（审计二-2/二-3）：
// 1. 指针按下触发 HapticFeedback.selectionClick（统一触感，全库按钮基座受益）；
// 2. 语义树始终暴露 button 角色（无 label 也可达，读屏可遍历）。
//
// 触感断言：截获 SystemChannels.platform 的 HapticFeedback.vibrate 方法调用。
import 'dart:ui' as ui;

import 'package:drawing_notes_app/shared/widgets/apple_pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApplePressable 触感（审计二-2）', () {
    testWidgets('指针按下触发 selectionClick 触感', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ApplePressable(
                onTap: () => taps++,
                child: const SizedBox(width: 80, height: 48),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ApplePressable));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(calls, isNotEmpty, reason: '按下即应有触感反馈');
      expect(
        calls.single.arguments,
        'HapticFeedbackType.selectionClick',
        reason: '统一使用 selectionClick（轻量选中确认感）',
      );

      await gesture.up();
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('禁用态按下不触发触感', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ApplePressable(
                enabled: false,
                child: SizedBox(width: 80, height: 48),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(ApplePressable));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(calls, isEmpty, reason: 'enabled=false 时一切输入忽略，含触感');
    });
  });

  group('ApplePressable 语义（审计二-3）', () {
    testWidgets('无 label 也暴露 button 角色', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ApplePressable(
                onTap: () {},
                child: const SizedBox(width: 80, height: 48),
              ),
            ),
          ),
        ),
      );

      final data = tester.getSemantics(find.byType(ApplePressable));
      expect(
        // SemanticsData.hasFlag 已弃用（3.32+），用 flagsCollection 具名字段。
        data.flagsCollection.isButton,
        isTrue,
        reason: '角色标注不应依赖 label 存在',
      );
      handle.dispose();
    });

    testWidgets('禁用态 button 角色 + enabled=false', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ApplePressable(
                enabled: false,
                child: SizedBox(width: 80, height: 48),
              ),
            ),
          ),
        ),
      );

      final data = tester.getSemantics(find.byType(ApplePressable));
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
      handle.dispose();
    });
  });
}
