import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/storage_directories.dart';
import 'package:drawing_notes_app/core/storage/storage_media_store.dart';
import 'package:drawing_notes_app/core/storage/storage_secret_session.dart';
import 'package:drawing_notes_app/core/storage/storage_write_pipeline.dart';
import 'package:drawing_notes_app/core/storage/vault_file_codec.dart';

// C-08（审计 2026-09-27）：自 StorageService 的 part 五域拆为真协作类。
// 本类承载**回收站域**（M-06 修复，专家审计 2026-08-15）：删除移入
// 回收站 + 30 天保留（Android 官方 createTrashRequest/Files by Google
// 模式）、恢复、永久删除。删除流程挂在 per-document 独占队列内执行
// （E-17：在途保存与删除交错会让已删文档复活）。
// StorageService 保留门面，消费方 API 零变化。

/// 回收站域：移入、恢复、列出、过期清理与永久删除。
class StorageTrashBin {
  StorageTrashBin({
    required this.directories,
    required this.secrets,
    required this.pipeline,
    required this.media,
    required this.codec,
    required this.fireOnWrite,
  });


  /// 内部协作面：仅 StorageService 门面装配（C-08 拆分协作类，只读）。
  final StorageDirectories directories;
  final StorageSecretSession secrets;
  final StorageWritePipeline pipeline;
  final StorageMediaStore media;
  final DocumentCodec codec;
  final void Function() fireOnWrite;

  /// 回收站保留期（M-06，30 天——Android 官方模式）。
  static const Duration defaultTrashRetention = Duration(days: 30);

  /// 删除指定文档：移入回收站并清理不再被引用的受管图片。
  ///
  /// 图片清理以文档中的引用清单为准，并且只会删除 storeImage 写入的
  /// `document_images/` 顶层文件。用户原始文件、外部路径、解码失败的文档及
  /// 仍被其他文档引用的资产全部保留，宁可留下可维护的孤儿文件也不冒误删风险。
  ///
  /// E-17 修复（审计 2026-09-07）：整个删除流程挂在与保存相同的 per-id
  /// 写尾队列内（由门面 delete 经 [StorageWritePipeline.runDocExclusive]
  /// 进入）——在途保存与删除交错会让已删文档复活（rename 进回收站后，
  /// 队列中的保存又写出正式文件）。
  Future<bool> deleteDocumentToTrash(String id) async {
    await directories.ensureDocuments();
    final file = File(directories.documentPathFor(id));
    if (!file.existsSync()) return false;

    // 必须在删除主文件前读取其引用；无法读取时不进行资产回收，保证数据安全。
    DrawingDocument? document;
    try {
      var raw = await file.readAsBytes();
      if (VaultFileCodec.isEncrypted(raw)) {
        final key = await pipeline.currentKey();
        // 锁定/无密钥：解不开就不读——文档置 null，保守跳过资产回收。
        if (key != null) {
          raw = await VaultFileCodec.decrypt(raw, key, aadContext: 'doc:$id');
        }
      }
      document = codec.decode(raw);
    } catch (_) {
      // 损坏/锁定文档仍允许用户删除，但不基于不可信内容删除任何资产。
    }

    final imagePaths = document == null
        ? <String>{}
        : await media.managedImagePathsOf(document);

    // M-06 修复（专家审计 2026-08-15）：删除移入回收站（30 天保留——
    // Android 官方 createTrashRequest 模式），非永久删除——误删可恢复。
    final trashDir = await directories.ensureTrash();
    await file.rename(
      '${trashDir.path}${Platform.pathSeparator}'
      '${id}_${DateTime.now().millisecondsSinceEpoch}.json',
    );
    final backup = File('${file.path}.bak');
    if (backup.existsSync()) {
      await backup.delete();
    }

    // 清理缩略图（尽力而为，缩略图缺失不影响使用）。
    try {
      await media.deleteThumbnail(id);
    } catch (_) {
      // 缩略图清理失败不影响文档删除与后续资产回收。
    }
    secrets.forgetFilePassword(id); // 批次②：删除后清除会话文件密码缓存

    await media.deleteUnreferencedManagedImages(
      imagePaths,
      excludingDocumentId: id,
    );
    fireOnWrite();
    return true;
  }

  /// 恢复回收站项（M-06）：trashName 如 `doc123_1720000000000.json`——
  /// 移回 documents/ 目录。返回恢复后的文档 ID；失败（原 ID 冲突等）返回 null。
  /// E-17 修复（审计 2026-09-07）：rename 挂入与保存/删除相同的 per-id
  /// 写尾队列——恢复与在途保存交错会把恢复出的旧文档覆盖为新快照，
  /// 或让同 ID 冲突判定出现 TOCTOU。
  Future<String?> restoreTrash(String trashName) async {
    final trashDir = await directories.ensureTrash();
    await directories.ensureDocuments();
    final src = File('${trashDir.path}${Platform.pathSeparator}$trashName');
    if (!src.existsSync()) return null;
    final id = trashName.split('_').first;
    if (!StorageDirectories.validIdPattern.hasMatch(id)) return null;
    return pipeline.runDocExclusive(id, () async {
      if (!src.existsSync()) return null;
      final dest = File(directories.documentPathFor(id));
      if (dest.existsSync()) return null; // 原 ID 已存在——拒绝覆盖
      await src.rename(dest.path);
      fireOnWrite();
      return id;
    });
  }

  /// 列出回收站项（M-06）：返回 (trashName, 原始 id, 删除时间)，最近在前。
  Future<List<(String, String, DateTime)>> listTrash() async {
    final trashDir = await directories.ensureTrash();
    final items = <(String, String, DateTime)>[];
    await for (final entity in trashDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      final parts = name.split('_');
      if (parts.length < 2 ||
          !StorageDirectories.validIdPattern.hasMatch(parts.first)) {
        continue;
      }
      final ts = int.tryParse(parts[1].split('.').first) ?? 0;
      items.add((name, parts.first, DateTime.fromMillisecondsSinceEpoch(ts)));
    }
    items.sort((a, b) => b.$3.compareTo(a.$3));
    return items;
  }

  /// 清理过期回收站项（M-06）：超过保留期（默认 30 天）永久删除。
  Future<int> purgeTrash({
    Duration retention = defaultTrashRetention,
  }) async {
    final trashDir = await directories.ensureTrash();
    final now = DateTime.now();
    var purged = 0;
    await for (final entity in trashDir.list()) {
      if (entity is! File) continue;
      try {
        final stat = entity.statSync();
        if (now.difference(stat.modified) > retention) {
          await entity.delete();
          purged++;
        }
      } catch (_) {
        // 单个清理失败忽略。
      }
    }
    return purged;
  }

  /// 永久删除单个回收站项（M-06 UI：Delete forever 与 Restore 分离——
  /// UX Patterns 官方模式）。返回是否删除成功。
  Future<bool> deleteTrashPermanently(String trashName) async {
    final trashDir = await directories.ensureTrash();
    // 防路径遍历：trashName 仅允许 `id_时间戳.json` 形态。
    if (!RegExp(r'^[A-Za-z0-9_-]+_\d+\.json$').hasMatch(trashName)) {
      return false;
    }
    final file = File('${trashDir.path}${Platform.pathSeparator}$trashName');
    if (!file.existsSync()) return false;
    await file.delete();
    return true;
  }
}
