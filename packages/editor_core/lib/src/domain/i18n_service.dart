// editor_core——i18n 国际化（Excalidraw locales/ + i18n.ts 借鉴——2026-08-21）。
//
// Excalidraw i18n 本地化——多语言支持（LocaleConfig + I18nService）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// Excalidraw 原版参考：
// - locales/ 目录——语言包（zh-CN.json/en.json/ja.json 等）
// - i18n.ts——语言检测 + 翻译加载 + 键值对翻译
// - 翻译键格式：toolbar.undo / export.png / layerPanel.title 等
library;

/// 语言方向（Excalidraw locale 配置借鉴）。
/// 注意：避免与 Flutter 的 TextDirection 冲突——重命名为 TextFlowDirection。
enum TextFlowDirection { ltr, rtl }

/// 语言配置（Excalidraw locale 本地化——不可变）。
class LocaleConfig {
  const LocaleConfig({
    required this.code,
    required this.name,
    required this.nativeName,
    this.direction = TextFlowDirection.ltr,
  });

  /// 语言代码（如 'en'、'zh-CN'、'ja'）。
  final String code;

  /// 英文名称。
  final String name;

  /// 本地名称。
  final String nativeName;

  /// 文本方向。
  final TextFlowDirection direction;

  /// 是否 RTL（阿拉伯语/希伯来语等）。
  bool get isRtl => direction == TextFlowDirection.rtl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LocaleConfig && code == other.code;

  @override
  int get hashCode => code.hashCode;

  /// 预设语言（Excalidraw locales 常用语言）。
  static const en = LocaleConfig(code: 'en', name: 'English', nativeName: 'English');
  static const zhCN = LocaleConfig(code: 'zh-CN', name: 'Chinese (Simplified)', nativeName: '简体中文');
  static const zhTW = LocaleConfig(code: 'zh-TW', name: 'Chinese (Traditional)', nativeName: '繁體中文');
  static const ja = LocaleConfig(code: 'ja', name: 'Japanese', nativeName: '日本語');
  static const ko = LocaleConfig(code: 'ko', name: 'Korean', nativeName: '한국어');
  static const de = LocaleConfig(code: 'de', name: 'German', nativeName: 'Deutsch');
  static const fr = LocaleConfig(code: 'fr', name: 'French', nativeName: 'Français');
  static const es = LocaleConfig(code: 'es', name: 'Spanish', nativeName: 'Español');
  static const ar = LocaleConfig(code: 'ar', name: 'Arabic', nativeName: 'العربية', direction: TextFlowDirection.rtl);

  /// 所有预设语言。
  static const List<LocaleConfig> all = [en, zhCN, zhTW, ja, ko, de, fr, es, ar];
}

/// 国际化服务（Excalidraw i18n.ts 本地化——积木式纯 Dart）。
///
/// 键值对翻译——不可变（copyWith 切换语言）。
/// 支持参数替换（`{0}`、`{1}` 格式——Excalidraw 模式）。
class I18nService {
  const I18nService({
    required this.locale,
    required this.translations,
    this.fallback = const {},
  });

  /// 当前语言。
  final LocaleConfig locale;

  /// 翻译映射（键 → 翻译文本）。
  final Map<String, String> translations;

  /// 回退翻译（英文默认）。
  final Map<String, String> fallback;

  /// 翻译（键 → 文本——不存在则回退到 fallback 或返回键本身）。
  String t(String key, [List<String>? args]) {
    var text = translations[key] ?? fallback[key] ?? key;
    // 参数替换（{0}、{1} 格式——Excalidraw 模式）。
    if (args != null) {
      for (var i = 0; i < args.length; i++) {
        text = text.replaceAll('{$i}', args[i]);
      }
    }
    return text;
  }

  /// 切换语言（不可变——返回新实例）。
  I18nService withLocale(LocaleConfig newLocale, Map<String, String> newTranslations) {
    return I18nService(
      locale: newLocale,
      translations: newTranslations,
      fallback: fallback,
    );
  }

  /// 是否有指定键的翻译。
  bool hasKey(String key) => translations.containsKey(key) || fallback.containsKey(key);

  /// 已翻译的键数量。
  int get translatedCount => translations.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is I18nService && locale == other.locale;

  @override
  int get hashCode => locale.hashCode;
}
