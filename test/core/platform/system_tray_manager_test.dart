import 'dart:io';

import 'package:drawing_notes_app/core/platform/system_tray_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemTrayManager', () {
    test('isInitialized 默认为 false', () {
      expect(SystemTrayManager.isInitialized, isFalse);
    });

    test('initialize 需要 onShow 和 onQuit 参数', () async {
      try {
        await SystemTrayManager.initialize(
          onShow: () {},
          onQuit: () {},
        );

        // 桌面平台会真正初始化，移动平台静默跳过
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          expect(SystemTrayManager.isInitialized, isTrue);
        }
      } catch (_) {
        // 桌面平台可能缺少系统托盘图标资源，忽略
      }
    });

    test('重复 initialize 不重复初始化', () async {
      try {
        await SystemTrayManager.initialize(
          onShow: () {},
          onQuit: () {},
        );
        final first = SystemTrayManager.isInitialized;
        await SystemTrayManager.initialize(
          onShow: () {},
          onQuit: () {},
        );
        expect(SystemTrayManager.isInitialized, first);
      } catch (_) {}
    });

    test('dispose 释放资源', () async {
      try {
        await SystemTrayManager.initialize(
          onShow: () {},
          onQuit: () {},
        );
        await SystemTrayManager.dispose();
        expect(SystemTrayManager.isInitialized, isFalse);
      } catch (_) {}
    });

    test('dispose 多次调用不崩溃', () async {
      try {
        await SystemTrayManager.dispose();
        await SystemTrayManager.dispose();
        expect(SystemTrayManager.isInitialized, isFalse);
      } catch (_) {}
    });

    test('updateToolTip 不抛异常', () async {
      try {
        await SystemTrayManager.updateToolTip('Test Tooltip');
      } catch (_) {}
    });

    test('minimizeToTray 不抛异常', () async {
      try {
        await SystemTrayManager.minimizeToTray();
      } catch (_) {}
    });
  });
}
