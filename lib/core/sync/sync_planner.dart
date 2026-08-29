// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步规划器（P3-W1）：纯逻辑清单比对 → 有序操作。
// 无 flutter/io/http/storage 依赖。

/// 文档快照：id + 最后修改时间（epoch ms）+ 字节大小。
class SyncSnapshot {
  const SyncSnapshot({
    required this.id,
    required this.updatedAt,
    required this.size,
  });

  final String id;
  final int updatedAt;
  final int size;

  SyncSnapshot copyWith({String? id, int? updatedAt, int? size}) => SyncSnapshot(
        id: id ?? this.id,
        updatedAt: updatedAt ?? this.updatedAt,
        size: size ?? this.size,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncSnapshot &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          updatedAt == other.updatedAt &&
          size == other.size;

  @override
  int get hashCode => Object.hash(id, updatedAt, size);

  @override
  String toString() =>
      'SyncSnapshot(id: $id, updatedAt: $updatedAt, size: $size)';
}

/// 同步清单：文档集 + 本地删除墓碑。
class SyncManifest {
  const SyncManifest({
    this.entries = const {},
    this.deletedIds = const {},
  });

  /// 文档 id → 快照。
  final Map<String, SyncSnapshot> entries;

  /// 本地已删除的文档 id（墓碑），用于通知远端删除。
  final Set<String> deletedIds;

  Map<String, dynamic> toJson() => {
        'entries': entries.map((k, v) => MapEntry(k, _snapshotToJson(v))),
        'deletedIds': deletedIds.toList(),
      };

  factory SyncManifest.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    Map<String, SyncSnapshot> parsedEntries;
    if (rawEntries is Map) {
      parsedEntries = rawEntries.map(
        (k, v) => MapEntry(
            k as String, _snapshotFromJson(v as Map<String, dynamic>)),
      );
    } else if (rawEntries is List) {
      // 兼容数组形式 [{id, updatedAt, size}, ...]
      parsedEntries = {
        for (final e in rawEntries)
          (e['id'] as String): _snapshotFromJson(e as Map<String, dynamic>),
      };
    } else {
      parsedEntries = {};
    }
    final parsedDeleted = (json['deletedIds'] as List? ?? const [])
        .map((e) => e as String)
        .toSet();
    return SyncManifest(entries: parsedEntries, deletedIds: parsedDeleted);
  }

  static Map<String, dynamic> _snapshotToJson(SyncSnapshot s) => {
        'id': s.id,
        'updatedAt': s.updatedAt,
        'size': s.size,
      };

  static SyncSnapshot _snapshotFromJson(Map<String, dynamic> json) => SyncSnapshot(
        id: json['id'] as String,
        updatedAt: json['updatedAt'] as int,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// 同步操作类型。
enum SyncOperationKind {
  /// 本地较新或仅本地存在 → 上传。
  upload,

  /// 远端较新或仅远端存在 → 下载。
  download,

  /// 本地已删除但远端仍有 → 删远端。
  deleteRemote,
}

/// 单条同步操作。
class SyncOperation {
  const SyncOperation({required this.kind, required this.id});

  final SyncOperationKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOperation &&
          runtimeType == other.runtimeType &&
          kind == other.kind &&
          id == other.id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'SyncOperation(kind: $kind, id: $id)';
}

/// 同步计划：有序操作列表 + 计数。
class SyncPlan {
  const SyncPlan({this.operations = const []});

  final List<SyncOperation> operations;

  int get uploadCount =>
      operations.where((o) => o.kind == SyncOperationKind.upload).length;
  int get downloadCount =>
      operations.where((o) => o.kind == SyncOperationKind.download).length;
  int get deleteCount =>
      operations.where((o) => o.kind == SyncOperationKind.deleteRemote).length;
}

/// 纯逻辑同步规划器。
///
/// 比对本地与远端清单，产出有序、确定性的操作序列。
/// 顺序：先 deleteRemote，再按 id 字典序的 upload、再 download（便于测试与幂等）。
class SyncPlanner {
  const SyncPlanner();

  /// 根据本地与远端清单生成同步计划。
  SyncPlan plan(SyncManifest local, SyncManifest remote) {
    final deletes = <String>[];
    final uploads = <String>[];
    final downloads = <String>[];

    // 1. 墓碑：本地已删（本地清单不再持有）但远端仍有 → 删远端。
    for (final id in local.deletedIds) {
      if (!local.entries.containsKey(id) && remote.entries.containsKey(id)) {
        deletes.add(id);
      }
    }

    // 2. 并集 ids 分类。
    final allIds = <String>{...local.entries.keys, ...remote.entries.keys};
    for (final id in allIds) {
      final localSnap = local.entries[id];
      final remoteSnap = remote.entries[id];
      final localDeleted = local.deletedIds.contains(id);

      if (localSnap != null && !localDeleted && remoteSnap == null) {
        // 仅本地且未被删 → upload。
        uploads.add(id);
      } else if (localSnap == null && remoteSnap != null) {
        // 仅远端：排除墓碑已处理的（deletedIds 含且 local 无 → deleteRemote）。
        if (!localDeleted) downloads.add(id);
      } else if (localSnap != null && remoteSnap != null) {
        if (localSnap.updatedAt > remoteSnap.updatedAt) {
          uploads.add(id);
        } else if (localSnap.updatedAt < remoteSnap.updatedAt) {
          downloads.add(id);
        }
        // == → 忽略
      }
    }

    // 3. 排序：deleteRemote 优先，然后 upload/download 按 id 字典序。
    deletes.sort();
    uploads.sort();
    downloads.sort();

    final ordered = <SyncOperation>[
      for (final id in deletes) SyncOperation(kind: SyncOperationKind.deleteRemote, id: id),
      for (final id in uploads) SyncOperation(kind: SyncOperationKind.upload, id: id),
      for (final id in downloads) SyncOperation(kind: SyncOperationKind.download, id: id),
    ];

    return SyncPlan(operations: ordered);
  }
}
