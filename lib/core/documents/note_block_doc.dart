// 由 Claude 团队生成 | Drawing Notes App
// NoteBlockDoc 文档容器：承载一个「文档=笔记」的块模型聚合。
// 纯 Dart，无 flutter/io/controller/存储依赖。

import 'package:drawing_notes_app/core/utils/time_serialization.dart';
import 'package:drawing_notes_app/core/documents/note_block.dart';

/// 一个「文档=笔记」的块模型聚合根。
///
/// [body] 是文档的正文块列表（有序）。M0 约定：一个文档 = 一个 root 块，
/// 其 children 即正文块列表；这里 [body] 直接持有该 children 列表，
/// 避免多余的根节点包装。[title] 由 NotebookPage 持有，此处可独立设置。
///
/// [body] 字段为 final，但列表内容在 M0 阶段允许通过 [copyWith] 替换。
/// 后续集成时由 NoteBlockEditor 操作后返回新 doc。
class NoteBlockDoc {
  const NoteBlockDoc({
    required this.id,
    this.title = '',
    List<NoteBlock>? body,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  }) : body = body ?? const [];

  /// 文档唯一标识。
  final String id;

  /// 文档标题。
  final String title;

  /// 正文块列表（有序、不可变引用）。
  final List<NoteBlock> body;

  /// 创建时间。
  final DateTime createdAt;

  /// 最后修改时间。
  final DateTime updatedAt;

  /// 标签 id 列表（M12.6 标签系统；标签定义存 TagStore，文档只持 id）。
  final List<String> tags;

  /// 生成含一个空 paragraph 的最小文档。
  factory NoteBlockDoc.empty(String id, {String title = '', DateTime? now}) {
    final timestamp = now ?? DateTime.fromMillisecondsSinceEpoch(0);
    return NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('${id}_b0', text: '')],
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// 是否有正文块。
  bool get hasBlocks => body.isNotEmpty;

  /// 不可变 copyWith。
  NoteBlockDoc copyWith({
    String? id,
    String? title,
    List<NoteBlock>? body,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteBlockDoc(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    tags: tags ?? this.tags,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  // ── 序列化 ─────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body.map((b) => b.toJson()).toList(),
    if (tags.isNotEmpty) 'tags': tags,
    'createdAt': timeToIso(createdAt),
    'updatedAt': timeToIso(updatedAt),
  };

  factory NoteBlockDoc.fromJson(Map<String, dynamic> json) {
    // DN-008 加固（解码侧结构闸门，与传输层字节闸门不可互替）：
    // 字节闸门只管「WebDAV 响应读进来多少」，而这个入口还吃着本地文件、
    // 备份恢复与 isolate 解码路径（NoteBlockDocStore / NoteBlockDocSyncStore
    // 都从这里进），任何一条都不过网络。此处按**规模**设预算：顶层块数、
    // 递归节点总数（含标签）、容器嵌套深度——超限即拒（FormatException，与
    // DocumentCodec.decode 的解码错误口径一致）。
    // 顺序也刻意如此：先过预算再构造 NoteBlock，恶意结构不会先物化成对象图；
    // 遍历用显式栈迭代，深嵌套输入不会把本闸门自己先炸掉（NoteBlock.fromJson
    // 是递归的，爆栈是进程级崩溃而非异常）。
    _enforceBlockBudget(json);
    return NoteBlockDoc(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      // B11 修复（审计 2026-09-07）：body 数组元素裸 `as Map` 强转——畸形
      // 元素抛 TypeError 使整个文档拒载；whereType 过滤畸形元素保住其余块。
      body: (json['body'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(NoteBlock.fromJson)
          .toList(),
      tags: (json['tags'] as List? ?? const []).whereType<String>().toList(),
      createdAt: timeFromIso(
        json['createdAt'],
        fallback: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      updatedAt: timeFromIso(
        json['updatedAt'],
        fallback: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  // ── 解码结构预算（DN-008 加固） ───────────────────────────

  /// 顶层正文块数上限。量级对齐画布文档的对象族预算（批次 DN-003 起收口在
  /// `core/storage/document_budgets.dart`：`maxShapeCount`/`maxImageCount`/
  /// `maxTextCount` = 5000、`maxTotalStrokes` = 50000）：块是笔记唯一的内容族，
  /// 取中间档 2 万——一篇 2 万块的笔记已是「整本书逐段成块」的量级，再高不
  /// 可能是用户打出来的。刻意留足余量：误拒一条合法长笔记比放行更糟。
  static const int maxBodyBlockCount = 20000;

  /// 正文 + 标签的 JSON 节点总数上限（键、标量、容器都计入）。
  /// 依据：单个块最小结构（`{"id":"a"}`）≈ 3 节点 / 11 字节，
  /// 传输层文档档 16 MiB 的恶意载荷可堆出 ≈ 150 万节点——本预算在
  /// 20 万处**先于字节档命中**，这才是它存在的理由（否则只是重复闸门）。
  /// 换算到正常内容 ≈ 每块 10 节点 × 2 万块，与 [maxBodyBlockCount] 同量级
  /// 自洽。
  static const int maxTotalJsonNodes = 200000;

  /// 嵌套深度上限（爆栈防护）：[NoteBlock.fromJson] 走 children 递归，
  /// 深结构不是「对象多」而是**直接栈溢出崩溃**（进程级，连异常都拿不到）。
  /// 取值口径：这里的深度是**原始 JSON 容器层级**（一个块 ≈ 3 层：
  /// map → children 数组 → 子块 map），128 ≈ 40 多层块嵌套；UI 大纲现实深度
  /// 个位数，而真正会爆栈的深度在千位以上——即该值只是余量，不会误拒
  /// 真实笔记。深度常量与 `SvgPreflight.maxNestingDepth = 128` 同名同值，
  /// 两处都是「递归遍历前的深度预检」这一种防护。
  static const int maxBlockNestingDepth = 128;

  /// 规模预检：在**任何 NoteBlock 被构造之前**走一遍原始 JSON 结构。
  /// 迭代显式栈（本闸门自己不能被深结构先炸掉），越界一律抛
  /// [FormatException]——与 `DocumentCodec.decode` 的解码错误口径一致，
  /// 上层（同步器的单操作隔离 / 文档存储的读失败分支）按既有方式收敛。
  /// 类型形状不在此校验（`as List?` 的既有 TypeError 行为原样保留，
  /// 本方法只加规模预算，不改判据）。
  static void _enforceBlockBudget(Map<String, dynamic> json) {
    var nodes = 0;
    final pending = <(Object?, int)>[];

    void enqueue(Object? value, int depth) {
      if (depth > maxBlockNestingDepth) {
        throw FormatException(
          '笔记文档嵌套深度超限（$depth > $maxBlockNestingDepth），拒绝载入',
        );
      }
      pending.add((value, depth));
    }

    void account() {
      nodes++;
      if (nodes > maxTotalJsonNodes) {
        throw FormatException(
          '笔记文档结构节点数超限（$nodes > $maxTotalJsonNodes），拒绝载入',
        );
      }
    }

    final body = json['body'];
    if (body is List && body.length > maxBodyBlockCount) {
      throw FormatException(
        '笔记文档正文块数超限（${body.length} > $maxBodyBlockCount），拒绝载入',
      );
    }
    enqueue(body, 0);
    enqueue(json['tags'], 0);

    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (node is Map) {
        for (final entry in node.entries) {
          account(); // 键本身也是字符串对象。
          enqueue(entry.value, depth + 1);
        }
      } else if (node is List) {
        for (final element in node) {
          enqueue(element, depth + 1);
        }
      } else if (node != null) {
        account(); // 标量值（字符串/数字/布尔）。null 不计。
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteBlockDoc &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          _bodyEqual(body, other.body) &&
          createdAt.isAtSameMomentAs(other.createdAt) &&
          updatedAt.isAtSameMomentAs(other.updatedAt);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    Object.hashAll(body),
    createdAt.millisecondsSinceEpoch,
    updatedAt.millisecondsSinceEpoch,
  );

  @override
  String toString() =>
      'NoteBlockDoc(id: $id, title: "$title", blocks: ${body.length})';
}

bool _bodyEqual(List<NoteBlock> a, List<NoteBlock> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
