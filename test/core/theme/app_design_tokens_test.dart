// 双令牌源收编锁定测试（审计四-1）：
// AppDesign 中与 AppleColor 同值的颜色常量必须经别名引用——
// 若有人改回字面量导致两源分叉，本测试立即红。
// lightSubtleSurface 刻意例外（systemGray6 ≠ AppleColor.subtleSurface，
// 两个灰阶并存是视觉决策，合并即改视觉，须实机对比另行裁决）。
import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDesign ↔ AppleColor 单一事实来源（审计四-1）', () {
    test('重复色值全部经 AppleColor 别名（identical 断言）', () {
      expect(identical(AppDesign.ink, AppleColor.ink), isTrue);
      expect(identical(AppDesign.accent, AppleColor.actionBlue), isTrue);
      expect(identical(AppDesign.lightCanvas, AppleColor.parchment), isTrue);
      expect(
        identical(AppDesign.lightSurface, AppleColor.surfaceWhite),
        isTrue,
      );
      expect(identical(AppDesign.darkCanvas, AppleColor.canvansDark), isTrue);
      expect(identical(AppDesign.darkSurface, AppleColor.surfaceDark), isTrue);
      expect(
        identical(AppDesign.darkSubtleSurface, AppleColor.subtleSurfaceDark),
        isTrue,
      );
    });

    test('lightSubtleSurface 是刻意保留的独立灰阶（systemGray6）', () {
      expect(AppDesign.lightSubtleSurface, isNot(AppleColor.subtleSurface));
      expect(AppDesign.lightSubtleSurface, const Color(0xFFF2F2F7));
    });
  });
}
