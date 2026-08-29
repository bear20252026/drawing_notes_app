// 块文档 ⇄ note 帧 拆分/合并纯逻辑（M8-2）。
// 纯 Dart，仅依赖 note_block / note_block_doc / edgeless_doc。
//
// 把线性 NoteBlockDoc 拆成无限画布上若干 NoteFrame（按 heading 分帧），
// 或把若干 NoteFrame 按 z 顺序拼回一个 NoteBlockDoc。

import 'dart:ui' show Rect;

import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';

/// 把块文档拆成 note 帧列表（1:1 初始转换）。
///
/// 规则：
/// - 若 doc.body 无顶层 heading → 产出一个帧装全部顶层块。
/// - 若存在顶层 heading（h1-h6）→ 每个顶层 heading 起一个新帧（heading 作为
///   该帧首块，其后非 heading 顶层块归入该帧）；heading 之前的前导块归入第一个帧。
/// - 各帧在初始位置级联排布：x = initialRect.left，
///   y = initialRect.top + i*(initialRect.height + 64)，宽度/高度用 initialRect，
///   zIndex = baseZ + i。
/// - 帧 title：首帧继承 doc.title，后续帧用 heading 文本。
List<NoteFrame> noteBlockDocToFrames(
  NoteBlockDoc doc, {
  required String docId,
  required Rect initialRect,
  int baseZ = 0,
}) {
  final blocks = doc.body;

  // 判断是否存在顶层 heading。
  final hasTopLevelHeading =
      blocks.any((b) => b.type == NoteBlockType.heading);

  // 按 heading 分组：每个 group 是一个帧的 body。
  final groups = <List<NoteBlock>>[];

  if (!hasTopLevelHeading) {
    // 无 heading → 单帧含全部块。
    groups.add(List<NoteBlock>.from(blocks));
  } else {
    // 有 heading → 按顶层 heading 切分。
    var currentGroup = <NoteBlock>[];
    for (final block in blocks) {
      if (block.type == NoteBlockType.heading && currentGroup.isNotEmpty) {
        // 遇到新 heading，先保存当前组，再以该 heading 开启新组。
        groups.add(currentGroup);
        currentGroup = [block];
      } else {
        currentGroup.add(block);
      }
    }
    // 最后一组。
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }
  }

  // 生成帧。
  final frames = <NoteFrame>[];
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final frameDocId = '${docId}_frame_$i';

    // 确定帧 title。
    final String frameTitle;
    if (i == 0) {
      frameTitle = doc.title;
    } else {
      // 后续帧 title 取首块（heading）文本。
      final firstBlock = group.first;
      frameTitle = firstBlock.type == NoteBlockType.heading
          ? firstBlock.text
          : doc.title;
    }

    final frameDoc = NoteBlockDoc(
      id: frameDocId,
      title: frameTitle,
      body: group,
      createdAt: doc.createdAt,
      updatedAt: doc.updatedAt,
    );

    frames.add(NoteFrame(
      id: '${docId}_f$i',
      x: initialRect.left,
      y: initialRect.top + i * (initialRect.height + 64),
      w: initialRect.width,
      h: initialRect.height,
      zIndex: baseZ + i,
      doc: frameDoc,
    ));
  }

  return frames;
}

/// 创建空白帧（doc 为空则用 NoteBlockDoc.empty）。
NoteFrame createBlankFrame({
  required String docId,
  required Rect rect,
  required int zIndex,
  NoteBlockDoc? doc,
}) {
  final frameDoc = doc ?? NoteBlockDoc.empty('${docId}_blank');
  return NoteFrame(
    id: '${docId}_blank',
    x: rect.left,
    y: rect.top,
    w: rect.width,
    h: rect.height,
    zIndex: zIndex,
    doc: frameDoc,
  );
}

/// 把帧按 z 升序把各自 doc.body 顺序拼回一个块文档（保序、去环绕）。
NoteBlockDoc mergeFramesToDoc(
  List<NoteFrame> frames, {
  required String id,
  String title = '',
}) {
  // 按 zIndex 升序排序。
  final sorted = List<NoteFrame>.from(frames)
    ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

  // 顺序拼合各帧 body。
  final mergedBody = <NoteBlock>[];
  for (final frame in sorted) {
    mergedBody.addAll(frame.doc.body);
  }

  final now = DateTime.now();
  return NoteBlockDoc(
    id: id,
    title: title,
    body: mergedBody,
    createdAt: now,
    updatedAt: now,
  );
}
