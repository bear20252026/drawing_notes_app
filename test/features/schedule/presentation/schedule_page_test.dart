// M10-B 冒烟测试：SchedulePage 渲染骨架不抛错。

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/schedule/presentation/schedule_page.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: Scaffold(body: child),
  );
}

Future<void> _setLargeView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('SchedulePage 渲染：标题「日程」存在', (tester) async {
    await _setLargeView(tester);
    await tester.pumpWidget(_wrap(const SchedulePage()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('日历 · 待办'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
  });

  testWidgets('SchedulePage 渲染：待办与文档动态区域存在', (tester) async {
    await _setLargeView(tester);
    await tester.pumpWidget(_wrap(const SchedulePage()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('日历 · 待办'), findsOneWidget);
    expect(find.text('全部日程'), findsOneWidget);
  });
}
