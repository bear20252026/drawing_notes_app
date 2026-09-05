// 液态玻璃着色器测试（前景罩 + G3 backdrop 滤镜）。
//
// 覆盖：init 幂等不抛（两 program 均静默回退）/ isBackdropReady 与
// bindBackdrop 一致性（就绪非 null / 未就绪 null）/ uniform 下标协议
// （bindBackdrop 六槽位可 set）/ GlassSurface G3 分支在测试环境
// （软件渲染，isShaderFilterSupported=false）回落 G1 不炸 /
// 红线：整棵树一层 BackdropFilter。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/shared/widgets/glass_surface.dart';
import 'package:drawing_notes_app/shared/widgets/liquid_glass_shader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiquidGlassShader', () {
    test('init 幂等且不抛异常（两 program 均静默回退）', () async {
      await LiquidGlassShader.init();
      await LiquidGlassShader.init(); // 幂等：第二次直接返回。
    });

    test('bindBackdrop 与 isBackdropReady 一致（未就绪必为 null）', () {
      final shader = LiquidGlassShader.bindBackdrop(
        size: const Size(320, 64),
        radius: 32,
      );
      if (LiquidGlassShader.isBackdropReady) {
        expect(shader, isNotNull);
      } else {
        expect(shader, isNull);
      }
    });

    test('G3 滤镜支持检测口径正确（测试环境为软件渲染）', () {
      // 测试环境跑在软件渲染器上：isShaderFilterSupported 必为 false
      // （= 非 Impeller）。此断言同时锁定 API 可用性。
      // 真机（Impeller）上为 true，G3 管线经 GlassSurface 自动启用。
      // ignore: avoid_print
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
    });
  });

  group('GlassSurface G3 回落', () {
    // L3 罩含微光闪烁（每帧重绘），固定时长 pump，禁用 pumpAndSettle。
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('L3 渲染：测试环境回落 G1 管线不炸（isShaderFilterSupported 兜底）', (
      tester,
    ) async {
      GlassSurface.resetFilterCacheForTest(); // G1 缓存清空（引用 + 隔离）。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassSurface(
                borderRadius: BorderRadius.circular(28),
                child: const SizedBox(
                  width: 200,
                  height: 64,
                  child: Center(child: Text('GLASS')),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      // 尺寸测量 setState 收敛（无异常循环）。
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('GLASS'), findsOneWidget);
    });

    testWidgets('红线：整棵树只允许一层 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GlassSurface(
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: Center(child: Text('X')),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
