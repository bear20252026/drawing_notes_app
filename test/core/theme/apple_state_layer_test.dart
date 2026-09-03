// 交互状态层令牌测试（平台域裁决 C8，2026-09-04）。
//
// 数值权威：`android/skills`（Google 官方）+ Material 3 状态层规范，
// 经 `docs/DESIGN_SYSTEM.md` 第 3.5 节裁决后落地到
// `lib/core/theme/apple_design.dart` 的 `AppleStateLayer`。
//
// 钉住这些数值的理由：它们被主题层统一应用到 filled/outlined/icon 三类按钮，
// 一旦漂移，全 App 的悬停与按压反馈会变得不一致，且肉眼很难定位源头。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';

void main() {
  const onSurface = Color(0xFF1C1B1F);

  Color? resolve(Set<WidgetState> states) =>
      AppleStateLayer.overlay(onSurface).resolve(states);

  group('AppleStateLayer 数值', () {
    test('无状态不叠色', () {
      expect(resolve(<WidgetState>{}), isNull);
    });

    test('hover = 8%', () {
      expect(
        resolve(<WidgetState>{WidgetState.hovered}),
        onSurface.withValues(alpha: 0.08),
      );
    });

    test('focus = 12%', () {
      expect(
        resolve(<WidgetState>{WidgetState.focused}),
        onSurface.withValues(alpha: 0.12),
      );
    });

    test('pressed = 12%', () {
      expect(
        resolve(<WidgetState>{WidgetState.pressed}),
        onSurface.withValues(alpha: 0.12),
      );
    });

    test('dragged = 16%', () {
      expect(
        resolve(<WidgetState>{WidgetState.dragged}),
        onSurface.withValues(alpha: 0.16),
      );
    });

    test('disabled 不叠状态色（交由主题统一压低前景）', () {
      expect(resolve(<WidgetState>{WidgetState.disabled}), isNull);
    });

    test('常量的绝对值与裁决一致（防止有人直接改常量而不改文档）', () {
      expect(AppleStateLayer.hover, 0.08);
      expect(AppleStateLayer.focus, 0.12);
      expect(AppleStateLayer.pressed, 0.12);
      expect(AppleStateLayer.dragged, 0.16);
      expect(AppleStateLayer.disabled, 0.38);
    });
  });

  group('状态优先级（自最强往下）', () {
    test('拖拽 > 按压', () {
      final c = resolve(<WidgetState>{
        WidgetState.dragged,
        WidgetState.pressed,
      });
      expect(c, onSurface.withValues(alpha: 0.16));
    });

    test('按压 > 悬停（同为按下与悬停时取 12% 而非 8%）', () {
      final c = resolve(<WidgetState>{
        WidgetState.pressed,
        WidgetState.hovered,
      });
      expect(c, onSurface.withValues(alpha: 0.12));
    });

    test('焦点 > 悬停（键盘用户优先）', () {
      final c = resolve(<WidgetState>{
        WidgetState.focused,
        WidgetState.hovered,
      });
      expect(c, onSurface.withValues(alpha: 0.12));
    });

    test('disabled 优先级最高：禁用且按压也不叠色', () {
      final c = resolve(<WidgetState>{
        WidgetState.disabled,
        WidgetState.pressed,
      });
      expect(c, isNull);
    });
  });
}
