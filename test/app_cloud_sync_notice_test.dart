// S-02（审计 2026-09-27 + 方案 B）：云同步路径未加密暴露警示宿主。
//
// 覆盖：数据根位于 OneDrive 路径 + 未设 PIN → 弹警示；「我知道了」永久
// 记住；二次挂载不再弹；常规 ApplicationSupport 路径/PIN 已设不弹。
// 检测/弹窗失败静默跳过。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/app.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/kdf_params.dart';
import 'package:drawing_notes_app/core/security/kek_session_cache.dart';
import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDocs;

  // testWidgets 跑在 FakeAsync zone——后台 isolate 结果永不回投
  // （app_lock_gate_test 同款双保险）：轻量 KDF 档 + 同 isolate 直派生。
  setUp(() {
    AppLockService.testPinKdfOverride = KdfParams.testLight;
    KekSessionCache.bypassIsolateForTests = true;
  });
  tearDown(() {
    AppLockService.testPinKdfOverride = null;
    KekSessionCache.bypassIsolateForTests = false;
  });

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('s02_docs_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDocs);
  });

  /// 方案 B 后检测的是**数据根**（ApplicationSupport）路径，故
  /// oneDrive 标志通过 supportDirProvider 注入。
  CloudSyncNoticeHost host({required bool oneDrive}) {
    final supportDir = oneDrive
        ? Directory('${tempDocs.path}${Platform.pathSeparator}OneDrive')
        : tempDocs;
    return CloudSyncNoticeHost(
      appDataRoot: AppDataRoot(
        documentsDirProvider: () async => tempDocs,
        supportDirProvider: () async => supportDir,
      ),
      appLockService: AppLockService(),
      child: const Scaffold(body: Text('home')),
    );
  }

  Future<void> settle(WidgetTester tester, CloudSyncNoticeHost h) async {
    await tester.pumpWidget(MaterialApp(home: h));
    await tester.pump(); // postFrame 回调
    await tester.pumpAndSettle();
  }

  testWidgets('数据根在 OneDrive 路径 + 未设 PIN → 弹警示；我知道了后永久记住', (tester) async {
    await settle(tester, host(oneDrive: true));

    expect(find.text('笔记存储在云同步文件夹中'), findsOneWidget);

    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(CloudSyncNoticeHost.dismissedPrefKey), isTrue);

    // 二次挂载（重启语义）不再弹。
    await settle(tester, host(oneDrive: true));
    expect(find.text('笔记存储在云同步文件夹中'), findsNothing);
  });

  testWidgets('常规 ApplicationSupport 路径不弹（S-02 B 默认根）', (tester) async {
    await settle(tester, host(oneDrive: false));
    expect(find.text('笔记存储在云同步文件夹中'), findsNothing);
  });

  testWidgets('已设 PIN（密文落盘）不弹', (tester) async {
    final service = AppLockService();
    await service.setPin('135790');
    final supportDir = Directory(
      '${tempDocs.path}${Platform.pathSeparator}OneDrive',
    );
    final h = CloudSyncNoticeHost(
      appDataRoot: AppDataRoot(
        documentsDirProvider: () async => tempDocs,
        supportDirProvider: () async => supportDir,
      ),
      appLockService: service,
      child: const Scaffold(body: Text('home')),
    );
    await settle(tester, h);
    expect(find.text('笔记存储在云同步文件夹中'), findsNothing);
  });
}
