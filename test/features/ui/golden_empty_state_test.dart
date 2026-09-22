// Golden 九宫格子集（2026-09-21）：
// 空态组件 × 明暗主题 × 两档窄宽，覆盖空列表首屏视觉回归。
// 字体：loadGoldenCjkFont（打包 CJK）。
// 基线在本机 Windows 生成；Linux CI 字体栅格化有亚像素差（~0.07%）
// 会误报——故仅在 Windows 跑比对（H 门禁策略，非放宽像素阈值）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/theme/app_design.dart';
import 'package:drawing_notes_app/shared/widgets/apple_empty_state.dart';
import '../../helpers/golden_fonts.dart';

bool get _goldenHost => Platform.isWindows;

Widget _wrap({required ThemeData theme, required Size size}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: Center(
          child: AppleEmptyState(
            icon: Icons.inbox_outlined,
            title: '还没有文档',
            tip: '新建笔记或画布开始记录',
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadGoldenCjkFont);

  const sizes = <String, Size>{
    'phone': Size(390, 844),
    'tablet': Size(900, 600),
  };

  for (final themeEntry in <String, ThemeData Function()>{
    'light': AppDesign.lightTheme,
    'dark': AppDesign.darkTheme,
  }.entries) {
    for (final sizeEntry in sizes.entries) {
      testWidgets('golden empty_state ${themeEntry.key}/${sizeEntry.key}', (
        tester,
      ) async {
        final theme = themeEntry.value();
        await tester.pumpWidget(
          _wrap(theme: theme, size: sizeEntry.value),
        );
        await expectLater(
          find.byType(AppleEmptyState),
          matchesGoldenFile(
            'goldens/empty_state_${themeEntry.key}_${sizeEntry.key}.png',
          ),
        );
      }, skip: _goldenHost ? null : 'Golden baseline is Windows-rendered');
    }
  }
}
