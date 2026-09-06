// 版本一致性门禁（2026-09-06 审计）：以 pubspec.yaml 为唯一版本源，
// 校验 Windows 安装器脚本与 CHANGELOG 同步。
// 用法：dart run tools/check_version_consistency.dart（非零退出 = 不一致）。
//
// 背景：曾出现 setup.iss 的 VersionInfoVersion 停留在 1.1.0 的历史残留；
// 本脚本进 quality_gate CI，防止再次漂移。windows/flutter/ephemeral/ 为
// 构建生成物（每次构建按 pubspec 重新生成），不作为手工版本源。

import 'dart:io';

Never fail(String message) {
  stderr.writeln('版本一致性校验失败：$message');
  exit(1);
}

void main() {
  final root = Directory.current.path;

  // 1. pubspec.yaml：唯一版本源（X.Y.Z+N）。
  final pubspec = File('$root/pubspec.yaml').readAsLinesSync();
  final versionLine = pubspec
      .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
  final match = RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
      .firstMatch(versionLine);
  if (match == null) {
    fail('pubspec.yaml 缺少合法的 version: X.Y.Z+N 行（读到「$versionLine」）');
  }
  final version =
      '${match.group(1)}.${match.group(2)}.${match.group(3)}';

  // 2. tools/drawing_notes_setup.iss：MyAppVersion 与 VersionInfoVersion。
  final iss = File('$root/tools/drawing_notes_setup.iss').readAsLinesSync();
  String? issDefine;
  String? issVersionInfo;
  for (final line in iss) {
    final define = RegExp(r'^#define\s+MyAppVersion\s+"([^"]+)"').firstMatch(
      line,
    );
    if (define != null) issDefine = define.group(1);
    final info = RegExp(r'^VersionInfoVersion=(.+)$').firstMatch(line);
    if (info != null) issVersionInfo = info.group(1)?.trim();
  }
  if (issDefine != version) {
    fail('setup.iss MyAppVersion="$issDefine" != pubspec $version');
  }
  // VersionInfoVersion 允许用 {#MyAppVersion} 预处理派生（编译期解析）。
  final derived = issVersionInfo == version ||
      issVersionInfo == '{#MyAppVersion}' ||
      issVersionInfo == '$version.0';
  if (!derived) {
    fail('setup.iss VersionInfoVersion="$issVersionInfo" 未从 pubspec $version 派生');
  }

  // 3. CHANGELOG.md：顶部（非文件头说明区）存在本版本条目。
  final changelog = File('$root/CHANGELOG.md').readAsLinesSync();
  final hasEntry = changelog.take(30).any(
        (l) => l.startsWith('## [$version]'),
      );
  if (!hasEntry) {
    fail('CHANGELOG.md 前 30 行内没有 "## [$version]" 条目');
  }

  // 4. android/app/build.gradle.kts：版本必须来自 Flutter 注入（防硬编码）。
  final gradle = File(
    '$root/android/app/build.gradle.kts',
  ).readAsLinesSync().join('\n');
  if (!gradle.contains('flutter.versionName') ||
      !gradle.contains('flutter.versionCode')) {
    fail('android/app/build.gradle.kts 未使用 flutter.versionName/Code 注入');
  }

  // 5. windows/runner/Runner.rc：版本必须来自 FLUTTER_VERSION 宏（防 1.0.0 回退）。
  final rc = File(
    '$root/windows/runner/Runner.rc',
  ).readAsLinesSync().join('\n');
  if (!rc.contains('FLUTTER_VERSION')) {
    fail('windows/runner/Runner.rc 未使用 FLUTTER_VERSION 宏');
  }

  stdout.writeln('版本一致性校验通过：pubspec=$version（安装器/CHANGELOG/平台注入一致）');
}
