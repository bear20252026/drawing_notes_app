// 同步进度数据模型（P4-B2）。
// 纯 Dart，无 Flutter/io/controller/存储依赖；不可变值类型。
//
// SyncService 通过 onProgress 回调发射 SyncProgress 事件，
// 设置页据此渲染进度条与状态文案。
//
// ⚠️ 文案归属（审计 P1-2，2026-10-06）：本文件的 [SyncProgress.description]
// 是**中文兜底**，不是界面文案来源——纯 Dart 层拿不到 `AppLocalizations`，
// 在这里写死中文并直接渲染上 UI，结果就是 en 用户整条进度全程中文。
// 界面文案请走 `webdav_sync_settings_page.dart` 的 `syncProgressLabel`
// （按 arb 键 `syncPhase*` 取，缺 l10n 时才回落到本方法）。

/// 同步阶段枚举。
enum SyncProgressPhase {
  started,
  connecting,
  planning,
  uploading,
  downloading,
  deleting,
  writingManifest,
  done,
  failed,
}

/// 同步进度（不可变值类型）。
///
/// 由 SyncService 在同步过程中逐步发射，UI 层订阅并渲染。
class SyncProgress {
  const SyncProgress({
    required this.phase,
    this.doneCount = 0,
    this.totalCount = 0,
    this.currentDocId,
    this.message,
  });

  /// 当前同步阶段。
  final SyncProgressPhase phase;

  /// 已完成操作数。
  final int doneCount;

  /// 总操作数（0 表示未知）。
  final int totalCount;

  /// 当前正在处理的文档 id（如有）。
  final String? currentDocId;

  /// 附加描述信息（如有）。
  final String? message;

  /// 进度比例 [0.0, 1.0]。
  ///
  /// - totalCount > 0 → doneCount / totalCount
  /// - phase == done → 1.0
  /// - 其他 → 0.0
  double get fraction {
    if (totalCount > 0) {
      final f = doneCount / totalCount;
      return f.clamp(0.0, 1.0);
    }
    if (phase == SyncProgressPhase.done) return 1.0;
    return 0.0;
  }

  /// 按阶段生成的**中文兜底**可读文案（无 `AppLocalizations` 时使用）。
  ///
  /// 界面不要直接渲染它——走 `syncProgressLabel`（见文件头 P1-2 说明）。
  String get description {
    switch (phase) {
      case SyncProgressPhase.started:
        return '正在启动同步…';
      case SyncProgressPhase.connecting:
        return '正在连接服务器…';
      case SyncProgressPhase.planning:
        return '正在比对变更…';
      case SyncProgressPhase.uploading:
        if (totalCount > 0) {
          return '正在上传 $doneCount/$totalCount …';
        }
        return '正在上传…';
      case SyncProgressPhase.downloading:
        if (totalCount > 0) {
          return '正在下载 $doneCount/$totalCount …';
        }
        return '正在下载…';
      case SyncProgressPhase.deleting:
        if (totalCount > 0) {
          return '正在删除远端 $doneCount/$totalCount …';
        }
        return '正在删除远端文件…';
      case SyncProgressPhase.writingManifest:
        return '正在写入同步清单…';
      case SyncProgressPhase.done:
        return '同步完成';
      case SyncProgressPhase.failed:
        return (message != null && message!.isNotEmpty) ? message! : '同步失败';
    }
  }

  /// 便捷工厂：同步启动。
  factory SyncProgress.starting() =>
      const SyncProgress(phase: SyncProgressPhase.started);

  /// 便捷工厂：指定阶段。
  factory SyncProgress.phase(
    SyncProgressPhase phase, {
    int doneCount = 0,
    int totalCount = 0,
    String? currentDocId,
    String? message,
  }) => SyncProgress(
    phase: phase,
    doneCount: doneCount,
    totalCount: totalCount,
    currentDocId: currentDocId,
    message: message,
  );

  /// 便捷工厂：同步完成。
  factory SyncProgress.complete() =>
      const SyncProgress(phase: SyncProgressPhase.done);

  /// 便捷工厂：同步失败。
  factory SyncProgress.failure(String msg) =>
      SyncProgress(phase: SyncProgressPhase.failed, message: msg);

  /// 不可变更新：返回仅变更指定字段的新实例。
  SyncProgress copyWith({
    SyncProgressPhase? phase,
    int? doneCount,
    int? totalCount,
    String? currentDocId,
    String? message,
  }) => SyncProgress(
    phase: phase ?? this.phase,
    doneCount: doneCount ?? this.doneCount,
    totalCount: totalCount ?? this.totalCount,
    currentDocId: currentDocId ?? this.currentDocId,
    message: message ?? this.message,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncProgress &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          doneCount == other.doneCount &&
          totalCount == other.totalCount &&
          currentDocId == other.currentDocId &&
          message == other.message;

  @override
  int get hashCode =>
      Object.hash(phase, doneCount, totalCount, currentDocId, message);

  @override
  String toString() =>
      'SyncProgress(phase: $phase, done: $doneCount/$totalCount, current: $currentDocId)';
}
