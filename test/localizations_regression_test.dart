// 回归测试：统一的 MaterialApp（flutter/material 方言）内，
// MaterialLocalizations 必须可用（AllDocsSidebar 搜索框即此场景）。
//
// 背景（已解决）：2026-08-30 前，应用混用 material_ui 与 flutter/material
// 两种方言——material_ui 是 material 的完整 fork，其 MaterialApp/Theme/
// MaterialLocalizations 与 flutter/material 是不同类型，需双 delegate 注册
// 才能避免 "No MaterialLocalizations found"。mui 退役后全库统一为
// flutter/material 单一方言，本测试锁定"单一 delegate 即可"的新契约。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) {
        // 模拟 AllDocsSidebar：一个 TextField。
        // 若 MaterialLocalizations 未被提供，这里会抛
        // "No MaterialLocalizations found"。
        return Scaffold(
          body: Column(
            children: [
              // 探针：直接读取 MaterialLocalizations，证明其存在。
              Builder(builder: (_) {
                final l = MaterialLocalizations.of(context);
                return Text('FL_ML=${l.backButtonTooltip}',
                    textDirection: TextDirection.ltr);
              }),
              const TextField(decoration: InputDecoration(hintText: '快速搜索')),
            ],
          ),
        );
      },
    ),
  );
}

void main() {
  testWidgets('统一方言：TextField 找到 MaterialLocalizations（单一 delegate）',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // 无异常抛出 => 未出现 "No MaterialLocalizations found"
    expect(tester.takeException(), isNull);

    // MaterialLocalizations 确实被提供
    final probe = tester.widget<Text>(find.textContaining('FL_ML='));
    expect(probe.data, isNot(contains('null')));
  });
}
