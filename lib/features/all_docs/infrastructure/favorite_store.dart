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

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  Future<File> _fileRef() async {
    if (_file != null) return _file!;
    final provider = directoryProvider;
    final base =
        provider != null ? await provider() : await getApplicationDocumentsDirectory();
    _file = File('${base.path}${Platform.pathSeparator}all_docs_favorites.json');
    return _file!;
  }

  /// 读取全部收藏键。文件不存在或损坏时返回空集（fail-open，不阻塞 UI）。
  Future<Set<String>> loadKeys() async {
    try {
      final file = await _fileRef();
      if (!await file.exists()) return <String>{};
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String>{};
      final list = decoded['favorites'];
      if (list is! List) return <String>{};
      return list.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// 写入全部收藏键（整体覆盖）。
  Future<void> _writeKeys(Set<String> keys) async {
    final file = await _fileRef();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({'favorites': keys.toList()..sort()}));
    await tmp.rename(file.path);
  }

  /// 收藏一个文档。
  Future<void> addKey(String key) async {
    final keys = await loadKeys();
    keys.add(key);
    await _writeKeys(keys);
  }

  /// 取消收藏一个文档。
  Future<void> removeKey(String key) async {
    final keys = await loadKeys();
    keys.remove(key);
    await _writeKeys(keys);
  }

  /// 切换收藏状态，返回切换后的新状态（true=已收藏）。
  Future<bool> toggleKey(String key) async {
    final keys = await loadKeys();
    if (keys.contains(key)) {
      keys.remove(key);
      await _writeKeys(keys);
      return false;
    }
    keys.add(key);
    await _writeKeys(keys);
    return true;
  }
}
