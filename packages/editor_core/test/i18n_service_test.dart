import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// Excalidraw 借鉴——I18nService 国际化测试（纯逻辑——不可变——不搞崩）。
void main() {
  test('LocaleConfig：默认值（LTR）', () {
    const locale = LocaleConfig(code: 'en', name: 'English', nativeName: 'English');
    expect(locale.code, 'en');
    expect(locale.direction, TextDirection.ltr);
    expect(locale.isRtl, false);
  });

  test('LocaleConfig：RTL（阿拉伯语）', () {
    expect(LocaleConfig.ar.isRtl, true);
    expect(LocaleConfig.ar.direction, TextDirection.rtl);
  });

  test('LocaleConfig：预设语言', () {
    expect(LocaleConfig.all.length, 9);
    expect(LocaleConfig.en.code, 'en');
    expect(LocaleConfig.zhCN.code, 'zh-CN');
    expect(LocaleConfig.zhTW.code, 'zh-TW');
    expect(LocaleConfig.ja.code, 'ja');
  });

  test('LocaleConfig：相等性（按 code）', () {
    const a = LocaleConfig(code: 'en', name: 'English', nativeName: 'English');
    const b = LocaleConfig(code: 'en', name: 'Eng', nativeName: 'Eng');
    expect(a, b); // code 相同。
  });

  test('I18nService：基本翻译（t 方法）', () {
    const i18n = I18nService(
      locale: LocaleConfig.zhCN,
      translations: {
        'toolbar.undo': '撤销',
        'toolbar.redo': '重做',
        'export.title': '导出',
      },
      fallback: {
        'toolbar.undo': 'Undo',
        'toolbar.redo': 'Redo',
        'export.title': 'Export',
      },
    );
    expect(i18n.t('toolbar.undo'), '撤销');
    expect(i18n.t('toolbar.redo'), '重做');
    expect(i18n.t('export.title'), '导出');
  });

  test('I18nService：回退到 fallback（英文默认）', () {
    const i18n = I18nService(
      locale: LocaleConfig.zhCN,
      translations: {'toolbar.undo': '撤销'},
      fallback: {'toolbar.redo': 'Redo'},
    );
    expect(i18n.t('toolbar.undo'), '撤销'); // 中文翻译。
    expect(i18n.t('toolbar.redo'), 'Redo'); // 回退英文。
    expect(i18n.t('unknown.key'), 'unknown.key'); // 无翻译——返回键本身。
  });

  test('I18nService：参数替换（{0}、{1} 格式——Excalidraw 模式）', () {
    const i18n = I18nService(
      locale: LocaleConfig.en,
      translations: {
        'export.success': 'Exported {0} files in {1}ms',
        'layer.count': '{0} layers',
      },
    );
    expect(i18n.t('export.success', ['5', '120']), 'Exported 5 files in 120ms');
    expect(i18n.t('layer.count', ['3']), '3 layers');
  });

  test('I18nService：withLocale 切换语言（不可变）', () {
    const i18nEn = I18nService(
      locale: LocaleConfig.en,
      translations: {'toolbar.undo': 'Undo'},
    );
    final i18nZh = i18nEn.withLocale(
      LocaleConfig.zhCN,
      {'toolbar.undo': '撤销'},
    );
    expect(i18nEn.locale.code, 'en'); // 原实例不变。
    expect(i18nZh.locale.code, 'zh-CN');
    expect(i18nZh.t('toolbar.undo'), '撤销');
  });

  test('I18nService：hasKey / translatedCount', () {
    const i18n = I18nService(
      locale: LocaleConfig.en,
      translations: {'a': 'A', 'b': 'B'},
      fallback: {'c': 'C'},
    );
    expect(i18n.hasKey('a'), true);
    expect(i18n.hasKey('c'), true); // fallback 中。
    expect(i18n.hasKey('d'), false);
    expect(i18n.translatedCount, 2);
  });

  test('I18nService：相等性（按 locale）', () {
    const a = I18nService(locale: LocaleConfig.en, translations: {});
    const b = I18nService(locale: LocaleConfig.en, translations: {'x': 'X'});
    expect(a, b); // locale 相同。
  });
}
