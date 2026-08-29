// 回归测试：material_ui MaterialApp 内的 Flutter(material) TextField
// 必须能找到自己的 MaterialLocalizations（AllDocsSidebar 搜索框即此场景）。
//
// 背景：应用同时用两种 Material 方言 —— material_ui(新官方库) 自带独立的
// MaterialApp/Theme/MaterialLocalizations，与 flutter/material 的是不同类型。
// material_ui 的 MaterialApp 默认只注册 material_ui 版 delegate，导致其内部
// flutter/material 组件（如 AllDocsSidebar 的 TextField）报
// "No MaterialLocalizations found"。
//
// 修复：同时注册两个 GlobalMaterialLocalizations.delegate（material_ui 版 +
// Flutter SDK 版），各方言各取所需、互不冲突（与 app/lib/app.dart 一致）。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    as fl_loc show GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart' as mui;
import 'package:flutter_test/flutter_test.dart';

Widget _app() {
  return mui.MaterialApp(
    localizationsDelegates: [
      // material_ui 组件用 material_ui 版
      mui.GlobalMaterialLocalizations.delegate,
      // flutter/material 组件（AllDocsSidebar TextField）用 Flutter SDK 版
      fl_loc.GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    debugShowCheckedModeBanner: false,
    home: Builder(
      builder: (context) {
        // 模拟 AllDocsSidebar：一个 Flutter(material) 的 TextField。
        // 若 Flutter 版 MaterialLocalizations 未被提供，这里会抛
        // "No MaterialLocalizations found"。
        return Scaffold(
          body: Column(
            children: [
              // 探针：直接读取 Flutter 版 MaterialLocalizations，证明其存在。
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
  testWidgets('Flutter TextField finds Flutter MaterialLocalizations '
      'under mui MaterialApp (dual delegate)', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // 无异常抛出 => 未出现 "No MaterialLocalizations found"
    expect(tester.takeException(), isNull);

    // Flutter 版 MaterialLocalizations 确实被提供
    final probe = tester.widget<Text>(find.textContaining('FL_ML='));
    expect(probe.data, isNot(contains('null')));
  });
}
