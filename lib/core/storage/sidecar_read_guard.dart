// 由 Claude 团队生成 | Drawing Notes App

/// 侧车注册表（标签注册表 / 收藏集合）的**三态读取**与**覆盖前抢救**。
///
/// 为什么单独一份（审计 2026-10-16，§4 第 1 条本仓头号复发形态）：这两个 store 的读法
/// 原来是 `catch (_) => 空集合`——「文件在、但读不出来」和「文件不在」给的是**同一个答案**。
/// 而它们的写是「整体覆盖」（`addTag` = 读全表 → 追加 → 写回），于是那条错答会被立刻
/// 放大成真的没有：一次半写/一次磁盘读失败，下一次加标签就把用户的全部标签与收藏抹掉。
/// 同一个形状已经发作过四次（SYN-D1 块文档、STO-012 操作日志、FDC-01 富文本 spans、
/// STO-001 保险库），判据这次只写一遍，两处共用。
///
/// 本文件只做两件事，都**不改变现有产品语义**：
///  1. 把三态分清楚，并在「读不出来」时落一条可查的审计（可观测半边）；
///  2. 在整体覆盖**之前**把那份读不出来的原件**复制**成 `<文件>.corrupt-<utc>-<随机>`
///     （复制而非移动：移动会拆掉后续读取与人工取证唯一的原件）。
///
/// 「读不出来就**拒绝**覆盖」那半边是默认阻断（改的是用户能感知的行为），审计台账里
/// 明确列为需业主点名——本批不做，见 `docs/audit_2026-10-15.md` §5。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/utils/hex_encode.dart';

/// 侧车注册表文件的一次读取能给出的三种答案，**不能合并成两种**。
enum SidecarRead {
  /// 文件不存在：确实是空注册表（新用户 / 已清理）。
  absent,

  /// 文件在且能解析出 `{<listKey>: [...]}` 这个形状；个别条目坏不改变这个判定
  /// （条目级 fail-closed 由各 store 自己跳过）。
  readable,

  /// 文件在，但读不动 / 不是合法 JSON / 顶层形状不对 ⇒ **不知道**里面有什么。
  /// 这时「返回空集合」是一个错误答案，不是一次空结果。
  unreadable,
}

/// 读 [file] 并取出 `decoded[listKey]` 那一份清单，返回三态与条目。
///
/// 同步签名：两个 store 的读都已在 `await` 链上，且这里只做一次整文件读，
/// 不用异步分片（清单本身是 KB 级侧车）。
///
/// **任何**读不动/解不开都归 `unreadable`（stat 失败、句柄失败、非法 UTF-8、非法 JSON、
/// 顶层形状不对）——这与改动前「`catch (_) => 空集合`」的容错面**一致**：本函数只是把
/// 那份容错**分了类**，没有把任何一条失败路径变成抛异常（两个 store 的调用方都不接异常，
/// UI 继续拿到空集合）。
({SidecarRead state, List<dynamic> items}) readSidecarList(File file, String listKey) {
  const unreadable = (state: SidecarRead.unreadable, items: <dynamic>[]);
  try {
    if (!file.existsSync()) {
      return (state: SidecarRead.absent, items: const <dynamic>[]);
    }
    final raw = file.readAsStringSync();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return unreadable; // 半写 / 截断 / 非法 JSON
    }
    if (decoded is! Map<String, dynamic>) return unreadable;
    final list = decoded[listKey];
    if (list is! List) return unreadable;
    return (state: SidecarRead.readable, items: list);
  } on FileSystemException {
    return unreadable; // stat / 读句柄失败（权限、盘没挂上、文件正被占用）
  } on FormatException {
    return unreadable; // readAsString 的 utf8 解码失败
  }
}

/// 整体覆盖之前抢救原件：**只在盘上此刻仍然读不出来时**复制一份，返回保留件路径。
///
/// 为什么要「此刻重读」而不是复用调用方刚才那次判据：读与写之间可能已经有别的会话
/// 把文件修好了——把一份**能读的**原件标成 `.corrupt-*` 会造出假的事故证据。
///
/// [alreadyPreserved] 由调用方持有（每实例最多复制一份）：不这么做的话，注册表一直
/// 读不出来时**每次写都会复制一份**，而第二份开始复制的已经是上一次覆盖后的残缺内容，
/// 既没有取证价值，又把数据目录变成垃圾场。
/// 复制失败**不阻断写入**（返回 null + 一条失败审计）：抢救是额外保障，不能变成新的故障源。
Future<String?> preserveUnreadableSidecar(
  File file, {
  required String listKey,
  required String auditScope,
  required bool alreadyPreserved,
}) async {
  if (alreadyPreserved) return null;
  final read = readSidecarList(file, listKey);
  if (read.state != SidecarRead.unreadable) return null;
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  final suffix = hexEncode(
    List<int>.generate(4, (_) => Random.secure().nextInt(256)),
  );
  final target = File('${file.path}.corrupt-$stamp-$suffix');
  try {
    await file.copy(target.path);
    AuditLogger.log(
      '$auditScope.sidecar_unreadable_preserved',
      detail: 'from=${file.uri.pathSegments.last} to=${target.uri.pathSegments.last}',
    );
    return target.path;
  } on FileSystemException {
    AuditLogger.log(
      '$auditScope.sidecar_unreadable_preserve_failed',
      success: false,
      detail: 'from=${file.uri.pathSegments.last}',
    );
    return null;
  }
}

/// 「读不出来」这件事的可观测半边：每实例落一条就够（审计环只有 1000 条，
/// 而注册表读是 UI 每次重建都会做的事——不设限会把真正的安全事件挤出可见窗口）。
void noteUnreadableSidecar(String auditScope, {required bool alreadyNoted}) {
  if (alreadyNoted) return;
  AuditLogger.log(
    '$auditScope.sidecar_unreadable',
    success: false,
    detail: '存在但读不出来：本次按空集合返回，原件未被删除',
  );
}

/// 解析侧车文件路径；**目录提供者自己抛异常**时返回 null。
///
/// 为什么要有这一条（本批改判据时差点自己造的新故障）：两个 store 原先的整个读都包在
/// `catch (_) => 空集合` 里，`await _fileRef()`（`path_provider` 在缺存储/平台不支持时
/// 会抛）也在其中。把判据换成 `readSidecarList` 时，`_fileRef()` 被挪到了 try 之外，
/// 那条一直存在的容错就悄悄消失了——UI 会从「显示空列表」变成「抛异常」。
/// 提供者失败**不是**「注册表读不出来」，所以它不进三态、不落 sidecar 审计，只保持原样：
/// 调用方按空集合处理，绝不把异常抛给界面。
Future<File?> resolveSidecarFile(Future<File> Function() fileRef) async {
  try {
    return await fileRef();
  } catch (_) {
    // 与改动前同形：这里要的就是「任何失败都不许冒到 UI」。
    return null;
  }
}
