// M10-B 冒烟测试：HomePage 渲染骨架 + AppBar/TabBar 不抛错。
// 视觉化改动保逻辑/测试不破。

import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/notes/presentation/home_page.dart';

Future<Directory> _tempDir() async {
  return Directory.systemTemp.createTemp('home_page_test');
}

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
  testWidgets('HomePage 渲染：AppBar + TabBar + FAB 存在', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomePage(
          docStorage: StorageService(directoryProvider: _tempDir),
          notebookStorage: NotebookStorage(directoryProvider: _tempDir),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(Tab), findsWidgets);
    expect(find.byType(FloatingActionButton), findsWidgets);
  });

  testWidgets('HomePage 显示「+」新建入口', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomePage(
          docStorage: StorageService(directoryProvider: _tempDir),
          notebookStorage: NotebookStorage(directoryProvider: _tempDir),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byIcon(Icons.add), findsWidgets);
  });
}
