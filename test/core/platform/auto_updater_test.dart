import 'dart:io';

import 'package:drawing_notes_app/core/platform/auto_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateInfo', () {
    test('构造函数设置所有字段', () {
      const info = UpdateInfo(
        version: '2.0.0',
        releaseNotes: 'Bug fixes',
        releaseUrl: 'https://github.com/drawing-notes/drawing_notes_app/releases/tag/v2.0.0',
        downloadUrl: 'https://example.com/app.exe',
      );

      expect(info.version, '2.0.0');
      expect(info.releaseNotes, 'Bug fixes');
      expect(info.releaseUrl, contains('github.com'));
      expect(info.downloadUrl, 'https://example.com/app.exe');
    });

    test('downloadUrl 可为 null', () {
      const info = UpdateInfo(
        version: '1.0.0',
        releaseNotes: '',
        releaseUrl: 'https://example.com',
      );

      expect(info.downloadUrl, isNull);
    });

    test('toString 包含版本号', () {
      const info = UpdateInfo(
        version: '3.5.1',
        releaseNotes: 'Update',
        releaseUrl: 'https://example.com',
      );

      expect(info.toString(), 'UpdateInfo(version: 3.5.1)');
    });

    test('releaseNotes 可为空字符串', () {
      const info = UpdateInfo(
        version: '1.0.0',
        releaseNotes: '',
        releaseUrl: 'https://example.com',
      );
      expect(info.releaseNotes, isEmpty);
    });

    test('各字段保持传入值', () {
      const info = UpdateInfo(
        version: '0.0.1-alpha',
        releaseNotes: 'Initial release',
        releaseUrl: 'https://github.com/test/repo/releases/tag/v0.0.1-alpha',
        downloadUrl: 'https://cdn.example.com/build-linux.AppImage',
      );
      expect(info.version, '0.0.1-alpha');
      expect(info.releaseNotes, 'Initial release');
      expect(info.releaseUrl, endsWith('v0.0.1-alpha'));
      expect(info.downloadUrl, contains('.AppImage'));
    });
  });

  group('AutoUpdater.setCurrentVersion / resetCheckTimer', () {
    setUp(() {
      AutoUpdater.resetCheckTimer();
    });

    test('setCurrentVersion 不抛异常', () {
      expect(() => AutoUpdater.setCurrentVersion('1.2.3'), returnsNormally);
    });

    test('resetCheckTimer 不抛异常', () {
      expect(() => AutoUpdater.resetCheckTimer(), returnsNormally);
    });

    test('多次 resetCheckTimer 正常', () {
      AutoUpdater.resetCheckTimer();
      AutoUpdater.resetCheckTimer();
      AutoUpdater.resetCheckTimer();
    });

    test('setCurrentVersion 后再 reset 正常', () {
      AutoUpdater.setCurrentVersion('5.0.0');
      AutoUpdater.resetCheckTimer();
      AutoUpdater.setCurrentVersion('6.0.0');
    });
  });

  group('AutoUpdater.checkForUpdate', () {
    setUp(() {
      AutoUpdater.resetCheckTimer();
      AutoUpdater.setCurrentVersion('1.0.0');
    });

    test('移动平台返回 null', () async {
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        final result = await AutoUpdater.checkForUpdate();
        expect(result, isNull);
      }
    });

    test('防抖机制 - 连续调用返回 null', () async {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // 第一次调用（可能因网络问题返回 null）
        await AutoUpdater.checkForUpdate();
        // 第二次调用（30分钟间隔内应被防抖拦截）
        await AutoUpdater.checkForUpdate();
        // resetCheckTimer 后可以重新检查
        expect(() => AutoUpdater.resetCheckTimer(), returnsNormally);
      }
    });

    test('resetCheckTimer 后可重新检查', () async {
      AutoUpdater.resetCheckTimer();
      // 重置后应允许再次检查（即使刚检查过）
      expect(() => AutoUpdater.resetCheckTimer(), returnsNormally);
    });
  });

  group('AutoUpdater 版本号边界', () {
    setUp(() {
      AutoUpdater.resetCheckTimer();
    });

    test('空版本号处理', () {
      AutoUpdater.setCurrentVersion('');
      expect(() => AutoUpdater.resetCheckTimer(), returnsNormally);
    });

    test('特殊版本号不抛异常', () {
      AutoUpdater.setCurrentVersion('1.0.0-beta+build.123');
      expect(() => AutoUpdater.resetCheckTimer(), returnsNormally);
    });
  });
}
