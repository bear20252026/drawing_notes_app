import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/root_guard.dart';

void main() {
  group('RootGuard.isRootedOnAndroid', () {
    test('任一已知特征路径存在即判 root', () {
      expect(
        RootGuard.isRootedOnAndroid(existingPaths: ['/system/xbin/su']),
        isTrue,
      );
      expect(
        RootGuard.isRootedOnAndroid(existingPaths: ['/data/adb/magisk']),
        isTrue,
      );
      expect(
        RootGuard.isRootedOnAndroid(
          existingPaths: ['/vendor/bin/su', '/su/bin/su'],
        ),
        isTrue,
      );
    });

    test('无特征路径不误判', () {
      expect(RootGuard.isRootedOnAndroid(existingPaths: const []), isFalse);
    });

    test('特征路径清单覆盖 su/SuperSU/Magisk 三类信号', () {
      final paths = RootGuard.knownRootPaths;
      expect(paths.any((p) => p.endsWith('/su')), isTrue);
      expect(paths.any((p) => p.contains('Superuser')), isTrue);
      expect(paths.any((p) => p.contains('magisk')), isTrue);
    });
  });

  group('RootGuard.detect（宿主平台真实性检查）', () {
    test('桌面测试宿主（非 Android）恒返回 false', () {
      // 本测试在 Windows 宿主上运行：detect 必须不误杀桌面平台。
      expect(RootGuard.detect(), isFalse);
    });
  });
}
