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

/// 一条删除墓碑（A3，第三轮协同方案 §9：删除必须带上「删在哪一版之上」）。
///
/// 为什么非要有它：远端清单里「某条目消失了」有两种完全不同的原因——有人删了
/// 它，或者清单被并发覆盖写丢了这一条（DN-104 的孤儿文件场景）。旧形状下两者
/// **不可区分**，于是手持该文档的设备一律按「本地独有 ⇒ 上传」处理：对前者这个
/// 动作把刚删掉的内容复活了（删除方下一轮再删 ⇒ 乒乓），对后者恰恰是唯一的修复
/// 手段。加害的不是判据，是信息不足。
///
/// 缺字段一律按「无因果」处理，绝不按「异常」处理（DN-206 同一纪律）：混合
/// 版本集群里旧客户端既不写也不读这块，行为与今天逐字节一致。
class SyncTombstone {
  const SyncTombstone({
    required this.id,
    this.deletedAt,
    this.baseRev,
    this.baseSize,
  });

  final String id;

  /// 删除在本设备落定的时刻（epoch ms）。跨设备时钟不可信（P2 的教训），所以
  /// 它**只**用于同一份清单内部的留存裁剪和 UI 叙述，不参与任何胜负判定。
  final int? deletedAt;

  /// 因果锚：这次删除作用在**哪一版之上**（生成墓碑时基线里那一条的
  /// `updatedAt`）。有了它，另一端手里的副本才可能被判成「删除之前的旧版」
  /// 而不是「删除之后的新改」。
  ///
  /// 它是**不需要自己基线**就能成立的判据：`updatedAt` 是文档自己的字段，
  /// 同步过之后两端拿到的是同一个数（不是判定时各读各的钟），所以「我手里这版
  /// 的 updatedAt 正等于被删那一版」是跨设备可比的因果事实。A3-2 的「不复活」
  /// 就落在这条判据上。
  final int? baseRev;

  /// 因果锚的第二条腿：被删那一版的字节数。只比 `baseRev` 的话，「另一端在同一
  /// 毫秒又存了一次、大小恰好没变」的真编辑会被误判成旧副本而被按住不上传；
  /// 要求两项都吻合之后，这条判据的假阳性面就窄到与结构判据同级。
  /// 缺字段（旧客户端写的清单）⇒ 退回只比时间戳，并由 [RemoteDeleteProof]
  /// 一侧如实记录证据强弱。
  final int? baseSize;

  /// 留存裁剪排序键：缺时间戳（旧清单 / 来路不明）按最旧处理——宁可先淘汰
  /// 信息不全的那条，也不因为「不知道」就把它当成最新的留下。
  int get retentionKey => deletedAt ?? 0;

  /// 是否带有任何因果信息（全空的墓碑与 `deletedIds` 里一个字符串等价，
  /// 写出它只会把清单撑大）。
  bool get hasCausality => deletedAt != null || baseRev != null;

  /// 这份墓碑能不能支撑「对方手里就是被删那一版」的因果判定。
  bool get hasRevisionAnchor => baseRev != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (deletedAt != null) 'deletedAt': deletedAt,
    if (baseRev != null) 'baseRev': baseRev,
    if (baseSize != null) 'baseSize': baseSize,
  };

  factory SyncTombstone.fromJson(String id, Map<String, dynamic> json) {
    final deletedAt = json['deletedAt'];
    final baseRev = json['baseRev'];
    final baseSize = json['baseSize'];
    if ((deletedAt != null && deletedAt is! int) ||
        (baseRev != null && baseRev is! int) ||
        (baseSize != null && baseSize is! int)) {
      throw const FormatException('远端清单墓碑格式损坏');
    }
    return SyncTombstone(
      id: id,
      deletedAt: deletedAt as int?,
      baseRev: baseRev as int?,
      baseSize: baseSize as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncTombstone &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          deletedAt == other.deletedAt &&
          baseRev == other.baseRev &&
          baseSize == other.baseSize;

  @override
  int get hashCode => Object.hash(id, deletedAt, baseRev, baseSize);

  @override
  String toString() =>
      'SyncTombstone(id: $id${deletedAt == null ? '' : ', deletedAt: $deletedAt'}'
      '${baseRev == null ? '' : ', baseRev: $baseRev'}'
      '${baseSize == null ? '' : ', baseSize: $baseSize'})';
}

/// 同步清单：文档集 + 本地删除墓碑（可选带因果）。
class SyncManifest {
  const SyncManifest({
    this.entries = const {},
    this.deletedIds = const {},
    this.tombstones = const {},
  });

  /// 文档 id → 快照。
  final Map<String, SyncSnapshot> entries;

  /// 本地已删除的文档 id（墓碑），用于通知远端删除。
  ///
  /// A3 之后它**仍然是「是否已删」的唯一裁决源**：[tombstones] 只是它的富信息
  /// 侧，不另立第二套真相。
  final Set<String> deletedIds;

  /// A3：`deletedIds` 的因果侧。不变量 **键 ⊆ deletedIds**——写侧在 [toJson]
  /// 里过滤，读侧在 [fromJson] 里把两侧并集（只写墓碑不写列表的畸形清单同样
  /// 算「已删」，否则对端会把它当不存在而重传复活）。
  final Map<String, SyncTombstone> tombstones;

  /// 墓碑留存上限：清单每轮整份拉取，删除记录不能无界增长。512 条 ≈ 20KB
  /// （每条几十字节），对「同一批设备各自离线数周」留了余量；超出按
  /// [pruneTombstones] 淘汰最旧的。
  static const int maxTombstones = 512;

  /// 按上限裁剪墓碑，保留最新的 [limit] 条。
  ///
  /// 排序必须**稳定**：清单要参与 ETag 条件写与逐字节断言，同一输入两次裁剪
  /// 结果不一致会让下一轮误判「清单变了」。同一时间戳下按 id 字典序兜底。
  static Map<String, SyncTombstone> pruneTombstones(
    Iterable<SyncTombstone> all, {
    int limit = maxTombstones,
  }) {
    final sorted = [...all]..sort((a, b) {
      final byTime = a.retentionKey.compareTo(b.retentionKey);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    final kept = sorted.length > limit
        ? sorted.sublist(sorted.length - limit)
        : sorted;
    return {for (final t in kept) t.id: t};
  }

  Map<String, dynamic> toJson() {
    // 只写「比 deletedIds 多出来的信息」：无因果字段的墓碑与列表项等价，重复
    // 一遍只会撑大清单。旧客户端读到未知键忽略，新客户端读到缺键按无因果处理。
    final enriched = {
      for (final t in tombstones.values)
        if (deletedIds.contains(t.id) && t.hasCausality) t.id: t.toJson(),
    };
    return {
      'entries': entries.map((k, v) => MapEntry(k, _snapshotToJson(v))),
      'deletedIds': deletedIds.toList(),
      if (enriched.isNotEmpty) 'tombstones': enriched,
    };
  }

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
    // A3：墓碑的因果侧。整块缺失（旧客户端写的清单）⇒ 空映射 ⇒ 所有墓碑按
    // 「无因果」处理，行为与今天完全一致；**畸形则整轮中止**（B10 同口径）——
    // 残缺的删除记录会被读成「没被删」，那正是把云端刚删掉的内容重传复活的方向。
    final parsedTombstones = <String, SyncTombstone>{};
    final rawTombstones = json['tombstones'];
    if (rawTombstones is Map) {
      for (final e in rawTombstones.entries) {
        if (e.key is! String || e.value is! Map<String, dynamic>) {
          throw const FormatException('远端清单墓碑格式损坏');
        }
        final tombstone = SyncTombstone.fromJson(
          e.key as String,
          e.value as Map<String, dynamic>,
        );
        parsedTombstones[tombstone.id] = tombstone;
      }
    } else if (rawTombstones != null) {
      throw const FormatException('远端清单墓碑格式损坏');
    }
    return SyncManifest(
      entries: parsedEntries,
      // 两侧并起来才是完整的删除集合：只写 tombstones 不写 deletedIds 的清单
      // 也算「已删」，否则 planner 看不见它，对端会按「本地独有」重传复活。
      deletedIds: {...parsedDeleted, ...parsedTombstones.keys},
      tombstones: parsedTombstones,
    );
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
