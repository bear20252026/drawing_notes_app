// Golden 测试基础设施：在测试进程里加载打包的 CJK 字体。
//
// Flutter 的默认测试字体（Ahem）只含占位字符，渲染中文会变成方框。
// 本工程把 `assets/fonts/DroidSansFallbackFull.ttf` 打在 assets 里用于
// PDF 导出；同样的字在测试里用 [loadGoldenCjkFont] 加载即可让 golden 跨
// 平台确定（Windows / Android / Linux runner 渲染一致）。
//
// 用法：
// ```dart
// setUpAll(loadGoldenCjkFont);
// ...
// theme: ThemeData(textTheme: const TextTheme(...).apply(fontFamily: 'GoldenCjk'))
// ```
import 'dart:io';

import 'package:flutter/services.dart';

/// 字体族名（测试里 `fontFamily: 'GoldenCjk'` 即可使用）。
const String kGoldenCjkFamily = 'GoldenCjk';

/// 加载打包的 CJK 字体；放在 `setUpAll(...)` 里只跑一次。
Future<void> loadGoldenCjkFont() async {
  final bytes = File('assets/fonts/DroidSansFallbackFull.ttf')
      .readAsBytesSync()
      .buffer
      .asByteData();
  final loader = FontLoader(kGoldenCjkFamily)
    ..addFont(Future.value(bytes));
  await loader.load();
}