// 由 Claude 团队生成 | Drawing Notes App

/// 原子写留下的「孤儿临时文件」清扫（审计 2026-10-16 新发现）。
///
/// 缘起：所有写腿都用 `写 tmp → .bak 备份 → rename 换入` 这套原子写。失败路径各自都
/// 清了 tmp，但**进程被杀 / 崩溃在 write 与 rename 之间**时没人回收；带生成器 id 的
/// 原子写在本仓有 **10 个生产者**（逐条实测 `grep -rn "LocalIdGenerator.next('" lib | grep '\.tmp'`：
/// `write` **7** 处、`thumb` 2 处、`oplog` 1 处），而清扫**只有保险库那一条腿**有
/// （`vault_key_service._sweepStaleTmpFiles`）——同一条风险在十条腿上只有一条有解，
/// 正是本仓「一修就漏九处」的头号形态。
/// 另有 **3 处裸 `.tmp`**（`note_block_doc_store_trash.dart:104/117`、
/// `storage_media_store.dart:153`）不带生成器 id ⇒ 按下面的判据**故意不扫**（判据表里
/// 钉住 `trash.meta.tmp` 这一格），它们的清理归各自那条腿的失败路径。
/// 还有 **6 处 `<目标>.tmp.<时间>.<十六进制>`**（实测：`vault_key_service.dart:688`、
/// `vfs/encrypted_vault.dart:345`、`tag_store.dart:187`、`favorite_store.dart:75`、
/// `file_sync_baseline_store.dart:68`、`file_sync_push_waiver_store.dart:60`）——
/// **只有保险库那一处**自带前缀清扫（`_sweepStaleTmpFiles`），另外 **5 处今天仍没人回收**。
/// 但同一批 `find` 实测：真根里**没有**这一族的残留 ⇒ 这条是「未覆盖」，不是「已观测到堆积」。
/// 本批刻意不伸手扩到那一族：它要的是「按前缀 + 目标名」的另一套授权边界，混进这条判据
/// 会让两边都变得说不清；已记入台账作为下一步的独立一格。
///
/// 实测证据（本机真实数据根 `Documents/绘图笔记数据/`，2026-10-16 只读列出、未删）：
/// **7 枚**孤儿——`documents/` 4 枚（最老 2026-09-04，最大 1,546,137 字节）、
/// `notebooks/` 2 枚（最大 4,644,724 字节）、`thumbnails/` 1 枚（`thumb_` 那一族）。
/// 前六枚合计 7,649,024 字节，每一枚里面都是**整份正文的副本**，与保险库那条腿注释里
/// 定性的「隐私残留」同一类。`blockdocs/` 今天没有残留 ⇒ 那条腿的接线是**预防**。
///
/// 三条边界（都是为了让清扫绝不变成新的风险源）：
///  - **只删「`.tmp` 后缀 + 末段是本生成器形状」的**：正式 `.json`、回滚用的 `.bak`、
///    以及没有本生成器形状的 `.tmp` 都永不触碰（判据一份定义在
///    [LocalIdGenerator.generatedIdPattern]，见 [isStaleLocalIdTempName]）；
///  - **只删超过 [staleTmpMaxAge] 的**：同进程/同机另一个实例正在写的 tmp 不会被抢删
///    （阈值与保险库那条腿同值，理由也同：一次写入是秒级，10 分钟余量充足）；
///  - **默认非递归**：调用方只拿自己那一个目录的授权；画布那条腿显式 `recursive: true`
///    扫整个数据根，是因为媒体、PDF 导入页图与缩略图的 tmp 落在子目录里，而上一条判据
///    已经保证子目录里别人的东西不会被算进来。
/// 失败一律吞（删不掉就下一轮再试）——清扫永不阻塞写入路径。
library;

import 'dart:io';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';

/// 孤儿临时文件的命名形状：`<目标>.<LocalIdGenerator 产出的 id>.tmp`。
///
/// 判据**复用生成器自己暴露的 [LocalIdGenerator.generatedIdPattern]**，不在这里抄
/// 前缀白名单：实测写这条形状的前缀有三家（`write`/`thumb`/`oplog`），本机真实数据根
/// 今天的 7 枚残留里就有 6 枚 `write_` 与 1 枚 `thumb_`——只认 `write_` 等于当着
/// 「修一条漏五条」的面，把同一条风险又切掉一半。
///
/// 必须**同时**满足「以 `.tmp` 结尾」与「最后那段是本生成器的形状」：后者是授权边界，
/// 前者挡住 `<目标>.tmp.<时间>.<十六进制>` 那一族（它由各自的 `.tmp.` 前缀清扫负责，
/// 覆盖情况见文件头——本判据不替它做主，两套判据不互相伸手）。
bool isStaleLocalIdTempName(String name) {
  if (!name.endsWith('.tmp')) return false;
  final head = name.substring(0, name.length - '.tmp'.length);
  final dot = head.lastIndexOf('.');
  if (dot < 0) return false;
  return LocalIdGenerator.isGeneratedId(head.substring(dot + 1));
}

/// 超过这个修改时间的 `.tmp` 才删。与保险库那条腿同值同理由。
const Duration staleTmpMaxAge = Duration(minutes: 10);

/// 扫 [dir]，删掉超龄的孤儿原子写临时文件，返回删除个数。
///
/// [recursive] 为真时深入子目录——画布那条腿用它一次覆盖整个数据根
/// （媒体、笔记本、PDF 导入的落点都在子目录里，那里也各自有 `*.write_*.tmp`）。
/// [auditScope] 只用于审计里区分是哪条腿（`documents` / `blockdocs` / `dataroot`）。
Future<int> sweepStaleTempFiles(
  Directory dir, {
  String auditScope = '',
  bool recursive = false,
  DateTime? now,
}) async {
  final List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(recursive: recursive);
  } on FileSystemException {
    // 目录还不存在/读不动：本轮不扫，也不报错——写入路径马上会自己建目录。
    return 0;
  }
  final reference = now ?? DateTime.now();
  var removed = 0;
  for (final entity in entries) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!isStaleLocalIdTempName(name)) continue;
    final DateTime modified;
    try {
      modified = entity.statSync().modified;
    } on FileSystemException {
      continue;
    }
    if (reference.difference(modified) < staleTmpMaxAge) continue;
    try {
      await entity.delete();
      removed++;
    } on FileSystemException {
      // 句柄还在别人手里：留着下一轮，不掩盖也不影响写入。
    }
  }
  if (removed > 0) {
    AuditLogger.log(
      'storage.stale_tmp_swept',
      detail: '${auditScope.isEmpty ? '' : '$auditScope:'}n=$removed',
    );
  }
  return removed;
}
