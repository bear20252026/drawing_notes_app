// 主题适配层黄金基线回归（2026-11-16）。
//
// 基线 = 适配层重构**前** app_design._theme 的四档 ThemeData 全字段
// 快照（golden/theme_baseline.json，重构前实机捕获）。本测试把重构后
// AppDesign.lightTheme/darkTheme（经 AppThemeSpec → MaterialThemeAdapter）
// 的产出与基线逐字段比对——任何视觉漂移（配色/圆角/字重/间距/转场）即红。
//
// 覆盖：ColorScheme 28 槽、scaffold/focus/appBar/card/divider/input/
// tabBar/snackBar/dialog/tooltip 各子主题、textTheme 四档、页面转场。
// 状态层（WidgetStateProperty）不可 JSON 序列化，由既有
// apple_state_layer_test.dart 单独钉住（本次未动其实现）。
//
// **基线更新纪律**：只有「有意的视觉变更」才准重捕获基线，且须在
// commit message 写明视觉裁决依据（DESIGN.md 条目/业主批准）——
// 重构类改动基线必须逐字节不变。
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/core/theme/apple_contrast.dart';

void main() {
  Map<String, dynamic> schemeToJson(ColorScheme s) => {
    'brightness': s.brightness.name,
    'primary': s.primary.toARGB32(), 'onPrimary': s.onPrimary.toARGB32(),
    'primaryContainer': s.primaryContainer.toARGB32(), 'onPrimaryContainer': s.onPrimaryContainer.toARGB32(),
    'secondary': s.secondary.toARGB32(), 'onSecondary': s.onSecondary.toARGB32(),
    'secondaryContainer': s.secondaryContainer.toARGB32(), 'onSecondaryContainer': s.onSecondaryContainer.toARGB32(),
    'tertiary': s.tertiary.toARGB32(), 'onTertiary': s.onTertiary.toARGB32(),
    'tertiaryContainer': s.tertiaryContainer.toARGB32(), 'onTertiaryContainer': s.onTertiaryContainer.toARGB32(),
    'error': s.error.toARGB32(), 'onError': s.onError.toARGB32(),
    'errorContainer': s.errorContainer.toARGB32(), 'onErrorContainer': s.onErrorContainer.toARGB32(),
    'surface': s.surface.toARGB32(), 'onSurface': s.onSurface.toARGB32(),
    'surfaceContainerHighest': s.surfaceContainerHighest.toARGB32(),
    'onSurfaceVariant': s.onSurfaceVariant.toARGB32(),
    'outline': s.outline.toARGB32(), 'outlineVariant': s.outlineVariant.toARGB32(),
    'shadow': s.shadow.toARGB32(), 'scrim': s.scrim.toARGB32(),
    'inverseSurface': s.inverseSurface.toARGB32(), 'onInverseSurface': s.onInverseSurface.toARGB32(),
    'inversePrimary': s.inversePrimary.toARGB32(), 'surfaceTint': s.surfaceTint.toARGB32(),
  };

  Map<String, dynamic> tsToJson(TextStyle? t) => t == null ? {} : {
    'color': t.color?.toARGB32(), 'fontSize': t.fontSize, 'fontWeight': t.fontWeight?.value,
    'letterSpacing': t.letterSpacing, 'height': t.height, 'fontFamily': t.fontFamily,
    'inherit': t.inherit,
  };

  Map<String, dynamic> themeToJson(ThemeData d) => {
    'useMaterial3': d.useMaterial3,
    'brightness': d.brightness.name,
    'colorScheme': schemeToJson(d.colorScheme),
    'scaffoldBackgroundColor': d.scaffoldBackgroundColor.toARGB32(),
    'focusColor': d.focusColor.toARGB32(),
    'visualDensity': '${d.visualDensity.horizontal},${d.visualDensity.vertical}',
    'tapTarget': d.materialTapTargetSize.name,
    'splashFactory': d.splashFactory.toString(),
    'appBar': {
      'bg': d.appBarTheme.backgroundColor?.toARGB32(), 'fg': d.appBarTheme.foregroundColor?.toARGB32(),
      'elev': d.appBarTheme.elevation, 'scrolled': d.appBarTheme.scrolledUnderElevation,
      'tint': d.appBarTheme.surfaceTintColor?.toARGB32(),
      'titleSpacing': d.appBarTheme.titleSpacing, 'toolbarHeight': d.appBarTheme.toolbarHeight,
      'titleStyle': tsToJson(d.appBarTheme.titleTextStyle),
    },
    'card': {
      'color': d.cardTheme.color?.toARGB32(), 'elev': d.cardTheme.elevation,
      'margin': d.cardTheme.margin.toString(), 'tint': d.cardTheme.surfaceTintColor?.toARGB32(),
      'shape': d.cardTheme.shape.toString(), 'clip': d.cardTheme.clipBehavior?.name,
    },
    'divider': {'color': d.dividerTheme.color?.toARGB32(), 'thickness': d.dividerTheme.thickness, 'space': d.dividerTheme.space},
    'input': {
      'filled': d.inputDecorationTheme.filled, 'fillColor': d.inputDecorationTheme.fillColor?.toARGB32(),
      'padding': d.inputDecorationTheme.contentPadding.toString(),
      'border': d.inputDecorationTheme.border.toString(),
      'enabled': d.inputDecorationTheme.enabledBorder.toString(),
      'focused': d.inputDecorationTheme.focusedBorder.toString(),
    },
    'tabBar': {
      'indicatorSize': d.tabBarTheme.indicatorSize?.name, 'dividerColor': d.tabBarTheme.dividerColor?.toARGB32(),
      'labelColor': d.tabBarTheme.labelColor?.toARGB32(), 'unselected': d.tabBarTheme.unselectedLabelColor?.toARGB32(),
      'labelStyle': tsToJson(d.tabBarTheme.labelStyle), 'unselectedStyle': tsToJson(d.tabBarTheme.unselectedLabelStyle),
      'indicator': d.tabBarTheme.indicator.toString(),
    },
    'snackBar': {
      'behavior': d.snackBarTheme.behavior?.name, 'elev': d.snackBarTheme.elevation,
      'bg': d.snackBarTheme.backgroundColor?.toARGB32(),
      'contentStyle': tsToJson(d.snackBarTheme.contentTextStyle), 'shape': d.snackBarTheme.shape.toString(),
    },
    'dialog': {
      'elev': d.dialogTheme.elevation, 'shadow': d.dialogTheme.shadowColor?.toARGB32(),
      'shape': d.dialogTheme.shape.toString(),
      'titleStyle': tsToJson(d.dialogTheme.titleTextStyle), 'contentStyle': tsToJson(d.dialogTheme.contentTextStyle),
      'actionsPadding': d.dialogTheme.actionsPadding.toString(),
    },
    'tooltip': {
      'wait': d.tooltipTheme.waitDuration?.inMilliseconds,
      'decoration': d.tooltipTheme.decoration.toString(),
      'textStyle': tsToJson(d.tooltipTheme.textStyle),
    },
    'textTheme': {
      for (final e in {'titleLarge': d.textTheme.titleLarge, 'labelLarge': d.textTheme.labelLarge, 'bodyMedium': d.textTheme.bodyMedium, 'bodySmall': d.textTheme.bodySmall}.entries)
        e.key: tsToJson(e.value),
    },
    'transitions': d.pageTransitionsTheme.builders.map((k, v) => MapEntry(k.name, v.toString())),
  };

  final baseline = jsonDecode(
    File('test/core/theme/golden/theme_baseline.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final variants = <String, ThemeData>{
    'light_normal': AppDesign.lightTheme(),
    'dark_normal': AppDesign.darkTheme(),
    'light_high': AppDesign.lightTheme(contrast: AppleContrast.high),
    'dark_high': AppDesign.darkTheme(contrast: AppleContrast.high),
  };

  for (final entry in variants.entries) {
    test('黄金基线：${entry.key} 与重构前逐字段等价', () {
      expect(baseline.containsKey(entry.key), isTrue, reason: '基线缺档');
      expect(themeToJson(entry.value), baseline[entry.key]);
    });
  }

  test('分母下限：基线四档 × 18 字段组，扫描面不许塌', () {
    expect(baseline.length, 4);
    for (final v in baseline.values) {
      expect((v as Map).length, greaterThanOrEqualTo(18));
    }
  });

  test('公开 ColorScheme 入口与主题内 scheme 同源（main.dart 兜底依赖）', () {
    expect(
      schemeToJson(AppDesign.appleLightScheme()),
      schemeToJson(AppDesign.lightTheme().colorScheme),
    );
    expect(
      schemeToJson(AppDesign.navyScheme()),
      schemeToJson(AppDesign.darkTheme().colorScheme),
    );
  });
}