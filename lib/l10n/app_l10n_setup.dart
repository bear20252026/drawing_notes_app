import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'app_localizations.dart';

/// 应用侧本地化装配收口（material_ui 迁移 2026-11-16）。
///
/// **为什么不直接用 `AppLocalizations.localizationsDelegates`**：
/// gen_l10n 生成模板（flutter_tools gen_l10n_templates.dart）硬编码
/// `flutter_localizations` 的三件套 delegate——SDK 3.50 起该源已弃用，
/// 且生成文件每次 `flutter pub get`（generate: true）都会被模板重写，
/// 手改生成码不可持续（实测被覆盖两次）。生成器无 delegates 覆写选项
/// （l10n.yaml 全选项核过），故把「App delegate + 全局三件套」的组合
/// 收进本文件——消费方一律用这里的两个常量，生成码的
/// localizationsDelegates 静态成员自此零消费（其弃用 info 由生成文件
/// 自带的 ignore_for_file 域外处理，见 l10n.yaml header 注入）。
///
/// 三件套新源 = material_ui 的 `GlobalMaterialLocalizations.delegates`
/// （官方迁移指南 Step 2：一个 getter 含 Material/Cupertino/Widgets 三委托）。
abstract final class AppL10nSetup {
  /// App 翻译委托 + 全局三件套（Material/Cupertino/Widgets）。
  static const List<LocalizationsDelegate<dynamic>> delegates =
      <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ];

  /// 支持的语言（转发 AppLocalizations.supportedLocales——该成员无弃用，
  /// 收口到此仅为消费方单一入口，不必记两个来源）。
  static const List<Locale> supportedLocales = AppLocalizations.supportedLocales;
}
