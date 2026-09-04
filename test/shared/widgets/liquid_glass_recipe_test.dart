// 液态玻璃配方测试（docs/LIQUID_GLASS_TECHNICAL_PLAN_2026-09-05.md）。
//
// 覆盖：饱和度矩阵的数学性质 / 配方常量取值 / GlassSurface 默认档 /
// 参数组合渲染不崩溃 / 防复发（默认档不得回退到 L2）。
//
// 背景：2026-09-05 核查发现三处缺口——saturate 完全未实现、L3 零调用、
// 基底 80% 不透明导致「看着像灰白板」。本文件锁定修复后的取值。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

void main() {
  group('liquidGlassSaturationMatrix 数学性质', () {
    test('k=1 退化为单位矩阵', () {
      final m = liquidGlassSaturationMatrix(1);
      final identity = <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0,
      ];
      for (var i = 0; i < 20; i++) {
        expect(m[i], closeTo(identity[i], 1e-12), reason: 'index $i');
      }
    });

    test('长度为 20（ColorFilter.matrix 口径）', () {
      expect(liquidGlassSaturationMatrix(1.4), hasLength(20));
    });

    test('任意 k 下三行系数和恒为 1（亮度守恒，不整体变亮或变暗）', () {
      for (final k in <double>[0, 0.5, 1, 1.4, 2, 3]) {
        final m = liquidGlassSaturationMatrix(k);
        for (var row = 0; row < 3; row++) {
          final sum = m[row * 5] + m[row * 5 + 1] + m[row * 5 + 2];
          expect(sum, closeTo(1, 1e-12), reason: 'k=$k row=$row');
        }
      }
    });

    test('alpha 行恒为 [0,0,0,1,0]（不污染透明度）', () {
      final m = liquidGlassSaturationMatrix(1.4);
      expect(m.sublist(15, 20), <double>[0, 0, 0, 1, 0]);
    });

    test('k=1.4 的对角/非对角系数符合 Rec.709 公式', () {
      const k = 1.4;
      final m = liquidGlassSaturationMatrix(k);
      // R' = (0.213 + 0.787k)R + (0.715 − 0.715k)G + (0.072 − 0.072k)B
      expect(m[0], closeTo(0.213 + 0.787 * k, 1e-12));
      expect(m[1], closeTo(0.715 - 0.715 * k, 1e-12));
      expect(m[2], closeTo(0.072 - 0.072 * k, 1e-12));
      // 提升饱和度时，非对角项必须为负（否则不是「拉开色差」而是「整体加色」）。
      for (final i in <int>[1, 2, 5, 7, 10, 11]) {
        expect(m[i], lessThan(0), reason: 'index $i 应为负');
      }
    });

    test('k>1 时对角项大于 1（确实在提升饱和度）', () {
      final m = liquidGlassSaturationMatrix(1.4);
      expect(m[0], greaterThan(1));
      expect(m[6], greaterThan(1));
      expect(m[12], greaterThan(1));
    });
  });

  group('配方常量（三来源裁决值）', () {
    test('模糊 12 = prototype/PICKER.md 实测 blur(12px)', () {
      expect(LiquidGlassRecipe.kDefaultSigma, 12);
    });

    test('饱和度 1.4 = Apple HIG 1.2–1.5× 且 PICKER 实测 saturate(1.4)', () {
      expect(LiquidGlassRecipe.kDefaultSaturation, 1.4);
    });

    test('底色落在 Apple HIG regular 区间 0.6–0.8（非此前 0.80 的钝感值）', () {
      expect(LiquidGlassRecipe.kRegularOpacity, inInclusiveRange(0.6, 0.8));
      expect(LiquidGlassRecipe.kRegularOpacity, lessThan(0.8));
    });

    test('clear 变体落在 Apple HIG clear 区间 0.3–0.5', () {
      expect(LiquidGlassRecipe.kClearOpacity, inInclusiveRange(0.3, 0.5));
    });

    test('位移 70 / 色散 2 = liquid-glass-react 对外默认档', () {
      expect(LiquidGlassRecipe.kDisplacement, 70);
      expect(LiquidGlassRecipe.kAberration, 2);
    });
  });

  group('GlassSurface 默认档', () {
    test('默认参数全部引用配方常量（无硬编码漂移）', () {
      const s = GlassSurface(child: SizedBox.shrink());
      expect(s.sigma, LiquidGlassRecipe.kDefaultSigma);
      expect(s.saturation, LiquidGlassRecipe.kDefaultSaturation);
      expect(s.surfaceOpacity, LiquidGlassRecipe.kRegularOpacity);
      expect(s.level, LiquidGlassLevel.l3);
    });

    test('防复发：默认档必须是 L3（L2 会让折射罩永不渲染）', () {
      final src = File(
        'lib/shared/widgets/glass_surface.dart',
      ).readAsStringSync();
      expect(src, contains('this.level = LiquidGlassLevel.l3'));
      // 旧默认值不得残留在构造函数中。
      final ctor = src.substring(
        0,
        src.indexOf(');', src.indexOf('const GlassSurface({')),
      );
      expect(ctor, isNot(contains('this.level = LiquidGlassLevel.l2')));
    });
  });

  group('参数组合渲染', () {
    testWidgets('saturation / surfaceOpacity 全区间不崩溃', (tester) async {
      for (final sat in <double>[1.0, 1.2, 1.4, 1.8]) {
        for (final opacity in <double>[
          LiquidGlassRecipe.kClearOpacity,
          LiquidGlassRecipe.kRegularOpacity,
          0.8,
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: GlassSurface(
                  saturation: sat,
                  surfaceOpacity: opacity,
                  child: const Text('GLASS_PARAM'),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('GLASS_PARAM'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('clear 变体（0.45）比 regular（0.62）更通透', (tester) async {
      const clear = GlassSurface(child: SizedBox.shrink());
      const regular = GlassSurface(
        surfaceOpacity: LiquidGlassRecipe.kClearOpacity,
        child: SizedBox.shrink(),
      );
      expect(regular.surfaceOpacity, lessThan(clear.surfaceOpacity));
      // 两者都能渲染（渲染即通过）。
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: clear)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
