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
/// ⚠ 这句话在写下时（R41）**只有一条腿成立**：媒体那条有 try/catch 清 tmp，块文档回收站
/// 那两条根本没有失败路径，写废的 `.meta.tmp` 里装着删除时间、回退那枚甚至装着整篇正文，
/// 而且 `listTrash`/`purgeExpiredTrash` 只认 `.json` 也看不见它们 ⇒ 永久明文残留。
/// R52 给那两条补上 `_discardTemp`，并由 `test/core/documents/block_doc_trash_tmp_test.dart`
/// 双重钉住（真造一次 rename 失败看残不留 + 源码级「每枚裸 tmp 都要有自己的失败路径」）。
/// **引用规范文档当理由之前先 grep 那句话在不在**——这次轮到我自查写过的这句话。
/// 还有 **6 处 `<目标>.tmp.<时间>.<十六进制>`**（实测：`vault_key_service.dart:695`、
/// `vfs/encrypted_vault.dart:345`、`tag_store.dart:217`、`favorite_store.dart:103`、
/// `file_sync_baseline_store.dart:68`、`file_sync_push_waiver_store.dart:60`）——
/// R18 当时只有保险库那一处自带前缀清扫，另外 **5 处没人回收**。
/// **R41 起这一族也归本文件扫**：判据是 [isStaleSuffixTempName]，与第一族互不伸手
/// （各自定义、各自钉形状）。递归那条腿（画布 / 数据根）覆盖五处的落点：侧车在数据根，
/// 保险库对象在 `objects/` 子目录。
/// 剩余缺口如实写着：一个会话**只**动侧车、从没保存过画布或块文档时，数据根的递归扫不会触发，
/// 那枚孤儿会活到下一次画布/块文档保存——与 `notebooks/` 那两枚同一条已知缺口，不是永久残留。
///
/// 实测证据（本机真实数据根 `Documents/绘图笔记数据/`，2026-10-16 只读列出、未删）：
/// **7 枚**孤儿——`documents/` 4 枚（最老 2026-09-04，最大 1,546,137 字节）、
/// `notebooks/` 2 枚（最大 4,644,724 字节）、`thumbnails/` 1 枚（`thumb_` 那一族）。
/// 前六枚合计 7,649,024 字节，每一枚里面都是**整份正文的副本**，与保险库那条腿注释里
/// 定性的「隐私残留」同一类。`blockdocs/` 今天没有残留 ⇒ 那条腿的接线是**预防**。
///
/// 三条边界（都是为了让清扫绝不变成新的风险源）：
///  - **只删两族里任一命中的**：第一族「`.tmp` 后缀 + 末段是本生成器形状」
///    （[isStaleLocalIdTempName]），第二族「`.tmp.<微秒>.<16 位十六进制>`」
///    （[isStaleSuffixTempName]）。正式 `.json`、回滚用的 `.bak`、裸 `.tmp`、
///    以及任何不符合这两组形状的名字都永不触碰（判据一份定义在本文件）；
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
/// 前者让这条判据只管第一族——`<目标>.tmp.<时间>.<十六进制>` 那一族由
/// [isStaleSuffixTempName] 各自定义、互不伸手（两条边界混进一条判据会让两边都说不清）。
bool isStaleLocalIdTempName(String name) {
  if (!name.endsWith('.tmp')) return false;
  final head = name.substring(0, name.length - '.tmp'.length);
  final dot = head.lastIndexOf('.');
  if (dot < 0) return false;
  return LocalIdGenerator.isGeneratedId(head.substring(dot + 1));
}

/// 第二族：`<目标>.tmp.<微秒时间>.<16 位十六进制>`——**R41 起这条也被清扫**。
///
/// 缘起（R18 那批的台账原文）：带生成器 id 的原子写有 10 个生产者，清扫当时只有保险库那
/// 一条腿有；而这一族另有 5 个生产者（实测 `grep -rn "\.tmp\." lib`：
/// `tag_store.dart:217`、`favorite_store.dart:103`、`file_sync_baseline_store.dart:68`、
/// `file_sync_push_waiver_store.dart:60`、`vfs/encrypted_vault.dart:345`），当时**一处都没人回收**。
/// R18 刻意没把手伸过来，是因为它需要另一套授权边界——现在就是补那套边界。
///
/// 长度钉死在 **16** 是实测出来的，不是猜的：五处生产者的十六进制尾巴全部来自
/// `hexEncode(8 字节)`（`vault_key_service` 的 `_randomHex(8)` 同一条路），也就是 16 个字符。
/// 宁可**少删**也不要多删：将来生成器改成别的字节数，这条判据只会停止回收（安全方向），
/// 绝不会去动一个形状不同的文件。
final RegExp _suffixTempShape = RegExp(r'\.tmp\.[0-9]+\.[0-9a-f]{16}$');

bool isStaleSuffixTempName(String name) {
  // 与第一族互斥：以 `.tmp` 收尾的归上面那条判据管。
  if (name.endsWith('.tmp')) return false;
  final match = _suffixTempShape.firstMatch(name);
  // `.tmp.` 前面必须有东西：整段名字不能就是 `.tmp.1234…`（那说明目标是空文件名）。
  return match != null && match.start > 0;
}

/// 清扫用的总判据：两族里**任一族**命中才算孤儿临时文件。
bool isStaleTempName(String name) =>
    isStaleLocalIdTempName(name) || isStaleSuffixTempName(name);

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
    if (!isStaleTempName(name)) continue;
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
