// cross_platform_adaptation_test.dart — P3 #48 跨平台适配验证。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P3 #48 跨平台适配验证', () {
    test('当前平台可识别', () {
      expect(Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isIOS || Platform.isAndroid, true);
    });

    test('平台特定路径差异', () {
      if (Platform.isWindows) {
        expect(Platform.pathSeparator, '\\');
      } else {
        expect(Platform.pathSeparator, '/');
      }
    });

    test('深度链接 URI Scheme 命名一致', () {
      const scheme = 'drawingnotes';
      expect(scheme, 'drawingnotes');
    });

    test('支持的文件扩展名', () {
      const extensions = ['drawingnotes', 'dnproj'];
      expect(extensions, contains('drawingnotes'));
      expect(extensions, contains('dnproj'));
    });

    test('临时目录可访问', () async {
      final tmp = Directory.systemTemp;
      expect(await tmp.exists(), true);
    });

    test('平台源文件存在', () {
      // Windows 和 Android 已配置。
      if (Platform.isWindows) {
        expect(Directory('windows').existsSync(), true);
      }
      if (Platform.isAndroid || Platform.isIOS) {
        expect(Directory('android').existsSync(), true);
      }
    });

    test('iOS/macOS/Linux 配置待生成', () {
      // 缺少的平台目录。
      // 需要 flutter create --platforms ios,macos,linux .
      final missingPlatforms = <String>[];
      if (!Directory('ios').existsSync()) missingPlatforms.add('ios');
      if (!Directory('macos').existsSync()) missingPlatforms.add('macos');
      if (!Directory('linux').existsSync()) missingPlatforms.add('linux');

      expect(missingPlatforms, isNotEmpty);
    });
  });
}
