// 由 Claude 团队生成 | Drawing Notes App
// WebDAV 本地优先同步规划器（P3-W1）：纯逻辑清单比对 → 有序操作。
// 无 flutter/io/http/storage 依赖。

/// 文档快照：id + 最后修改时间（epoch ms）+ 字节大小 +（可选）内容摘要。
class SyncSnapshot {
  const SyncSnapshot({
    required this.id,
    required this.updatedAt,
    required this.size,
    this.digest,
  });

  final String id;
  final int updatedAt;
  final int size;

  /// DN-206（第三轮专家审计 2026-10-13）：内容摘要——十六进制前 16 位
  /// （SHA-256 截断，64 bit）。
  ///
  /// 为什么必须存在：`updatedAt` 相同 + `size` 恰好相同的两次不同编辑，在本类
  /// 旧形状下**指纹完全一样**，于是 planner 的「== → 忽略」与冲突检测的
  /// `local == remote → continue` 双双静默，两端永久分叉且没有任何自愈路径。
  /// 截断到 64 bit 是为了清单体积：1000 篇笔记的 manifest 只多 16KB 而不是 64KB，
  /// 而这里的用途是「检测同一时刻的字节差异」，不是抗第二原像攻击。
  ///
  /// 可为 null：旧版本写入的远端清单/基线没有这个字段。**null 一律按
  /// 「不可比」处理**，绝不按「不同」处理——否则每个用户升级后的第一轮同步
  /// 会被当成全库冲突（假红风暴）。
  final String? digest;

  /// 两端都有摘要且不同 ⇒ 内容确实不同。任一侧缺摘要 ⇒ 返回 false（不可比）。
  bool contentDiffersFrom(SyncSnapshot other) {
    final a = digest;
    final b = other.digest;
    if (a == null || b == null) return false;
    return a != b;
  }

  SyncSnapshot copyWith({
    String? id,
    int? updatedAt,
    int? size,
    String? digest,
  }) => SyncSnapshot(
    id: id ?? this.id,
    updatedAt: updatedAt ?? this.updatedAt,
    size: size ?? this.size,
    digest: digest ?? this.digest,
  );

  /// 结构指纹相等性**刻意不含 digest**（DN-206 的兼容性关键）：
  /// 「时间戳 + 大小」是新旧客户端都有的公共语言，把摘要并进来会让升级后的
  /// 第一轮把所有旧基线条目判成「本地改过」。内容是否真的不同请走
  /// [contentDiffersFrom]，它自带「缺摘要即不可比」的兜底。
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
      'SyncSnapshot(id: $id, updatedAt: $updatedAt, size: $size'
      '${digest == null ? '' : ', digest: $digest'})';
}

/// 同步清单：文档集 + 本地删除墓碑。
class SyncManifest {
  const SyncManifest({this.entries = const {}, this.deletedIds = const {}});

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
    // B10 修复（审计 2026-09-07）：远端清单不可信——原 `k as String` /
    // `v as Map` / `e['id'] as String` 裸强转畸形数据抛 TypeError。改为
    // 类型检查，畸形条目抛 FormatException 整轮中止（fail-closed：宁可
    // 不同步，也不按残缺清单行动——漏看条目会误判「仅本地」而覆盖远端）。
    final parsedEntries = <String, SyncSnapshot>{};
    if (rawEntries is Map) {
      for (final entry in rawEntries.entries) {
        if (entry.key is! String || entry.value is! Map<String, dynamic>) {
          throw const FormatException('远端清单条目格式损坏');
        }
        parsedEntries[entry.key as String] = _snapshotFromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    } else if (rawEntries is List) {
      // 兼容数组形式 [{id, updatedAt, size}, ...]
      for (final e in rawEntries) {
        if (e is! Map<String, dynamic>) {
          throw const FormatException('远端清单条目格式损坏');
        }
        final snapshot = _snapshotFromJson(e);
        parsedEntries[snapshot.id] = snapshot;
      }
    }
    // 墓碑列表同理用类型过滤（非字符串墓碑忽略——不行动无数据风险）。
    final parsedDeleted = (json['deletedIds'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    return SyncManifest(entries: parsedEntries, deletedIds: parsedDeleted);
  }

  static Map<String, dynamic> _snapshotToJson(SyncSnapshot s) => {
    'id': s.id,
    'updatedAt': s.updatedAt,
    'size': s.size,
    // 与 v4 样式字段同一条纪律：**只在有值时写键**。旧客户端读到未知键会忽略，
    // 而把缺键定格成 `digest: null` 会让「升级后第一轮」在所有条目上都写出 null，
    // 反而把清单撑大、也让再降回旧版时读出多余字段。
    if (s.digest != null) 'digest': s.digest,
  };

  static SyncSnapshot _snapshotFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final updatedAt = json['updatedAt'];
    if (id is! String || updatedAt is! int) {
      throw const FormatException('远端清单条目格式损坏');
    }
    // digest 是**可选**字段（DN-206）：缺键 ⇒ null ⇒ 按「不可比」处理。
    // 但「存在却不是字符串/长到离谱」是畸形数据，按 B10 的既有口径整轮中止，
    // 不猜它的意图。
    final rawDigest = json['digest'];
    if (rawDigest != null &&
        (rawDigest is! String || rawDigest.length > _maxDigestLength)) {
      throw const FormatException('远端清单条目格式损坏');
    }
    return SyncSnapshot(
      id: id,
      updatedAt: updatedAt,
      size: (json['size'] as num?)?.toInt() ?? 0,
      digest: rawDigest as String?,
    );
  }

  /// 摘要字段允许的最大长度：本仓用的是 SHA-256 前 16 位十六进制，
  /// 128 已经宽松到能容纳将来换全长度散列，再长只可能是畸形/膨胀数据。
  static const int _maxDigestLength = 128;
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
        // == → 忽略。**这里刻意不因摘要不同而补一条操作**（DN-206）：时间戳相等时
        // 规划器没有任何依据判断哪边该胜——硬选一个方向就是「静默覆盖任一侧」。
        // 同 ts（同大小或同摘要不同）的分叉由 `detectSyncConflicts` 报成冲突，
        // 再由 `applyConflictResolutions` 给没有操作的冲突文档补上强制动作，
        // 用户裁决在那一环闭环。
      }
    }

    // 3. 排序：deleteRemote 优先，然后 upload/download 按 id 字典序。
    deletes.sort();
    uploads.sort();
    downloads.sort();

    final ordered = <SyncOperation>[
      for (final id in deletes)
        SyncOperation(kind: SyncOperationKind.deleteRemote, id: id),
      for (final id in uploads)
        SyncOperation(kind: SyncOperationKind.upload, id: id),
      for (final id in downloads)
        SyncOperation(kind: SyncOperationKind.download, id: id),
    ];

    return SyncPlan(operations: ordered);
  }
}
