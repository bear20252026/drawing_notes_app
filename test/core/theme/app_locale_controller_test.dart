// AppLocaleController 单测（2026-09-27 增量）：三态循环 + 持久化 + 非法值回退。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/theme/app_locale_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认跟随系统（无持久化值）', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppLocaleController();
    await Future<void>.delayed(Duration.zero); // _load 异步完成
    expect(controller.locale, isNull);
    expect(controller.loaded, isTrue);
  });

  test('cycle：跟随系统 → 中文 → English → 跟随系统，并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppLocaleController();
    await Future<void>.delayed(Duration.zero);

    controller.cycle();
    expect(controller.locale, const Locale('zh'));
    await Future<void>.delayed(Duration.zero);

    controller.cycle();
    expect(controller.locale, const Locale('en'));
    await Future<void>.delayed(Duration.zero);

    controller.cycle();
    expect(controller.locale, isNull);
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'system');
  });

  test('持久化值在下次创建时恢复（zh）', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'zh'});
    final controller = AppLocaleController();
    await Future<void>.delayed(Duration.zero);
    expect(controller.locale, const Locale('zh'));
  });

  test('非法持久化值回退跟随系统', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'fr'});
    final controller = AppLocaleController();
    await Future<void>.delayed(Duration.zero);
    expect(controller.locale, isNull);
  });

  test('setLocale(null) 恢复跟随系统并写回 system', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    final controller = AppLocaleController();
    await Future<void>.delayed(Duration.zero);
    await controller.setLocale(null);
    expect(controller.locale, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'system');
  });
}
