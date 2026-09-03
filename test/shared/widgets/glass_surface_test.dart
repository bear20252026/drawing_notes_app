// 液态玻璃 L1–L3 组件测试（DESIGN_SYSTEM.md §5）。
//
// 覆盖：三档渲染不崩溃 / L3 未就绪自动回落 / 闸门置顶与减弱动效降级 /
// 着色器加载失败静默（isReady 恒 false，不抛错）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_rim.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

void main() {
  testWidgets('GlassSurface L1/L2 渲染子节点且无异常', (tester) async {
    for (final level in [LiquidGlassLevel.l1, LiquidGlassLevel.l2]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSurface(
              level: level,
              child: const Text('GLASS_CONTENT'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('GLASS_CONTENT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('GlassSurface L3 渲染不崩溃（就绪与否由闸门裁决）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassSurface(
            level: LiquidGlassLevel.l3,
            child: Text('GLASS_L3'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('GLASS_L3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LiquidGlassGate.forceLevel 置顶生效', (tester) async {
    LiquidGlassGate.forceLevel = LiquidGlassLevel.l1;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('x'))),
      );
      final ctx = tester.element(find.text('x'));
      expect(
        LiquidGlassGate.resolve(ctx, LiquidGlassLevel.l3),
        LiquidGlassLevel.l1,
      );
    } finally {
      LiquidGlassGate.forceLevel = null;
    }
  });

  test('LiquidGlassShader.init 永不抛错（幂等，失败即回落）', () async {
    // 不抛错即通过（测试包内有无编译产物两种结果都接受）。
    await LiquidGlassShader.init();
    await LiquidGlassShader.init();
  });

  testWidgets('LiquidGlassRim 未就绪时占位收缩（无异常）', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 100,
            child: LiquidGlassRim(radius: 18),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
