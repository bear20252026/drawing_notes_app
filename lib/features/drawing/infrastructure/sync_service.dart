import 'dart:typed_data';

import 'sync_path_cipher.dart';

/// 云端同步条目：一个待同步/已同步的文件（本地 + 远程双端描述）。
///
/// 对齐 Saber `SaberSyncFile`：统一承载本地路径与远程（加密）路径，
/// 由 [SyncService] 三件套接口驱动双向同步。
class SyncFile {
  const SyncFile({required this.localPath, required this.remotePath});

  /// 本地文件路径（应用文档目录内）。
  final String localPath;

  /// 远程路径（云端相对根）；经 [SyncPathCipher] 加密的文件带 `.sbe` 扩展。
  final String remotePath;

  SyncFile copyWith({String? localPath, String? remotePath}) => SyncFile(
    localPath: localPath ?? this.localPath,
    remotePath: remotePath ?? this.remotePath,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncFile &&
      other.localPath == localPath &&
      other.remotePath == remotePath;

  @override
  int get hashCode => Object.hash(localPath, remotePath);
}

/// 同步服务抽象层（落地 Saber `abstract_sync` 的设计，独立实现）。
///
/// 三件套接口负责"找出差异"与"择优"：
/// - [findLocalChanges]：本地有、云端没有（或本地更新）的文件；
/// - [findRemoteChanges]：云端有、本地没有（或云端更新）的文件；
/// - [getBestFile]：冲突时按"本地优先/远程优先/最近修改"策略选优。
/// 传输层（HTTP/WebDAV 客户端）由具体实现注入，本抽象不绑定协议，
/// 便于政府验收时对同步逻辑做纯单元测试。
abstract class SyncService {
  /// 本地已修改/新增、需要上传的文件列表。
  Future<List<SyncFile>> findLocalChanges();

  /// 云端已新增/修改、需要下载的文件列表。
  Future<List<SyncFile>> findRemoteChanges();

  /// 冲突择优：同一文件双端都有且都改过时，按 [preferLocal] 决定取舍，
  /// 返回胜出端的内容读取器。
  Future<SyncFile> getBestFile(SyncFile file, {required bool preferLocal});

  /// 上传：把本地文件写入云端（经 [SyncPathCipher] 加密路径）。
  Future<void> upload(SyncFile file, Uint8List bytes);

  /// 下载：从云端读取文件内容。
  Future<Uint8List?> download(SyncFile file);
}

/// 冲突择优策略（对齐 Saber `getBestFile` 的 onEqualFiles 语义）。
enum SyncConflictStrategy { local, remote, newest }
