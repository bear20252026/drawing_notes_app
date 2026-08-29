// M10-B 冒烟测试：NotesWritingPage 渲染骨架 + 空态。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/presentation/notes_writing_page.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: child,
  );
}

void main() {
  testWidgets('NotesWritingPage 渲染：标题 + 空态提示', (tester) async {
    await tester.pumpWidget(_wrap(const NotesWritingPage()));

    expect(find.text('笔记'), findsWidgets);
    expect(find.text('纯笔记（待完善）'), findsOneWidget);
    expect(find.text('最近'), findsOneWidget);
  });
}
