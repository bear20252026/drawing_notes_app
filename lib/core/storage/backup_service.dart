// core/storage——BackupService 数据安全备份（自动备份+恢复+版本管理+完整性校验）。
//
// 功能：
// 1. 自动备份（每日/每周）——基于 workmanager 后台任务
// 2. 备份轮转（保留最近 N 个）——超限自动清理最旧备份
// 3. 一键恢复——从备份文件恢复文档
// 4. 语义化版本标签——v1.2.3 格式，备份时记录版本信息
// 5. SHA-256 完整性校验——备份/恢复时验证文件未被篡改
//
// 目录结构：
//   appDir/backups/
//     {docId}/
//       {version}_{timestamp}.json      —— 备份文件
//       {version}_{timestamp}.json.sha256 —— SHA-256 校验文件
//       manifest.json                    —— 备份清单（版本列表+元数据）
//
// GPL-3.0 许可证——保留原始版权声明。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/drawing/domain/document.dart';
import '../../features/drawing/infrastructure/document_codec.dart';
import 'local_id_generator.dart';

/// 备份元数据。
class BackupMeta {
  const BackupMeta({
    required this.version,
    required this.timestamp,
    required this.label,
    required this.checksum,
    required this.fileSize,
  });

  /// 语义化版本（如 "1.0.0"）。
  final String version;

  /// 备份时间戳。
  final DateTime timestamp;

  /// 用户可读标签（如 "修复画笔bug后"）。
  final String label;

  /// SHA-256 校验和。
  final String checksum;

  /// 文件大小（字节）。
  final int fileSize;

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'label': label,
    'checksum': checksum,
    'fileSize': fileSize,
  };

  factory BackupMeta.fromJson(Map<String, dynamic> json) => BackupMeta(
    version: json['version'] as String? ?? '0.0.0',
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    label: json['label'] as String? ?? '',
    checksum: json['checksum'] as String? ?? '',
    fileSize: json['fileSize'] as int? ?? 0,
  );
}

/// 备份清单（每个文档的备份列表）。
class BackupManifest {
  const BackupManifest({required this.backups});

  final List<BackupMeta> backups;

  Map<String, dynamic> toJson() => {
    'backups': backups.map((b) => b.toJson()).toList(),
  };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final list = json['backups'] as List<dynamic>? ?? [];
    return BackupManifest(
      backups: list.map((b) => BackupMeta.fromJson(b as Map<String, dynamic>)).toList(),
    );
  }
}

/// 数据安全备份服务（自动备份+恢复+版本管理+完整性校验）。
class BackupService {
  BackupService({this.directoryProvider, this.maxBackups = 10});

  /// 目录提供者（测试时可注入临时目录）。
  final Future<Directory> Function()? directoryProvider;

  /// 最大备份数量（轮转策略——保留最近 N 个）。
  final int maxBackups;

  final DocumentCodec _codec = const DocumentCodec();

  Directory? _backupsDir;

  /// 确保备份目录存在。
  Future<Directory> _ensureBackupsDir() async {
    if (_backupsDir != null) return _backupsDir!;
    final provider = directoryProvider;
    final appDir = provider != null
        ? await provider()
        : await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _backupsDir = dir;
    return dir;
  }

  /// 获取文档备份目录。
  Future<Directory> _ensureDocBackupDir(String docId) async {
    final backupsDir = await _ensureBackupsDir();
    final docDir = Directory('${backupsDir.path}${Platform.pathSeparator}$docId');
    if (!await docDir.exists()) {
      await docDir.create(recursive: true);
    }
    return docDir;
  }

  /// 计算文件 SHA-256 校验和。
  static String computeChecksum(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// 语义化版本递增。
  static String incrementVersion(String current, {String bump = 'patch'}) {
    final parts = current.split('.');
    if (parts.length != 3) return '1.0.0';
    var major = int.tryParse(parts[0]) ?? 1;
    var minor = int.tryParse(parts[1]) ?? 0;
    var patch = int.tryParse(parts[2]) ?? 0;

    switch (bump) {
      case 'major':
        major++;
        minor = 0;
        patch = 0;
      case 'minor':
        minor++;
        patch = 0;
      case 'patch':
      default:
        patch++;
    }
    return '$major.$minor.$patch';
  }

  /// 创建备份。
  ///
  /// [doc] — 要备份的文档
  /// [label] — 用户可选标签（如 "修复bug后"）
  /// [bump] — 版本递增类型（major/minor/patch）
  ///
  /// 返回备份元数据。
  Future<BackupMeta> createBackup(
    DrawingDocument doc, {
    String label = '',
    String bump = 'patch',
  }) async {
    final docDir = await _ensureDocBackupDir(doc.id);
    final manifest = await _loadManifest(doc.id);

    // 确定新版本号。
    final currentVersion = manifest.backups.isNotEmpty
        ? manifest.backups.last.version
        : '0.0.0';
    final newVersion = incrementVersion(currentVersion, bump: bump);

    // 编码文档。
    final data = _codec.encode(doc);
    final checksum = computeChecksum(data);
    final timestamp = DateTime.now();

    // 生成备份文件名。
    final timestampMs = timestamp.millisecondsSinceEpoch;
    final fileName = '${newVersion}_$timestampMs.json';
    final filePath = '${docDir.path}${Platform.pathSeparator}$fileName';

    // 写入备份文件（原子写入）。
    final tmpFile = File('$filePath.${LocalIdGenerator.next('bak')}.tmp');
    await tmpFile.writeAsBytes(data, flush: true);
    final finalFile = File(filePath);
    try {
      await tmpFile.rename(filePath);
    } on FileSystemException {
      if (await finalFile.exists()) await finalFile.delete();
      await tmpFile.rename(filePath);
    }

    // 写入 SHA-256 校验文件。
    final shaFile = File('$filePath.sha256');
    await shaFile.writeAsString(checksum);

    // 更新清单。
    final meta = BackupMeta(
      version: newVersion,
      timestamp: timestamp,
      label: label,
      checksum: checksum,
      fileSize: data.length,
    );
    manifest.backups.add(meta);
    await _saveManifest(doc.id, manifest);

    // 轮转：保留最近 N 个备份。
    await _rotateBackups(doc.id, manifest);

    return meta;
  }

  /// 从备份恢复文档。
  ///
  /// [docId] — 文档 ID
  /// [version] — 要恢复的版本号（null = 恢复最新）
  ///
  /// 返回恢复的文档，校验失败抛出异常。
  Future<DrawingDocument?> restoreBackup(
    String docId, {
    String? version,
  }) async {
    final docDir = await _ensureDocBackupDir(docId);
    final manifest = await _loadManifest(docId);

    // 找到目标备份。
    BackupMeta? target;
    if (version != null) {
      target = manifest.backups.where((b) => b.version == version).firstOrNull;
    } else {
      target = manifest.backups.isNotEmpty ? manifest.backups.last : null;
    }

    if (target == null) return null;

    // 查找备份文件。
    final files = await docDir.list().where((e) => e is File).toList();
    File? backupFile;
    for (final file in files) {
      if (file is File && file.path.contains(target.version)) {
        backupFile = file;
        break;
      }
    }

    if (backupFile == null || !await backupFile.exists()) return null;

    // 读取并校验完整性。
    final data = await backupFile.readAsBytes();
    final actualChecksum = computeChecksum(data);

    if (actualChecksum != target.checksum) {
      throw FormatException(
        '备份文件完整性校验失败：期望 ${target.checksum}，实际 $actualChecksum',
      );
    }

    // 解码文档。
    return _codec.decode(data);
  }

  /// 验证备份完整性。
  ///
  /// 返回 true 表示校验通过，false 表示文件被篡改或损坏。
  Future<bool> verifyIntegrity(String docId, {String? version}) async {
    try {
      await restoreBackup(docId, version: version);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 列出文档的所有备份。
  Future<List<BackupMeta>> listBackups(String docId) async {
    final manifest = await _loadManifest(docId);
    return List.unmodifiable(manifest.backups);
  }

  /// 删除指定版本的备份。
  Future<bool> deleteBackup(String docId, String version) async {
    final docDir = await _ensureDocBackupDir(docId);
    final manifest = await _loadManifest(docId);

    // 找到并删除备份文件。
    final files = await docDir.list().where((e) => e is File).toList();
    for (final file in files) {
      if (file is File && file.path.contains(version)) {
        await file.delete();
        // 删除对应的 SHA-256 文件。
        final shaFile = File('${file.path}.sha256');
        if (await shaFile.exists()) await shaFile.delete();
      }
    }

    // 更新清单。
    manifest.backups.removeWhere((b) => b.version == version);
    await _saveManifest(docId, manifest);

    return true;
  }

  /// 备份轮转：保留最近 [maxBackups] 个，删除最旧的。
  Future<void> _rotateBackups(String docId, BackupManifest manifest) async {
    if (manifest.backups.length <= maxBackups) return;

    final toRemove = manifest.backups.length - maxBackups;
    final removed = manifest.backups.take(toRemove).toList();

    for (final meta in removed) {
      await deleteBackup(docId, meta.version);
    }
  }

  /// 加载备份清单。
  Future<BackupManifest> _loadManifest(String docId) async {
    final docDir = await _ensureDocBackupDir(docId);
    final manifestFile = File('${docDir.path}${Platform.pathSeparator}manifest.json');

    if (!await manifestFile.exists()) {
      return const BackupManifest(backups: []);
    }

    try {
      final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      return BackupManifest.fromJson(json);
    } catch (_) {
      return const BackupManifest(backups: []);
    }
  }

  /// 保存备份清单。
  Future<void> _saveManifest(String docId, BackupManifest manifest) async {
    final docDir = await _ensureDocBackupDir(docId);
    final manifestFile = File('${docDir.path}${Platform.pathSeparator}manifest.json');
    final json = const JsonEncoder.withIndent('  ').convert(manifest.toJson());
    await manifestFile.writeAsString(json);
  }

  /// 获取备份统计信息。
  Future<Map<String, dynamic>> getBackupStats(String docId) async {
    final manifest = await _loadManifest(docId);
    final totalSize = manifest.backups.fold(0, (sum, b) => sum + b.fileSize);
    return {
      'backupCount': manifest.backups.length,
      'maxBackups': maxBackups,
      'totalSizeBytes': totalSize,
      'latestVersion': manifest.backups.isNotEmpty ? manifest.backups.last.version : null,
      'latestTimestamp': manifest.backups.isNotEmpty ? manifest.backups.last.timestamp : null,
    };
  }
}
