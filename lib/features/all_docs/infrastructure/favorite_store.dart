/// All Docs 收藏（精选）持久化门面。
///
/// 以 [AllDoc.dedupKey]（'kind:id'）为稳定键，持久化收藏集合。
/// 存储文件（应用文档目录下）：
///   `appDir/all_docs_favorites.json`
///     `{"favorites": ["canvas:abc", "blockdoc:xyz"]}`
///
/// 仅依赖 dart:io + directoryProvider；不 import presentation，
/// 层方向严格 domain ← infrastructure（与 NoteBlockDocStore 同模式）。
library;

import 'package:drawing_notes_app/core/storage/app_data_root.dart';
import 'package:drawing_notes_app/core/storage/sidecar_read_guard.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 收藏键集合持久化门面。
class FavoriteStore {
  /// 创建收藏存储门面。
  ///
  /// [directoryProvider] 为可选的目录提供者回调。测试时可注入临时目录，
  /// 生产环境默认使用系统文档目录。
  FavoriteStore({this.directoryProvider});

  /// 目录提供者：测试时可注入临时目录，生产环境使用系统文档目录。
  final Future<Directory> Function()? directoryProvider;

  File? _file;

  /// 每实例只落一条「读不出来」审计、只抢救一份原件（见 `sidecar_read_guard.dart`）。
  bool _unreadableNoted = false;
  bool _corruptPreserved = false;

  /// 已被抢救出来的那份原件的保留件文件名（`.corrupt-*`；没抢救过为 null）。
  /// DOC-12 乙（业主 2026-10-16 点名）：与标签注册表的 `salvagedOriginalName` 同一件事、
  /// 同一个形状——「收藏看起来全空了」必须被说成「旧内容保住了一份原件」。
  String? get salvagedOriginalName => _salvagedOriginalName;
  String? _salvagedOriginalName;

  /// 写链（P2 修复：add/remove/toggle 的读-改-写非原子——快速连点丢更新）。
  Future<void> _tail = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() fn) {
    final task = _tail.then((_) => fn());
    _tail = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<File> _fileRef() async {
    if (_file != null) return _file!;
    final provider = directoryProvider;
    final base = provider != null
        ? await provider()
        : await AppDataRoot.defaultRootDir();
    _file = File(
      '${base.path}${Platform.pathSeparator}all_docs_favorites.json',
    );
    return _file!;
  }

  /// 读取全部收藏键。
  ///
  /// DOC-12（审计 2026-10-16）：与标签注册表**同一条判据**（`sidecar_read_guard.dart`，
  /// 不抄第二份）——「文件在但读不出来」与「文件不存在」都仍然返回空集（**产品语义未变**），
  /// 但前者落一条审计，且下一次整体覆盖前先把原件复制成 `.corrupt-*`（见 [_writeKeys]）。
  /// 原来这里是 `catch (_) => {}`：一次半写就够把「用户收藏过什么」答成「什么都没收藏」，
  /// 而 `toggleFavorite` 紧接着按这份空集整体覆盖，收藏集合就此清零。
  Future<Set<String>> loadKeys() async {
    final file = await resolveSidecarFile(_fileRef);
    if (file == null) return <String>{}; // 目录解析失败：同改动前，不抛给 UI
    final read = readSidecarList(file, 'favorites');
    if (read.state != SidecarRead.readable) {
      if (read.state == SidecarRead.unreadable) {
        noteUnreadableSidecar('favorites', alreadyNoted: _unreadableNoted);
        _unreadableNoted = true;
      }
      return <String>{};
    }
    return read.items.whereType<String>().toSet();
  }

  /// 写入全部收藏键（整体覆盖）。
  /// P2 修复：随机 tmp + flush + 失败清理（固定名劫持/崩溃半写）。
  Future<void> _writeKeys(Set<String> keys) async {
    final file = await _fileRef();
    // 覆盖前抢救（DOC-12 可观测半边）：盘上此刻仍读不出来时先复制一份 `.corrupt-*`。
    // 复制失败不阻断写入，也不静默——`preserveUnreadableSidecar` 自己落审计。
    final preserved = await preserveUnreadableSidecar(
      file,
      listKey: 'favorites',
      auditScope: 'favorites',
      alreadyPreserved: _corruptPreserved,
    );
    if (preserved != null) {
      _corruptPreserved = true;
      _salvagedOriginalName ??= File(preserved).uri.pathSegments.last;
    }
    final r = Random.secure();
    final suffix = hexEncode(List<int>.generate(8, (_) => r.nextInt(256)));
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    try {
      await tmp.writeAsString(
        jsonEncode({'favorites': keys.toList()..sort()}),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) await tmp.delete();
      } catch (_) {
        /* 幂等清理：写入失败后删 tmp 尽力而为，失败不覆盖将 rethrow 的原始错误 */
      }
      rethrow;
    }
  }

  /// 收藏键合法性（P2 修复：loadKeys 无界——超长/海量键磁盘填充）。
  static bool _isValidKey(String key) =>
      key.isNotEmpty && key.length <= 256 && !key.contains('/');

  /// 收藏一个文档。
  Future<void> addKey(String key) => _enqueue(() async {
    if (!_isValidKey(key)) return;
    final keys = await loadKeys();
    keys.add(key);
    await _writeKeys(keys);
  });

  /// 取消收藏一个文档。
  Future<void> removeKey(String key) => _enqueue(() async {
    final keys = await loadKeys();
    keys.remove(key);
    await _writeKeys(keys);
  });

  /// 切换收藏状态，返回切换后的新状态（true=已收藏）。
  Future<bool> toggleKey(String key) => _enqueue(() async {
    if (!_isValidKey(key)) return false;
    final keys = await loadKeys();
    if (keys.contains(key)) {
      keys.remove(key);
      await _writeKeys(keys);
      return false;
    }
    keys.add(key);
    await _writeKeys(keys);
    return true;
  });
}
